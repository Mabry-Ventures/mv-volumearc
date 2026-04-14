import Foundation

enum VolumeArcCloudConfiguration {
    static let syncZoneName = "VolumeArcSyncZone"

    /// VOL-55: the container identifier used to live in Info.plist as a
    /// custom `VolumeArcCloudKitContainer` key read via
    /// `Bundle.main.object(forInfoDictionaryKey:)`. That approach failed
    /// because `INFOPLIST_KEY_*` silently drops custom (non-Apple-known)
    /// keys, so the built bundle never actually had the value. The
    /// plist-file workaround caused iOS 26 launch crashes, and the
    /// Run Script patching approach also triggered launch crashes
    /// in CI. The container ID is bound to the app's bundle ID and never
    /// varies at runtime, so hardcoding it as a constant is both simpler
    /// and more reliable than any of the plist approaches.
    static let containerIdentifier: String = "iCloud.com.mabryventures.VolumeArc"

    /// Kept as an optional return so the rest of the codebase doesn't
    /// have to change shape. The value is always non-nil now.
    static var configuredContainerIdentifier: String? {
        containerIdentifier
    }

    static var startupWarning: String? {
        // Always configured now that it's a compile-time constant.
        nil
    }
}
