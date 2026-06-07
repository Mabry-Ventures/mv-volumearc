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

    // MARK: - VOL-252: three-way environment classification

    func testEnvironmentIsDevelopmentForDebugBuilds() {
        // Debug always wins, regardless of StoreKit environment — devs
        // running tests against sandbox transactions must not be
        // misclassified as TestFlight.
        let env = VolumeArcSentryConfiguration.resolveEnvironment(
            isDebugBuild: true,
            storeKitEnvironment: "sandbox"
        )
        XCTAssertEqual(env, "development")
    }

    func testEnvironmentIsTestFlightForSandboxStoreKitEnvironment() {
        let env = VolumeArcSentryConfiguration.resolveEnvironment(
            isDebugBuild: false,
            storeKitEnvironment: "sandbox"
        )
        XCTAssertEqual(env, "testflight")
    }

    func testEnvironmentIsTestFlightForXcodeStoreKitEnvironment() {
        let env = VolumeArcSentryConfiguration.resolveEnvironment(
            isDebugBuild: false,
            storeKitEnvironment: "xcode"
        )
        XCTAssertEqual(env, "testflight")
    }

    func testEnvironmentIsProductionForAppStoreEnvironment() {
        let env = VolumeArcSentryConfiguration.resolveEnvironment(
            isDebugBuild: false,
            storeKitEnvironment: "production"
        )
        XCTAssertEqual(env, "production")
    }

    func testEnvironmentIsProductionWhenStoreKitEnvironmentMissing() {
        // Defensive default — a Release build without a resolved StoreKit
        // app transaction falls to
        // "production" so we don't accidentally drop crash data into the
        // wrong bucket. This is the conservative direction (false negative
        // on testflight-bucket attribution beats false negative on
        // production crash visibility).
        let env = VolumeArcSentryConfiguration.resolveEnvironment(
            isDebugBuild: false,
            storeKitEnvironment: nil
        )
        XCTAssertEqual(env, "production")
    }

    func testEnvironmentIsProductionForUnknownStoreKitEnvironment() {
        let env = VolumeArcSentryConfiguration.resolveEnvironment(
            isDebugBuild: false,
            storeKitEnvironment: "mystery"
        )
        XCTAssertEqual(env, "production")
    }

    func testBundleOverloadDelegatesToPureFormForEnvironment() {
        // The `Bundle.main` overload should produce one of the three
        // documented values. We don't pin which value because that depends
        // on the test runner's build configuration.
        let env = VolumeArcSentryConfiguration.resolveEnvironment()
        XCTAssertTrue(
            ["development", "testflight", "production"].contains(env),
            "Bundle-form environment '\(env)' must be one of development/testflight/production"
        )
    }

    // MARK: - DSN validation

    func testValidatedDSNAcceptsSentryDSN() {
        let dsn = VolumeArcSentryConfiguration.validatedDSN(
            from: "https://publicKey@o123456.ingest.sentry.io/987654"
        )

        XCTAssertEqual(dsn, "https://publicKey@o123456.ingest.sentry.io/987654")
    }

    func testValidatedDSNRejectsBuildSettingPlaceholder() {
        XCTAssertNil(VolumeArcSentryConfiguration.validatedDSN(from: "$(SENTRY_DSN)"))
    }

    func testValidatedDSNRejectsPlainHTTP() {
        XCTAssertNil(VolumeArcSentryConfiguration.validatedDSN(
            from: "http://publicKey@o123456.ingest.sentry.io/987654"
        ))
    }

    func testValidatedDSNRejectsMissingPublicKey() {
        XCTAssertNil(VolumeArcSentryConfiguration.validatedDSN(
            from: "https://o123456.ingest.sentry.io/987654"
        ))
    }

    func testValidatedDSNRejectsWhitespaceContamination() {
        XCTAssertNil(VolumeArcSentryConfiguration.validatedDSN(
            from: " https://publicKey@o123456.ingest.sentry.io/987654"
        ))
    }

    func testValidatedDSNRejectsMissingProjectPath() {
        XCTAssertNil(VolumeArcSentryConfiguration.validatedDSN(
            from: "https://publicKey@o123456.ingest.sentry.io"
        ))
    }

    func testMissingDSNIsInformationalForDebugBuilds() {
        XCTAssertEqual(
            VolumeArcSentryConfiguration.startupWarningSeverity(isDebugBuild: true),
            .info
        )
        XCTAssertTrue(
            VolumeArcSentryConfiguration.startupWarningMessage(isDebugBuild: true)
                .contains("local Debug build")
        )
    }

    func testMissingDSNIsWarningForReleaseBuilds() {
        XCTAssertEqual(
            VolumeArcSentryConfiguration.startupWarningSeverity(isDebugBuild: false),
            .warning
        )
        XCTAssertTrue(
            VolumeArcSentryConfiguration.startupWarningMessage(isDebugBuild: false)
                .contains("Release build")
        )
    }
}
#endif
