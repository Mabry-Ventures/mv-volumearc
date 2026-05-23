// VOL-141 — App Intent journey coverage.
//
// These tests drive the production deep-link handler through a
// deterministic launch argument instead of invoking Siri / Shortcuts.
// The URL shape is the same one returned by `VolumeArcIntents.swift`:
// `?source=intent&intent=<name>`. That keeps the journeys hermetic while
// still proving the app routes to the right surface and records the
// operator-visible `intent/<name>.invoked` telemetry event.

import XCTest

@MainActor
final class VolumeArcIntentJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        let app = XCUIApplication()
        VolumeArcAppUITestSupport.attachDebugSnapshot(
            of: app,
            named: "tearDown.\(name).accessibility-tree",
            to: self
        )
        VolumeArcAppUITestSupport.defensiveTerminate(app)
    }

    // MARK: - intent.start-next-workout

    func testStartNextWorkoutIntentStartsLiveSessionAndEmitsTelemetry() throws {
        let app = launchIntentDeepLink(
            "volumearc://action/startWorkoutSession?source=intent&intent=start_next_workout"
        )

        assertWorkoutsActiveSession(in: app)
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "intent",
            name: "start_next_workout.invoked",
            within: 10,
            test: self
        )
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "workout",
            name: "session_started",
            within: 10,
            test: self
        )
    }

    // MARK: - intent.ask-coach

    func testAskCoachIntentPrefillsPromptAndEmitsTelemetry() throws {
        let expectedPrompt = "Should I deadlift today?"
        let app = launchIntentDeepLink(
            "volumearc://coach?prompt=Should%20I%20deadlift%20today%3F&source=intent&intent=ask_coach"
        )

        let composer = app.descendants(matching: .any)
            .matching(identifier: "coach.input")
            .firstMatch
        XCTAssertTrue(
            composer.waitForExistence(timeout: 15),
            "Coach composer should appear after the ask-coach intent deep link"
        )
        let composerValue = composer.value as? String ?? ""
        XCTAssertTrue(
            composerValue.contains(expectedPrompt),
            "Ask Coach intent should prefill the prompt. Actual value: \(composerValue)"
        )

        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "intent",
            name: "ask_coach.invoked",
            within: 10,
            test: self
        )
    }

    // MARK: - intent.open-signals

    func testOpenSignalsIntentRoutesToSignalsAndEmitsTelemetry() throws {
        let app = launchIntentDeepLink(
            "volumearc://signals?source=intent&intent=open_signals"
        )

        assertSignalsRoot(in: app)
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "intent",
            name: "open_signals.invoked",
            within: 10,
            test: self
        )
    }

    // MARK: - intent.start-workout-session

    func testStartWorkoutSessionIntentStartsLiveSessionAndEmitsTelemetry() throws {
        let app = launchIntentDeepLink(
            "volumearc://action/startWorkoutSession?source=intent&intent=start_workout_session"
        )

        assertWorkoutsActiveSession(in: app)
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "intent",
            name: "start_workout_session.invoked",
            within: 10,
            test: self
        )
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "workout",
            name: "session_started",
            within: 10,
            test: self
        )
    }

    // MARK: - intent.log-recommended-set

    func testLogRecommendedSetIntentLogsSetAndEmitsTelemetry() throws {
        let app = launchIntentDeepLink(
            "volumearc://action/logRecommendedSet?source=intent&intent=log_recommended_set"
        )

        assertWorkoutsActiveSession(in: app)
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "intent",
            name: "log_recommended_set.invoked",
            within: 10,
            test: self
        )
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "workout",
            name: "set_logged",
            within: 10,
            test: self
        )
    }

    // MARK: - intent.sync-volumearc

    func testSyncVolumeArcIntentRoutesToSignalsAndRequestsSync() throws {
        let app = launchIntentDeepLink(
            "volumearc://action/syncNow?source=intent&intent=sync_now"
        )

        assertSignalsRoot(in: app)
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "intent",
            name: "sync_now.invoked",
            within: 10,
            test: self
        )
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "sync",
            name: "sync_requested",
            within: 10,
            test: self
        )
    }

    // MARK: - Helpers

    private func launchIntentDeepLink(_ url: String) -> XCUIApplication {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenDeepLinkOnLaunch", url]
        )
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )
        return app
    }

    private func assertWorkoutsActiveSession(in app: XCUIApplication) {
        let workoutsRoot = app.descendants(matching: .any)
            .matching(identifier: "workouts.root")
            .firstMatch
        XCTAssertTrue(
            workoutsRoot.waitForExistence(timeout: 15),
            "Workouts tab should appear after the workout intent deep link"
        )

        let activeSession = app.descendants(matching: .any)
            .matching(identifier: "workouts.activeSession")
            .firstMatch
        XCTAssertTrue(
            activeSession.waitForExistence(timeout: 15),
            "Workout intent deep link should create and show an active session"
        )
    }

    private func assertSignalsRoot(in app: XCUIApplication) {
        let signalsRoot = app.descendants(matching: .any)
            .matching(identifier: "signals.root")
            .firstMatch
        XCTAssertTrue(
            signalsRoot.waitForExistence(timeout: 15),
            "Signals tab should appear after the intent deep link"
        )
    }
}
