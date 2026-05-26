import XCTest

/// App Store screenshot automation for `fastlane ios screenshots`.
final class VolumeArcScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["VOLUMEARC_RUN_SCREENSHOT_CAPTURE"] != "1",
            "App Store screenshot capture is an explicit release-lane/manual " +
            "opt-in. Set VOLUMEARC_RUN_SCREENSHOT_CAPTURE=1 when running " +
            "`fastlane ios screenshots` or the screenshot UI test directly."
        )
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

        tapTab(atIndex: 1, in: app)

        let activeSession = app.descendants(matching: .any)
            .matching(identifier: "workouts.activeSession")
            .firstMatch
        XCTAssertTrue(activeSession.waitForExistence(timeout: 10))
        snapshot("02_live_workout")

        tapTab(atIndex: 2, in: app)
        let coachComposer = app.descendants(matching: .any)
            .matching(identifier: "coach.composer")
            .firstMatch
        XCTAssertTrue(coachComposer.waitForExistence(timeout: 10))
        snapshot("03_coach")

        tapTab(atIndex: 3, in: app)
        let signalsRoot = app.descendants(matching: .any)
            .matching(identifier: "signals.root")
            .firstMatch
        XCTAssertTrue(signalsRoot.waitForExistence(timeout: 10))
        snapshot("04_signals")

        tapTab(atIndex: 4, in: app)
        let profileRoot = app.descendants(matching: .any)
            .matching(identifier: "profile.root")
            .firstMatch
        XCTAssertTrue(profileRoot.waitForExistence(timeout: 10))
        snapshot("05_profile")

        app.terminate()

        let paywallApp = VolumeArcAppUITestSupport.makeSeededApp(extra: ["-ShowPaywallOnLaunch", "1"])
        setupSnapshot(paywallApp)
        paywallApp.launch()

        let paywallRoot = paywallApp.descendants(matching: .any)
            .matching(identifier: "paywall.root")
            .firstMatch
        XCTAssertTrue(paywallRoot.waitForExistence(timeout: 20))
        let monthlyPlan = paywallApp.descendants(matching: .any)
            .matching(identifier: "paywall.plan.com.mabryventures.VolumeArc.premium.monthly")
            .firstMatch
        let planLoaded = monthlyPlan.waitForExistence(timeout: 20)
        let requiresStoreKitProducts = paywallApp.launchArguments.contains { argument in
            argument == "-RequireStoreKitProducts" || argument.hasPrefix("-RequireStoreKitProducts=")
        }
        if requiresStoreKitProducts {
            XCTAssertTrue(planLoaded, "Premium screenshot should wait for StoreKit products before capture")
        } else if !planLoaded {
            // VOL-202: same skip→fail policy as the purchase test —
            // release screenshot capture is not allowed to silently
            // skip the premium screen when products fail to load. CI
            // must produce a complete screenshot matrix. Local dev can
            // opt in to the skip via ALLOW_STOREKIT_SKIP=1.
            if ProcessInfo.processInfo.environment["ALLOW_STOREKIT_SKIP"] == "1" {
                throw XCTSkip(
                    "StoreKit products unavailable on this simulator; premium screenshot capture skipped (ALLOW_STOREKIT_SKIP=1)."
                )
            }
            XCTFail(
                "StoreKit products did not load before premium screenshot capture. The release screenshot matrix would be incomplete; fix the StoreKit Test daemon / .storekit config, or set ALLOW_STOREKIT_SKIP=1 locally."
            )
            return
        }
        snapshot("06_premium")
    }

    @MainActor
    private func tapTab(atIndex index: Int, in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        let tabs = tabBar.buttons
        XCTAssertGreaterThan(tabs.count, index)
        let target = tabs.element(boundBy: index)
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        expectation(
            for: NSPredicate(format: "isHittable == true"),
            evaluatedWith: target
        )
        waitForExpectations(timeout: 5)
        target.tap()
    }
}
