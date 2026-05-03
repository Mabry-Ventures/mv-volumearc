#if canImport(Sentry)
import XCTest

// `VolumeArcSentryConfiguration` is compiled directly into the test
// bundle (its source file is added to the test target's Sources build
// phase by `scripts/generate_xcode_project.rb`'s `add_selected_swift_sources`
// list — see VOL-129). Mirrors the pattern used by VOL-72's
// `VolumeArcSentryPIIScrubberTests` so its `internal` symbols are
// accessible without `@testable import`.

/// VOL-129. Asserts the release-identifier format that
/// `VolumeArcSentryConfiguration.bootstrapIfNeeded()` passes to
/// `SentrySDK.start { options in options.releaseName = ... }`.
///
/// `SentrySDK.start` is global state that we intentionally don't unit-test
/// directly. The 3-arg pure overload `computeReleaseName(bundleID:marketingVersion:buildNumber:)`
/// is what gets covered here — the `Bundle`-reading overload is a thin
/// adapter over it. Subclassing `Bundle` to fake Info.plist values trips
/// Foundation's `init(path:)` designated-initializer requirement, which
/// is why the tests target the pure form.
final class VolumeArcSentryConfigurationTests: XCTestCase {
    func testReleaseNameUsesBundleIdMarketingAndBuildNumber() {
        let release = VolumeArcSentryConfiguration.computeReleaseName(
            bundleID: "com.mabryventures.VolumeArc",
            marketingVersion: "1.0.2",
            buildNumber: "12345"
        )

        XCTAssertEqual(release, "com.mabryventures.VolumeArc@1.0.2+12345")
    }

    func testReleaseNameFallsBackWhenBundleIdMissing() {
        let release = VolumeArcSentryConfiguration.computeReleaseName(
            bundleID: nil,
            marketingVersion: "1.0.2",
            buildNumber: "12345"
        )

        XCTAssertEqual(release, "com.mabryventures.VolumeArc@1.0.2+12345")
    }

    func testReleaseNameFallsBackWhenMarketingVersionMissing() {
        let release = VolumeArcSentryConfiguration.computeReleaseName(
            bundleID: "com.mabryventures.VolumeArc",
            marketingVersion: nil,
            buildNumber: "12345"
        )

        XCTAssertEqual(release, "com.mabryventures.VolumeArc@0.0.0+12345")
    }

    func testReleaseNameFallsBackWhenBuildNumberMissing() {
        let release = VolumeArcSentryConfiguration.computeReleaseName(
            bundleID: "com.mabryventures.VolumeArc",
            marketingVersion: "1.0.2",
            buildNumber: nil
        )

        XCTAssertEqual(release, "com.mabryventures.VolumeArc@1.0.2+0")
    }

    func testBundleOverloadDelegatesToPureForm() {
        // The `Bundle.main` overload should produce a non-empty release
        // string in the format `<id>@<version>+<build>`. We don't pin the
        // exact values because the test bundle's Info.plist isn't stable
        // across Xcode versions; we just verify the structure.
        let release = VolumeArcSentryConfiguration.computeReleaseName()

        let parts = release.split(separator: "@", maxSplits: 1)
        XCTAssertEqual(parts.count, 2, "Release name should have one '@' separator")

        let versionAndBuild = parts[1]
        XCTAssertTrue(versionAndBuild.contains("+"), "Version+build should have a '+' separator")
    }
}
#endif
