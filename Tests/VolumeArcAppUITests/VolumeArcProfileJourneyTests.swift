// VOL-200 Phase 4 — Profile surface journey coverage.
//
// Closes 2 of the 5 uncovered `profile.*` rows from
// `docs/USER_JOURNEYS.md`:
//   * `profile.edit-profile`
//   * `profile.diagnostics`
//
// Deferred to follow-up PRs:
//   * `profile.coaching-style`  — needs a dedicated
//     `profile.coaching_style.changed` telemetry event at the
//     `save()` call site (currently the only emitted event is the
//     generic `profile.updated`). Wire the event + add the test in
//     the same PR.
//   * `profile.privacy-mode`    — same shape; needs
//     `profile.privacy_mode.changed`.
//   * `profile.manage-subscription` — already deferred to
//     VOL-142 Phase 2 deep-link smoke test.
//
// Both tests use the existing `-OpenProfileOnLaunch 1` affordance
// (added in earlier VOL-200 work) to land on the Profile tab
// without depending on simulator-specific TabView hit testing.

import XCTest

@MainActor
final class VolumeArcProfileJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - profile.edit-profile

    /// Tap the Coaching style row on Profile → assert the Edit
    /// Profile sheet appears → tap Save → assert sheet dismisses.
    /// Telemetry: `profile.updated` fires from
    /// `WorkoutDashboardModel.updateProfile` after Save.
    func testProfileOpenEditAndSaveRoundTripDismissesSheet() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenProfileOnLaunch", "1"]
        )
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )

        // Coaching-style row identifier was added in VOL-200 P4 —
        // ProfileView's "Coaching style" training row taps into the
        // EditProfileView sheet via `isEditingProfile = true`.
        let row = app.descendants(matching: .any)
            .matching(identifier: "profile.coachingStyleRow")
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "Coaching style row should render on Profile within 15s of cold launch"
        )
        row.tap()

        // EditProfileView's Form root carries `editProfile.root`
        // (added VOL-200 P4) so we can confirm the sheet presented
        // without depending on the localized navigation-title text.
        let editRoot = app.descendants(matching: .any)
            .matching(identifier: "editProfile.root")
            .firstMatch
        XCTAssertTrue(
            editRoot.waitForExistence(timeout: 5),
            "EditProfile sheet should appear within 5s of tapping the row"
        )

        let saveButton = app.descendants(matching: .any)
            .matching(identifier: "editProfile.save")
            .firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        // The sheet dismisses on Save (see `save()` → `isPresented = false`).
        // Assert the edit-root is no longer reachable.
        let editRootGone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(
            predicate: editRootGone,
            object: editRoot
        )
        let waitResult = XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertEqual(
            waitResult, .completed,
            "Edit Profile sheet should dismiss within 5s of tapping Save"
        )

        // Telemetry: `profile.updated` is the contract event for the
        // save round-trip. The granular `coaching_style.changed` /
        // `privacy_mode.changed` events documented in the journey
        // catalog rows are not yet wired (follow-up — see header).
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "profile",
            name: "profile_updated",
            within: 10,
            test: self
        )
    }

    // MARK: - profile.diagnostics

    /// Tap the Diagnostics row on Profile → assert DiagnosticsView
    /// pushes onto the navigation stack.
    func testProfileDiagnosticsRowOpensView() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenProfileOnLaunch", "1"]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let row = app.descendants(matching: .any)
            .matching(identifier: "profile.diagnostics")
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "Diagnostics row should render on Profile within 15s of cold launch"
        )
        row.tap()

        let diagnosticsRoot = app.descendants(matching: .any)
            .matching(identifier: "diagnostics.root")
            .firstMatch
        XCTAssertTrue(
            diagnosticsRoot.waitForExistence(timeout: 5),
            "DiagnosticsView should appear within 5s of tapping the row"
        )
    }
}
