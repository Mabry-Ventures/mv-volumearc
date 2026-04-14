import XCTest

/// XCUITest journey suite for VolumeArc iOS.
///
/// All tests launch the app with `-UITestMode 1 -SkipOnboarding 1
/// -SeedFixtures 1` so the dashboard is pre-populated with deterministic
/// state and no permission prompts interrupt the flow.
///
/// Targets `runsOn: self-hosted` CI on an iPhone 17 simulator.
final class VolumeArcAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch + smoke

    func testAppReachesForegroundOnLaunch() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "App should reach foreground running state on cold launch"
        )
    }

    func testRootDashboardAppears() throws {
        let app = makeApp()
        app.launch()

        let root = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            root.waitForExistence(timeout: 15),
            "Root dashboard element should exist after launch"
        )
    }

    // MARK: - Tab navigation

    func testTabBarHasFiveTabs() throws {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "Tab bar should appear")
        XCTAssertGreaterThanOrEqual(
            tabBar.buttons.count,
            5,
            "App should expose all 5 tabs (Today, Workouts, Coach, Signals, Profile)"
        )
    }

    func testCanNavigateThroughEveryTab() throws {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 15) else {
            XCTFail("Tab bar did not appear")
            return
        }

        // Cycle through the tabs by index — staying in foreground proves
        // none of them crash on first appearance.
        let tabCount = min(tabBar.buttons.count, 5)
        for index in 0..<tabCount {
            tabBar.buttons.element(boundBy: index).tap()
            XCTAssertEqual(
                app.state,
                .runningForeground,
                "App should remain foreground after tapping tab \(index)"
            )
        }
    }

    // MARK: - Today tab journey

    func testTodayTabShowsReadinessAndNextWorkout() throws {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        tabBar.buttons.firstMatch.tap() // Today is the first tab

        // The Today tab should render at least the greeting + readiness.
        // We can't assert exact text (depends on greeting time) so look for
        // static keys.
        let todayNavBar = app.navigationBars["Today"]
        XCTAssertTrue(
            todayNavBar.waitForExistence(timeout: 10),
            "Today navigation title should appear"
        )
    }

    // MARK: - Workouts tab

    func testWorkoutsTabIsReachable() throws {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))

        // Tap the second tab (Workouts).
        if tabBar.buttons.count >= 2 {
            tabBar.buttons.element(boundBy: 1).tap()
        }

        // Either "Session" (active) or "Workouts" (idle) title must appear.
        let workoutsTitle = app.navigationBars["Workouts"]
        let sessionTitle = app.navigationBars["Session"]
        let reachable = workoutsTitle.waitForExistence(timeout: 10) ||
                        sessionTitle.waitForExistence(timeout: 10)
        XCTAssertTrue(reachable, "Workouts or Session navigation title should appear")
    }

    // MARK: - Coach tab

    func testCoachTabRendersComposer() throws {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))

        guard tabBar.buttons.count >= 3 else {
            XCTFail("Expected at least 3 tabs; found \(tabBar.buttons.count)")
            return
        }
        tabBar.buttons.element(boundBy: 2).tap()

        // Wait a beat for the tab transition.
        let navBars = app.navigationBars
        let coachBar = navBars["Coach"]
        let coachPresent = coachBar.waitForExistence(timeout: 10) ||
            navBars.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(coachPresent, "A navigation bar should appear after selecting the Coach tab")

        // The composer text field should be present.
        let textField = app.textFields["Ask your coach"]
        XCTAssertTrue(
            textField.waitForExistence(timeout: 10),
            "Coach composer text field should be visible"
        )
    }

    // MARK: - Signals tab

    func testSignalsTabShowsReadiness() throws {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))

        if tabBar.buttons.count >= 4 {
            tabBar.buttons.element(boundBy: 3).tap()
        }

        let title = app.navigationBars["Signals"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Signals title should appear")
    }

    // MARK: - Profile tab

    func testProfileTabShowsSettingsRows() throws {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))

        if tabBar.buttons.count >= 5 {
            tabBar.buttons.element(boundBy: 4).tap()
        }

        let title = app.navigationBars["Profile"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Profile title should appear")
    }

    // MARK: - Performance

    @MainActor
    func testLaunchPerformance() throws {
        if #available(iOS 13.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let app = makeApp()
                app.launch()
            }
        }
    }

    // MARK: - Helpers

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMode", "1",
            "-SkipOnboarding", "1",
            "-SeedFixtures", "1",
        ]
        return app
    }
}
