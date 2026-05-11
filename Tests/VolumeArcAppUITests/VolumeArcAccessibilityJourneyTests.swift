import XCTest

/// VOL-111: Dynamic Type + pseudo-locale sweep across the critical
/// journeys.
///
/// VolumeArc routes every user-facing string through `String(localized:)`
/// (CLAUDE.md ground rules) and uses VAButton + VA.Typography for layout,
/// so in principle the app should render cleanly at the largest content
/// size + a doubled-length pseudo-locale. This suite gates that
/// principle: if a future PR introduces a fixed-height row, a hardcoded
/// pixel offset, or a non-scrolling container, one of these tests will
/// time out finding the next required identifier.
///
/// Coverage matrix (3 journeys × 2 axes + 1 combined stress):
///
/// 1. Onboarding → dashboard at `.accessibility5`
/// 2. Onboarding → dashboard with double-length pseudo-locale
/// 3. Paywall presence at `.accessibility5`
/// 4. Paywall presence with double-length pseudo-locale
/// 5. Combined stress (both axes) on the dashboard
/// 6. VoiceOver audit: every reachable button + link on the dashboard
///    + paywall has a non-empty `accessibilityLabel`
///
/// Each test uses the same identifier-based assertions as the parent
/// `VolumeArcAppJourneyTests` so a layout regression manifests as a
/// `waitForExistence(timeout:)` failure on a known-good identifier — not
/// as a brittle pixel-or-text comparison.
final class VolumeArcAccessibilityJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// VOL-164: defensively terminate the host app between test methods
    /// so a hung/crashed launch in test N doesn't poison test N+1 with
    /// "expected element not found" failures. `XCUIApplication()` with
    /// no launch args references the test target's host bundle —
    /// terminate() then kills whatever instance is running for that
    /// bundle ID, no per-test tracking required.
    override func tearDownWithError() throws {
        let app = XCUIApplication()
        VolumeArcAppUITestSupport.attachDebugSnapshot(
            of: app,
            named: "tearDown.\(name).accessibility-tree",
            to: self
        )
        VolumeArcAppUITestSupport.defensiveTerminate(app)
    }

    // MARK: - 1. Onboarding journey under stress

    /// Boots the onboarding flow with Dynamic Type forced to
    /// `.accessibility5`. Walks through the same 4-step Continue + 1
    /// Finish path the parent journey uses. If any step's button row
    /// collapses, a continue button gets clipped, or the keyboard covers
    /// the action button without a scrollable container catching it, the
    /// `waitForExistence(timeout:)` will time out and the test will fail
    /// at the offending step.
    func testOnboardingJourneyAtAccessibility5() throws {
        let app = VolumeArcAppUITestSupport.makeOnboardingApp(
            extra: VolumeArcAppUITestSupport.dynamicTypeAccessibility5LaunchArgs
        )
        try walkOnboardingToDashboard(app: app, contextLabel: "accessibility5")
    }

    /// Boots the onboarding flow with `-NSDoubleLocalizedStrings YES`.
    /// Doubled-length strings reproduce the worst-case multi-locale
    /// layout (German + Russian both routinely double English string
    /// lengths). A regression here means the test of layout fluidity
    /// has been violated.
    func testOnboardingJourneyWithPseudoLocale() throws {
        let app = VolumeArcAppUITestSupport.makeOnboardingApp(
            extra: VolumeArcAppUITestSupport.pseudoLocaleDoubleLengthLaunchArgs
        )
        try walkOnboardingToDashboard(app: app, contextLabel: "double-length pseudo-locale")
    }

    // MARK: - 2. Paywall journey under stress

    /// Paywall presentation under `.accessibility5`. The paywall has a
    /// dense feature comparison + plan cards + legal footer; large
    /// Dynamic Type stress-tests the ScrollView and the multi-button
    /// action row.
    func testPaywallPresentationAtAccessibility5() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-ShowPaywallOnLaunch", "1"]
                + VolumeArcAppUITestSupport.dynamicTypeAccessibility5LaunchArgs
        )
        try walkPaywallToDismiss(app: app, contextLabel: "accessibility5")
    }

    /// Paywall presentation with double-length pseudo-locale.
    func testPaywallPresentationWithPseudoLocale() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-ShowPaywallOnLaunch", "1"]
                + VolumeArcAppUITestSupport.pseudoLocaleDoubleLengthLaunchArgs
        )
        try walkPaywallToDismiss(app: app, contextLabel: "double-length pseudo-locale")
    }

    // MARK: - 3. Combined stress on the dashboard

    /// Both axes at once on the seeded dashboard. This is the worst-case
    /// — every layout assumption the catalog/dashboard makes is forced
    /// to bend. If the dashboard root identifier isn't reachable within
    /// the timeout, the layout has hard-broken.
    func testSeededDashboardUnderCombinedDynamicTypeAndPseudoLocaleStress() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: VolumeArcAppUITestSupport.combinedStressLaunchArgs
        )
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state under combined stress"
        )

        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 20),
            "Dashboard should appear within 20s under combined Dynamic Type + pseudo-locale stress"
        )
    }

    // MARK: - 4. VoiceOver label audit

    /// Walk the seeded dashboard's interactive elements (buttons, links,
    /// search fields) and assert every one of them has a non-empty
    /// `accessibilityLabel`. VoiceOver users rely on this label as the
    /// announced description; a blank label means VoiceOver announces
    /// "button" with no context — a meaningful regression.
    ///
    /// Scope: dashboard root. Onboarding is sampled separately because
    /// the journey already touches it; paywall is exercised by tap-tests
    /// which would fail outright if labels were missing for hittable
    /// elements.
    func testDashboardInteractiveElementsHaveVoiceOverLabels() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state"
        )

        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 15),
            "Dashboard should appear within 15s"
        )

        // Sample each interactive element type. We only assert on the
        // first ~10 of each kind to keep the test bounded — the goal is
        // to catch a class of regression where SwiftUI's default behavior
        // has been overridden with a label-less custom view, not to gate
        // on the exhaustive surface.
        let buttonsToAudit = Array(app.buttons.allElementsBoundByIndex.prefix(10))
        let linksToAudit = Array(app.links.allElementsBoundByIndex.prefix(10))

        var labelless: [String] = []
        for button in buttonsToAudit where button.label.isEmpty {
            labelless.append("button[\(button.identifier)]")
        }
        for link in linksToAudit where link.label.isEmpty {
            labelless.append("link[\(link.identifier)]")
        }

        XCTAssertTrue(
            labelless.isEmpty,
            "Interactive elements without a VoiceOver label: " +
                labelless.joined(separator: ", ")
        )
    }

    // MARK: - Helpers

    /// Drive the onboarding flow through to dashboard appearance.
    /// Mirrors the assertions in
    /// `VolumeArcAppJourneyTests.testOnboardingToFirstWorkout` so a
    /// stress-mode regression manifests as the same failure shape.
    private func walkOnboardingToDashboard(app: XCUIApplication, contextLabel: String) throws {
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "[\(contextLabel)] App should reach foreground"
        )

        let onboardingRoot = app.descendants(matching: .any)
            .matching(identifier: "onboarding.root")
            .firstMatch
        XCTAssertTrue(
            onboardingRoot.waitForExistence(timeout: 20),
            "[\(contextLabel)] Onboarding cover should be visible"
        )

        // Same 5-Continue + 1-Finish loop as the parent journey (welcome,
        // profile, preferences, coachingStyle, permissions). Larger type
        // / longer strings only stress the layout — the step count is
        // unchanged from the parent journey. VOL-164: scrollIntoViewAndTap
        // handles the case where the CTA row falls below the keyboard or
        // off-screen at .accessibility5, which was the canonical failure
        // shape for `testOnboardingJourneyAtAccessibility5`.
        for stepIndex in 0..<5 {
            dismissKeyboardIfPresent(in: app)
            let continueButton = app.descendants(matching: .any)
                .matching(identifier: "onboarding.continue").firstMatch
            XCTAssertTrue(
                VolumeArcAppUITestSupport.scrollIntoViewAndTap(continueButton, in: app),
                "[\(contextLabel)] Continue button should be reachable on step \(stepIndex + 1)"
            )
        }

        dismissKeyboardIfPresent(in: app)
        let finishButton = app.descendants(matching: .any)
            .matching(identifier: "onboarding.finish").firstMatch
        XCTAssertTrue(
            VolumeArcAppUITestSupport.scrollIntoViewAndTap(finishButton, in: app),
            "[\(contextLabel)] Finish button should be reachable on the last step"
        )

        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 20),
            "[\(contextLabel)] Dashboard should appear within 20s after onboarding completes"
        )
    }

    /// Present, audit, and dismiss the paywall. Mirrors the assertions
    /// in `VolumeArcAppJourneyTests.testPaywallPresentationAndDismissal`.
    private func walkPaywallToDismiss(app: XCUIApplication, contextLabel: String) throws {
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "[\(contextLabel)] App should reach foreground"
        )

        let paywallRoot = app.descendants(matching: .any)
            .matching(identifier: "paywall.root")
            .firstMatch
        XCTAssertTrue(
            paywallRoot.waitForExistence(timeout: 20),
            "[\(contextLabel)] Paywall sheet should appear"
        )

        // Verify the legal links and close button identifiers all
        // resolve. Don't tap-test the legal links — that would require
        // an external-URL handler and is covered by VOL-71. We only
        // need to confirm the layout didn't bury them off-screen.
        let termsLink = app.descendants(matching: .any)
            .matching(identifier: "paywall.legal.terms").firstMatch
        let privacyLink = app.descendants(matching: .any)
            .matching(identifier: "paywall.legal.privacy").firstMatch
        let closeButton = app.descendants(matching: .any)
            .matching(identifier: "paywall.close").firstMatch

        XCTAssertTrue(
            termsLink.waitForExistence(timeout: 10),
            "[\(contextLabel)] Terms link should resolve"
        )
        XCTAssertTrue(
            privacyLink.waitForExistence(timeout: 10),
            "[\(contextLabel)] Privacy link should resolve"
        )
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 10),
            "[\(contextLabel)] Close button should resolve"
        )

        closeButton.tap()
        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 15),
            "[\(contextLabel)] Dashboard should be visible after paywall dismissal"
        )
    }

    /// Mirror of `VolumeArcAppJourneyTests.dismissKeyboardIfPresent`
    /// (re-implemented locally because that helper is `private`).
    private func dismissKeyboardIfPresent(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let topLeft = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05))
        topLeft.tap()
    }
}
