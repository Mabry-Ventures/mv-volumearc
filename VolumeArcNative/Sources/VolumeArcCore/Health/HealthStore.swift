import Foundation

public protocol HealthStore: Sendable {}

#if canImport(HealthKit)
public struct HealthKitRuntimeStore: HealthStore {
    public init() {}
}
#endif

public struct UnavailableHealthStore: HealthStore {
    public init() {}
}

public struct HealthBackgroundUpdate: Sendable {
    public let workoutID: String
    public init(workoutID: String) { self.workoutID = workoutID }
}

public enum HealthNotifications {
    public static let backgroundWorkoutDidArrive = Notification.Name("VolumeArc.HealthNotifications.backgroundWorkoutDidArrive")
    public static let backgroundWorkoutUserInfoKey = "backgroundWorkoutUpdate"
}
