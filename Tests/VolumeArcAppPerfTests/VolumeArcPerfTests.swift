import XCTest

/// VOL-99: performance regression suite.
///
/// Ships the four budget-bearing metrics called out in the VOL-99 Linear
/// ticket. **Numeric budgets are NOT duplicated in these comments —
/// they live in `docs/performance-budgets.json` keyed by the IDs below.
/// Read the budget file for the current pass/fail thresholds, never
/// these comments.** (VOL-221 audit follow-up: prior comments listed
/// 1.2s cold-launch + fps/hitch scroll budgets that no longer match
/// the actual budget file, which now enforces duration-based gates.)
///
/// * `testColdLaunchTime` — `XCTApplicationLaunchMetric` against the
///   seeded `-PerfTestMode 1` build. Budget ID: `cold_launch`.
/// * `testTodayScrollPerformance` — `XCTOSSignpostMetric.scrollingAndDecelerationMetric`
///   while scrolling the Today tab's recent-sessions list with 50 seeded rows.
///   Budget ID: `today_scroll_duration` (per-iteration duration in seconds,
///   not a hitch ratio — see the budget file's `description` for why).
/// * `testMemoryFootprintDuringWorkout` — `XCTMemoryMetric` over a short
///   synthetic "active workout" exercising the Workouts tab's rest
///   timer + session header. Budget ID: `workout_memory_peak`.
/// * `testCoachFirstTokenLatency` — a custom `XCTClockMetric`
///   measurement from the "Ask Coach" tap to the first streaming coach
///   bubble appearing with non-empty content. Budget ID:
///   `coach_first_token_latency`.
///
/// Each test calls `measure(metrics:options:block:)`. The XCTest runner
/// serializes the per-iteration metrics into the `.xcresult` bundle;
/// `scripts/check_performance.sh` parses them with `xcrun xcresulttool`
/// and compares the mean against the budgets in
/// `docs/performance-budgets.json`, failing the build when any metric
/// breaches its fail-threshold.
///
/// The suite is **not** run on every PR — see the `perf-regression`
/// job in `.github/workflows/ci.yml`, which is tag-gated (`on: push:
/// tags: ['v*']`) to keep CI cost bounded.
///
/// The `@MainActor` annotation on the class is required by Swift 6 /
/// Xcode 26 — `XCUIApplication` and every `XCUIElement` descendant are
/// `@MainActor`-isolated, so calls like `app.launch()` and `app.buttons[...]`
/// would otherwise generate isolation warnings (promoted to errors by
/// the project's SwiftLint+warning policy).
@MainActor
final class VolumeArcPerfTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Cold launch

    /// Budget ID: `cold_launch` in `docs/performance-budgets.json`.
    ///
    /// `XCTApplicationLaunchMetric` tears down and re-launches the
    /// hosted app on each iteration so the measurement captures real
    /// cold-launch cost — process spawn, binary load, dyld link,
    /// `+load`, and the first-frame paint — not a warm relaunch.
    func testColdLaunchTime() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            let app = makePerfApp()
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 20)
        }
    }

    // MARK: - Today scroll performance

    /// Scroll performance across 50 seeded workout rows.
    ///
    /// Budget ID: `today_scroll_duration` in
    /// `docs/performance-budgets.json`. The gate compares a
    /// per-iteration **duration** in seconds (NOT a hitches-per-second
    /// or fps-mean derivation — those were prior assumptions; see the
    /// budget file's `description` for the rationale). We use
    /// `XCTOSSignpostMetric.scrollingAndDecelerationMetric` (which
    /// instruments the scroll interaction itself) plus
    /// `XCTMemoryMetric` as a secondary guard against UI-side leaks
    /// during long scroll runs. The future-improvement candidate is
    /// `XCTOSSignpostMetric.scrollDecelerationHitchTimeRatioMetric`
    /// for direct hitch-ratio signal (also noted in the budget file).
    func testTodayScrollPerformance() throws {
        let app = makePerfApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(
            scroll.waitForExistence(timeout: 10),
            "Today tab scroll view should be reachable within 10s in -PerfTestMode"
        )

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(
            metrics: [
                XCTOSSignpostMetric.scrollingAndDecelerationMetric,
                XCTMemoryMetric(application: app),
            ],
            options: options
        ) {
            // Perform multiple large swipes so the measurement samples
            // a realistic number of frames. Five swipe-ups + five
            // swipe-downs gives the framework enough data to compute a
            // stable mean frame rate and hitch count per iteration.
            for _ in 0..<5 {
                scroll.swipeUp()
            }
            for _ in 0..<5 {
                scroll.swipeDown()
            }
        }
    }

    // MARK: - Memory footprint

    /// Memory budget: <150MB steady-state after a 5-minute workout;
    /// fail at +20% (>180MB). We compress "5 minutes" into a 45-second
    /// iteration (the rest timer runs at 1Hz, so this still exercises
    /// the same periodic view refresh pattern) and average across
    /// iterations so transient allocation spikes don't poison the
    /// measurement.
    func testMemoryFootprintDuringWorkout() throws {
        let app = makePerfApp(extraArguments: [
            "-OpenDeepLinkOnLaunch", "volumearc://action/startWorkoutSession",
        ])
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let activeSession = app.descendants(matching: .any)
            .matching(identifier: "workouts.activeSession")
            .firstMatch
        XCTAssertTrue(
            activeSession.waitForExistence(timeout: 20),
            "Perf memory test should measure the active workout surface, not the default Today tab."
        )

        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTMemoryMetric(application: app)], options: options) {
            // Poll for 45 seconds — long enough to observe real
            // steady-state footprint while the rest timer updates every
            // second. Much shorter and we'd capture the allocation
            // overshoot from the first timer tick; much longer and we'd
            // triple the CI cost of a single iteration.
            let deadline = Date().addingTimeInterval(45)
            while Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(1))
            }
        }
    }

    // MARK: - Coach first-token latency

    /// Coach first-token latency budget: <800ms P50, <2s P95.
    ///
    /// We measure the clock time from the "Ask Coach" quick-action tap
    /// to the first streaming coach bubble appearing with non-empty
    /// content (identified by the `coach.firstResponse` accessibility
    /// identifier, which is only assigned once the bubble has
    /// received its first token).
    ///
    /// `-PerfTestMode 1` guarantees the coach runs through the
    /// `LocalHeuristicAICoachProvider` fallback (no network), so this
    /// test is hermetic — no relay dependency, no live-model variance.
    /// The fallback streams one word every 30ms, so the first-token
    /// time is dominated by view setup, not network.
    func testCoachFirstTokenLatency() throws {
        let app = makePerfApp(extraArguments: ["-OpenCoachOnLaunch", "1"])
        defer { app.terminate() }

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        // VOL-126 / first tag-deploy smoke: opt into manual measurement
        // control so each iteration begins with the clock OFF. The
        // composer setup (find Today's "Ask Coach" quick action, tap to
        // open Coach, type the prompt) varies per iteration with the
        // simulator's animation/idle state — including those taps in
        // the measured window would inflate the latency reading well
        // beyond the actual ask→first-token cost.
        //
        // With `[.manuallyStart, .manuallyStop]` each iteration enters
        // un-measured: launch a fresh seeded app, navigate to Coach, type
        // the prompt, then call `startMeasuring()` to begin the measured
        // action (`sendButton.tap()` → first-token response) and
        // `stopMeasuring()` immediately after the wait returns.
        options.invocationOptions = [.manuallyStart, .manuallyStop]

        measure(metrics: [XCTClockMetric()], options: options) {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

            openCoachComposer(in: app)

            let composerInput = app.textFields["coach.input"].firstMatch
            XCTAssertTrue(composerInput.waitForExistence(timeout: 5))
            composerInput.tap()
            composerInput.typeText("How does my recent volume look?")

            let sendButton = app.buttons["coach.send"].firstMatch
            XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
            XCTAssertTrue(sendButton.isEnabled && sendButton.isHittable, "Coach send button should be armed before measuring.")

            let firstResponse = app.descendants(matching: .any)
                .matching(identifier: "coach.firstResponse")
                .firstMatch
            XCTAssertFalse(firstResponse.exists, "Fresh perf launch should not contain a stale coach response.")

            self.startMeasuring()
            sendButton
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .tap()

            let didReceiveFirstToken = waitForVisibleFirstToken(firstResponse, timeout: 10)
            self.stopMeasuring()
            XCTAssertTrue(didReceiveFirstToken, "Coach first response should stream within the perf timeout.")
        }
    }

    // MARK: - Helpers

    private func openCoachComposer(in app: XCUIApplication) {
        let composer = app.descendants(matching: .any)
            .matching(identifier: "coach.composer")
            .firstMatch
        let composerInput = app.textFields["coach.input"].firstMatch
        if composer.waitForExistence(timeout: 1),
           composerInput.waitForExistence(timeout: 1),
           composerInput.isHittable {
            return
        }

        if tapCoachTab(in: app),
           composer.waitForExistence(timeout: 5),
           composerInput.waitForExistence(timeout: 1),
           composerInput.isHittable {
            return
        }

        let askCoachQuickAction = app.buttons["today.askCoach"].firstMatch
        if askCoachQuickAction.waitForExistence(timeout: 5) {
            askCoachQuickAction.tap()
        }

        XCTAssertTrue(
            composer.waitForExistence(timeout: 10),
            "Coach composer should be visible after opening the Coach surface."
        )
        XCTAssertTrue(
            composerInput.waitForExistence(timeout: 5) && composerInput.isHittable,
            "Coach composer input should be hittable before typing."
        )
    }

    private func tapCoachTab(in app: XCUIApplication) -> Bool {
        let candidates = [
            app.tabBars.buttons["tab.coach"].firstMatch,
            app.buttons["tab.coach"].firstMatch,
            app.tabBars.buttons["Coach"].firstMatch,
        ]

        for candidate in candidates where candidate.waitForExistence(timeout: 2) {
            candidate.tap()
            return true
        }

        return false
    }

    /// `XCUIElement.waitForExistence` polls coarsely enough to add around a
    /// second to a sub-second first-token path. For this budget we need the
    /// first visible token edge, so poll the accessibility tree directly with
    /// a short interval after the send tap.
    private func waitForVisibleFirstToken(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return element.exists
    }

    /// Build the XCUIApplication configured for perf-mode:
    ///
    /// - `-PerfTestMode 1` flips `VolumeArcRuntimeFlags.isPerformanceTestMode`
    ///   on, which bumps the dashboard fetch limit to 60 and removes
    ///   the Today tab's `.prefix(3)` cap so the scroll list has 50
    ///   rows to scroll past.
    /// - `-UITestMode 1` and `-SkipOnboarding 1` are implied by the
    ///   bootstrapper when perf mode is set, but we pass them
    ///   explicitly so the launch arguments surface clearly in the CI
    ///   log.
    private func makePerfApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMode", "1",
            "-SkipOnboarding", "1",
            "-SeedFixtures", "1",
            "-PerfTestMode", "1",
        ]
        app.launchArguments += extraArguments
        return app
    }
}
