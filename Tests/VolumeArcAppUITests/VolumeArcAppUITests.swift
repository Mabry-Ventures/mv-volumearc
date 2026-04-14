import XCTest

/// XCUITest journey suite for VolumeArc iOS.
///
/// All tests launch the app with `-UITestMode 1 -SkipOnboarding 1
/// -SeedFixtures 1` so the dashboard is pre-populated with deterministic
/// state and no permission prompts interrupt the flow.
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

    // MARK: - Launch smoke

    func testAppReachesForegroundOnLaunch() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )
    }

    func testAppStaysRunningForOneSecondAfterLaunch() throws {
        let app = makeApp()
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
        let app = makeApp()
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
