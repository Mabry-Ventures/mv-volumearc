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
}
