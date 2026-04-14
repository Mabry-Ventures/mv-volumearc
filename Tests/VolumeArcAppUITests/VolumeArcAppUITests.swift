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

    func testUpgradePresentsPaywallAndDismissesBackToProfile() throws {
        let app = makeSeededApp()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        // Tap the Profile tab. SwiftUI tab bar buttons are normal buttons,
        // so the localized title query is reliable.
        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), "Profile tab should be available")
        profileTab.tap()

        // SwiftUI Form rows wrap the Button as a Cell with combined
        // accessibility. Try buttons → cells → any descendant in order so
        // the test is robust across SwiftUI runtime revisions.
        let upgradeRow = firstUpgradeElement(in: app)
        XCTAssertTrue(upgradeRow.waitForExistence(timeout: 15), "Upgrade row should appear on the profile screen")
        upgradeRow.tap()

        let paywall = app.descendants(matching: .any)
            .matching(identifier: "paywall.root")
            .firstMatch
        XCTAssertTrue(paywall.waitForExistence(timeout: 10), "Paywall should be presented after tapping Upgrade")

        let closeButton = app.descendants(matching: .any)
            .matching(identifier: "paywall.close")
            .firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10), "Paywall close button should be visible")
        closeButton.tap()

        // The cover dismisses and we should be back on the profile row.
        XCTAssertTrue(firstUpgradeElement(in: app).waitForExistence(timeout: 10), "Profile screen should still be visible after dismissing the paywall")
    }

    /// Best-effort lookup for the Profile → Upgrade row across SwiftUI
    /// runtime revisions. Tries `buttons`, then `cells`, then any descendant
    /// matching the `profile.upgrade` accessibility identifier.
    private func firstUpgradeElement(in app: XCUIApplication) -> XCUIElement {
        let asButton = app.buttons["profile.upgrade"]
        if asButton.exists { return asButton }
        let asCell = app.cells["profile.upgrade"]
        if asCell.exists { return asCell }
        return app.descendants(matching: .any)
            .matching(identifier: "profile.upgrade")
            .firstMatch
    }

    // MARK: - Performance

    @MainActor
    func testLaunchPerformance() throws {
        if #available(iOS 13.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let app = makeSeededApp()
                app.launch()
            }
        }
    }

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
