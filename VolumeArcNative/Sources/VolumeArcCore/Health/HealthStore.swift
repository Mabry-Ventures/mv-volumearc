import Foundation

public protocol HealthStore: Sendable {
    /// Request authorization for workout tracking.
    func requestAuthorization() async throws -> Bool

    /// Whether HealthKit is available and authorized on this device.
    var isAuthorized: Bool { get async }

    /// Start a HealthKit workout session (watchOS only on real devices).
    func startWorkoutSession(activityType: WorkoutActivityType) async throws

    /// End the current workout session and save to HealthKit.
    func endWorkoutSession() async throws
}

public enum WorkoutActivityType: String, Sendable {
    case strengthTraining
    case functionalStrengthTraining
    case coreTraining
    case mixedCardio
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

public final class HealthKitRuntimeStore: HealthStore, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    #if os(watchOS)
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    #endif

    public init() {}

    public var isAuthorized: Bool {
        get async {
            guard HKHealthStore.isHealthDataAvailable() else { return false }
            let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            return status == .sharingAuthorized
        }
    }

    public func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

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
        #else
        let typesToRead = Self.phoneReadTypes()
        #endif

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        return true
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
        #if os(watchOS)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = mapActivityType(activityType)
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

        self.session = session
        self.builder = builder

        session.startActivity(with: Date.now)
        try await builder.beginCollection(at: Date.now)
        #endif
    }

    public func endWorkoutSession() async throws {
        #if os(watchOS)
        guard let session, let builder else { return }
        session.end()
        try await builder.endCollection(at: Date.now)
        _ = try await builder.finishWorkout()
        self.session = nil
        self.builder = nil
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
    #endif
}
#endif

public struct UnavailableHealthStore: HealthStore {
    public init() {}

    public var isAuthorized: Bool {
        get async { false }
    }

    public func requestAuthorization() async throws -> Bool { false }
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
