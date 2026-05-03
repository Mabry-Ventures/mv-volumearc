#if canImport(Sentry)
import XCTest

// `VolumeArcSentryConfiguration` is compiled directly into the test
// bundle (its source file is added to the test target's Sources build
// phase by `scripts/generate_xcode_project.rb`), so its `internal` symbols
// are accessible without `@testable import`. Mirrors the pattern used by
// `VolumeArcSentryPIIScrubberTests`.

/// VOL-129. Asserts the release-identifier format that
/// `VolumeArcSentryConfiguration.bootstrapIfNeeded()` passes to
/// `SentrySDK.start { options in options.releaseName = ... }`.
///
/// `SentrySDK.start` is global state that we intentionally don't unit-test
/// directly — the bootstrap is exercised in production at app launch. But
/// `computeReleaseName(bundle:)` is a pure function, so we can verify the
/// string shape against synthetic bundles here. Keeping the format under
/// test prevents a refactor from quietly breaking the dSYM-to-event
/// release correlation in Sentry.
final class VolumeArcSentryConfigurationTests: XCTestCase {
    func testReleaseNameUsesBundleIdMarketingAndBuildNumber() {
        let bundle = StubBundle(
            bundleId: "com.mabryventures.VolumeArc",
            marketingVersion: "1.0.2",
            buildNumber: "12345"
        )

        let release = VolumeArcSentryConfiguration.computeReleaseName(bundle: bundle)

        XCTAssertEqual(release, "com.mabryventures.VolumeArc@1.0.2+12345")
    }

    func testReleaseNameFallsBackWhenBundleIdMissing() {
        let bundle = StubBundle(
            bundleId: nil,
            marketingVersion: "1.0.2",
            buildNumber: "12345"
        )

        let release = VolumeArcSentryConfiguration.computeReleaseName(bundle: bundle)

        XCTAssertEqual(release, "com.mabryventures.VolumeArc@1.0.2+12345")
    }

    func testReleaseNameFallsBackWhenMarketingVersionMissing() {
        let bundle = StubBundle(
            bundleId: "com.mabryventures.VolumeArc",
            marketingVersion: nil,
            buildNumber: "12345"
        )

        let release = VolumeArcSentryConfiguration.computeReleaseName(bundle: bundle)

        XCTAssertEqual(release, "com.mabryventures.VolumeArc@0.0.0+12345")
    }

    func testReleaseNameFallsBackWhenBuildNumberMissing() {
        let bundle = StubBundle(
            bundleId: "com.mabryventures.VolumeArc",
            marketingVersion: "1.0.2",
            buildNumber: nil
        )

        let release = VolumeArcSentryConfiguration.computeReleaseName(bundle: bundle)

        XCTAssertEqual(release, "com.mabryventures.VolumeArc@1.0.2+0")
    }
}

/// Test-only bundle subclass that returns synthetic Info.plist values
/// without touching the real on-disk bundle. Mirrors the pattern used in
/// `VolumeArcAppConfigurationTests`.
private final class StubBundle: Bundle {
    private let stubBundleId: String?
    private let stubInfo: [String: Any]

    init(bundleId: String?, marketingVersion: String?, buildNumber: String?) {
        self.stubBundleId = bundleId
        var info: [String: Any] = [:]
        if let marketingVersion {
            info["CFBundleShortVersionString"] = marketingVersion
        }
        if let buildNumber {
            info["CFBundleVersion"] = buildNumber
        }
        self.stubInfo = info
        // Re-using Bundle.main's bundleURL is enough for super.init; we
        // override every method we read from below.
        super.init(url: Bundle.main.bundleURL)!
    }

    override var bundleIdentifier: String? {
        stubBundleId
    }

    override func object(forInfoDictionaryKey key: String) -> Any? {
        stubInfo[key]
    }
}
#endif
