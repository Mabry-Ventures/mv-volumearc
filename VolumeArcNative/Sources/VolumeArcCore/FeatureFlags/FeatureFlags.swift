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

// MARK: - Flag-gate telemetry

/// Records a one-shot `feature.flag.applied` event the first time each
/// `FeatureFlag` is resolved for a given launch so the current runtime flag
/// state is observable remotely without spamming the sink on every call.
///
/// Instances are created per gating surface (factory, coordinator, controller)
/// and keyed by `FeatureFlag`: the internal set tracks which flags have
/// already emitted an event during this process's lifetime. Subsequent
/// `recordIfFirst(…)` calls for the same flag return the resolved value but
/// suppress the telemetry emission.
///
/// VOL-61. Telemetry contract is intentionally minimal: one event per flag
/// per launch, `.info` severity, category `feature.flag.applied`, metadata
/// `{flag: "<raw value>", enabled: "true|false"}`. Category is
/// `feature.flag.applied` (not `feature.flag`) so dashboards can filter on
/// the applied-event stream without mixing in future flag-service events.
public final class FlagGateTelemetry: @unchecked Sendable {
    private let flags: FeatureFlagProvider
    private let telemetry: (any TelemetrySink)?
    private let lock = NSLock()
    private var recorded: Set<FeatureFlag> = []

    public init(
        flags: FeatureFlagProvider,
        telemetry: (any TelemetrySink)? = nil
    ) {
        self.flags = flags
        self.telemetry = telemetry
    }

    /// Return `flags.isEnabled(flag)` and, if this is the first call for that
    /// flag on this recorder, fire the `feature.flag.applied` event. Safe to
    /// call from any isolation context.
    @discardableResult
    public func recordIfFirst(_ flag: FeatureFlag) -> Bool {
        let enabled = flags.isEnabled(flag)
        let shouldEmit: Bool = {
            lock.lock()
            defer { lock.unlock() }
            return recorded.insert(flag).inserted
        }()
        if shouldEmit {
            telemetry?.record(TelemetryEvent(
                category: "feature.flag.applied",
                name: flag.rawValue,
                severity: .info,
                message: "Flag \(flag.rawValue) resolved to \(enabled) at first gate.",
                metadata: [
                    "flag": flag.rawValue,
                    "enabled": enabled ? "true" : "false",
                ]
            ))
        }
        return enabled
    }

    /// Reset the recorded set. Primarily useful for tests that want to
    /// verify the first-call emission twice in the same process.
    public func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        recorded.removeAll()
    }
}
