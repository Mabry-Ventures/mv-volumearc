// AppConfiguration.swift
// BeastMode
// Centralized configuration constants for the app

import Foundation

/// Centralized configuration for app-wide constants
enum AppConfiguration {

    // MARK: - Bundle Identifiers

    /// Main app bundle identifier
    static let bundleIdentifier = "com.beastmode.app"

    /// Watch app bundle identifier
    static let watchBundleIdentifier = "com.beastmode.app.watchkitapp"

    // MARK: - App Groups

    /// App Group identifier for sharing data between iOS app and Watch
    static let appGroupIdentifier = "group.com.beastmode.app"

    /// User defaults suite for shared data
    static var sharedUserDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    /// Container URL for shared files
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    // MARK: - Keychain

    /// Team identifier - MUST be set to your Apple Developer Team ID
    /// Find this in your Apple Developer account under Membership Details
    static let teamIdentifier: String = {
        // Read from Info.plist or use environment at build time
        if let teamId = Bundle.main.object(forInfoDictionaryKey: "DevelopmentTeam") as? String,
           !teamId.isEmpty, teamId != "XXXXXXXXXX" {
            return teamId
        }
        #if DEBUG
        // In debug, warn but don't crash
        assertionFailure("Team identifier not configured. Set DevelopmentTeam in Info.plist or update AppConfiguration.swift")
        return "DEVELOPMENT"
        #else
        fatalError("Team identifier must be configured for production builds")
        #endif
    }()

    /// Keychain access group for shared credentials
    static var keychainAccessGroup: String {
        "\(teamIdentifier).com.beastmode.shared"
    }

    // MARK: - API Configuration

    /// Anthropic API base URL
    static let anthropicAPIBaseURL = "https://api.anthropic.com/v1/messages"

    /// API version header value
    static let anthropicAPIVersion = "2023-06-01"

    /// Default AI model
    static let defaultAIModel = "claude-sonnet-4-20250514"

    // MARK: - Feature Flags

    /// Whether AI coaching features are enabled
    static let isAICoachingEnabled = true

    /// Whether HealthKit integration is enabled
    static let isHealthKitEnabled = true

    /// Whether CloudKit sync is enabled
    static let isCloudKitSyncEnabled = false  // Not yet implemented

    // MARK: - Cache Configuration

    /// AI response cache expiration in seconds
    static let aiResponseCacheExpiration: TimeInterval = 3600  // 1 hour

    /// Maximum number of cached AI responses
    static let maxCachedAIResponses = 50

    // MARK: - Limits

    /// Maximum workout duration before auto-finish prompt (in seconds)
    static let maxWorkoutDuration: TimeInterval = 14400  // 4 hours

    /// Maximum rest timer duration (in seconds)
    static let maxRestTimerDuration: TimeInterval = 600  // 10 minutes

    /// Maximum exercises per workout
    static let maxExercisesPerWorkout = 50

    /// Maximum sets per exercise
    static let maxSetsPerExercise = 20

    // MARK: - Deep Links

    /// URL scheme for deep links
    static let urlScheme = "beastmode"

    /// Universal link domain
    static let universalLinkDomain = "beastmode.app"

    // MARK: - Support

    /// Support email address
    static let supportEmail = "support@beastmode.app"

    /// Privacy policy URL
    static var privacyPolicyURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://beastmode.app/privacy")!
    }

    /// Terms of service URL
    static var termsOfServiceURL: URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://beastmode.app/terms")!
    }

    /// Support URL for contacting help
    static var supportURL: URL? {
        URL(string: "mailto:\(supportEmail)")
    }
}

// MARK: - Debug Configuration

#if DEBUG
extension AppConfiguration {
    /// Whether to use mock data in previews and tests
    static let useMockData = true

    /// Whether to log verbose debug information
    static let verboseLogging = true

    /// Whether to skip authentication in debug mode
    static let skipAuthentication = false
}
#endif
