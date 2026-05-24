import XCTest

/// VOL-109: HealthKit permission sheet + graceful denial coverage.
///
/// The Apple Health connection flow lives in two places:
/// - **Onboarding permissions step** (between coachingStyle and done)
/// - **Profile → Apple Health** row (Settings entry point)
///
/// Both routes call `WorkoutDashboardModel.requestHealthKitAuthorization()`,
/// which gates on `VolumeArcRuntimeFlags.shouldSurfacePermissionPrompts`.
/// Without `-SimulatePermissionPrompts 1`, regular `-UITestMode 1` runs
/// short-circuit the prompt entirely (records a `health.auth_skipped`
/// telemetry event and returns `false`) so existing journey tests don't
/// trip on the system sheet.
///
/// This suite covers:
/// 1. Onboarding can be completed by skipping the permissions step
///    (the default path — Continue advances without engaging Connect).
/// 2. The permissions step renders the Connect button + footer text
///    when `onRequestHealthAuthorization` is wired (the production
///    path).
/// 3. Tapping the Profile-tab Apple Health row routes through the
///    same `requestHealthKitAuthorization` path (no prompt under
///    plain `-UITestMode 1` thanks to the gate; because the gate
///    returns `false`, the row must remain in its "Connect" state).
///
/// Driving the actual HealthKit system sheet via `addUIInterruptionMonitor`
/// requires `-SimulatePermissionPrompts 1` which is intentionally NOT
/// the default for this suite — it's covered separately so the suite
/// runs hermetically without the system-modal flake risk on Tart VMs.
@MainActor
final class VolumeArcHealthKitPermissionJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// VOL-164: defensively terminate the host app between test methods.
    override func tearDownWithError() throws {
        MainActor.assumeIsolated {
            let app = XCUIApplication()
            VolumeArcAppUITestSupport.defensiveTerminate(app)
        }
    }

    /// VOL-109 contract: a fresh user can complete onboarding by tapping
    /// Continue through every step, including permissions, without
    /// engaging the Connect Apple Health button. The prompt-skipped path
    /// must reach the dashboard cleanly.
    func testOnboardingPermissionsStepCanBeSkippedByContinuing() throws {
        let app = VolumeArcAppUITestSupport.makeOnboardingApp()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground on cold launch"
        )

        let onboardingRoot = app.descendants(matching: .any)
            .matching(identifier: "onboarding.root").firstMatch
        XCTAssertTrue(
            onboardingRoot.waitForExistence(timeout: 20),
            "Onboarding cover should be visible on first launch"
        )

        // Tap Continue 5 times: welcome → profile → preferences →
        // coachingStyle → permissions → done. Each Continue advances
        // one step. The permissions step is the 5th Continue tap.
        for stepIndex in 0..<5 {
            dismissKeyboardIfPresent(in: app)
            let continueButton = app.descendants(matching: .any)
                .matching(identifier: "onboarding.continue").firstMatch
            XCTAssertTrue(
                continueButton.waitForExistence(timeout: 15),
                "Continue should be reachable on step \(stepIndex + 1)"
            )

            // VOL-109: on the coachingStyle → permissions transition,
            // verify the Connect button is rendered before we advance
            // past it. This pins the contract that the permissions step
            // surfaces a connect affordance, not just informational text.
            //
            // VOL-127: additionally pin the four rationale bullets that
            // the audit's UAT-readiness checklist requires before the
            // system prompt fires — what's read, why, on-device, iCloud.
            // We match each bullet by a substring that's stable across
            // copy edits (e.g. "heart rate" not the full sentence) so a
            // wording polish doesn't trip the contract test.
            if stepIndex == 4 {
                let connectButton = app.descendants(matching: .any)
                    .matching(identifier: "onboarding.permissions.connect-health")
                    .firstMatch
                XCTAssertTrue(
                    connectButton.waitForExistence(timeout: 10),
                    "Permissions step should expose the Connect Apple Health button"
                )

                for rationaleNeedle in [
                    "heart rate",            // VOL-127 bullet 1: what's read (watch HR)
                    "Coach prescription",    // VOL-127 bullet 2: why we read it
                    "Apple Health on this device",  // VOL-127 bullet 3: on-device guarantee
                    "private iCloud database",      // VOL-127 bullet 4: CloudKit + revocation
                ] {
                    let predicate = NSPredicate(format: "label CONTAINS[c] %@", rationaleNeedle)
                    let match = app.staticTexts.matching(predicate).firstMatch
                    XCTAssertTrue(
                        match.waitForExistence(timeout: 5),
                        "VOL-127: permissions step rationale should surface '\(rationaleNeedle)' before the system prompt fires"
                    )
                }
            }

            continueButton.tap()
        }

        dismissKeyboardIfPresent(in: app)
        let finishButton = app.descendants(matching: .any)
            .matching(identifier: "onboarding.finish").firstMatch
        XCTAssertTrue(
            finishButton.waitForExistence(timeout: 15),
            "Finish button should be reachable on the done step"
        )
        finishButton.tap()

        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 20),
            "Dashboard should appear within 20s after onboarding completes via skipping permissions"
        )
    }

    /// VOL-109 contract: tapping the Profile-tab Apple Health row routes
    /// through the same permission gate. Under plain `-UITestMode 1`
    /// the prompt is short-circuited (no system sheet appears), and the
    /// row must stay in its "Connect" state because the model returned
    /// `false`. This proves the wiring without requiring a real system
    /// sheet and catches accidental "Connected" lies on denial/skips.
    func testProfileHealthRowRoutesThroughPermissionGate() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenProfileOnLaunch", "1"]
        )
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground"
        )

        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 15),
            "Dashboard should appear"
        )
        openProfileTabIfNeeded(in: app)

        let healthRow = waitForProfileHealthRow(in: app)
        XCTAssertTrue(
            healthRow.exists,
            "Profile tab should expose the Apple Health connect row"
        )

        // Tap the row. Under `-UITestMode 1` without
        // `-SimulatePermissionPrompts 1`, the dashboard model's
        // permission gate short-circuits the prompt — no system sheet
        // fires. Since the model returns `false` for this route, the row
        // should not claim HealthKit is connected.
        healthRow.tap()

        let postTapHealthRow = profileHealthRow(in: app)
        XCTAssertTrue(
            waitForLabel("Connect to Apple Health", on: postTapHealthRow, timeout: 5),
            "Skipped HealthKit authorization should return the Profile row to its Connect state"
        )
        XCTAssertEqual(
            postTapHealthRow.label,
            "Connect to Apple Health",
            "Skipped HealthKit authorization should leave the Profile row in its Connect state"
        )
    }

    /// VOL-109 contract: `-SimulatePermissionPrompts 1` must route the
    /// HealthKit entry point into the prompt-enabled path. The test avoids
    /// driving SpringBoard's HealthKit sheet on Tart VMs; instead, the
    /// Profile row exposes the prompt routing as an accessibility value.
    func testHealthKitConnectButtonSurfacesSimulationPromptPath() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenProfileOnLaunch", "1", "-SimulatePermissionPrompts", "1"]
        )
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground"
        )

        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 15),
            "Dashboard should appear"
        )
        openProfileTabIfNeeded(in: app)

        let healthRow = waitForProfileHealthRow(in: app)
        XCTAssertTrue(
            waitForValue("System permission prompt enabled", on: healthRow, timeout: 5),
            "Profile health row should expose the prompt-enabled accessibility value"
        )

        XCTAssertEqual(
            healthRow.value as? String,
            "System permission prompt enabled",
            "-SimulatePermissionPrompts should mark the Apple Health row as prompt-enabled"
        )
    }

    // MARK: - Helpers

    /// Mirror of the keyboard-dismissal helper in `VolumeArcAppJourneyTests`
    /// (re-implemented locally because that helper is `private`).
    private func dismissKeyboardIfPresent(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let topLeft = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05))
        topLeft.tap()
    }

    private func waitForProfileHealthRow(in app: XCUIApplication, timeout: TimeInterval = 20) -> XCUIElement {
        var row = profileHealthRow(in: app)
        if row.waitForExistence(timeout: 2) { return row }

        let deadline = Date().addingTimeInterval(timeout)
        let profileForm = app.collectionViews.firstMatch
        while Date() < deadline {
            if profileForm.exists {
                profileForm.swipeUp()
            } else {
                app.swipeUp()
            }
            row = profileHealthRow(in: app)
            if row.waitForExistence(timeout: 1) { return row }
        }

        return row
    }

    private func profileHealthRow(in app: XCUIApplication) -> XCUIElement {
        let identified = app.descendants(matching: .any)
            .matching(identifier: "profile.health.connect").firstMatch
        if identified.exists { return identified }

        let labelPredicate = NSPredicate(
            format: "label == %@ OR label == %@ OR label CONTAINS %@",
            "Connect to Apple Health",
            "Connect Apple Health",
            "Apple Health"
        )
        return app.descendants(matching: .any)
            .matching(labelPredicate)
            .firstMatch
    }

    private func waitForLabel(_ expected: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        waitForElementState(timeout: timeout) {
            element.label == expected
        }
    }

    private func waitForValue(_ expected: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        waitForElementState(timeout: timeout) {
            (element.value as? String) == expected
        }
    }

    private func waitForElementState(timeout: TimeInterval, matches: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if matches() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return matches()
    }

    private func openProfileTabIfNeeded(in app: XCUIApplication) {
        let profileRoot = app.descendants(matching: .any)
            .matching(identifier: "profile.root").firstMatch
        if profileRoot.waitForExistence(timeout: 2) { return }

        let profileTab = app.tabBars.buttons["Profile"].firstMatch
        if profileTab.waitForExistence(timeout: 5) {
            profileTab.tap()
            _ = profileRoot.waitForExistence(timeout: 5)
            return
        }

        let identifiedTab = app.descendants(matching: .any)
            .matching(identifier: "tab.profile").firstMatch
        if identifiedTab.waitForExistence(timeout: 2) {
            identifiedTab.tap()
            _ = profileRoot.waitForExistence(timeout: 5)
        }
    }
}
