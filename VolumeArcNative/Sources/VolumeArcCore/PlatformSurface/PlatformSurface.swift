import Foundation

public protocol PlatformSurfaceStateStore: Sendable {}

public struct UserDefaultsPlatformSurfaceStateStore: PlatformSurfaceStateStore {
    public init() {}
}

public enum PlatformSurfaceNotifications {
    public static let widgetSnapshotDidChange = Notification.Name("VolumeArc.PlatformSurface.widgetSnapshotDidChange")
    public static let liveActivityDidChange = Notification.Name("VolumeArc.PlatformSurface.liveActivityDidChange")
    public static let liveActivityDidEnd = Notification.Name("VolumeArc.PlatformSurface.liveActivityDidEnd")
    public static let liveActivityUserInfoKey = "liveActivityState"
}

public struct LiveActivityState: Sendable {
    public let workoutTitle: String
    public let activeExerciseName: String
    public let targetSummary: String
    public let restSecondsRemaining: Int?

    public init(workoutTitle: String, activeExerciseName: String, targetSummary: String, restSecondsRemaining: Int?) {
        self.workoutTitle = workoutTitle
        self.activeExerciseName = activeExerciseName
        self.targetSummary = targetSummary
        self.restSecondsRemaining = restSecondsRemaining
    }
}

#if canImport(ActivityKit)
import ActivityKit

public struct ActiveWorkoutAttributes: ActivityAttributes {
    public let workoutTitle: String

    public init(workoutTitle: String) {
        self.workoutTitle = workoutTitle
    }

    public struct ContentState: Codable, Hashable {
        public let activeExerciseName: String
        public let targetSummary: String
        public let restSecondsRemaining: Int?

        public init(activeExerciseName: String, targetSummary: String, restSecondsRemaining: Int?) {
            self.activeExerciseName = activeExerciseName
            self.targetSummary = targetSummary
            self.restSecondsRemaining = restSecondsRemaining
        }
    }
}
#endif

public struct WidgetSummarySnapshot: Sendable {
    public let nextWorkoutTitle: String
    public let readinessScore: String
    public let primaryLiftForecast: String
    public let nextActionTitle: String
    public let syncSummary: String
    public let streakDays: Int
    public let coachPrompt: String

    public init(
        nextWorkoutTitle: String,
        readinessScore: String,
        primaryLiftForecast: String,
        nextActionTitle: String,
        syncSummary: String,
        streakDays: Int,
        coachPrompt: String
    ) {
        self.nextWorkoutTitle = nextWorkoutTitle
        self.readinessScore = readinessScore
        self.primaryLiftForecast = primaryLiftForecast
        self.nextActionTitle = nextActionTitle
        self.syncSummary = syncSummary
        self.streakDays = streakDays
        self.coachPrompt = coachPrompt
    }
}

public enum PlatformSurfaceDefaultsReader {
    public static func loadWidgetSnapshot() -> WidgetSummarySnapshot? { nil }
    public static func loadLiveActivityState() -> LiveActivityState? { nil }
}

public enum PlatformSurfaceFactory {
    public static func makeEmptyWidgetSnapshot() -> WidgetSummarySnapshot {
        WidgetSummarySnapshot(
            nextWorkoutTitle: "No Workout Scheduled",
            readinessScore: "--",
            primaryLiftForecast: "Open VolumeArc to get started.",
            nextActionTitle: "Start",
            syncSummary: "Not synced",
            streakDays: 0,
            coachPrompt: "What should I do next?"
        )
    }
}
