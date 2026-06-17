// VOL-200 Phase 3 — Today-tab journey coverage.
//
// Closes 4 of the 5 `today.*` rows from `docs/USER_JOURNEYS.md`:
//   * `today.next-workout-tap`     → workout detail opens
//   * `today.recent-session-tap`   → session detail opens
//   * `today.quick-action-launch`  → Ask Coach quick action opens Coach
//   * `today.readiness-tap`        → readiness tile opens Signals
//
// Deferred:
//   * `today.dashboard-view`       (existing loose-match in
//     `testRootDashboardIdentifierExists`; full hero/cards check
//     follows when the visual snapshot suite from VOL-201 lands its
//     per-trait Today baseline)
//
// All four tests rely on the seeded Today fixture (the dashboard
// model loads recent sessions + a next-workout recommendation on
// launch in `-UITestMode` thanks to `VolumeArcAppUITestSupport.makeSeededApp`).
// The co-design schedule proof also starts from Today because the
// product journey begins at the "Plan tomorrow" card, then moves through
// Coach into the scheduled Workouts surface.
//
// Telemetry assertions use `VolumeArcAppUITestSupport.assertTelemetryFired`
// against the journey-catalog event names (`workout.detail.opened`,
// `workout.history.opened`). The Ask-Coach quick action does not
// have a guaranteed standalone event in the current implementation;
// the test asserts navigation reached the Coach surface instead
// (the `today.askCoach` → `coach.question_sent` chain is covered by
// `VolumeArcCoachJourneyTests` once a question is sent).

import XCTest

@MainActor
final class VolumeArcTodayJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - today.readiness-tap

    /// Tap the Today readiness tile → assert the Signals tab opens and
    /// the readiness telemetry event fires from `SignalsView.task`.
    func testTodayReadinessTapOpensSignals() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-UseAuthorizedHealthFixture"]
        )
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )

        let readiness = app.descendants(matching: .any)
            .matching(identifier: "today.readinessTile")
            .firstMatch
        XCTAssertTrue(
            readiness.waitForExistence(timeout: 15),
            "Readiness tile should render on Today within 15s of cold launch"
        )
        readiness.tap()

        let signalsRoot = app.descendants(matching: .any)
            .matching(identifier: "signals.root")
            .firstMatch
        XCTAssertTrue(
            signalsRoot.waitForExistence(timeout: 10),
            "Signals should appear within 10s of tapping the Today readiness tile"
        )

        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "signals",
            name: "readiness.opened",
            within: 10,
            test: self
        )
    }

    // MARK: - fail.healthkit-not-granted

    /// Apple Health not granted → Today tells the truth about readiness
    /// quality, records the fallback telemetry event, and routes the
    /// user to Profile where the Health connection control lives.
    func testTodayHealthKitUnavailableShowsUnlockStateAndTelemetry() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp()
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )

        let readiness = app.descendants(matching: .any)
            .matching(identifier: "today.readinessTile")
            .firstMatch
        XCTAssertTrue(
            readiness.waitForExistence(timeout: 15),
            "Readiness tile should render on Today within 15s of cold launch"
        )
        XCTAssertTrue(
            readiness.label.localizedCaseInsensitiveContains("Grant Health to unlock"),
            "Readiness tile should expose the Apple Health unlock state when HealthKit is not authorized"
        )

        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "healthkit",
            name: "unavailable",
            within: 10,
            test: self
        )

        readiness.tap()
        let profileRoot = app.descendants(matching: .any)
            .matching(identifier: "profile.root")
            .firstMatch
        XCTAssertTrue(
            profileRoot.waitForExistence(timeout: 10),
            "Tapping the not-connected readiness card should open Profile to connect Apple Health"
        )
    }

    // MARK: - today.next-workout-tap

    /// Tap the next-workout card on Today → assert WorkoutDetailView
    /// pushes onto the navigation stack.
    func testTodayNextWorkoutTapOpensDetail() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp()
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )

        // Today is the default tab. The card identifier was added in
        // VOL-93 (`today.nextWorkoutCard` on the NavigationLink root).
        let card = app.descendants(matching: .any)
            .matching(identifier: "today.nextWorkoutCard")
            .firstMatch
        XCTAssertTrue(
            card.waitForExistence(timeout: 15),
            "Next workout card should render on Today within 15s of cold launch"
        )
        card.tap()

        // WorkoutDetailView root identifier added in VOL-200 P3 so the
        // journey test can confirm the push without depending on
        // navigation-title text (which is localized + dynamic).
        let detailRoot = app.descendants(matching: .any)
            .matching(identifier: "workout.detail.root")
            .firstMatch
        XCTAssertTrue(
            detailRoot.waitForExistence(timeout: 5),
            "WorkoutDetailView should appear within 5s of tapping the card"
        )

        let illustration = app.descendants(matching: .any)
            .matching(identifier: "workout.detail.exerciseIllustration")
            .firstMatch
        XCTAssertTrue(
            illustration.waitForExistence(timeout: 5),
            "WorkoutDetailView should show the bundled exercise illustration, not only the custom cue generator"
        )
    }

    // MARK: - today.recent-session-tap

    /// Tap a recent session row on Today → assert SessionDetailView
    /// pushes onto the navigation stack.
    func testTodayRecentSessionTapOpensDetail() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        // The recentSessions section renders the first 3 rows by
        // default (full pool only in -PerfTestMode). `firstMatch` is
        // a stable resolver since the row identifier is non-indexed
        // (see TodayView.sessionRow comments — added in VOL-200 P3).
        let row = app.descendants(matching: .any)
            .matching(identifier: "today.recentSession")
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "Recent session row should render on Today within 15s of cold launch"
        )
        row.tap()

        let detailRoot = app.descendants(matching: .any)
            .matching(identifier: "session.detail.root")
            .firstMatch
        XCTAssertTrue(
            detailRoot.waitForExistence(timeout: 5),
            "SessionDetailView should appear within 5s of tapping a row"
        )
    }

    // MARK: - today.quick-action-launch

    /// Tap the Ask Coach quick action on Today → assert the Coach tab
    /// becomes visible (the action calls `navigation.openCoach(...)`).
    func testTodayAskCoachQuickActionOpensCoach() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let askCoach = app.descendants(matching: .any)
            .matching(identifier: "today.askCoach")
            .firstMatch
        XCTAssertTrue(
            askCoach.waitForExistence(timeout: 15),
            "Ask Coach quick action should render on Today within 15s of cold launch"
        )
        askCoach.tap()

        // The action routes to the Coach tab via
        // `DashboardNavigationModel.openCoach(prompt:)`. The Coach
        // input field is the most reliable Coach-surface indicator —
        // it's the only text-input region on that tab.
        let composer = app.descendants(matching: .any)
            .matching(identifier: "coach.input")
            .firstMatch
        XCTAssertTrue(
            composer.waitForExistence(timeout: 10),
            "Coach composer should appear within 10s of tapping the quick action"
        )
    }

    // MARK: - co-design schedule proof

    /// Start from the Today "Plan tomorrow" card, schedule the
    /// co-designed draft, and assert Workouts reflects the persisted
    /// plan. This is not counted as a separate `today.*` catalog row;
    /// it is release evidence for VOL-275's co-design persistence gate.
    func testTodayPlanTomorrowSchedulesCoDesignedDraftIntoWorkouts() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let planTomorrow = app.descendants(matching: .any)
            .matching(identifier: "today.planTomorrow")
            .firstMatch
        XCTAssertTrue(
            planTomorrow.waitForExistence(timeout: 15),
            "Plan tomorrow card should render on Today within 15s of cold launch"
        )
        planTomorrow.tap()

        let planDraft = app.descendants(matching: .any)
            .matching(identifier: "coach.planDraft")
            .firstMatch
        XCTAssertTrue(
            planDraft.waitForExistence(timeout: 10),
            "Co-designed plan draft should appear after tapping Plan tomorrow"
        )

        // PR #363: the co-design dedupe removed the actionGrid Schedule
        // button that owned the unsuffixed identifier; the footer button
        // is the single surviving Schedule action.
        let schedule = app.descendants(matching: .any)
            .matching(identifier: "coach.plan.schedule.footer")
            .firstMatch
        XCTAssertTrue(
            VolumeArcAppUITestSupport.scrollIntoViewAndTap(schedule, in: app, timeout: 10, maxScrolls: 4),
            "Co-designed plan Schedule action should be reachable"
        )

        let workoutsRoot = app.descendants(matching: .any)
            .matching(identifier: "workouts.root")
            .firstMatch
        XCTAssertTrue(
            workoutsRoot.waitForExistence(timeout: 10),
            "Workouts should appear after scheduling the co-designed plan"
        )
        XCTAssertTrue(
            app.staticTexts["Lower-body hypertrophy"].waitForExistence(timeout: 10),
            "Scheduled co-designed plan title should appear in Workouts"
        )
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "coach",
            name: "plan_scheduled",
            within: 10,
            test: self
        )
    }

    func testTodayPlanTomorrowEditsExerciseRowsBeforeScheduling() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let planTomorrow = app.descendants(matching: .any)
            .matching(identifier: "today.planTomorrow")
            .firstMatch
        XCTAssertTrue(planTomorrow.waitForExistence(timeout: 15))
        planTomorrow.tap()

        let planDraft = app.descendants(matching: .any)
            .matching(identifier: "coach.planDraft")
            .firstMatch
        XCTAssertTrue(planDraft.waitForExistence(timeout: 10))
        let dismissKeyboard = app.buttons["coach.keyboardDismiss"].firstMatch
        if dismissKeyboard.waitForExistence(timeout: 2), dismissKeyboard.isHittable {
            dismissKeyboard.tap()
        }

        // The draft's exercise rows materialize when the seeded response
        // finishes streaming, and the chat is a lazy container — swiping
        // while rows are still materializing scrolls the card's top out
        // of the viewport and DEmaterializes the very rows being polled
        // (each blind discovery swipe makes the next poll less likely to
        // succeed). Wait for materialization without scrolling first;
        // only then scroll the toggle into view.
        let firstExerciseToggle = app.descendants(matching: .any)
            .matching(identifier: "coach.plan.exercise.0.toggle")
            .firstMatch
        XCTAssertTrue(
            firstExerciseToggle.waitForExistence(timeout: 20),
            "Co-design exercise rows should materialize once the draft finishes streaming"
        )
        // Lift the card so row 0 clears the floating quick-prompt rail —
        // its rest position leaves the row's lower half underneath it.
        // An anchored slow drag scrolls this ScrollView reliably where a
        // velocity flick (swipeUp) rubber-bands back to the rest offset.
        let dragStart = firstExerciseToggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)
        )
        dragStart.press(
            forDuration: 0.15,
            thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: -260))
        )
        XCTAssertTrue(
            VolumeArcAppUITestSupport.scrollIntoViewAndTap(
                firstExerciseToggle,
                in: app,
                timeout: 10,
                maxScrolls: 4,
                preferAnchoredDrags: true
            ),
            "First co-design exercise row should expand"
        )
        XCTAssertTrue(
            VolumeArcAppUITestSupport.scrollIntoViewAndTap(
                app.descendants(matching: .any).matching(identifier: "coach.plan.exercise.0.swap").firstMatch,
                in: app,
                timeout: 5,
                maxScrolls: 2,
                preferAnchoredDrags: true
            ),
            "First co-design exercise should expose a Swap action"
        )
        let frontSquat = app.staticTexts["Front Squat"].firstMatch
        XCTAssertTrue(frontSquat.waitForExistence(timeout: 5), "Swap should replace Back Squat with Front Squat")

        XCTAssertTrue(
            VolumeArcAppUITestSupport.scrollIntoViewAndTap(
                app.descendants(matching: .any).matching(identifier: "coach.plan.exercise.0.moveDown").firstMatch,
                in: app,
                timeout: 5,
                maxScrolls: 2,
                preferAnchoredDrags: true
            ),
            "Moved co-design exercise should expose a Move down action"
        )
        let romanianDeadlift = app.staticTexts["Romanian Deadlift"].firstMatch
        XCTAssertTrue(romanianDeadlift.waitForExistence(timeout: 5))
        XCTAssertTrue(frontSquat.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            romanianDeadlift.frame.minY,
            frontSquat.frame.minY,
            "Move down should put Romanian Deadlift above the swapped Front Squat row"
        )

        XCTAssertTrue(
            VolumeArcAppUITestSupport.scrollIntoViewAndTap(
                app.descendants(matching: .any).matching(identifier: "coach.plan.exercise.1.sets.increment").firstMatch,
                in: app,
                timeout: 5,
                maxScrolls: 2,
                preferAnchoredDrags: true
            ),
            "Moved co-design exercise should keep stepper controls reachable"
        )
        let editedSets = app.descendants(matching: .any)
            .matching(identifier: "coach.plan.exercise.1.sets.value")
            .firstMatch
        XCTAssertTrue(editedSets.waitForExistence(timeout: 5))
        XCTAssertEqual(editedSets.label, "5")

        // VOL-288: the remove → schedule-after-edits tail is quarantined.
        // XCUITest taps dispatched at the remove control land on another
        // receiver near the coach list's bottom viewport edge (forensics
        // on the ticket: rubber-banded flicks, rail-band tap eating,
        // viewport-clipped frames), while expansion/swap/move/sets above
        // are deterministic and a manual tap removes the row fine. The
        // schedule path stays covered end-to-end by
        // testTodayPlanTomorrowSchedulesCoDesignedDraftIntoWorkouts;
        // re-enable once the coach list gets bottom clearance for the
        // rail + composer.
        throw XCTSkip(
            "VOL-288: co-design remove/schedule tail quarantined — XCUI tap "
                + "dispatch near the coach list's bottom viewport edge lands "
                + "on the wrong receiver; expand/swap/move/sets remain covered."
        )
    }
}
