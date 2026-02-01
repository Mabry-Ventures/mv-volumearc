import Foundation

/// App-wide configuration and environment settings
enum Configuration {
    // MARK: - API Keys

    /// Claude API key for AI coaching features
    /// In production, this should be fetched from a secure source
    static var claudeAPIKey: String {
        // Try to read from environment or Info.plist
        if let key = ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] {
            return key
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "CLAUDE_API_KEY") as? String {
            return key
        }
        return ""
    }

    /// TelemetryDeck app ID for privacy-focused analytics
    static var telemetryDeckAppID: String {
        if let appID = ProcessInfo.processInfo.environment["TELEMETRYDECK_APP_ID"] {
            return appID
        }
        if let appID = Bundle.main.object(forInfoDictionaryKey: "TELEMETRYDECK_APP_ID") as? String {
            return appID
        }
        // Replace with your TelemetryDeck App ID
        return ""
    }

    // MARK: - CloudKit

    static let cloudKitContainerIdentifier = "iCloud.com.beastmode.BeastMode"

    // MARK: - App Group

    static let appGroupIdentifier = "group.com.beastmode.BeastMode"

    // MARK: - Feature Flags

    static let isAICoachEnabled = true
    static let isHealthKitEnabled = true
    static let isWatchSyncEnabled = true
    static let isAnalyticsEnabled = true

    // MARK: - Default Values

    static let defaultRestTimerDuration: TimeInterval = 90
    static let debounceInterval: TimeInterval = 0.5
    static let maxSetsPerExercise = 10
    static let maxReps = 100
    static let maxWeight: Double = 2000

    // MARK: - Animation Durations

    static let quickAnimationDuration: Double = 0.2
    static let standardAnimationDuration: Double = 0.3
    static let slowAnimationDuration: Double = 0.5
}

// MARK: - Build Configuration

extension Configuration {
    enum BuildType {
        case debug
        case release
    }

    static var buildType: BuildType {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    static var isDebug: Bool {
        buildType == .debug
    }
}
