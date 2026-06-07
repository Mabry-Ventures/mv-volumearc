// VOL-200 Phase 4 — Profile surface journey coverage.
//
// Closes the currently automated `profile.*` rows from
// `docs/USER_JOURNEYS.md`:
//   * `profile.edit-profile`
//   * `profile.coaching-style`
//   * `profile.privacy-mode`
//   * `profile.diagnostics`
//   * `profile.about`
//   * `profile.session-profiles`
//   * `profile.manage-subscription`
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

    /// Tap the profile header on Profile → assert the Edit
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

        let row = app.descendants(matching: .any)
            .matching(identifier: "profile.hero.edit")
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "Editable profile header should render on Profile within 15s of cold launch"
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

        openCoachingPreferences(from: app)
        tapPickerOption("Minimal", in: app)
        tapCoachingSave(in: app)

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

        openCoachingPreferences(from: app)
        tapPickerOption("Strict", in: app)
        tapCoachingSave(in: app)

        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "profile",
            name: "privacy_mode.changed",
            within: 10,
            test: self
        )
    }

    // MARK: - profile.appearance

    func testProfileAppearancePickerExposesSystemLightAndDarkOnly() throws {
        let app = launchProfileTab()

        let picker = app.descendants(matching: .any)
            .matching(identifier: "profile.appearance.picker")
            .firstMatch
        XCTAssertTrue(
            picker.waitForExistence(timeout: 10),
            "Profile should expose the app appearance picker"
        )
        XCTAssertTrue(app.buttons["System"].exists || app.staticTexts["System"].exists)
        XCTAssertTrue(app.buttons["Light"].exists || app.staticTexts["Light"].exists)
        XCTAssertTrue(app.buttons["Dark"].exists || app.staticTexts["Dark"].exists)
        XCTAssertFalse(app.buttons["Warm"].exists || app.staticTexts["Warm"].exists)
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
        XCTAssertTrue(
            VolumeArcAppUITestSupport.scrollIntoViewAndTap(row, in: app, timeout: 15, maxScrolls: 3),
            "Diagnostics row should be visible and tappable after Profile opens"
        )

        let diagnosticsRoot = app.descendants(matching: .any)
            .matching(identifier: "diagnostics.root")
            .firstMatch
        if !diagnosticsRoot.waitForExistence(timeout: 8) {
            VolumeArcAppUITestSupport.attachDebugSnapshot(
                of: app,
                named: "profile.diagnostics.missing-root",
                to: self
            )
            XCTFail("DiagnosticsView should appear within 8s of tapping the row")
        }
        let export = app.descendants(matching: .any)
            .matching(identifier: "diagnostics.export")
            .firstMatch
        if !export.waitForExistence(timeout: 5) {
            VolumeArcAppUITestSupport.attachDebugSnapshot(
                of: app,
                named: "diagnostics.missing-export",
                to: self
            )
            XCTFail("Diagnostics should expose an export affordance for tester/support reports")
        }
    }

    // MARK: - profile.about

    func testProfileAboutRowOpensUsefulAboutSurface() throws {
        let app = launchProfileTab()

        let row = findProfileRow(identifier: "profile.about", in: app)
        row.tap()

        let aboutRoot = app.descendants(matching: .any)
            .matching(identifier: "profile.about.root")
            .firstMatch
        XCTAssertTrue(
            aboutRoot.waitForExistence(timeout: 5),
            "About screen should appear within 5s of tapping the row"
        )
        XCTAssertTrue(
            app.staticTexts["Privacy posture"].waitForExistence(timeout: 5),
            "About screen should explain the privacy posture"
        )
        XCTAssertTrue(
            app.staticTexts["Support"].waitForExistence(timeout: 5),
            "About screen should expose support"
        )
    }

    // MARK: - profile.session-profiles

    func testSessionProfilesCanCreateCustomProfileAndExposeRules() throws {
        let app = launchProfileTab()

        let row = findProfileRow(identifier: "profile.sessionProfilesRow", in: app)
        row.tap()

        let sheet = app.descendants(matching: .any)
            .matching(identifier: "profile.sessionProfiles.sheet")
            .firstMatch
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "Session Profiles sheet should appear"
        )

        let nameField = app.textFields["profile.sessionProfiles.newName"].firstMatch
        XCTAssertTrue(
            nameField.waitForExistence(timeout: 5),
            "Session Profiles should expose a custom profile name field"
        )
        nameField.tap()
        nameField.typeText("Pull Day")

        let addButton = app.buttons["profile.sessionProfiles.add"].firstMatch
        XCTAssertTrue(
            addButton.waitForExistence(timeout: 5),
            "Session Profiles should expose an Add profile action"
        )
        addButton.tap()

        XCTAssertTrue(
            app.staticTexts["Pull Day"].waitForExistence(timeout: 5),
            "New custom profile should appear after adding it"
        )

        let legDayRule = app.switches["profile.sessionProfiles.rule.legDay"].firstMatch
        scrollUntilVisible(legDayRule, in: sheet, app: app)
        XCTAssertTrue(
            legDayRule.waitForExistence(timeout: 5),
            "Session Profiles should expose weekday rules"
        )

        let saveButton = app.buttons["Save"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let updatedRow = findProfileRow(identifier: "profile.sessionProfilesRow", in: app)
        XCTAssertTrue(
            updatedRow.label.localizedCaseInsensitiveContains("Pull Day"),
            "Profile row should show the active custom session profile; label=\(updatedRow.label), value=\(updatedRow.value)"
        )
    }

    // MARK: - profile.manage-subscription

    func testProfileManageSubscriptionRecordsTelemetryWithoutLeavingApp() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: [
                "-OpenProfileOnLaunch", "1",
                "-UseScreenshotStoreKitFixtures", "1",
                "-UsePremiumEntitlementFixture", "1",
                "-SuppressSubscriptionManageExternalURL", "1",
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let subscriptionCard = app.descendants(matching: .any)
            .matching(identifier: "profile.subscription")
            .firstMatch
        XCTAssertTrue(
            subscriptionCard.waitForExistence(timeout: 15),
            "Profile should render the subscription card"
        )
        XCTAssertTrue(
            subscriptionCard.label.localizedCaseInsensitiveContains("manage"),
            "Premium fixture should render the Manage subscription action"
        )
        subscriptionCard.tap()

        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "subscription",
            name: "manage_opened",
            within: 10,
            test: self
        )
        XCTAssertEqual(
            app.state,
            .runningForeground,
            "Suppressed subscription manage URL should keep the app foreground for deterministic UI tests"
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

    private func findProfileRow(identifier: String, in app: XCUIApplication) -> XCUIElement {
        let row = app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        let scrollView = app.scrollViews.firstMatch
        var scrollCount = 0
        while (!row.exists || !isVisible(row, in: app)) && scrollCount < 6 {
            scrollView.swipeUp()
            scrollCount += 1
        }
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "\(identifier) row should be reachable on Profile"
        )
        XCTAssertTrue(
            isVisible(row, in: app),
            "\(identifier) row should be visible on Profile"
        )
        return row
    }

    private func openEditProfile(from app: XCUIApplication) {
        let row = app.descendants(matching: .any)
            .matching(identifier: "profile.hero.edit")
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "Editable profile header should render on Profile within 15s of cold launch"
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

    private func openCoachingPreferences(from app: XCUIApplication) {
        let row = app.descendants(matching: .any)
            .matching(identifier: "profile.coachingStyleRow")
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "Coaching style row should render on Profile within 15s of cold launch"
        )
        row.tap()

        let sheet = app.descendants(matching: .any)
            .matching(identifier: "profile.coaching.sheet")
            .firstMatch
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "Coaching preferences sheet should appear within 5s of tapping the row"
        )
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

    private func scrollUntilVisible(
        _ element: XCUIElement,
        in scrollContainer: XCUIElement,
        app: XCUIApplication,
        maxScrolls: Int = 6
    ) {
        var scrollCount = 0
        while (!element.exists || !isVisible(element, in: app)) && scrollCount < maxScrolls {
            scrollContainer.swipeUp()
            scrollCount += 1
        }
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

    private func tapCoachingSave(in app: XCUIApplication) {
        let saveButton = app.descendants(matching: .any)
            .matching(identifier: "profile.coaching.save")
            .firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
    }
}
