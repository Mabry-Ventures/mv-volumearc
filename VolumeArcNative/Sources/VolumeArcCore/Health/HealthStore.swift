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

        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        var typesToRead: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            typesToRead.insert(heartRate)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            typesToRead.insert(activeEnergy)
        }

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        return true
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
