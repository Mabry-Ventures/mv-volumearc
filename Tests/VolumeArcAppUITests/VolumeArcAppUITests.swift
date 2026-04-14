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

        // The upgrade row is a SwiftUI Form `Button`. Accessibility
        // identifiers attached to a Button inside a Form can be swallowed
        // by the row's cell wrapping across SwiftUI revisions, so query by
        // the visible "Upgrade" label text — that's what the user sees and
        // the test runner can reliably find across runtimes. `firstMatch`
        // avoids disambiguation against the Premium section header.
        let upgradeLabel = app.staticTexts["Upgrade"].firstMatch
        XCTAssertTrue(upgradeLabel.waitForExistence(timeout: 15), "Upgrade row should appear on the profile screen")
        upgradeLabel.tap()

        let paywall = app.descendants(matching: .any)
            .matching(identifier: "paywall.root")
            .firstMatch
        XCTAssertTrue(paywall.waitForExistence(timeout: 10), "Paywall should be presented after tapping Upgrade")

        let closeButton = app.descendants(matching: .any)
            .matching(identifier: "paywall.close")
            .firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10), "Paywall close button should be visible")
        closeButton.tap()

        // Wait on `exists == false` via an NSPredicate expectation rather
        // than negating `waitForExistence`. The latter is an appearance
        // wait and can flake on slow runners during the dismissal animation
        // (it returns true while the cover is still on-screen). This
        // explicitly waits for the cover to actually disappear.
        let disappearance = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: paywall
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [disappearance], timeout: 10),
            .completed,
            "Paywall should dismiss after tapping close"
        )

        // And the profile row is back in place.
        XCTAssertTrue(app.staticTexts["Upgrade"].firstMatch.waitForExistence(timeout: 10), "Profile screen should still be visible after dismissing the paywall")
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
