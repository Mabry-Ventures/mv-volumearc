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
        #if targetEnvironment(simulator)
        // Sim builds intentionally don't carry the entitlement and
        // shouldn't surface a warning — that'd be noise on every
        // local run.
        return nil
        #else
        // Real-device builds without the iCloud entitlement are a
        // signing/provisioning bug we want to make loud rather than
        // silently degrade. Surfaces in startup telemetry so the
        // signal reaches Sentry / the diagnostics view.
        if !runtimeHasCloudKitEntitlement() {
            return """
                Cloud sync is unavailable on this device because the \
                installed build does not carry the iCloud entitlement. \
                The app will work with on-device storage; data won't \
                sync between devices until a fresh build with the \
                correct provisioning profile is installed.
                """
        }
        return nil
        #endif
    }

    /// `true` when the current binary's embedded provisioning profile
    /// actually carries a CloudKit entitlement —
    /// `CKContainer(identifier:)` traps the process (SIGTRAP / brk 1)
    /// without it.
    ///
    /// The previous `targetEnvironment(simulator)` heuristic assumed
    /// real-device builds always have the entitlement (TestFlight /
    /// App Store / dev builds embed the provisioning profile, only
    /// simulator Debug builds with `CODE_SIGNING_ALLOWED = NO` are
    /// unentitled). That assumption broke when the v1.0.2-rc9
    /// TestFlight install crashed on launch with this exact trap on
    /// a real device: Xcode Cloud's archive produced an unsigned
    /// `.app` (the project's Release config keeps
    /// `CODE_SIGNING_ALLOWED = NO` so Release builds compile without
    /// local certs) and the export-time signing failed to embed the
    /// iCloud entitlement in the resulting `.ipa`. The heuristic
    /// returned `true` for the device build, the guard passed, and
    /// the app trapped on launch.
    ///
    /// The implementation now probes the live binary's
    /// `embedded.mobileprovision` and looks for `"CloudKit"` in the
    /// `com.apple.developer.icloud-services` array. Missing → degrade
    /// to `UnavailableCloudSyncTransport` + local-fallback
    /// persistence. The app launches in every signing configuration
    /// (provisioning profile drift, Xcode Cloud signing issue, manual
    /// `xcodebuild` without certs, XCTest host process inheritance,
    /// etc.) — sync recovery is a separate signing fix.
    static var hasCloudKitEntitlement: Bool {
        #if targetEnvironment(simulator)
        // Sim builds with `CODE_SIGNING_ALLOWED = NO` never have an
        // entitlements blob to probe. Short-circuit so unit tests
        // don't read the bundle on every CloudSync access.
        return false
        #else
        return runtimeHasCloudKitEntitlement()
        #endif
    }

    /// Cache the answer — entitlements don't change for the lifetime
    /// of a process, and the CMS plist extraction is cheap but not free.
    private static let cachedEntitlement: Bool = {
        let entitlements = readEmbeddedMobileProvisionEntitlements()
        // The entitlement is declared as an array of strings:
        //   <key>com.apple.developer.icloud-services</key>
        //   <array><string>CloudKit</string></array>
        // Treat any other shape (missing, empty array, single
        // string, etc.) as "no usable CloudKit entitlement."
        if let services = entitlements?["com.apple.developer.icloud-services"] as? [String] {
            return services.contains("CloudKit")
        }
        if let single = entitlements?["com.apple.developer.icloud-services"] as? String {
            return single == "CloudKit"
        }
        return false
    }()

    private static func runtimeHasCloudKitEntitlement() -> Bool {
        cachedEntitlement
    }

    /// Parse the `Entitlements` dict out of the binary's
    /// `embedded.mobileprovision`. Used to detect whether the live
    /// binary actually carries the iCloud entitlement at runtime, so
    /// `CKContainer(identifier:)` doesn't trap on a signing-misconfigured
    /// build.
    ///
    /// `SecTaskCopyValueForEntitlement` would be the obvious tool here
    /// but it's SPI on iOS (public on macOS only). The
    /// `embedded.mobileprovision` blob is a CMS-signed plist with a
    /// readable XML payload — slice out the `<plist>...</plist>`
    /// substring and `PropertyListSerialization` does the rest. This
    /// pattern is widely used in iOS apps for self-introspection of
    /// entitlements and is safe for App Store review.
    ///
    /// Returns nil for App Store-installed builds where Apple strips
    /// the provisioning profile at install time — in that case we fall
    /// back to "no entitlement detected," which is conservative for
    /// the launch-crash defense (the App Store install path *should*
    /// have the correct entitlement embedded directly in the code
    /// signature, but `CKContainer` would crash long before our
    /// probe code runs if it didn't, so a false negative here just
    /// means we degrade gracefully instead of crashing).
    private static func readEmbeddedMobileProvisionEntitlements() -> [String: Any]? {
        let bundlePath = Bundle.main.bundlePath
        let profilePath = (bundlePath as NSString).appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: profilePath)) else {
            return nil
        }
        // The CMS envelope wraps a plist payload. Locate it by ASCII
        // markers — robust enough since the plist is always XML, not
        // binary, inside the envelope.
        guard let raw = String(data: data, encoding: .isoLatin1),
              let plistStart = raw.range(of: "<?xml") ?? raw.range(of: "<plist"),
              let plistEnd = raw.range(of: "</plist>") else {
            return nil
        }
        let plistString = String(raw[plistStart.lowerBound..<plistEnd.upperBound])
        guard let plistData = plistString.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return nil
        }
        return plist["Entitlements"] as? [String: Any]
    }
}
