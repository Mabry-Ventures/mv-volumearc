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

    // MARK: - Complication Configuration

    /// How often to refresh complications (in seconds)
    static let complicationRefreshInterval: TimeInterval = 900  // 15 minutes

    // MARK: - Feature Flags

    /// Whether complications are enabled
    static let isComplicationsEnabled = true
}
