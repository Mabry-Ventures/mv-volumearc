import Foundation

public enum FeatureFlag: String, CaseIterable, Sendable {
    case voiceCoaching = "voice_coaching"
    case cloudSync = "cloud_sync"
    case liveActivities = "live_activities"
    case foundationModelCoach = "foundation_model_coach"
}

public protocol FeatureFlagProvider: Sendable {
    func isEnabled(_ flag: FeatureFlag) -> Bool
    func setOverride(_ flag: FeatureFlag, enabled: Bool)
    func clearOverride(_ flag: FeatureFlag)
    func clearAllOverrides()
}

public final class LocalFeatureFlagProvider: FeatureFlagProvider, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String

    /// Default values when no override is set.
    private let defaultValues: [FeatureFlag: Bool] = [
        .voiceCoaching: true,
        .cloudSync: true,
        .liveActivities: true,
        .foundationModelCoach: true,
    ]

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "com.mabryventures.VolumeArc.featureFlags."
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        let key = keyPrefix + flag.rawValue
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return defaultValues[flag] ?? true
    }

    public func setOverride(_ flag: FeatureFlag, enabled: Bool) {
        defaults.set(enabled, forKey: keyPrefix + flag.rawValue)
    }

    public func clearOverride(_ flag: FeatureFlag) {
        defaults.removeObject(forKey: keyPrefix + flag.rawValue)
    }

    public func clearAllOverrides() {
        for flag in FeatureFlag.allCases {
            clearOverride(flag)
        }
    }
}
