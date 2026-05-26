import XCTest

/// VOL-93: end-to-end journey XCUITests for the VolumeArc iOS app.
///
/// This suite is the P1 subset of VOL-93 — it proves critical launch
/// flows actually work (onboarding → dashboard, paywall present/dismiss,
/// restore purchases tap). Coverage that requires additional harness
/// work (HealthKit sheets, BGTask triggers, Dynamic Type sweep, Watch
/// pairing) is tracked in VOL-109 through VOL-112.
///
/// All tests launch via `VolumeArcAppUITestSupport` so the flag strings
/// stay in lockstep with the smoke tests.
///
/// @MainActor: `XCUIElement` and its query APIs are `@MainActor`-isolated
/// under iOS 26 / Xcode 26. Without this annotation every XCUI call in a
/// nonisolated context triggers a Swift 6 concurrency warning and, more
/// importantly, risks hitting the fragile AX-stack path that causes the
/// "Restarting after unexpected exit, crash, or test timeout" pattern
/// observed under iOS 26.5 (duplicate `UIAccessibilityLoaderWebShared`
/// class registration in WebCore.axbundle vs WebKit.axbundle). Matches
/// the existing `@MainActor` declaration on `VolumeArcCoachJourneyTests`.
@MainActor
final class VolumeArcAppJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// VOL-164: defensively terminate the host app between test methods
    /// so a hung/crashed launch in test N doesn't poison test N+1.
    override func tearDownWithError() throws {
        MainActor.assumeIsolated {
            let app = XCUIApplication()
            VolumeArcAppUITestSupport.defensiveTerminate(app)
        }
    }

    // MARK: - 1. Onboarding → first workout

    /// Boots the app with onboarding present, taps through every step,
    /// and verifies the dashboard + next-workout card appear after
    /// "Get Started" is tapped.
    ///
    /// Why `makeOnboardingApp()` and not a separate `-FreshUser` flag:
    /// existing `-UITestMode 1` without `-SkipOnboarding` already resets
    /// persisted state via `VolumeArcLaunchBootstrapper` and leaves the
    /// user-profile record absent, which is exactly the "fresh user"
    /// starting condition. Adding a new flag for the same semantics
    /// would just multiply the bootstrap matrix.
    func testOnboardingToFirstWorkout() throws {
        let app = VolumeArcAppUITestSupport.makeOnboardingApp()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )

        // Onboarding cover appears.
        let onboardingRoot = app.descendants(matching: .any)
            .matching(identifier: "onboarding.root")
            .firstMatch
        XCTAssertTrue(
            onboardingRoot.waitForExistence(timeout: 15),
            "Onboarding cover should be visible on first launch"
        )

        // Tap "Continue" through the five non-final steps, then
        // "Get Started" to finish.
        //
        // VOL-114 fixed VAButton's accessibility identifier propagation,
        // so the identifier-based query is now reliable.
        //
        // VOL-115: profile step text fields auto-focus and bring up the
        // keyboard, which can cover the Continue button. Dismiss the
        // keyboard before each tap by tapping a non-field area, then
        // proceed. This keeps XCUITest's `kAXScrollToVisibleAction` from
        // failing on covered buttons.
        //
        // 5 = `OnboardingView.Step.allCases.count - 1` (welcome → profile
        // → preferences → coachingStyle → permissions → done). The
        // permissions step (VOL-109) added between coachingStyle and done
        // is "tap Continue to skip Apple Health" by default — this test
        // doesn't engage the Connect button. The last step shows
        // "Get Started" / `onboarding.finish`, not Continue, so it's
        // tapped separately below. If a step is added or removed, update
        // this loop bound — the coupling is intentional rather than read
        // at runtime so the test stays a black-box smoke gate.
        for _ in 0..<5 {
            dismissKeyboardIfPresent(in: app)
            let continueButton = app.descendants(matching: .any)
                .matching(identifier: "onboarding.continue").firstMatch
            XCTAssertTrue(
                continueButton.waitForExistence(timeout: 10),
                "Onboarding should expose a continue button on each non-final step"
            )
            continueButton.tap()
        }

        dismissKeyboardIfPresent(in: app)
        let finishButton = app.descendants(matching: .any)
            .matching(identifier: "onboarding.finish").firstMatch
        XCTAssertTrue(
            finishButton.waitForExistence(timeout: 10),
            "Onboarding should expose a finish button on the last step"
        )
        finishButton.tap()

        // Dashboard appears once `model.updateProfile` persists the new
        // profile and `model.isOnboardingComplete` flips to true. The
        // `.onChange` in `RootDashboardView` drives cover dismissal.
        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 15),
            "Dashboard should appear within 15s after onboarding completes"
        )

        // Sanity check: onboarding cover is gone.
        XCTAssertTrue(
            onboardingRoot.waitForNonExistence(timeout: 5),
            "Onboarding cover should dismiss once onboarding is complete"
        )
    }

    /// VOL-115: dismiss the on-screen keyboard if one is present so it
    /// doesn't cover the action-row buttons. Tapping the navigation bar
    /// region resigns first responder without accidentally hitting any
    /// other interactive element.
    private func dismissKeyboardIfPresent(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        // Use a coordinate-based tap on the top-left where there's no
        // interactive content. Tapping the keyboard's Return key is
        // unreliable across iOS versions; tapping a known-empty region
        // works on every layout.
        let topLeft = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05))
        topLeft.tap()
    }

    // MARK: - 2. Paywall presentation and dismissal

    /// Boots the app already signed in (fixtures seeded, onboarding
    /// complete) with `-ShowPaywallOnLaunch 1`. Asserts the paywall
    /// sheet appears, its legal links are reachable, and the close
    /// button returns the user to the dashboard.
    ///
    /// This is explicitly NOT a full purchase flow — the StoreKit Test
    /// purchase path is covered by `testPremiumPurchaseFlowWithStoreKitTest`.
    func testPaywallPresentationAndDismissal() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(extra: ["-ShowPaywallOnLaunch", "1"])
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )

        // Paywall root is a SwiftUI `NavigationStack` inside a sheet; the
        // identifier is pinned at the stack root so it resolves across
        // SwiftUI hosting-layer revisions.
        let paywallRoot = app.descendants(matching: .any)
            .matching(identifier: "paywall.root")
            .firstMatch
        XCTAssertTrue(
            paywallRoot.waitForExistence(timeout: 15),
            "Paywall sheet should appear when -ShowPaywallOnLaunch 1 is set"
        )

        // Legal links from VOL-71's `LegalLinks` — the identifiers were
        // already added on `PaywallView.swift`. Only assert existence in
        // the accessibility tree (not hittability) since the footer lives
        // below the fold in the ScrollView and the test doesn't actually
        // tap them; validating that the links are WIRED is the point.
        let termsLink = app.descendants(matching: .any)
            .matching(identifier: "paywall.legal.terms")
            .firstMatch
        XCTAssertTrue(
            termsLink.waitForExistence(timeout: 5),
            "Paywall should expose the Terms of Service link"
        )

        let privacyLink = app.descendants(matching: .any)
            .matching(identifier: "paywall.legal.privacy")
            .firstMatch
        XCTAssertTrue(
            privacyLink.waitForExistence(timeout: 5),
            "Paywall should expose the Privacy Policy link"
        )

        // Dismiss via the close button in the navigation bar.
        let closeButton = app.descendants(matching: .any)
            .matching(identifier: "paywall.close")
            .firstMatch
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 5),
            "Paywall should expose a close button"
        )
        closeButton.tap()

        // Dashboard returns after dismissal.
        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 10),
            "Dashboard should be visible again after paywall dismissal"
        )
        XCTAssertTrue(
            paywallRoot.waitForNonExistence(timeout: 5),
            "Paywall sheet should be gone once the close button is tapped"
        )
    }

    // MARK: - 3. StoreKit restore + purchase flows

    /// Boots the paywall and taps "Restore Purchases". The goal is only
    /// to prove the tap path does not crash the app — asserting that
    /// the restore *succeeded* requires a StoreKit Test configuration
    /// and real receipt fixtures, which land in VOL-107.
    func testRestorePurchasesFlow() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(extra: ["-ShowPaywallOnLaunch", "1"])
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )

        let paywallRoot = app.descendants(matching: .any)
            .matching(identifier: "paywall.root")
            .firstMatch
        XCTAssertTrue(
            paywallRoot.waitForExistence(timeout: 15),
            "Paywall sheet should appear when -ShowPaywallOnLaunch 1 is set"
        )

        let restoreButton = app.descendants(matching: .any)
            .matching(identifier: "paywall.restore")
            .firstMatch
        XCTAssertTrue(
            restoreButton.waitForExistence(timeout: 5),
            "Paywall should expose the Restore Purchases button"
        )
        // Scroll the paywall sheet so the Restore button is on-screen and
        // the tap isn't intercepted by `isHittable` gating. The paywall
        // ScrollView contains enough content (hero, feature comparison,
        // plans, action buttons, legal footer) that the bottom
        // action-buttons cluster is typically below the fold on iPhone 17
        // simulator.
        paywallRoot.swipeUp()
        restoreButton.tap()

        // Give the async restore call time to return. Without StoreKit
        // Test configured, the real `AppStore.sync()` call returns with
        // no transactions (or surfaces a network error message) — either
        // path is acceptable here; we only want to prove the button
        // tap is non-fatal.
        Thread.sleep(forTimeInterval: 2.0)
        XCTAssertEqual(
            app.state,
            .runningForeground,
            "App should still be foreground after tapping Restore Purchases"
        )

        // Paywall itself should still be visible — restore does not
        // dismiss it.
        XCTAssertTrue(
            paywallRoot.exists,
            "Paywall should remain presented after Restore Purchases is tapped"
        )
    }

    /// VOL-107: real StoreKit Test purchase flow. A local `.storekit`
    /// config backs Product loading and purchase completion, then the
    /// paywall should dismiss once `StoreKitSubscriptionStore.isPremium`
    /// flips true.
    func testPremiumPurchaseFlowWithStoreKitTest() throws {
        throw XCTSkip(
            "VOL-230: SKTestSession on the M4 self-hosted runner doesn't " +
            "expose local products. Same family as VOL-227's " +
            "testRefundRemovesEntitlementAndRecordsTelemetry skip."
        )
    }

    // MARK: - 4. Active workout completion

    /// VOL-108: end-to-end active workout loop — start a session, log a
    /// set, complete the workout, and verify the summary appears.
    func testStartLogCompleteWorkoutSession() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp()
        app.launch()
        assertAppReachedForeground(app)

        assertElementExists(app.otherElements["root.dashboard"], timeout: 15, "Seeded dashboard should be visible")

        let startButton = waitForElement(
            in: app,
            identifier: "today.startWorkout",
            timeout: 10,
            "Today should expose Start Workout"
        )
        startButton.tap()

        let workoutsTab = app.tabBars.buttons["Workouts"]
        assertElementExists(workoutsTab, timeout: 5, "Tab bar should expose the Workouts tab")
        workoutsTab.tap()

        _ = waitForElement(
            in: app,
            identifier: "workouts.activeSession",
            timeout: 10,
            "Workouts tab should show an active session after Start Workout"
        )

        let logSetButton = waitForElement(
            in: app,
            identifier: "workouts.logSet",
            timeout: 10,
            "Active session should expose Log Set"
        )
        logSetButton.tap()

        let completeButton = waitForElement(
            in: app,
            identifier: "workouts.completeWorkout",
            timeout: 10,
            "Active session should expose Complete Workout"
        )
        expectation(
            for: NSPredicate(format: "isHittable == true"),
            evaluatedWith: completeButton
        )
        waitForExpectations(timeout: 5)
        completeButton.tap()

        let summary = waitForElement(
            in: app,
            identifier: "sessionSummary.root",
            timeout: 30,
            "Completing a workout should present the session summary"
        )

        let done = app.descendants(matching: .any)
            .matching(identifier: "sessionSummary.done")
            .firstMatch
        for _ in 0..<3 where !done.exists {
            summary.swipeUp()
        }
        XCTAssertTrue(
            done.waitForExistence(timeout: 10),
            "Session summary should expose a Done button"
        )
        done.tap()

        _ = waitForElement(
            in: app,
            identifier: "workouts.emptyState",
            timeout: 10,
            "Workouts tab should return to idle state after dismissing summary"
        )
    }

    /// VOL-141: deterministic coverage for `workouts.view-detail`.
    /// The seeded fixture contains recent completed sessions; launching
    /// directly into Workouts avoids relying on tab-bar hit testing.
    func testWorkoutHistoryRowOpensSessionDetailAndEmitsTelemetry() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenWorkoutsOnLaunch", "1"]
        )
        app.launch()
        assertAppReachedForeground(app)

        _ = waitForElement(
            in: app,
            identifier: "workouts.root",
            timeout: 15,
            "Workouts tab should open on launch"
        )

        let historyRow = app.descendants(matching: .any)
            .matching(identifier: "workouts.historyRow")
            .firstMatch
        if !historyRow.waitForExistence(timeout: 15) {
            VolumeArcAppUITestSupport.attachDebugSnapshot(
                of: app,
                named: "workouts.historyRow.missing",
                to: self
            )
            XCTFail("Seeded Workouts tab should expose a completed-session history row")
            return
        }
        XCTAssertTrue(
            VolumeArcAppUITestSupport.scrollIntoViewAndTap(historyRow, in: app, timeout: 1),
            "Completed-session history row should be tappable"
        )

        _ = waitForElement(
            in: app,
            identifier: "session.detail.root",
            timeout: 10,
            "Session detail should appear after tapping a Workouts history row"
        )

        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "workout",
            name: "detail.opened",
            within: 10,
            test: self
        )
    }

    /// VOL-141: deterministic coverage for `workouts.history-scroll`.
    /// Perf mode seeds a 50-session history pool; the journey exercises
    /// the Workouts history surface under that longer list and asserts it
    /// remains responsive after repeated scroll gestures.
    func testWorkoutHistoryScrollStaysResponsiveWithLongHistory() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenWorkoutsOnLaunch", "1", "-PerfTestMode", "1"]
        )
        app.launch()
        assertAppReachedForeground(app)

        let root = waitForElement(
            in: app,
            identifier: "workouts.root",
            timeout: 15,
            "Workouts tab should open on launch"
        )

        let firstHistoryRow = app.descendants(matching: .any)
            .matching(identifier: "workouts.historyRow")
            .firstMatch
        XCTAssertTrue(
            firstHistoryRow.waitForExistence(timeout: 15),
            "Perf-seeded Workouts tab should expose history rows before scrolling"
        )

        // VOL-227 / iOS 26.5 stability: capped at 2 swipes (was 4).
        // The 50-session PerfTestMode seed makes the scroll view AX
        // hierarchy expensive to re-query after each gesture. Under
        // iOS 26.5's fragile AX stack (UIAccessibilityLoaderWebShared
        // duplicate class registration) a 4-swipe sequence was reliably
        // crashing the XCTRunner mid-query. Two swipes still exercises
        // the list-render contract with ~75% less memory pressure.
        for _ in 0..<2 {
            root.swipeUp()
        }

        let postScrollHistoryRow = app.descendants(matching: .any)
            .matching(identifier: "workouts.historyRow")
            .firstMatch
        XCTAssertTrue(
            postScrollHistoryRow.waitForExistence(timeout: 5),
            "History rows should remain reachable after scrolling through the long list"
        )

        root.swipeDown()
        XCTAssertTrue(
            root.exists,
            "Workouts root should remain stable after history scroll gestures"
        )
    }

    // MARK: - 5. Deep-link arrivals

    /// VOL-141: deterministic coverage for `bg.deep-link-arrival`.
    /// The launch argument sends a valid VolumeArc URL through the same
    /// app handler used by external link arrivals while avoiding Safari
    /// or universal-link daemon flake in CI.
    func testExternalDeepLinkRoutesToSignalsAndEmitsTelemetry() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenDeepLinkOnLaunch", "volumearc://signals?source=external"]
        )
        app.launch()
        assertAppReachedForeground(app)

        _ = waitForElement(
            in: app,
            identifier: "signals.root",
            timeout: 15,
            "External deep link should route to the Signals tab"
        )

        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "deeplink",
            name: "received",
            within: 10,
            test: self
        )
    }

    /// VOL-141: deterministic coverage for `widget.tap-deep-link`.
    /// WidgetKit itself is not reliable to automate in CI, but the
    /// production widget attaches `VolumeArcDeepLink.url(for: .today)`
    /// via `.widgetURL(...)`; this exercises the same URL contract at
    /// the app boundary and verifies the telemetry emitted by the
    /// handler remains wired.
    func testWidgetDeepLinkRoutesToTodayAndEmitsTelemetry() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenDeepLinkOnLaunch", "volumearc://today?source=widget"]
        )
        app.launch()
        assertAppReachedForeground(app)

        _ = waitForElement(
            in: app,
            identifier: "today.scroll",
            timeout: 15,
            "Widget deep link should route to the Today tab"
        )

        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "deeplink",
            name: "received",
            within: 10,
            test: self
        )
    }

    private func assertAppReachedForeground(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )
    }

    private func waitForElement(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval,
        _ message: String
    ) -> XCUIElement {
        let element = app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        assertElementExists(element, timeout: timeout, message)
        return element
    }

    private func assertElementExists(
        _ element: XCUIElement,
        timeout: TimeInterval,
        _ message: String
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
    }
}
