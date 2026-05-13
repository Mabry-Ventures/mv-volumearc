import XCTest

/// VOL-93: shared XCUITest helpers for the VolumeArc iOS app.
///
/// Centralizes the launch-argument configurations used by both the
/// original smoke tests (`VolumeArcAppUITests`) and the journey suite
/// (`VolumeArcAppJourneyTests`). Keeping one definition per flag
/// combination keeps the tests aligned if we ever rename or add a new
/// bootstrap flag.
enum VolumeArcAppUITestSupport {
    /// Fully-seeded dashboard: onboarding pre-completed, deterministic
    /// fixtures installed. Used by any test whose starting point is the
    /// home dashboard.
    static func makeSeededApp(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMode", "1",
            "-SkipOnboarding", "1",
            "-SeedFixtures", "1",
        ]
        app.launchArguments += extra
        return app
    }

    /// First-launch experience: the app boots into the onboarding cover
    /// because no user profile has been persisted yet. Used by the
    /// onboarding gate smoke test and the onboarding journey.
    static func makeOnboardingApp(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMode", "1",
        ]
        app.launchArguments += extra
        return app
    }

    // MARK: - VOL-111: Dynamic Type + pseudo-locale launch helpers

    /// `accessibility5` Dynamic Type — the absolute largest content-size
    /// category iOS exposes. Catches truncation, button-row collapse, and
    /// scrollable content that doesn't actually scroll under stress.
    ///
    /// The raw string is the platform constant Apple's launch-argument
    /// parser recognizes; using the constant directly via
    /// `UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue`
    /// would couple this helper to UIKit, which the test target doesn't
    /// import directly.
    static let accessibility5SizeCategoryArgument =
        "UICTContentSizeCategoryAccessibilityXXXL"

    /// Re-decorate any launcher with Dynamic Type set to `.accessibility5`.
    /// Compose with `makeOnboardingApp` / `makeSeededApp` by passing the
    /// returned `[String]` as `extra:`.
    static var dynamicTypeAccessibility5LaunchArgs: [String] {
        [
            "-UIPreferredContentSizeCategoryName",
            accessibility5SizeCategoryArgument,
        ]
    }

    /// Apple's `-NSDoubleLocalizedStrings YES` pseudo-locale: every
    /// localized string is doubled in length at runtime, surfacing layout
    /// breaks that only happen with longer translations (German, Russian,
    /// French — the realistic target locales VolumeArc will ship to).
    static var pseudoLocaleDoubleLengthLaunchArgs: [String] {
        [
            "-NSDoubleLocalizedStrings", "YES",
            // Force the bundle to load via a non-en-US development region
            // so the doubled strings actually resolve through the
            // localization path. `en` is fine — the doubling middleware
            // catches the resolved value regardless of locale.
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
    }

    /// One-stop helper for the "extreme stress" combination: largest
    /// Dynamic Type + double-length pseudo-locale at the same time. Use
    /// this for the worst-case smoke test; individual axis tests use the
    /// per-axis launch-arg arrays above.
    static var combinedStressLaunchArgs: [String] {
        dynamicTypeAccessibility5LaunchArgs + pseudoLocaleDoubleLengthLaunchArgs
    }

    // MARK: - VOL-164: cascade-flakiness defenses

    /// Best-effort terminate of the VolumeArc app process. Use in test
    /// `tearDown` to guarantee a clean state for the next test method,
    /// so a hung/crashed launch in test N doesn't poison test N+1 with
    /// "expected element not found" failures.
    ///
    /// `XCUIApplication.terminate()` itself can fail if the app is
    /// genuinely stuck (the watch-payload journey logged
    /// `Failed to terminate com.mabryventures.VolumeArc:73459` in CI).
    /// Catching here keeps tearDown clean — XCUIApplication's own
    /// next-test launch will retry termination internally if needed.
    static func defensiveTerminate(_ app: XCUIApplication) {
        guard app.state != .notRunning else { return }
        app.terminate()
        // Don't assert state here — terminate is fire-and-forget.
        // Springboard's process-watchdog cleans up zombies within a
        // few seconds even if our terminate() raced.
    }

    /// Tap an element after scrolling it into view if necessary. At
    /// `.accessibility5` the Continue / Finish button row can land
    /// below the keyboard or off-screen on shorter simulators (iPhone
    /// SE / mini); a single `swipeUp()` reliably brings the bottom
    /// CTA back into the hittable region without pushing it past.
    ///
    /// `XCUIElement.tap()` claims to handle off-screen elements via
    /// `coordinate(withNormalizedOffset:).tap()` internally, but in
    /// practice it errors out with "element is not hittable" when the
    /// element is fully clipped — see VOL-164 trace of run
    /// 25413454434 line 198 (`Finish button should be reachable on
    /// the last step`).
    ///
    /// Returns `true` if the element was found-and-tapped, `false`
    /// otherwise so the caller can produce a contextual XCTAssert
    /// failure with the right framing.
    @discardableResult
    static func scrollIntoViewAndTap(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 15,
        maxScrolls: Int = 3
    ) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        var attempts = 0
        while !element.isHittable && attempts < maxScrolls {
            app.swipeUp()
            attempts += 1
        }
        guard element.isHittable else { return false }
        element.tap()
        return true
    }

    /// Attach a snapshot of the app's accessibility tree to the running
    /// XCTest so a CI failure carries enough context to debug from the
    /// xcresult bundle alone — no need to repro locally to know what
    /// was on screen when an assertion fired. Cheap to call on success
    /// paths too; XCTest only persists attachments from failed tests.
    static func attachDebugSnapshot(
        of app: XCUIApplication,
        named name: String,
        to test: XCTestCase
    ) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    // MARK: - VOL-149: telemetry-as-UAT

    /// Assert that a telemetry event with the given `category` + `name`
    /// has fired since the app launched, within `timeout` seconds.
    /// Reads the `debug.telemetry.events` accessibility overlay which
    /// the deterministic-mode app shell populates from
    /// `VolumeArcTelemetryDebugProbe`.
    ///
    /// The overlay's label is a JSON array of `{c, n, s}` records
    /// (category / name / severity raw value), maintained as a rolling
    /// 50-event buffer. The poll loop reads the label once per 0.1s
    /// until either the event appears or the budget expires.
    ///
    /// Failure attaches a snapshot of the failing label and the full
    /// accessibility tree to the xcresult so a CI breakage is
    /// debuggable from the artifact alone.
    static func assertTelemetryFired(
        in app: XCUIApplication,
        category: String,
        name: String,
        within timeout: TimeInterval = 15,
        test: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // VOL-175: default bumped from 5s to 15s. The original 5s was
        // generous for individual events but tight under load — when
        // the test bundle grows (e.g., new test class added), cold-
        // launch overhead can push the first probe assertion past 5s
        // even though the probe itself is healthy. 15s preserves
        // fail-fast semantics while absorbing realistic CI variance.
        let overlay = app.descendants(matching: .any)
            .matching(identifier: "debug.telemetry.events")
            .firstMatch
        guard overlay.waitForExistence(timeout: 5) else {
            XCTFail(
                "[VOL-149] debug.telemetry.events overlay missing — is the app launched with -UITestMode 1?",
                file: file,
                line: line
            )
            return
        }

        let deadline = Date().addingTimeInterval(timeout)
        var lastLabel = ""
        while Date() < deadline {
            lastLabel = overlay.label
            if telemetryLabel(lastLabel, contains: category, name: name) {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let attachment = XCTAttachment(
            string: "telemetry probe label at timeout:\n\(lastLabel)"
        )
        attachment.name = "telemetry.probe.timeout-snapshot"
        attachment.lifetime = .keepAlways
        test.add(attachment)
        attachDebugSnapshot(
            of: app,
            named: "telemetry.assertion-failed.\(category).\(name).a11y-tree",
            to: test
        )

        XCTFail(
            "[VOL-149] Expected telemetry event (\(category)/\(name)) within \(timeout)s; not found in probe buffer.",
            file: file,
            line: line
        )
    }

    /// Internal parser for the compact JSON the probe writes. Public
    /// only so the test target itself can unit-test the matcher.
    static func telemetryLabel(_ label: String, contains category: String, name: String) -> Bool {
        guard let data = label.data(using: .utf8) else { return false }
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let entries = raw as? [[String: Any]] else {
            return false
        }
        return entries.contains { entry in
            (entry["c"] as? String) == category && (entry["n"] as? String) == name
        }
    }
}
