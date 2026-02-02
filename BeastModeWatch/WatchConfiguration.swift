// WatchConfiguration.swift
// BeastModeWatch
// Centralized configuration constants for the watch app
// Note: This mirrors AppConfiguration.swift from the iOS app for shared constants

import Foundation

/// Centralized configuration for watch app constants
enum WatchConfiguration {

    // MARK: - App Groups

    /// App Group identifier for sharing data between iOS app and Watch
    /// Must match AppConfiguration.appGroupIdentifier in the iOS app
    static let appGroupIdentifier = "group.com.beastmode.app"

    /// User defaults suite for shared data
    static var sharedUserDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    /// Container URL for shared files
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    // MARK: - Data Keys

    /// Key for complication data in shared user defaults
    static let complicationDataKey = "complicationData"

    /// Key for pending workout sessions awaiting sync
    static let pendingWorkoutsKey = "pendingWatchWorkouts"

    /// Key for exercise templates synced from iPhone
    static let exerciseTemplatesKey = "exerciseTemplates"

    /// Key for last used weights per exercise
    static let lastUsedWeightsKey = "lastUsedWeights"

    /// Key for workout settings
    static let workoutSettingsKey = "workoutSettings"

    // MARK: - Workout Configuration

    /// Default weight increment for Digital Crown (in lbs)
    static let defaultWeightIncrement: Double = 5.0

    /// Maximum pending workouts to store locally
    static let maxPendingWorkouts = 50

    /// Auto-end workout after inactivity (in seconds)
    static let workoutInactivityTimeout: TimeInterval = 3600  // 1 hour

    // MARK: - Complication Configuration

    /// How often to refresh complications (in seconds)
    static let complicationRefreshInterval: TimeInterval = 900  // 15 minutes

    // MARK: - Feature Flags

    /// Whether complications are enabled
    static let isComplicationsEnabled = true

    /// Whether independent workout logging is enabled
    static let isIndependentWorkoutEnabled = true

    /// Whether HealthKit workout tracking is enabled
    static let isHealthKitWorkoutEnabled = true

    // MARK: - WatchConnectivity

    /// Message keys for WatchConnectivity
    enum MessageKey {
        static let type = "type"
        static let payload = "payload"
        static let timestamp = "timestamp"
        static let workoutIds = "workoutIds"
        static let success = "success"
        static let error = "error"
    }
}
