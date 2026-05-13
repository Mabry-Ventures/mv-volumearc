import XCTest

/// XCUITest journey suite for VolumeArc iOS.
///
/// Most tests launch the app with `-UITestMode 1 -SkipOnboarding 1
/// -SeedFixtures 1` so the dashboard is pre-populated with deterministic
/// state and no permission prompts interrupt the flow. The onboarding
/// coverage intentionally launches with only `-UITestMode 1`.
///
/// Strategy: validate the app boots and reaches a runnable foreground
/// state. These smoke-level tests don't attempt to traverse the full UI
/// because the tab bar element identity varies between SwiftUI runtime
/// revisions. Deeper journey coverage lives in the integration test
/// suite (`VolumeArcDashboardIntegrationTests`).
final class VolumeArcAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// VOL-164: defensively terminate the host app between test methods.
    override func tearDownWithError() throws {
        VolumeArcAppUITestSupport.defensiveTerminate(XCUIApplication())
    }

    // MARK: - Launch smoke

    func testAppReachesForegroundOnLaunch() throws {
        let app = makeSeededApp()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )
    }

    func testAppStaysRunningForOneSecondAfterLaunch() throws {
        let app = makeSeededApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        // Give the app a moment to finish building its initial view.
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(
            app.state,
            .runningForeground,
            "App should still be foreground 1 second after launch — no early crashes"
        )
    }

    func testRootDashboardIdentifierExists() throws {
        let app = makeSeededApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        // Either the root.dashboard identifier or any tab bar should exist.
        let root = app.otherElements["root.dashboard"]
        let anyTabBar = app.tabBars.firstMatch
        let rootExists = root.waitForExistence(timeout: 10)
        let tabBarExists = anyTabBar.exists

        XCTAssertTrue(
            rootExists || tabBarExists,
            "Either the root.dashboard element or a tab bar should be visible"
        )
    }

    // MARK: - VOL-149: telemetry-as-UAT

    /// Proof-of-concept for the telemetry assertion helper:
    /// `WorkoutDashboardModel.refresh()` records a `dashboard.refresh`
    /// info event whenever the dashboard reloads. This test launches
    /// a seeded app, waits for the dashboard, then asserts the event
    /// appeared in the test probe's buffer.
    ///
    /// If this passes, every other journey can adopt the same pattern
    /// (Onboarding → `onboarding.completed`, workout completion →
    /// `workout.completed`, etc.) — the wiring proven here generalizes.
    /// If this fails, the bug is in the probe / overlay plumbing, not
    /// in any one journey.
    func testDashboardRefreshTelemetryReachesTheProbe() throws {
        let app = makeSeededApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        // Wait for the dashboard to render and the model to record
        // its refresh event. The probe is updated on the main queue
        // via NotificationCenter; under a warm simulator + small
        // bundle the assertion lands in ~4s. The 30s budget is
        // VOL-175-driven: adding more test classes to the bundle
        // (VolumeArcChaosJourneyTests landed in PR #154) shifted
        // the cold-launch path's first-test-run latency past the
        // original 10s threshold. 30s gives ample headroom while
        // still failing fast if the probe is genuinely broken.
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "dashboard",
            name: "refresh",
            within: 30,
            test: self
        )
    }

    func testOnboardingAppearsWhenLaunchDoesNotSkipIt() throws {
        let app = makeOnboardingApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        // Onboarding is presented in a fullScreenCover; the accessibility
        // identifier may surface as either an `otherElement` or a generic
        // descendant depending on SwiftUI's hosting layer. Match by identifier
        // across any element type for robustness.
        let onboardingRoot = app.descendants(matching: .any)
            .matching(identifier: "onboarding.root")
            .firstMatch
        XCTAssertTrue(
            onboardingRoot.waitForExistence(timeout: 15),
            "Onboarding should appear when launch arguments do not skip it"
        )
    }

    // The upgrade-row XCUITest is deferred (tracked in VOL-58).
    //
    // Background: SwiftUI Form cells in iOS 26 XCUITest don't reliably
    // expose inner `accessibilityIdentifier`s across runtime revisions.
    // After 5 fixup attempts (Button + identifier, Button + descendants
    // query, Button + combined accessibility, HStack + onTapGesture,
    // visible-text query), none of the approaches produced a stable
    // XCUITest lookup for the upgrade row inside `Form.Section`.
    //
    // VOL-58's actual wiring is verified instead by:
    //
    // 1. `VolumeArcDashboardIntegrationTests.testProfileViewWiresPaywallSheet`
    //    which asserts that `ProfileView`'s `isShowingPaywall` binding is
    //    wired to a `.sheet(isPresented:)` modifier and that the sheet
    //    receives the model's `subscriptionStore`.
    //
    // 2. Manual smoke test on device during code review.
    //
    // Follow-up: when Apple publishes a reliable pattern for querying
    // Form cells in XCUITest (or we migrate the row out of Form into a
    // VStack), replace the integration test with a real end-to-end
    // XCUITest.

    // MARK: - Helpers

    private func makeSeededApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMode", "1",
            "-SkipOnboarding", "1",
            "-SeedFixtures", "1",
        ]
        return app
    }

    private func makeOnboardingApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMode", "1",
        ]
        return app
    }
}
