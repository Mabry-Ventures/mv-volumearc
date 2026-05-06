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

    /// `true` when the current binary's embedded entitlements actually
    /// grant CloudKit access — `CKContainer(identifier:)` traps the
    /// process (SIGTRAP / brk 1) without it.
    ///
    /// Implementation history:
    ///
    /// 1. **Original (VOL-59):** static `targetEnvironment(simulator)`
    ///    heuristic. Returned `true` on every real-device build,
    ///    which crashed rc9 / Build 6 when Xcode Cloud's signing
    ///    didn't embed the iCloud entitlement.
    ///
    /// 2. **First runtime probe (rc10 hotfix, #118):** parsed the
    ///    binary's `embedded.mobileprovision`. App launched on rc10
    ///    + rc11 but rc11's `embedded.mobileprovision` was *missing
    ///    entirely*: Xcode Cloud archives strip the provisioning
    ///    profile and bake entitlements straight into the Mach-O
    ///    code signature, so the probe always returned `false` even
    ///    after #120 actually started embedding the entitlement.
    ///    Diagnostics view kept showing the "no entitlement"
    ///    warning even though sync should have worked.
    ///
    /// 3. **`SecStaticCode` attempt:** would have read entitlements
    ///    out of the binary's signature, but `SecStaticCodeCreateWithPath`
    ///    is SPI on iOS (only public on macOS). Same goes for
    ///    `SecTaskCopyValueForEntitlement`. Apple gives no public iOS
    ///    API for self-introspection of code-signature entitlements.
    ///
    /// 4. **Current (this file):** byte-pattern scan of the running
    ///    executable. The Mach-O `LC_CODE_SIGNATURE` blob stores
    ///    entitlements as inline XML (a `CSMAGIC_EMBEDDED_ENTITLEMENTS`
    ///    super-blob), so the literal string
    ///    `<key>com.apple.developer.icloud-services</key>` paired with
    ///    `<string>CloudKit</string>` appears verbatim in the binary
    ///    file when the entitlement is signed in. No SPI required —
    ///    `Bundle.main.executableURL` is iOS-public, and reading the
    ///    file is plain Foundation I/O. ~5 MB read at startup, cached
    ///    for the lifetime of the process.
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
    /// of a process.
    private static let cachedEntitlement: Bool = scanExecutableForCloudKitEntitlement()

    private static func runtimeHasCloudKitEntitlement() -> Bool {
        cachedEntitlement
    }

    /// Scan the running binary for the iCloud-services / CloudKit
    /// entitlement pair. The Mach-O code-signature blob stores the
    /// entitlements plist as inline XML (UTF-8), so the canonical
    /// `<key>com.apple.developer.icloud-services</key>` /
    /// `<string>CloudKit</string>` pair appears verbatim in the
    /// executable file when the entitlement is granted.
    ///
    /// The bare entitlement key string also appears in the
    /// `__cstring` data section as a Swift string literal and again
    /// in a DER-encoded copy of the entitlements blob. Including the
    /// `</key>` XML closing tag in the search pattern restricts the
    /// match to the XML form so we don't have to disambiguate
    /// otherwise-collidable occurrences. The DER form lacks `</key>`
    /// (it uses ASN.1 length prefixes); the `__cstring` occurrence
    /// is followed by null bytes.
    private static func scanExecutableForCloudKitEntitlement() -> Bool {
        guard let executable = Bundle.main.executableURL,
              let data = try? Data(contentsOf: executable, options: [.mappedIfSafe]) else {
            return false
        }
        let keyData = Data("com.apple.developer.icloud-services</key>".utf8)
        let valueData = Data("<string>CloudKit</string>".utf8)
        guard let keyRange = data.range(of: keyData) else { return false }
        // The XML value (`<array>\n\t\t<string>CloudKit</string>`)
        // appears within ~50 bytes of the key — 256 is generous.
        let windowEnd = min(keyRange.upperBound + 256, data.count)
        let window = data[keyRange.upperBound..<windowEnd]
        return window.range(of: valueData) != nil
    }
}
