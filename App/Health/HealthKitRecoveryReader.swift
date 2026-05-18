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
/// - **Apple Watch Vitals score** — not exposed as a public HK type as
///   of 2026-05; returns `nil`. A future Apple SDK release may
///   surface this; tracked separately.
///
/// All reads are non-throwing-on-no-data: if HK has no samples in the
/// window, the corresponding `RecoveryContext` field is `nil` (so
/// `RecoveryContext.asPromptBullets()` simply omits that line). Errors
/// are only thrown for HK availability or authorization failures.
///
/// The struct accepts a `HKHealthStore` dependency at init so the
/// production path can share the app's existing store instance and
/// tests (which can't easily mock `HKHealthStore` directly) can
/// substitute a different reader implementation via the
/// `RecoveryReader` protocol seam.
public struct HealthKitRecoveryReader: RecoveryReader {

    private let healthStore: HKHealthStore
    private let sleepTargetHours: Double
    private let strengthActivityType: HKWorkoutActivityType
    /// VOL-203: optional telemetry sink. When set, the reader emits
    /// typed events so operators can distinguish "user has no data"
    /// from "permission revoked" from "query failed" — three states
    /// previously indistinguishable because every error was swallowed
    /// by `try?`. The protocol surface stays non-throwing (callers
    /// still get a `RecoveryContext` and don't have to handle errors)
    /// but the typed telemetry stream now carries the diagnostic info
    /// the operator needs to act on.
    private let telemetrySink: (any TelemetrySink)?

    public init(
        healthStore: HKHealthStore = HKHealthStore(),
        sleepTargetHours: Double = 8.0,
        strengthActivityType: HKWorkoutActivityType = .traditionalStrengthTraining,
        telemetrySink: (any TelemetrySink)? = nil
    ) {
        self.healthStore = healthStore
        self.sleepTargetHours = sleepTargetHours
        self.strengthActivityType = strengthActivityType
        self.telemetrySink = telemetrySink
    }

    public func currentRecovery(now: Date = .now) async -> RecoveryContext {
        guard HKHealthStore.isHealthDataAvailable() else {
            // VOL-203: simulator / unsupported-device path. Operator
            // shouldn't see this as a real "user data missing" event,
            // so route it to its own category for filtering.
            telemetrySink?.record(TelemetryEvent(
                category: "healthkit",
                name: "recovery_unavailable",
                severity: .info,
                message: "HKHealthStore not available on this device — recovery context omitted.",
                metadata: ["reason": "HKHealthStore.isHealthDataAvailable() == false"]
            ))
            return RecoveryContext()
        }

        // VOL-203: each query now goes through `runQuery` which emits
        // a `healthkit.recovery_query_failed` event on throw and a
        // `healthkit.recovery_query_empty` event on "no data" so an
        // operator can distinguish missing data from missing
        // permissions from query failures. The reader still returns
        // `RecoveryContext` (the protocol contract); the caller path
        // doesn't change, but the telemetry stream carries the signal.
        async let hrv7 = runQuery(field: "hrv7") { try await self.meanHRV(overDays: 7, now: now) }
        async let hrv28 = runQuery(field: "hrv28") { try await self.meanHRV(overDays: 28, now: now) }
        async let sleep7 = runQuery(field: "sleep7") { try await self.totalSleepHours(overDays: 7, now: now) }
        async let load = runQuery(field: "strength_load") { try await self.strengthLoad(overDays: 7, now: now) }

        let mean7Day = await hrv7
        let baseline = await hrv28
        let sleepTotal = await sleep7
        let strengthSummary = await load

        // VOL-203: if EVERY field is nil after we exited the
        // availability gate above, that's diagnostic information —
        // either the user denied authorization for every type, or all
        // four queries failed simultaneously. Emit a partial-result
        // summary so the operator dashboard can show "N% of recovery
        // reads are returning empty" without us logging the user's
        // actual values.
        let emptyFieldCount = [
            mean7Day == nil,
            baseline == nil,
            sleepTotal == nil,
            strengthSummary == nil
        ].filter { $0 }.count
        if emptyFieldCount == 4 {
            telemetrySink?.record(TelemetryEvent(
                category: "healthkit",
                name: "recovery_all_empty",
                severity: .warning,
                message: "All four HK recovery fields returned no data — likely permission denied or fresh install.",
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

        let deltaPercent: Double? = {
            guard let mean7Day, let baseline, baseline > 0 else { return nil }
            return ((mean7Day - baseline) / baseline) * 100.0
        }()

        let debt: Double? = sleepTotal.map { total in
            total - (sleepTargetHours * 7.0)
        }

        return RecoveryContext(
            hrvMean7Day: mean7Day,
            hrvBaseline28Day: baseline,
            hrvDeltaPercent: deltaPercent,
            sleep7DayTotalHours: sleepTotal,
            sleepDailyTargetHours: sleepTargetHours,
            sleepDebtHours: debt,
            strengthLoad7DayKJ: strengthSummary?.kj,
            strengthLoad7DayMinutes: strengthSummary?.minutes,
            appleWatchVitalsScore: nil
        )
    }

    // MARK: - Query telemetry wrapper (VOL-203)

    /// Wraps a single HK-backed query so a throw becomes a typed
    /// `healthkit.recovery_query_failed` telemetry event (with the
    /// field name and the underlying error code, but never the user
    /// values) and a successful empty result becomes a
    /// `healthkit.recovery_query_empty` event. The caller still gets
    /// a flat `Double?` / typed-optional back, so the per-field
    /// degradation behavior matches the prior `try?` pattern exactly.
    /// `T` is the per-field optional shape (Double? for HRV/sleep,
    /// (kj, minutes)? for strength load).
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
                severity: .error,
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

    // MARK: - HRV

    private func meanHRV(overDays days: Int, now: Date) async throws -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return nil
        }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrvType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let ms = result?.averageQuantity()?.doubleValue(for: HKUnit.secondUnit(with: .milli))
                continuation.resume(returning: ms)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Sleep

    private func totalSleepHours(overDays days: Int, now: Date) async throws -> Double? {
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

    private struct StrengthLoadSummary {
        let kj: Double
        let minutes: Double
    }

    private func strengthLoad(overDays days: Int, now: Date) async throws -> StrengthLoadSummary? {
        let workoutType = HKObjectType.workoutType()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let activityPredicate = HKQuery.predicateForWorkouts(with: strengthActivityType)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, activityPredicate])

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
                guard let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                    continuation.resume(returning: nil)
                    return
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
                continuation.resume(returning: StrengthLoadSummary(kj: totalKJ, minutes: totalMinutes))
            }
            healthStore.execute(query)
        }
    }
}

#endif
