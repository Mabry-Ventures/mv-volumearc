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

// MARK: - LiveActivityState

public struct LiveActivityState: Sendable, Codable {
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

// MARK: - WidgetSummarySnapshot

public struct WidgetSummarySnapshot: Sendable, Codable {
    public let nextWorkoutTitle: String
    public let readinessScore: String
    public let primaryLiftForecast: String
    public let nextActionTitle: String
    public let syncSummary: String
    public let streakDays: Int
    public let coachPrompt: String
    public let updatedAt: Date

    public init(
        nextWorkoutTitle: String,
        readinessScore: String,
        primaryLiftForecast: String,
        nextActionTitle: String,
        syncSummary: String,
        streakDays: Int,
        coachPrompt: String,
        updatedAt: Date = .now
    ) {
        self.nextWorkoutTitle = nextWorkoutTitle
        self.readinessScore = readinessScore
        self.primaryLiftForecast = primaryLiftForecast
        self.nextActionTitle = nextActionTitle
        self.syncSummary = syncSummary
        self.streakDays = streakDays
        self.coachPrompt = coachPrompt
        self.updatedAt = updatedAt
    }
}

// MARK: - Shared state bridge

/// App Group identifier shared between the app, watch, and widgets.
public enum PlatformSurfaceSharedStorage {
    public static let appGroupID = "group.com.mabryventures.volumearc"
    public static let widgetSnapshotKey = "widgetSummarySnapshot"
    public static let liveActivityStateKey = "liveActivityState"

    /// Returns the shared UserDefaults instance for the app group,
    /// or `.standard` as a fallback if the app group isn't entitled.
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

/// Reads shared state from the app group container.
public enum PlatformSurfaceDefaultsReader {
    /// Returns the last widget snapshot the app wrote to shared storage, or nil if none.
    public static func loadWidgetSnapshot() -> WidgetSummarySnapshot? {
        let defaults = PlatformSurfaceSharedStorage.defaults
        guard let data = defaults.data(forKey: PlatformSurfaceSharedStorage.widgetSnapshotKey),
              let decoded = try? JSONDecoder().decode(WidgetSummarySnapshot.self, from: data)
        else {
            return nil
        }
        return decoded
    }

    /// Returns the last live activity state the app wrote to shared storage, or nil if none.
    public static func loadLiveActivityState() -> LiveActivityState? {
        let defaults = PlatformSurfaceSharedStorage.defaults
        guard let data = defaults.data(forKey: PlatformSurfaceSharedStorage.liveActivityStateKey),
              let decoded = try? JSONDecoder().decode(LiveActivityState.self, from: data)
        else {
            return nil
        }
        return decoded
    }
}

/// Writes shared state to the app group container. Call from the main app target
/// whenever workout state changes.
public enum PlatformSurfaceDefaultsWriter {
    /// Persist a widget snapshot and post the change notification.
    public static func saveWidgetSnapshot(_ snapshot: WidgetSummarySnapshot) {
        let defaults = PlatformSurfaceSharedStorage.defaults
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: PlatformSurfaceSharedStorage.widgetSnapshotKey)
        }
        NotificationCenter.default.post(
            name: PlatformSurfaceNotifications.widgetSnapshotDidChange,
            object: nil
        )
    }

    /// Persist a live activity state and post the change notification.
    public static func saveLiveActivityState(_ state: LiveActivityState) {
        let defaults = PlatformSurfaceSharedStorage.defaults
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: PlatformSurfaceSharedStorage.liveActivityStateKey)
        }
        NotificationCenter.default.post(
            name: PlatformSurfaceNotifications.liveActivityDidChange,
            object: nil,
            userInfo: [PlatformSurfaceNotifications.liveActivityUserInfoKey: state]
        )
    }

    /// Clear the live activity state and post the end notification.
    public static func clearLiveActivityState() {
        let defaults = PlatformSurfaceSharedStorage.defaults
        defaults.removeObject(forKey: PlatformSurfaceSharedStorage.liveActivityStateKey)
        NotificationCenter.default.post(
            name: PlatformSurfaceNotifications.liveActivityDidEnd,
            object: nil
        )
    }
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
