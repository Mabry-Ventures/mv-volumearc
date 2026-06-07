import XCTest

/// VOL-179 (Phase 1C of VOL-176 / VOL-146): XCUITest journey for the
/// in-app feedback flow that landed in PR #169.
///
/// The Phase 1B PR delivered the SwiftUI feedback surface (`FeedbackView`) and
/// the App-layer adapter (`VolumeArcFeedbackSubmitter`) but explicitly
/// deferred the XCUITest journey + the `docs/USER_JOURNEYS.md`
/// `profile.send-feedback` row to this ticket so the merge wave
/// could land without coupling the test to the still-flaking
/// chaos+probe bundle interaction (VOL-175).
///
/// Surface contract (set by PR #169):
/// - `profile.feedback` accessibility identifier on the Profile row.
/// - `feedback.sheet` on the sheet root.
/// - `feedback.cancel`, `feedback.submit` on the toolbar / CTA.
/// - `feedback.description` on the `TextEditor`.
/// - `feedback.category.<rawValue>` on each category chip
///   (`bug`, `idea`, `coach_quality`, `other`).
///
/// On submit, the App-layer adapter records a `feedback.submitted`
/// telemetry event with metadata `{category, build, bytes}`. The
/// `VolumeArcTelemetryDebugProbe` (VOL-149) surfaces that event on
/// the `debug.telemetry.events` accessibility overlay, which the
/// `assertTelemetryFired` helper polls for up to 15s.
///
/// Swift 6 strict concurrency: `XCUIApplication` is MainActor-isolated;
/// marking the class `@MainActor` mirrors the chaos / health-permission
/// suites already in this target.
@MainActor
final class VolumeArcFeedbackJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// VOL-164: defensively terminate the host app between test methods
    /// so a hung launch in test N doesn't poison test N+1.
    override func tearDownWithError() throws {
        MainActor.assumeIsolated {
            let app = XCUIApplication()
            VolumeArcAppUITestSupport.defensiveTerminate(app)
        }
    }

    /// Opens the Profile feedback surface, fills in a bug-report
    /// description, taps Submit, and asserts the
    /// `feedback.submitted` telemetry event fires.
    ///
    /// Why the seeded launcher: the Profile row is gated on the
    /// dashboard model existing, which `-SeedFixtures 1` already
    /// guarantees. `-OpenProfileOnLaunch 1` routes the dashboard
    /// straight to the Profile tab so the test doesn't depend on
    /// the tab-bar identity (which has varied between SwiftUI
    /// runtime revisions per the existing chaos journey's notes).
    func testProfileSendFeedbackJourney() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenProfileOnLaunch", "1"]
        )
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground on cold launch"
        )

        // ---- 1. Profile feedback row reachable -------------------
        let feedbackRow = app.descendants(matching: .any)
            .matching(identifier: "profile.feedback")
            .firstMatch
        XCTAssertTrue(
            feedbackRow.waitForExistence(timeout: 15),
            "Profile 'Send feedback' row should be reachable when the App-layer onSendFeedback closure is wired"
        )
        feedbackRow.tap()

        // ---- 2. Feedback surface appears -------------------------
        let sheet = app.descendants(matching: .any)
            .matching(identifier: "feedback.sheet")
            .firstMatch
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "Feedback surface root should appear after tapping the profile row"
        )

        // ---- 3. Pick a category ----------------------------------
        // `bug` is the default selection in `FeedbackView`, but
        // tapping the chip explicitly exercises the picker's tap
        // path (the on-tap closure also fires `VAHaptics.tap()`,
        // and we want that surface to be covered too).
        let bugChip = app.descendants(matching: .any)
            .matching(identifier: "feedback.category.bug")
            .firstMatch
        XCTAssertTrue(
            bugChip.waitForExistence(timeout: 5),
            "Bug category chip should be reachable inside the sheet"
        )
        bugChip.tap()

        // ---- 4. Type a description -------------------------------
        let descriptionEditor = app.descendants(matching: .any)
            .matching(identifier: "feedback.description")
            .firstMatch
        XCTAssertTrue(
            descriptionEditor.waitForExistence(timeout: 5),
            "Description TextEditor should be reachable"
        )
        descriptionEditor.tap()
        // The exact text doesn't matter for the telemetry assertion
        // but a realistic shape exercises the trim + scrub path.
        descriptionEditor.typeText("Crash on paywall after restore tap")

        // ---- 5. Submit -------------------------------------------
        let submitButton = app.descendants(matching: .any)
            .matching(identifier: "feedback.submit")
            .firstMatch
        XCTAssertTrue(
            submitButton.waitForExistence(timeout: 5),
            "Submit button should be reachable"
        )
        XCTAssertTrue(
            submitButton.isEnabled,
            "Submit button should be enabled once description is non-empty"
        )
        submitButton.tap()

        // ---- 6. Telemetry assertion ------------------------------
        // The submitter posts `feedback.submitted` via the same
        // TelemetrySink the rest of the app uses. The probe overlay
        // (`debug.telemetry.events`) emits it; `assertTelemetryFired`
        // polls the overlay's label for up to 15s.
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "feedback",
            name: "submitted",
            test: self
        )

        // ---- 7. Sheet dismissed ----------------------------------
        // The submit closure sets `isPresented = false` in
        // `FeedbackView`. The sheet root accessibility element
        // should disappear shortly after.
        let dismissedDeadline = Date().addingTimeInterval(5)
        while sheet.exists && Date() < dismissedDeadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertFalse(
            sheet.exists,
            "Feedback surface should dismiss after submit completes"
        )
    }

    /// Cancel path: open the sheet, tap Cancel, assert dismissal +
    /// no `feedback.submitted` event fires. Complements the submit
    /// path so future regressions that bind Submit to the wrong
    /// closure surface immediately.
    func testFeedbackCancelDoesNotEmitSubmitTelemetry() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenProfileOnLaunch", "1"]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let feedbackRow = app.descendants(matching: .any)
            .matching(identifier: "profile.feedback")
            .firstMatch
        XCTAssertTrue(feedbackRow.waitForExistence(timeout: 15))
        feedbackRow.tap()

        let sheet = app.descendants(matching: .any)
            .matching(identifier: "feedback.sheet")
            .firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        let cancelButton = app.descendants(matching: .any)
            .matching(identifier: "feedback.cancel")
            .firstMatch
        XCTAssertTrue(
            cancelButton.waitForExistence(timeout: 5),
            "Cancel button should be reachable in the sheet toolbar"
        )
        cancelButton.tap()

        // Wait for dismissal — same shape as the submit-path
        // dismissal probe.
        let dismissedDeadline = Date().addingTimeInterval(5)
        while sheet.exists && Date() < dismissedDeadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertFalse(
            sheet.exists,
            "Feedback surface should dismiss on Cancel"
        )

        // No `feedback.submitted` event should appear within a
        // short window — read the overlay label directly and
        // assert it doesn't contain the submitted event. The
        // probe buffer is 50 events; the cancel path emits
        // nothing, so any presence of the event would indicate
        // the cancel closure was wired wrong.
        let overlay = app.descendants(matching: .any)
            .matching(identifier: "debug.telemetry.events")
            .firstMatch
        if overlay.waitForExistence(timeout: 5) {
            let label = overlay.label
            XCTAssertFalse(
                label.contains("feedback") && label.contains("submitted"),
                "Cancel must not emit feedback.submitted; probe label = \(label)"
            )
        }
    }
}
