import Foundation

public protocol HealthStore: Sendable {
    /// Request authorization for workout tracking.
    ///
    /// HealthKit exposes authorization status for write/share types, but not
    /// for read types. The returned result reports the inspectable workout
    /// sharing status and the platform read scopes that were requested.
    func requestAuthorization() async throws -> HealthAuthorizationResult

    /// Whether HealthKit is available and authorized to share workouts on this device.
    var isAuthorized: Bool { get async }

    /// Start a HealthKit workout session (watchOS only on real devices).
    func startWorkoutSession(activityType: WorkoutActivityType) async throws

    /// Start a HealthKit workout session linked to the app's stable workout id.
    func startWorkoutSession(activityType: WorkoutActivityType, workoutID: String) async throws

    /// End the current workout session and save to HealthKit.
    func endWorkoutSession() async throws

    /// Stream live workout metrics produced by the active watchOS workout.
    func liveWorkoutMetrics() async -> AsyncStream<LiveWorkoutMetrics>
}

public extension HealthStore {
    func startWorkoutSession(activityType: WorkoutActivityType, workoutID: String) async throws {
        try await startWorkoutSession(activityType: activityType)
    }

    func liveWorkoutMetrics() async -> AsyncStream<LiveWorkoutMetrics> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

public struct HealthAuthorizationResult: Sendable, Equatable {
    public let canShareWorkouts: Bool
    public let requestedReadIdentifiers: Set<String>

    public init(canShareWorkouts: Bool, requestedReadIdentifiers: Set<String>) {
        self.canShareWorkouts = canShareWorkouts
        self.requestedReadIdentifiers = requestedReadIdentifiers
    }
}

public enum WorkoutActivityType: String, Sendable {
    case strengthTraining
    case functionalStrengthTraining
    case coreTraining
    case mixedCardio
}

public struct LiveWorkoutMetrics: Sendable, Equatable {
    public let workoutID: String
    public let heartRateBPM: Int?
    public let activeEnergyKilocalories: Double?
    public let elapsedTime: TimeInterval
    public let capturedAt: Date

    public init(
        workoutID: String,
        heartRateBPM: Int?,
        activeEnergyKilocalories: Double?,
        elapsedTime: TimeInterval,
        capturedAt: Date
    ) {
        self.workoutID = workoutID
        self.heartRateBPM = heartRateBPM
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.elapsedTime = elapsedTime
        self.capturedAt = capturedAt
    }
}

public enum HealthWorkoutMetadata {
    public static let volumeArcWorkoutIDKey = "VolumeArcWorkoutID"
}

/// The set of HealthKit types the app asks authorization for, expressed as
/// platform-agnostic identifiers so tests can assert the shape without
/// importing HealthKit (HealthKit is unavailable on macOS test hosts).
///
/// Source of truth for VOL-80. Any change here should also update the
/// matching `INFOPLIST_KEY_NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`
/// strings in `scripts/generate_xcode_project.rb`.
public enum HealthKitAuthorizationScope {
    /// Types the app asks permission to WRITE. Identical across iOS and watchOS.
    public static let sharedWriteIdentifiers: Set<String> = [
        "HKWorkoutTypeIdentifier"
    ]

    /// Types the app asks permission to READ on iPhone. Workouts feed
    /// readiness + coach context + training history UI; HRV (SDNN) and
    /// sleep analysis feed the VOL-181 `HealthKitRecoveryReader` which
    /// drives the "Recovery (Apple Health)" section of the coach
    /// prompt and the Today-tab recovery chip. No heart rate, no
    /// active energy at phone scope — those are only consumed by the
    /// watchOS live-workout pipeline.
    public static let phoneReadIdentifiers: Set<String> = [
        "HKWorkoutTypeIdentifier",
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
        "HKCategoryTypeIdentifierSleepAnalysis",
    ]

    /// Types the app asks permission to READ on Apple Watch. Adds heart rate
    /// + active energy on top of the phone set because `HKLiveWorkoutDataSource`
    /// collects them during the live strength session so the saved workout
    /// carries an HR chart and calorie total in Apple Health.
    public static let watchReadIdentifiers: Set<String> = [
        "HKWorkoutTypeIdentifier",
        "HKQuantityTypeIdentifierHeartRate",
        "HKQuantityTypeIdentifierActiveEnergyBurned"
    ]
}

#if canImport(HealthKit)
import HealthKit

public extension HealthWorkoutMetadata {
    static func healthKitMetadata(for workoutID: String) -> [String: Any] {
        [
            HKMetadataKeyExternalUUID: workoutID,
            volumeArcWorkoutIDKey: workoutID,
        ]
    }
}

#if os(watchOS)
private actor LiveWorkoutMetricsHub {
    private var continuations: [UUID: AsyncStream<LiveWorkoutMetrics>.Continuation] = [:]

    func stream() -> AsyncStream<LiveWorkoutMetrics> {
        AsyncStream { continuation in
            let id = UUID()
            Task { self.register(continuation, id: id) }
            continuation.onTermination = { @Sendable _ in
                Task { await self.unregister(id) }
            }
        }
    }

    func yield(_ metrics: LiveWorkoutMetrics) {
        for continuation in continuations.values {
            continuation.yield(metrics)
        }
    }

    func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func register(_ continuation: AsyncStream<LiveWorkoutMetrics>.Continuation, id: UUID) {
        continuations[id] = continuation
    }

    private func unregister(_ id: UUID) {
        continuations[id] = nil
    }
}
#endif

public actor HealthKitRuntimeStore: HealthStore {
    private let healthStore = HKHealthStore()
    #if os(watchOS)
    private final class DelegateRelay: NSObject, HKLiveWorkoutBuilderDelegate {
        weak var owner: HealthKitRuntimeStore?

        func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
            emitMetrics(from: workoutBuilder)
        }

        func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
            emitMetrics(from: workoutBuilder)
        }

        private func emitMetrics(from workoutBuilder: HKLiveWorkoutBuilder) {
            let heartRateBPM = HealthKitRuntimeStore.heartRateBPM(from: workoutBuilder)
            let activeEnergyKilocalories = HealthKitRuntimeStore.activeEnergyKilocalories(from: workoutBuilder)
            let elapsedTime = workoutBuilder.elapsedTime
            let capturedAt = Date.now

            Task { [weak owner] in
                await owner?.emitMetrics(
                    heartRateBPM: heartRateBPM,
                    activeEnergyKilocalories: activeEnergyKilocalories,
                    elapsedTime: elapsedTime,
                    capturedAt: capturedAt
                )
            }
        }
    }

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let metricsHub = LiveWorkoutMetricsHub()
    private let delegateRelay = DelegateRelay()
    private var currentWorkoutID: String?
    #endif

    public init() {
        #if os(watchOS)
        delegateRelay.owner = self
        #endif
    }

    public var isAuthorized: Bool {
        get async {
            guard HKHealthStore.isHealthDataAvailable() else { return false }
            let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            return status == .sharingAuthorized
        }
    }

    public func requestAuthorization() async throws -> HealthAuthorizationResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return HealthAuthorizationResult(canShareWorkouts: false, requestedReadIdentifiers: [])
        }

        // VOL-80: HealthKit read scope is least-privilege per platform.
        //
        // Shared (iOS + watchOS):
        //   - HKWorkoutType — write: save completed workouts to Apple Health.
        //                     read:  render training history, feed `ReadinessModel`
        //                            (`VolumeArcCore/Workout/ReadinessModel.swift`) and
        //                            `CoachContext` (`VolumeArcCore/AI/CoachPromptTemplate.swift`)
        //                            via `WorkoutDashboardModel.buildCoachContext`.
        //
        // watchOS only:
        //   - .heartRate            — consumed by `HKLiveWorkoutDataSource` in
        //                             `startWorkoutSession` so the saved workout in Apple
        //                             Health carries an HR chart. No phone-side consumer.
        //   - .activeEnergyBurned   — consumed by the same data source so the saved
        //                             workout carries kcal. No phone-side consumer.
        //
        // Heart rate and active energy are intentionally NOT requested on iOS because
        // no phone-side surface (readiness, coach prompt, progression engine, UI)
        // reads them. If you add a consumer, expand `HealthKitAuthorizationScope`
        // and update the matching `INFOPLIST_KEY_NSHealthShareUsageDescription`
        // in `scripts/generate_xcode_project.rb`.
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        #if os(watchOS)
        let typesToRead = Self.watchReadTypes()
        let requestedReadIdentifiers = HealthKitAuthorizationScope.watchReadIdentifiers
        #else
        let typesToRead = Self.phoneReadTypes()
        let requestedReadIdentifiers = HealthKitAuthorizationScope.phoneReadIdentifiers
        #endif

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        return HealthAuthorizationResult(
            canShareWorkouts: await isAuthorized,
            requestedReadIdentifiers: requestedReadIdentifiers
        )
    }

    static func phoneReadTypes() -> Set<HKObjectType> {
        // Mirrors `HealthKitAuthorizationScope.phoneReadIdentifiers`.
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        // VOL-181: HRV (SDNN) + sleep analysis are read on iPhone by
        // `HealthKitRecoveryReader` to populate the coach prompt's
        // recovery section and the Today-tab recovery chip.
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    static func watchReadTypes() -> Set<HKObjectType> {
        // Mirrors `HealthKitAuthorizationScope.watchReadIdentifiers`.
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        return types
    }

    public func startWorkoutSession(activityType: WorkoutActivityType) async throws {
        try await startWorkoutSession(activityType: activityType, workoutID: UUID().uuidString)
    }

    public func startWorkoutSession(activityType: WorkoutActivityType, workoutID: String) async throws {
        #if os(watchOS)
        let startDate = Date.now
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = mapActivityType(activityType)
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        builder.delegate = delegateRelay

        self.session = session
        self.builder = builder
        self.currentWorkoutID = workoutID

        do {
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            try await builder.addMetadata(HealthWorkoutMetadata.healthKitMetadata(for: workoutID))
        } catch {
            session.end()
            builder.delegate = nil
            self.session = nil
            self.builder = nil
            self.currentWorkoutID = nil
            throw error
        }
        #endif
    }

    public func endWorkoutSession() async throws {
        #if os(watchOS)
        guard let session, let builder else { return }
        let endDate = Date.now
        session.end()
        do {
            try await builder.endCollection(at: endDate)
            _ = try await builder.finishWorkout()
            clearWorkoutSession(builder: builder)
            await metricsHub.finish()
        } catch {
            clearWorkoutSession(builder: builder)
            await metricsHub.finish()
            throw error
        }
        #endif
    }

    public func liveWorkoutMetrics() async -> AsyncStream<LiveWorkoutMetrics> {
        #if os(watchOS)
        await metricsHub.stream()
        #else
        AsyncStream { continuation in
            continuation.finish()
        }
        #endif
    }

    #if os(watchOS)
    private func mapActivityType(_ type: WorkoutActivityType) -> HKWorkoutActivityType {
        switch type {
        case .strengthTraining: return .traditionalStrengthTraining
        case .functionalStrengthTraining: return .functionalStrengthTraining
        case .coreTraining: return .coreTraining
        case .mixedCardio: return .mixedCardio
        }
    }

    private func emitMetrics(
        heartRateBPM: Int?,
        activeEnergyKilocalories: Double?,
        elapsedTime: TimeInterval,
        capturedAt: Date
    ) async {
        guard let currentWorkoutID else { return }
        let metrics = LiveWorkoutMetrics(
            workoutID: currentWorkoutID,
            heartRateBPM: heartRateBPM,
            activeEnergyKilocalories: activeEnergyKilocalories,
            elapsedTime: elapsedTime,
            capturedAt: capturedAt
        )
        await metricsHub.yield(metrics)
    }

    private static func heartRateBPM(from builder: HKLiveWorkoutBuilder) -> Int? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let quantity = builder.statistics(for: heartRateType)?.mostRecentQuantity()
        else { return nil }

        let unit = HKUnit.count().unitDivided(by: .minute())
        return Int(quantity.doubleValue(for: unit).rounded())
    }

    private static func activeEnergyKilocalories(from builder: HKLiveWorkoutBuilder) -> Double? {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let quantity = builder.statistics(for: energyType)?.sumQuantity()
        else { return nil }

        return quantity.doubleValue(for: .kilocalorie())
    }

    private func clearWorkoutSession(builder: HKLiveWorkoutBuilder) {
        builder.delegate = nil
        self.session = nil
        self.builder = nil
        self.currentWorkoutID = nil
    }
    #endif
}
#endif

public struct UnavailableHealthStore: HealthStore {
    public init() {}

    public var isAuthorized: Bool {
        get async { false }
    }

    public func requestAuthorization() async throws -> HealthAuthorizationResult {
        HealthAuthorizationResult(canShareWorkouts: false, requestedReadIdentifiers: [])
    }
    public func startWorkoutSession(activityType: WorkoutActivityType) async throws {}
    public func endWorkoutSession() async throws {}
}

public struct HealthBackgroundUpdate: Sendable {
    public let workoutID: String
    public init(workoutID: String) { self.workoutID = workoutID }
}

public enum HealthNotifications {
    public static let backgroundWorkoutDidArrive = Notification.Name("VolumeArc.HealthNotifications.backgroundWorkoutDidArrive")
    public static let backgroundWorkoutUserInfoKey = "backgroundWorkoutUpdate"
}
