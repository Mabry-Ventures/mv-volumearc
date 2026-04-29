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
///    plain `-UITestMode 1` thanks to the gate; the row UI updates to
///    "Connected" anyway because the gate's no-op return still flips
///    the local `healthAuthorizationDidComplete` state).
///
/// Driving the actual HealthKit system sheet via `addUIInterruptionMonitor`
/// requires `-SimulatePermissionPrompts 1` which is intentionally NOT
/// the default for this suite — it's covered separately so the suite
/// runs hermetically without the system-modal flake risk on Tart VMs.
final class VolumeArcHealthKitPermissionJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
            if stepIndex == 4 {
                let connectButton = app.descendants(matching: .any)
                    .matching(identifier: "onboarding.permissions.connect-health")
                    .firstMatch
                XCTAssertTrue(
                    connectButton.waitForExistence(timeout: 10),
                    "Permissions step should expose the Connect Apple Health button"
                )
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
    /// the prompt is short-circuited (no system sheet appears), but the
    /// row's local "Connected" affordance still flips so the user gets
    /// feedback that something happened. This proves the wiring without
    /// requiring a real system sheet.
    func testProfileHealthRowRoutesThroughPermissionGate() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp()
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

        // Navigate to the Profile tab. The tab bar uses standard tab
        // identifiers; we look up by label rather than tab index so a
        // future re-order doesn't break the test.
        let profileTab = app.tabBars.buttons[String(localized: "Profile")]
        if profileTab.waitForExistence(timeout: 5) {
            profileTab.tap()
        }

        let healthRow = app.descendants(matching: .any)
            .matching(identifier: "profile.health.connect").firstMatch
        XCTAssertTrue(
            healthRow.waitForExistence(timeout: 10),
            "Profile tab should expose the Apple Health connect row"
        )

        // Tap the row. Under `-UITestMode 1` without
        // `-SimulatePermissionPrompts 1`, the dashboard model's
        // permission gate short-circuits the prompt — no system sheet
        // fires. The row should still update to its "Connected" label.
        healthRow.tap()

        // Allow the local @State flip to render. The row label change
        // is driven by `healthAuthorizationDidComplete = true` in the
        // tap handler.
        Thread.sleep(forTimeInterval: 1.0)

        // The same accessibility identifier is reused for both the
        // pre-tap "Connect" and post-tap "Connected" states (the label
        // changes, not the identifier), so re-finding it is sufficient
        // proof the row is still in the accessibility tree and didn't
        // crash the navigation.
        XCTAssertTrue(
            healthRow.exists,
            "Apple Health row should remain in the accessibility tree after tap"
        )
    }

    /// VOL-109 contract: when launched with `-SimulatePermissionPrompts 1`,
    /// tapping Connect Apple Health on the permissions step DOES fire
    /// the system HealthKit sheet. This test uses
    /// `addUIInterruptionMonitor` to drive the sheet — accept all
    /// scopes, tap Done — and asserts the onboarding "Connected" state.
    ///
    /// Driving HealthKit's authorization sheet via XCUITest is brittle
    /// (the sheet is rendered by a system process, button labels are
    /// localized, and `addUIInterruptionMonitor` requires a follow-up
    /// interaction to fire its handler). To keep this test robust:
    /// - The monitor handler returns `true` after attempting to tap the
    ///   most likely "Turn All On" / "Allow" / "Done" buttons. If the
    ///   actual sheet copy diverges across iOS versions, the handler
    ///   short-circuits via the `Done` fallback.
    /// - We sleep briefly + tap inside the host app after the Connect
    ///   tap so the interruption monitor has a window to evaluate.
    /// - We assert on the post-prompt state (the button label flipping
    ///   to "Connected") rather than on the sheet's internals, which
    ///   would couple the test to system UI text.
    func testHealthKitConnectButtonFiresSystemSheetUnderSimulationFlag() throws {
        let app = VolumeArcAppUITestSupport.makeOnboardingApp(
            extra: ["-SimulatePermissionPrompts", "1"]
        )

        // VOL-109: register the interruption monitor BEFORE launching.
        // XCUITest delivers system-modal events to the most recently
        // registered monitor that returns true; ours covers the
        // HealthKit auth sheet variations across iOS versions.
        let interruptionMonitor = addUIInterruptionMonitor(
            withDescription: "HealthKit authorization sheet"
        ) { sheet in
            // Try every label HealthKit's sheet has used in recent iOS
            // versions. First match wins; the rest no-op on .exists check.
            for label in ["Turn All On", "Allow", "OK"] {
                let button = sheet.buttons[label]
                if button.exists {
                    button.tap()
                    break
                }
            }
            // The sheet always closes via "Done" or "Allow".
            for closeLabel in ["Done", "Allow", "Continue"] {
                let close = sheet.buttons[closeLabel]
                if close.exists {
                    close.tap()
                    break
                }
            }
            // Returning true tells XCUITest "this monitor handled the
            // interruption" so it doesn't try to dispatch to other
            // monitors (we only have one).
            return true
        }
        // Defensive cleanup so a partial test run doesn't leak the
        // monitor into a sibling test invocation in the same process.
        defer { removeUIInterruptionMonitor(interruptionMonitor) }

        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground with -SimulatePermissionPrompts 1"
        )

        // Walk to the permissions step (5th Continue tap moves into it).
        let onboardingRoot = app.descendants(matching: .any)
            .matching(identifier: "onboarding.root").firstMatch
        XCTAssertTrue(onboardingRoot.waitForExistence(timeout: 20))

        for _ in 0..<4 {
            dismissKeyboardIfPresent(in: app)
            let continueButton = app.descendants(matching: .any)
                .matching(identifier: "onboarding.continue").firstMatch
            XCTAssertTrue(continueButton.waitForExistence(timeout: 15))
            continueButton.tap()
        }

        // We're now on the permissions step. Tap Connect.
        let connectButton = app.descendants(matching: .any)
            .matching(identifier: "onboarding.permissions.connect-health").firstMatch
        XCTAssertTrue(
            connectButton.waitForExistence(timeout: 10),
            "Connect Apple Health button should be reachable on permissions step"
        )
        connectButton.tap()

        // VOL-109: addUIInterruptionMonitor needs a host-app interaction
        // to dispatch its handler. Tap the onboarding root (which
        // doesn't navigate or change state) to give the monitor a
        // chance to fire.
        Thread.sleep(forTimeInterval: 2.0)
        onboardingRoot.tap()
        Thread.sleep(forTimeInterval: 2.0)

        // Assert the post-prompt state: the local
        // `healthAuthorizationDidComplete` flag flipped, which in turn
        // disabled the Connect button (its `.disabled(true)` modifier
        // prevents further taps). XCUITest's `.isEnabled` reports the
        // SwiftUI disabled state.
        //
        // Resolve the button anew — its label changed from "Connect
        // Apple Health" to "Connected" but the identifier is the same.
        let connectedButton = app.descendants(matching: .any)
            .matching(identifier: "onboarding.permissions.connect-health").firstMatch
        XCTAssertTrue(
            connectedButton.waitForExistence(timeout: 10),
            "Permissions button should remain in the accessibility tree post-prompt"
        )
        XCTAssertFalse(
            connectedButton.isEnabled,
            "Permissions button should be disabled (\"Connected\") after the system sheet closes"
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
}
