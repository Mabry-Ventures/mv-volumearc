import XCTest

/// XCUITest journey suite for VolumeArc iOS.
///
/// These tests exercise the critical user journeys end-to-end against
/// the real app binary. They run on the iPhone simulator in CI.
///
/// Note: many of these tests require seeded test state that the app should
/// accept via launch arguments (e.g., `-UITestMode 1 -SeedFixtures 1`).
/// Until that plumbing lands in the host app, these tests act as smoke
/// checks — they verify the app launches and major UI elements exist.
final class VolumeArcAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Smoke

    func testAppReachesForegroundOnLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "1"]
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "App should reach foreground running state on cold launch"
        )
    }

    // MARK: - Navigation

    func testTabBarAppearsWithFiveTabs() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "1"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 15),
            "Tab bar should appear after launch"
        )
        // Five tabs: Today, Workouts, Coach, Signals, Profile
        XCTAssertGreaterThanOrEqual(tabBar.buttons.count, 5,
            "App should expose all 5 navigation tabs")
    }

    func testSwitchingTabsPreservesAppRunning() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "1"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 15) else {
            XCTFail("Tab bar did not appear")
            return
        }

        // Tap through several tabs — app should not crash or deadlock.
        let tabCount = min(tabBar.buttons.count, 5)
        for index in 0..<tabCount {
            tabBar.buttons.element(boundBy: index).tap()
            XCTAssertTrue(
                app.state == .runningForeground,
                "App should remain in foreground after tapping tab \(index)"
            )
        }
    }

    // MARK: - Performance

    @MainActor
    func testLaunchPerformance() throws {
        if #available(iOS 13.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
