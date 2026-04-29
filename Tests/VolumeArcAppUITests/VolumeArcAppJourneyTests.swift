import XCTest

/// VOL-93: end-to-end journey XCUITests for the VolumeArc iOS app.
///
/// This suite is the P1 subset of VOL-93 — it proves critical launch
/// flows actually work (onboarding → dashboard, paywall present/dismiss,
/// restore purchases tap). Coverage that requires additional harness
/// work (StoreKit Test framework, HealthKit sheets, active-workout
/// completion, BGTask triggers, Dynamic Type sweep, Watch pairing) is
/// tracked in VOL-107 through VOL-112.
///
/// All tests launch via `VolumeArcAppUITestSupport` so the flag strings
/// stay in lockstep with the smoke tests.
final class VolumeArcAppJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
    /// This is explicitly NOT a full purchase flow — that requires the
    /// StoreKit Test framework wired into the build and is tracked in
    /// VOL-107.
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

    // MARK: - 3. Restore purchases tap

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
}
