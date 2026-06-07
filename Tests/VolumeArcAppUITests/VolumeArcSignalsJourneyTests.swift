// VOL-200 Phase 5 — Signals surface journey coverage.
//
// Closes all 3 `signals.*` rows from `docs/USER_JOURNEYS.md`:
//   * `signals.readiness-breakdown`
//   * `signals.volume-chart`
//   * `signals.frequency-heatmap`
//
// All three events fire together from `SignalsView.task` via
// `WorkoutDashboardModel.recordSignalsViewed()`. The journey catalog
// originally described these as drill-down gestures, but the current
// SignalsView renders all three sections on a single scroll view —
// there is no separate "open" interaction. Emitting on appearance is
// the implementation that matches today's product; the catalog rows
// stay accurate to the contract event names. Future work that adds
// per-section expand/collapse affordances can split the emit into
// three independent calls without changing the test expectations.
//
// Tests use the `-OpenSignalsOnLaunch 1` launch arg (added in
// VOL-200 P5 alongside the existing Profile + Coach affordances)
// so the journey assertions don't depend on simulator-specific
// TabView hit testing.

import XCTest

@MainActor
final class VolumeArcSignalsJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - signals.readiness-breakdown

    func testSignalsReadinessOpenedFiresOnLaunch() throws {
        let app = launchSignalsTab()
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "signals",
            name: "readiness.opened",
            within: 10,
            test: self
        )
    }

    // MARK: - signals.volume-chart

    func testSignalsVolumeOpenedFiresOnLaunch() throws {
        let app = launchSignalsTab()
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "signals",
            name: "volume.opened",
            within: 10,
            test: self
        )
    }

    // MARK: - signals.frequency-heatmap

    func testSignalsFrequencyOpenedFiresOnLaunch() throws {
        let app = launchSignalsTab()
        VolumeArcAppUITestSupport.assertTelemetryFired(
            in: app,
            category: "signals",
            name: "frequency.opened",
            within: 10,
            test: self
        )
    }

    func testSignalsExplainsHowReadinessChangesTraining() throws {
        let app = launchSignalsTab()
        let usageCard = app.descendants(matching: .any)
            .matching(identifier: "signals.readiness.usage")
            .firstMatch
        XCTAssertTrue(
            usageCard.waitForExistence(timeout: 10),
            "Signals should explain how readiness changes the training prescription"
        )
        XCTAssertTrue(
            app.staticTexts["How readiness changes training"].waitForExistence(timeout: 5),
            "Signals readiness usage card should have a clear title"
        )
        XCTAssertTrue(
            app.staticTexts[
                "Readiness guides training choices. It is not a medical clearance or a reason to ignore symptoms."
            ].waitForExistence(timeout: 5),
            "Signals readiness usage card should include a safety boundary"
        )
    }

    // MARK: - Helpers

    /// Cold-launch the app into the Signals tab and confirm the
    /// signals root identifier renders. Returns the launched app so
    /// the caller can assert telemetry from the shared scaffold.
    private func launchSignalsTab() -> XCUIApplication {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-OpenSignalsOnLaunch", "1"]
        )
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground running state on cold launch"
        )

        let signalsRoot = app.descendants(matching: .any)
            .matching(identifier: "signals.root")
            .firstMatch
        XCTAssertTrue(
            signalsRoot.waitForExistence(timeout: 15),
            "SignalsView should appear within 15s when -OpenSignalsOnLaunch is set"
        )
        return app
    }
}
