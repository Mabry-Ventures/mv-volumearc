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

        // Tap "Continue" through the four non-final steps, then
        // "Get Started" to finish. The continue and finish buttons share
        // `onboarding.continue` / `onboarding.finish` identifiers so the
        // test doesn't depend on localized titles.
        //
        // We query `onboarding.continue` repeatedly because SwiftUI
        // rebuilds the button's identity between steps (`withAnimation`
        // + state change) — the hit-testable element changes every tap.
        for _ in 0..<4 {
            let continueButton = app.descendants(matching: .any)
                .matching(identifier: "onboarding.continue")
                .firstMatch
            XCTAssertTrue(
                continueButton.waitForExistence(timeout: 10),
                "Onboarding should expose a continue button on each non-final step"
            )
            continueButton.tap()
        }

        let finishButton = app.descendants(matching: .any)
            .matching(identifier: "onboarding.finish")
            .firstMatch
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

        // Sanity check: onboarding cover is gone. `waitForNonExistence`
        // polls until the element is dismissed; if the cover is still
        // there after the timeout the assertion fails.
        XCTAssertTrue(
            onboardingRoot.waitForNonExistence(timeout: 5),
            "Onboarding cover should dismiss once onboarding is complete"
        )

        // The Today tab should show a workout ready to start. The Today
        // tab is the default selected tab; we rely on the existing
        // dashboard refresh path to populate the next-workout card.
        // Note: without `-SeedFixtures` the default-plan Monday/Wed/Fri
        // workouts are used; the first autopilot pass gives us a valid
        // recommendation even for a brand-new profile.
        let nextWorkoutCard = app.descendants(matching: .any)
            .matching(identifier: "today.nextWorkoutCard")
            .firstMatch
        XCTAssertTrue(
            nextWorkoutCard.waitForExistence(timeout: 15),
            "Today tab should surface a workout-ready card once onboarding finishes"
        )
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
        // already added on `PaywallView.swift`.
        let termsLink = app.descendants(matching: .any)
            .matching(identifier: "paywall.legal.terms")
            .firstMatch
        XCTAssertTrue(
            termsLink.waitForExistence(timeout: 5),
            "Paywall should expose the Terms of Service link"
        )
        XCTAssertTrue(termsLink.isHittable, "Terms of Service link should be tappable")

        let privacyLink = app.descendants(matching: .any)
            .matching(identifier: "paywall.legal.privacy")
            .firstMatch
        XCTAssertTrue(
            privacyLink.waitForExistence(timeout: 5),
            "Paywall should expose the Privacy Policy link"
        )
        XCTAssertTrue(privacyLink.isHittable, "Privacy Policy link should be tappable")

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
        XCTAssertTrue(restoreButton.isHittable, "Restore Purchases button should be tappable")
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
