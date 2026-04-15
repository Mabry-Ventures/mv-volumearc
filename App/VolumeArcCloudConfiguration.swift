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

    /// VOL-59 fixup: `true` when the current build can safely call
    /// `CKContainer(identifier:)` without crashing.
    ///
    /// `CKContainer.init` traps the process (SIGTRAP / brk 1) if the
    /// calling binary's effective entitlements don't include the
    /// requested container. Simulator builds with
    /// `CODE_SIGNING_ALLOWED = NO` never carry the
    /// `com.apple.developer.icloud-services` entitlement — that's the
    /// path every local/CI Debug build takes — so CloudKit attachment
    /// would crash `VolumeArcApp.init()` at launch. Real device builds
    /// (TestFlight / App Store / development with a provisioning
    /// profile) embed the entitlement and work normally.
    ///
    /// The cleanest runtime signal for "is this a CODE_SIGNING_ALLOWED=NO
    /// simulator build" is `targetEnvironment(simulator)` combined with
    /// a `#if DEBUG` check: sim Debug builds are unsigned, sim Release
    /// builds from a provisioning profile *could* work in principle,
    /// and device builds always carry entitlements via their profile.
    /// Since we don't currently ship sim Release builds with
    /// provisioning profiles, treating any simulator build as
    /// "unentitled" is correct for everything we actually ship.
    static var hasCloudKitEntitlement: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
}
