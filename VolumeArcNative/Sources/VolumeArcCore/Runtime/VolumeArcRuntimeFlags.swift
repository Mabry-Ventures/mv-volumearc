import Foundation

public enum VolumeArcRuntimeFlags {
    private static let deterministicModeKey = "com.mabryventures.VolumeArc.runtime.deterministicMode"
    private static let performanceTestModeKey = "com.mabryventures.VolumeArc.runtime.performanceTestMode"

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
}
