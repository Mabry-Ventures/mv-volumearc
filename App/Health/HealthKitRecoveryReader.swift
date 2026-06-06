#if canImport(HealthKit)
import Foundation
import HealthKit
import VolumeArcCore

/// VOL-181 Phase 1B: HealthKit-backed `RecoveryReader` that produces a
/// real `RecoveryContext` from `HKHealthStore` samples. Reads:
///
/// - **HRV (SDNN)** — 7-day mean and 28-day rolling baseline. Delta is
///   computed in Swift from the two means; HK has no native "delta vs
///   baseline" type.
/// - **Sleep** — 7-day total of `.asleepCore + .asleepDeep + .asleepREM`
///   per Apple's sleep-analysis recommendation. Compared against a
///   default 8h/night target to compute sleep debt.
/// - **Strength load** — 7-day sum of `traditionalStrengthTraining`
///   workouts: total active energy (converted kcal → kJ) and total
///   duration (seconds → minutes).
/// - **Apple Workout Effort** — explicit scores attached to workouts via
///   `HKWorkoutEffortRelationshipQuery`, plus HealthKit's estimated effort
///   score as the graceful fallback.
/// - **Vitals trends** — overnight wrist temperature and respiratory rate
///   as 7-day means vs 28-day baselines. Apple's Vitals composite score is
///   not exposed as a public HealthKit type as of 2026-05, so the composite
///   field remains `nil` while the underlying public metrics drive the chip.
///
/// All reads are non-throwing-on-no-data: if HK has no samples in the
/// window, the corresponding `RecoveryContext` field is `nil` (so
/// `RecoveryContext.asPromptBullets()` simply omits that line). Errors
/// are only thrown for HK availability or authorization failures.
///
/// VOL-136: the reader is split into two pieces so its orchestration
/// (query fan-out, telemetry routing, HRV-delta / sleep-debt
/// aggregation) is unit-testable without a live `HKHealthStore`:
///
/// - `RecoverySampleSource` is a HealthKit-free seam exposing the
///   primitive fetches the reader needs as plain `Double?` / typed
///   optionals.
/// - `HealthKitRecoverySampleSource` is the production implementation
///   that runs the real `HKStatisticsQuery` / `HKSampleQuery` calls.
/// - `HealthKitRecoveryReader` orchestrates the source: it owns the
///   availability gate, the per-field `runQuery` telemetry wrapper, the
///   empty/partial diagnostics, and the final `RecoveryContext`
///   assembly. Tests inject a `FakeRecoverySampleSource` to exercise all
///   of that deterministically (see `HealthKitRecoveryReaderTests`).
///
/// The public `init(healthStore:…)` is unchanged, so the production call
/// site in `VolumeArcApp` keeps working with no edits.

/// Strength-training load summary for a window: total active energy in
/// kilojoules and total workout minutes. HealthKit-free so it can cross
/// the `RecoverySampleSource` seam and be asserted in unit tests.
public struct RecoveryStrengthLoad: Sendable, Equatable {
    public let kj: Double
    public let minutes: Double

    public init(kj: Double, minutes: Double) {
        self.kj = kj
        self.minutes = minutes
    }
}

/// Apple Workout Effort summary for a window. `workoutScore` comes from
/// effort samples related to workouts through HealthKit's public
/// `HKWorkoutEffortRelationshipQuery`. `estimatedScore` is HealthKit's
/// inferred effort when no user-authored score is present.
public struct RecoveryWorkoutEffort: Sendable, Equatable {
    public let workoutScore: Double?
    public let estimatedScore: Double?

    public init(workoutScore: Double?, estimatedScore: Double?) {
        self.workoutScore = workoutScore
        self.estimatedScore = estimatedScore
    }
}

/// HealthKit-free seam over the primitive recovery fetches.
/// Implementations absorb HealthKit specifics and return plain numeric
/// optionals (`nil` == "no samples in window"); throwing is reserved for
/// genuine query failures so the reader can route them to distinct
/// telemetry.
public protocol RecoverySampleSource: Sendable {
    /// Whether health data can be read on this device at all (the
    /// production source forwards `HKHealthStore.isHealthDataAvailable()`).
    var isHealthDataAvailable: Bool { get }

    /// Discrete-average HRV (SDNN) in milliseconds over the trailing
    /// `days` window, or `nil` if there were no samples.
    func meanHRVMilliseconds(overDays days: Int, now: Date) async throws -> Double?

    /// Total asleep hours (Core + Deep + REM) over the trailing `days`
    /// window, or `nil` if there were no asleep samples.
    func totalAsleepHours(overDays days: Int, now: Date) async throws -> Double?

    /// Strength-training load (energy + duration) over the trailing
    /// `days` window, or `nil` if there were no strength workouts.
    func strengthLoad(overDays days: Int, now: Date) async throws -> RecoveryStrengthLoad?

    /// Apple Workout Effort scores over the trailing `days` window, or
    /// `nil` if HealthKit has no effort samples.
    func workoutEffort(overDays days: Int, now: Date) async throws -> RecoveryWorkoutEffort?

    /// Mean overnight wrist temperature in Celsius over the trailing
    /// `days` window, or `nil` if there were no samples.
    func meanWristTemperatureCelsius(overDays days: Int, now: Date) async throws -> Double?

    /// Mean respiratory rate in breaths/min over the trailing `days`
    /// window, or `nil` if there were no samples.
    func meanRespiratoryRate(overDays days: Int, now: Date) async throws -> Double?
}

public struct HealthKitRecoveryReader: RecoveryReader {

    private struct RecoveryQuerySnapshot {
        let mean7Day: Double?
        let baseline: Double?
        let sleepTotal: Double?
        let strengthSummary: RecoveryStrengthLoad?
        let effortSummary: RecoveryWorkoutEffort?
        let wristMean7Day: Double?
        let wristBaseline: Double?
        let respiratoryMean7Day: Double?
        let respiratoryBaseline: Double?
    }

    private let source: RecoverySampleSource
    private let sleepTargetHours: Double
    /// VOL-203: optional telemetry sink. When set, the reader emits
    /// typed events so operators can distinguish "user has no data"
    /// from "permission revoked" from "query failed" — three states
    /// previously indistinguishable because every error was swallowed
    /// by `try?`. The protocol surface stays non-throwing (callers
    /// still get a `RecoveryContext` and don't have to handle errors)
    /// but the typed telemetry stream now carries breadcrumb-level
    /// diagnostics without turning optional HealthKit recovery gaps
    /// into Sentry issues.
    private let telemetrySink: (any TelemetrySink)?

    /// Production initializer. Builds a real `HKHealthStore`-backed
    /// sample source. The signature is unchanged from before VOL-136 so
    /// existing call sites compile without edits.
    public init(
        healthStore: HKHealthStore = HKHealthStore(),
        sleepTargetHours: Double = 8.0,
        strengthActivityType: HKWorkoutActivityType = .traditionalStrengthTraining,
        telemetrySink: (any TelemetrySink)? = nil
    ) {
        self.init(
            source: HealthKitRecoverySampleSource(
                healthStore: healthStore,
                strengthActivityType: strengthActivityType
            ),
            sleepTargetHours: sleepTargetHours,
            telemetrySink: telemetrySink
        )
    }

    /// VOL-136 seam initializer. Injects an arbitrary `RecoverySampleSource`
    /// so tests can drive the reader's aggregation + telemetry paths with a
    /// deterministic in-memory fake. `internal` (not `private`) so the App
    /// test target can reach it; not part of the public API.
    init(
        source: RecoverySampleSource,
        sleepTargetHours: Double = 8.0,
        telemetrySink: (any TelemetrySink)? = nil
    ) {
        self.source = source
        self.sleepTargetHours = sleepTargetHours
        self.telemetrySink = telemetrySink
    }

    public func currentRecovery(now: Date = .now) async -> RecoveryContext {
        guard source.isHealthDataAvailable else {
            // VOL-203: simulator / unsupported-device path. Operator
            // shouldn't see this as a real "user data missing" event,
            // so route it to its own category for filtering.
            telemetrySink?.record(TelemetryEvent(
                category: "healthkit",
                name: "recovery_unavailable",
                severity: .info,
                message: "Health data not available on this device — recovery context omitted.",
                metadata: ["reason": "isHealthDataAvailable == false"]
            ))
            return RecoveryContext()
        }

        let snapshot = await recoveryQuerySnapshot(now: now)
        emitRecoveryDiagnostics(for: snapshot)
        return recoveryContext(from: snapshot)
    }

    private func recoveryQuerySnapshot(now: Date) async -> RecoveryQuerySnapshot {
        // VOL-203: each query now goes through `runQuery` which emits
        // a warning-level `healthkit.recovery_query_failed` event on
        // throw and a `healthkit.recovery_query_empty` event on "no data"
        // so an operator can distinguish missing data from missing
        // permissions from query failures. The reader still returns
        // `RecoveryContext` (the protocol contract); the caller path
        // doesn't change, but the telemetry stream carries the signal.
        async let hrv7 = runQuery(field: "hrv7") { try await self.source.meanHRVMilliseconds(overDays: 7, now: now) }
        async let hrv28 = runQuery(field: "hrv28") { try await self.source.meanHRVMilliseconds(overDays: 28, now: now) }
        async let sleep7 = runQuery(field: "sleep7") { try await self.source.totalAsleepHours(overDays: 7, now: now) }
        async let load = runQuery(field: "strength_load") { try await self.source.strengthLoad(overDays: 7, now: now) }
        async let effort = runQuery(field: "workout_effort") { try await self.source.workoutEffort(overDays: 7, now: now) }
        async let wrist7 = runQuery(field: "wrist_temperature7") {
            try await self.source.meanWristTemperatureCelsius(overDays: 7, now: now)
        }
        async let wrist28 = runQuery(field: "wrist_temperature28") {
            try await self.source.meanWristTemperatureCelsius(overDays: 28, now: now)
        }
        async let respiratory7 = runQuery(field: "respiratory_rate7") {
            try await self.source.meanRespiratoryRate(overDays: 7, now: now)
        }
        async let respiratory28 = runQuery(field: "respiratory_rate28") {
            try await self.source.meanRespiratoryRate(overDays: 28, now: now)
        }

        return RecoveryQuerySnapshot(
            mean7Day: await hrv7,
            baseline: await hrv28,
            sleepTotal: await sleep7,
            strengthSummary: await load,
            effortSummary: await effort,
            wristMean7Day: await wrist7,
            wristBaseline: await wrist28,
            respiratoryMean7Day: await respiratory7,
            respiratoryBaseline: await respiratory28
        )
    }

    private func emitRecoveryDiagnostics(for snapshot: RecoveryQuerySnapshot) {
        // VOL-203: if EVERY field is nil after we exited the
        // availability gate above, that's diagnostic information —
        // either the user denied authorization for every type, or all
        // four queries failed simultaneously. Emit a partial-result
        // summary so the operator dashboard can show "N% of recovery
        // reads are returning empty" without us logging the user's
        // actual values.
        let emptyFieldCount = [
            snapshot.mean7Day == nil,
            snapshot.baseline == nil,
            snapshot.sleepTotal == nil,
            snapshot.strengthSummary == nil,
            snapshot.effortSummary == nil,
            snapshot.wristMean7Day == nil,
            snapshot.wristBaseline == nil,
            snapshot.respiratoryMean7Day == nil,
            snapshot.respiratoryBaseline == nil
        ].filter { $0 }.count
        if emptyFieldCount == 9 {
            telemetrySink?.record(TelemetryEvent(
                category: "healthkit",
                name: "recovery_all_empty",
                severity: .warning,
                message: "All HK recovery fields returned no data — likely permission denied or fresh install.",
                metadata: [:]
            ))
        } else if emptyFieldCount > 0 {
            telemetrySink?.record(TelemetryEvent(
                category: "healthkit",
                name: "recovery_partial",
                severity: .info,
                message: "HK recovery context populated partially.",
                metadata: ["empty_field_count": String(emptyFieldCount)]
            ))
        }
    }

    private func recoveryContext(from snapshot: RecoveryQuerySnapshot) -> RecoveryContext {
        let deltaPercent: Double? = {
            guard let mean7Day = snapshot.mean7Day,
                  let baseline = snapshot.baseline,
                  baseline > 0 else { return nil }
            return ((mean7Day - baseline) / baseline) * 100.0
        }()

        let debt: Double? = snapshot.sleepTotal.map { total in
            total - (sleepTargetHours * 7.0)
        }
        let wristDelta = Self.delta(recent: snapshot.wristMean7Day, baseline: snapshot.wristBaseline)
        let respiratoryDelta = Self.delta(recent: snapshot.respiratoryMean7Day, baseline: snapshot.respiratoryBaseline)

        return RecoveryContext(
            hrvMean7Day: snapshot.mean7Day,
            hrvBaseline28Day: snapshot.baseline,
            hrvDeltaPercent: deltaPercent,
            sleep7DayTotalHours: snapshot.sleepTotal,
            sleepDailyTargetHours: sleepTargetHours,
            sleepDebtHours: debt,
            strengthLoad7DayKJ: snapshot.strengthSummary?.kj,
            strengthLoad7DayMinutes: snapshot.strengthSummary?.minutes,
            appleWorkoutEffort7DayAverage: snapshot.effortSummary?.workoutScore,
            appleEstimatedWorkoutEffort7DayAverage: snapshot.effortSummary?.estimatedScore,
            wristTemperature7DayMeanCelsius: snapshot.wristMean7Day,
            wristTemperature28DayBaselineCelsius: snapshot.wristBaseline,
            wristTemperatureDeltaCelsius: wristDelta,
            respiratoryRate7DayMean: snapshot.respiratoryMean7Day,
            respiratoryRate28DayBaseline: snapshot.respiratoryBaseline,
            respiratoryRateDelta: respiratoryDelta,
            appleWatchVitalsScore: nil
        )
    }

    private static func delta(recent: Double?, baseline: Double?) -> Double? {
        guard let recent, let baseline else { return nil }
        return recent - baseline
    }

    // MARK: - Query telemetry wrapper (VOL-203)

    /// Wraps a single source query so a throw becomes a typed
    /// warning-level `healthkit.recovery_query_failed` telemetry event
    /// (with the field name and the underlying error code, but never the
    /// user values) and a successful empty result becomes a
    /// `healthkit.recovery_query_empty` event. The caller still gets
    /// a flat `Double?` / typed-optional back, so the per-field
    /// degradation behavior matches the prior `try?` pattern exactly.
    /// Keep failures below `.error`: `SentryTelemetrySink` captures
    /// `.error` events as standalone issues, and optional HealthKit
    /// recovery reads can fail when a tester has denied one field,
    /// lacks a watch-backed metric, or HealthKit reports a transient
    /// read error. Those should be diagnostics and breadcrumbs, not
    /// nine production Sentry messages from one refresh.
    /// `T` is the per-field optional shape (Double? for scalar metrics,
    /// `RecoveryStrengthLoad?` / `RecoveryWorkoutEffort?` for typed summaries).
    private func runQuery<T>(field: String, work: @Sendable () async throws -> T?) async -> T? {
        do {
            let value = try await work()
            if value == nil {
                telemetrySink?.record(TelemetryEvent(
                    category: "healthkit",
                    name: "recovery_query_empty",
                    severity: .info,
                    message: "HK recovery query returned no samples for field \(field).",
                    metadata: ["field": field]
                ))
            }
            return value
        } catch {
            telemetrySink?.record(TelemetryEvent(
                category: "healthkit",
                name: "recovery_query_failed",
                severity: .warning,
                message: "HK recovery query failed for field \(field).",
                metadata: [
                    "field": field,
                    "error_code": String((error as NSError).code),
                    "error_domain": (error as NSError).domain,
                    "error_description": (error as NSError).localizedDescription
                ]
            ))
            return nil
        }
    }
}

/// Production `RecoverySampleSource` that runs the real HealthKit
/// queries. Extracted from `HealthKitRecoveryReader` in VOL-136 so the
/// reader's orchestration can be unit-tested behind the seam.
public struct HealthKitRecoverySampleSource: RecoverySampleSource {

    private let healthStore: HKHealthStore
    private let strengthActivityType: HKWorkoutActivityType

    public init(
        healthStore: HKHealthStore = HKHealthStore(),
        strengthActivityType: HKWorkoutActivityType = .traditionalStrengthTraining
    ) {
        self.healthStore = healthStore
        self.strengthActivityType = strengthActivityType
    }

    public var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - HRV

    public func meanHRVMilliseconds(overDays days: Int, now: Date) async throws -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return nil
        }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        return try await meanQuantity(
            type: hrvType,
            unit: HKUnit.secondUnit(with: .milli),
            predicate: predicate
        )
    }

    // MARK: - Sleep

    public func totalAsleepHours(overDays days: Int, now: Date) async throws -> Double? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                // Filter to actual asleep states (Core/Deep/REM). Apple
                // recommends this over `.asleepUnspecified` for
                // duration-sensitive computations like sleep debt.
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let totalSeconds = categorySamples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { running, sample in
                        running + sample.endDate.timeIntervalSince(sample.startDate)
                    }
                if totalSeconds == 0 {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: totalSeconds / 3600.0)
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Strength load

    public func strengthLoad(overDays days: Int, now: Date) async throws -> RecoveryStrengthLoad? {
        let workouts = try await strengthWorkouts(overDays: days, now: now)
        guard !workouts.isEmpty else {
            return nil
        }
        // Modern API: HKWorkout.statistics(for:) — works on
        // iOS 16+ and replaces the deprecated
        // `totalEnergyBurned` accessor. Sum across workouts.
        let energyType = HKQuantityType(.activeEnergyBurned)
        let totalKcal: Double = workouts.reduce(0.0) { acc, workout in
            let kcal = workout.statistics(for: energyType)?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie()) ?? 0
            return acc + kcal
        }
        let totalMinutes = workouts.reduce(0.0) { acc, workout in
            acc + (workout.duration / 60.0)
        }
        // 1 kcal = 4.184 kJ (Apple Health convention).
        let totalKJ = totalKcal * 4.184
        return RecoveryStrengthLoad(kj: totalKJ, minutes: totalMinutes)
    }

    private func strengthWorkouts(overDays days: Int, now: Date) async throws -> [HKWorkout] {
        let workoutType = HKObjectType.workoutType()
        let predicate = strengthWorkoutPredicate(overDays: days, now: now)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Apple Workout Effort

    public func workoutEffort(overDays days: Int, now: Date) async throws -> RecoveryWorkoutEffort? {
        do {
            return try await workoutEffortViaRelationships(overDays: days, now: now)
        } catch {
            let relationshipError = error
            let estimatedScore: Double?
            do {
                estimatedScore = try await estimatedWorkoutEffortAverageInStrengthWorkoutWindows(
                    overDays: days,
                    now: now
                )
            } catch {
                throw relationshipError
            }
            return try Self.makeWorkoutEffortSummary(
                explicitScore: nil,
                explicitError: relationshipError,
                estimatedScore: estimatedScore
            )
        }
    }

    static func makeWorkoutEffortSummary(
        explicitScore: Double?,
        explicitError: Error?,
        estimatedScore: Double?
    ) throws -> RecoveryWorkoutEffort? {
        guard explicitScore != nil || estimatedScore != nil else {
            if let explicitError { throw explicitError }
            return nil
        }
        return RecoveryWorkoutEffort(workoutScore: explicitScore, estimatedScore: estimatedScore)
    }

    static func makeWorkoutEffortSummary(from samples: [HKSample]) -> RecoveryWorkoutEffort? {
        let explicitScore = averageEffortSamples(in: samples, matching: .workoutEffortScore)
        let estimatedScore = averageEffortSamples(in: samples, matching: .estimatedWorkoutEffortScore)
        guard explicitScore != nil || estimatedScore != nil else {
            return nil
        }
        return RecoveryWorkoutEffort(workoutScore: explicitScore, estimatedScore: estimatedScore)
    }

    // MARK: - Vitals

    public func meanWristTemperatureCelsius(overDays days: Int, now: Date) async throws -> Double? {
        try await averageQuantitySample(
            identifier: .appleSleepingWristTemperature,
            unit: .degreeCelsius(),
            overDays: days,
            now: now
        )
    }

    public func meanRespiratoryRate(overDays days: Int, now: Date) async throws -> Double? {
        try await averageQuantitySample(
            identifier: .respiratoryRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            overDays: days,
            now: now
        )
    }

    private func averageQuantitySample(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        overDays days: Int,
        now: Date
    ) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        return try await meanQuantity(type: type, unit: unit, predicate: predicate)
    }

    private func meanQuantity(type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = result?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func workoutEffortViaRelationships(overDays days: Int, now: Date) async throws -> RecoveryWorkoutEffort? {
        let predicate = strengthWorkoutPredicate(overDays: days, now: now)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKWorkoutEffortRelationshipQuery(
                predicate: predicate,
                anchor: nil,
                options: .mostRelevant
            ) { query, relationships, _, error in
                self.healthStore.stop(query)
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let samples = relationships?.flatMap { $0.samples ?? [] } ?? []
                continuation.resume(returning: Self.makeWorkoutEffortSummary(from: samples))
            }
            healthStore.execute(query)
        }
    }

    private func estimatedWorkoutEffortAverageInStrengthWorkoutWindows(
        overDays days: Int,
        now: Date
    ) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .estimatedWorkoutEffortScore) else {
            return nil
        }
        let workouts = try await strengthWorkouts(overDays: days, now: now)
        let predicates = workouts.map {
            HKQuery.predicateForSamples(withStart: $0.startDate, end: $0.endDate, options: .strictStartDate)
        }
        guard !predicates.isEmpty else {
            return nil
        }
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        return try await meanQuantity(type: type, unit: .appleEffortScore(), predicate: predicate)
    }

    private func strengthWorkoutPredicate(overDays days: Int, now: Date) -> NSPredicate {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let activityPredicate = HKQuery.predicateForWorkouts(with: strengthActivityType)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, activityPredicate])
    }

    private static func averageEffortSamples(
        in samples: [HKSample],
        matching identifier: HKQuantityTypeIdentifier
    ) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        let values = samples.compactMap { sample -> Double? in
            guard let quantitySample = sample as? HKQuantitySample,
                  quantitySample.quantityType == type
            else { return nil }
            return quantitySample.quantity.doubleValue(for: .appleEffortScore())
        }
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }
}

#endif
