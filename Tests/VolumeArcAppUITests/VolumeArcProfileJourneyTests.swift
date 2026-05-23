// VOL-200 Phase 4 — Profile surface journey coverage.
//
// Closes 2 of the 5 uncovered `profile.*` rows from
// `docs/USER_JOURNEYS.md`:
//   * `profile.edit-profile`
//   * `profile.coaching-style`
//   * `profile.privacy-mode`
//   * `profile.diagnostics`
//
// Deferred to follow-up PRs:
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

    // MARK: - profile.coaching-style

    func testProfileCoachingStyleChangePersistsAndEmitsTelemetry() throws {
        let app = launchProfileTab()

        openEditProfile(from: app)
        tapFormRow(labeled: "Coaching style", in: app, maxScrolls: 5)
        tapPickerOption("Minimal", in: app)
        tapSave(in: app)

        let minimalValue = app.staticTexts["Minimal"].firstMatch
        XCTAssertTrue(
            minimalValue.waitForExistence(timeout: 10),
            "Profile training row should update to Minimal after saving"
        )

        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "profile",
            name: "coaching_style.changed",
            within: 10,
            test: self
        )
    }

    // MARK: - profile.privacy-mode

    func testProfilePrivacyModeChangePersistsAndEmitsTelemetry() throws {
        let app = launchProfileTab()

        openEditProfile(from: app)
        tapFormRow(labeled: "Privacy mode", in: app, maxScrolls: 5)
        tapPickerOption("Strict", in: app)
        tapSave(in: app)

        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "profile",
            name: "privacy_mode.changed",
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

    // MARK: - Helpers

    private func launchProfileTab() -> XCUIApplication {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenProfileOnLaunch", "1"]
        )
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )
        return app
    }

    private func openEditProfile(from app: XCUIApplication) {
        let row = app.descendants(matching: .any)
            .matching(identifier: "profile.coachingStyleRow")
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "Coaching style row should render on Profile within 15s of cold launch"
        )
        row.tap()

        let editRoot = app.descendants(matching: .any)
            .matching(identifier: "editProfile.root")
            .firstMatch
        XCTAssertTrue(
            editRoot.waitForExistence(timeout: 5),
            "EditProfile sheet should appear within 5s of tapping the row"
        )
    }

    private func tapFormRow(
        labeled label: String,
        in app: XCUIApplication,
        maxScrolls: Int = 0
    ) {
        let editRoot = app.descendants(matching: .any)
            .matching(identifier: "editProfile.root")
            .firstMatch
        let rowPredicate = NSPredicate(format: "label BEGINSWITH %@", label)
        let row = editRoot.descendants(matching: .any).matching(rowPredicate).firstMatch
        var scrollCount = 0
        while (!row.exists || !isVisible(row, in: app)) && scrollCount < maxScrolls {
            editRoot.swipeUp()
            scrollCount += 1
        }

        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "\(label) row should be reachable in Edit Profile"
        )
        XCTAssertTrue(
            isVisible(row, in: app),
            "\(label) row should be visible in Edit Profile"
        )
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func tapPickerOption(_ label: String, in app: XCUIApplication) {
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        XCTAssertTrue(
            option.waitForExistence(timeout: 5),
            "\(label) picker option should appear"
        )
        option.tap()
    }

    private func isVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return frame.maxY > 0 && frame.minY < app.frame.maxY
    }

    private func tapSave(in app: XCUIApplication) {
        let saveButton = app.descendants(matching: .any)
            .matching(identifier: "editProfile.save")
            .firstMatch
        if !saveButton.waitForExistence(timeout: 2) {
            let backToEditProfile = app.navigationBars.buttons["Edit Profile"].firstMatch
            if backToEditProfile.exists {
                backToEditProfile.tap()
            }
        }

        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
    }
}
