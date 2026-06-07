import Foundation

public enum VolumeArcRuntimeFlags {
    private static let deterministicModeKey = "com.mabryventures.VolumeArc.runtime.deterministicMode"
    private static let performanceTestModeKey = "com.mabryventures.VolumeArc.runtime.performanceTestMode"
    private static let simulatePermissionPromptsKey = "com.mabryventures.VolumeArc.runtime.simulatePermissionPrompts"
    private static let suppressSubscriptionManageExternalURLKey =
        "com.mabryventures.VolumeArc.runtime.suppressSubscriptionManageExternalURL"
    private static let restTimerDurationOverrideKey =
        "com.mabryventures.VolumeArc.runtime.restTimerDurationOverride"
    private static let voicePromptTranscriptFixtureKey =
        "com.mabryventures.VolumeArc.runtime.voicePromptTranscriptFixture"

    public static var isDeterministicMode: Bool {
        get { UserDefaults.standard.bool(forKey: deterministicModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: deterministicModeKey) }
    }

    /// VOL-99: when true, the dashboard fetches a larger session history
    /// and the Today tab renders the full recent-session list so
    /// `VolumeArcPerfTests` can scroll a realistic number of rows when
    /// measuring frame rate and hitches. Set by the app at launch when
    /// `-PerfTestMode 1` is passed.
    public static var isPerformanceTestMode: Bool {
        get { UserDefaults.standard.bool(forKey: performanceTestModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: performanceTestModeKey) }
    }

    /// VOL-109: when true, permission-prompt sites surface the actual
    /// system dialog (HealthKit, Notifications, etc.) instead of being
    /// short-circuited by `isDeterministicMode`. Used by the
    /// `VolumeArcHealthKitPermissionJourneyTests` XCUITest suite to drive
    /// the prompt path with `addUIInterruptionMonitor`. Off in production
    /// and in regular `-UITestMode 1` runs.
    ///
    /// Contract: a permission-prompt call site MUST honor
    /// `isDeterministicMode && !simulatePermissionPrompts` as the "skip
    /// the prompt" predicate. With both flags on (`-UITestMode 1
    /// -SimulatePermissionPrompts 1`), the prompt fires and the test can
    /// drive it; with only `-UITestMode 1`, the prompt is skipped exactly
    /// like every existing journey test expects.
    public static var simulatePermissionPrompts: Bool {
        get { UserDefaults.standard.bool(forKey: simulatePermissionPromptsKey) }
        set { UserDefaults.standard.set(newValue, forKey: simulatePermissionPromptsKey) }
    }

    /// VOL-271: deterministic UI tests prove the premium "Manage"
    /// subscription tap path without leaving the host app for App Store /
    /// Settings. Production leaves this false, so the Profile action opens
    /// the Apple subscription-management URL after recording telemetry.
    public static var suppressSubscriptionManageExternalURL: Bool {
        get { UserDefaults.standard.bool(forKey: suppressSubscriptionManageExternalURLKey) }
        set { UserDefaults.standard.set(newValue, forKey: suppressSubscriptionManageExternalURLKey) }
    }

    /// VOL-271: deterministic UI tests can shorten the active-session
    /// rest timer without changing the athlete-facing production
    /// default. The app target only sets this from `-UITestMode 1`
    /// launches; `nil` means use the standard 90-second rest.
    public static var restTimerDurationOverride: TimeInterval? {
        get {
            let value = UserDefaults.standard.double(forKey: restTimerDurationOverrideKey)
            return value > 0 ? value : nil
        }
        set {
            if let newValue, newValue > 0 {
                UserDefaults.standard.set(newValue, forKey: restTimerDurationOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: restTimerDurationOverrideKey)
            }
        }
    }

    /// VOL-271: deterministic voice-journey tests can inject the text
    /// that a speech-recognition pass would have produced. Production
    /// leaves this nil and relies on the user's typed or dictated prompt.
    public static var voicePromptTranscriptFixture: String? {
        get {
            guard let value = UserDefaults.standard.string(forKey: voicePromptTranscriptFixtureKey),
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return value
        }
        set {
            if let newValue,
               !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserDefaults.standard.set(newValue, forKey: voicePromptTranscriptFixtureKey)
            } else {
                UserDefaults.standard.removeObject(forKey: voicePromptTranscriptFixtureKey)
            }
        }
    }

    /// VOL-109: convenience predicate for permission-prompt call sites.
    /// `true` when the site should fire the system prompt; `false` when
    /// it should silently no-op (test mode without simulation flag, or
    /// production paths that are intentionally bypassed elsewhere).
    public static var shouldSurfacePermissionPrompts: Bool {
        if !isDeterministicMode {
            return true
        }
        return simulatePermissionPrompts
    }
}

public enum OnboardingProgressStore {
    private static let stepKey = "com.mabryventures.VolumeArc.onboarding.stepRaw"
    private static let resultKey = "com.mabryventures.VolumeArc.onboarding.resultData"

    public static func loadStepRaw() -> Int? {
        guard UserDefaults.standard.object(forKey: stepKey) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: stepKey)
    }

    public static func saveStepRaw(_ rawValue: Int) {
        UserDefaults.standard.set(rawValue, forKey: stepKey)
    }

    public static func loadResultData() -> Data? {
        UserDefaults.standard.data(forKey: resultKey)
    }

    public static func saveResultData(_ data: Data) {
        UserDefaults.standard.set(data, forKey: resultKey)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: stepKey)
        UserDefaults.standard.removeObject(forKey: resultKey)
    }
}

public enum CoachStreamRecoveryStore {
    private static let inFlightKey = "com.mabryventures.VolumeArc.coach.streamInFlight"
    private static let lock = NSLock()

    public static func markInFlight() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.set(true, forKey: inFlightKey)
        UserDefaults.standard.synchronize()
    }

    public static func clear() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: inFlightKey)
        UserDefaults.standard.synchronize()
    }

    @discardableResult
    public static func consumeAbortedStream() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasInFlight = UserDefaults.standard.bool(forKey: inFlightKey)
        if wasInFlight {
            UserDefaults.standard.removeObject(forKey: inFlightKey)
            UserDefaults.standard.synchronize()
        }
        return wasInFlight
    }
}
