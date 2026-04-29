import Foundation

public enum VolumeArcRuntimeFlags {
    private static let deterministicModeKey = "com.mabryventures.VolumeArc.runtime.deterministicMode"
    private static let performanceTestModeKey = "com.mabryventures.VolumeArc.runtime.performanceTestMode"
    private static let simulatePermissionPromptsKey = "com.mabryventures.VolumeArc.runtime.simulatePermissionPrompts"

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
