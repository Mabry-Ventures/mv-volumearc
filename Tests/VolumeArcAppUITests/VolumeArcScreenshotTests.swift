import XCTest

/// App Store screenshot automation for `fastlane ios screenshots`.
final class VolumeArcScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureAppStoreScreenshots() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp()
        setupSnapshot(app)
        app.launch()

        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 20),
            "Seeded dashboard should appear before screenshots begin"
        )
        snapshot("01_today_dashboard")

        let startButton = app.descendants(matching: .any)
            .matching(identifier: "today.startWorkout")
            .firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let workoutsTab = app.tabBars.buttons["Workouts"]
        XCTAssertTrue(workoutsTab.waitForExistence(timeout: 5))
        workoutsTab.tap()

        let activeSession = app.descendants(matching: .any)
            .matching(identifier: "workouts.activeSession")
            .firstMatch
        XCTAssertTrue(activeSession.waitForExistence(timeout: 10))
        snapshot("02_live_workout")

        let coachTab = app.tabBars.buttons["Coach"]
        XCTAssertTrue(coachTab.waitForExistence(timeout: 5))
        coachTab.tap()
        snapshot("03_coach")

        app.terminate()

        let paywallApp = VolumeArcAppUITestSupport.makeSeededApp(extra: ["-ShowPaywallOnLaunch", "1"])
        setupSnapshot(paywallApp)
        paywallApp.launch()

        let paywallRoot = paywallApp.descendants(matching: .any)
            .matching(identifier: "paywall.root")
            .firstMatch
        XCTAssertTrue(paywallRoot.waitForExistence(timeout: 20))
        snapshot("04_premium")
    }
}
