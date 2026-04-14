import Foundation

public enum VolumeArcRuntimeFlags {
    private static let deterministicModeKey = "com.mabryventures.VolumeArc.runtime.deterministicMode"

    public static var isDeterministicMode: Bool {
        get { UserDefaults.standard.bool(forKey: deterministicModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: deterministicModeKey) }
    }
}
