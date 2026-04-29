import XCTest

/// VOL-112: simulator-only Watch payload arrival tests.
///
/// The full Watch/iPhone live pairing path (start session on iPhone,
/// mirror on Watch, complete set on Watch, sync back) requires a
/// paired-simulator session that not every runner has, plus real
/// `WCSession` activation that simulator can only approximate. The full
/// pairing coverage lives in VOL-94's real-device canary.
///
/// This subset proves the iPhone side of the wire: when a `WatchPayload`
/// notification fires (regardless of whether it came from a real Watch
/// or a simulated post), the dashboard's `handleWatchPayload` path runs
/// and observable state reflects the most-recent payload kind.
///
/// Wiring:
/// - The app, when launched with `-UITestMode 1 -PostFakeWatchPayload <kind>`,
///   posts a `WatchConnectivityNotifications.payloadDidArrive` notification
///   on first appearance via `VolumeArcAppFactories.postSimulatedWatchPayloadIfRequested()`.
/// - `VolumeArcApp`'s `.onReceive` for that notification forwards the
///   payload to `dashboardModel.handleWatchPayload(_:)`.
/// - That handler records a telemetry event and, critically, sets
///   `dashboardModel.lastWatchPayloadKindForTesting` to the kind's raw
///   value.
/// - A test-only overlay in `VolumeArcApp.rootContent` (gated on
///   `VolumeArcRuntimeFlags.isDeterministicMode`) renders a 1×1 invisible
///   `Text` with `accessibilityIdentifier("debug.watch.last-payload-kind")`
///   that the test asserts on.
///
/// If a future PR removes the overlay, the launch arg, the published
/// state, or the handler wiring, the test fails fast with a
/// `waitForExistence(timeout:)` timeout on the missing identifier.
final class VolumeArcWatchSimulationJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Post a `restTimer` payload at launch and confirm the dashboard
    /// observes the kind. `restTimer` is the most common Watch-→-iPhone
    /// payload (the watch ticks down rest, the phone learns when the
    /// timer expires) so it's the highest-signal kind to gate on.
    func testRestTimerPayloadFromWatchUpdatesDashboardState() throws {
        try assertSimulatedPayloadIsObservedByDashboard(kind: "restTimer")
    }

    /// Post an `endSession` payload at launch and confirm the dashboard
    /// observes the kind. End-of-session is the kind that, in the full
    /// real-device canary, would actually mutate persisted state (a new
    /// completed workout lands in the repo via the sync path). At the
    /// simulator level we only assert the kind is observed; the
    /// repository round-trip is covered by integration tests.
    func testEndSessionPayloadFromWatchUpdatesDashboardState() throws {
        try assertSimulatedPayloadIsObservedByDashboard(kind: "endSession")
    }

    /// Post a `coachCue` payload at launch — the kind the watch sends
    /// when the on-watch coach prompt updates. Confirms the iPhone
    /// receives + observes that kind too. Round-trip into the iPhone
    /// coach UI is out of scope for this test (covered by the coach
    /// stream tests).
    func testCoachCuePayloadFromWatchUpdatesDashboardState() throws {
        try assertSimulatedPayloadIsObservedByDashboard(kind: "coachCue")
    }

    /// An unrecognized payload kind is silently ignored by the launch
    /// helper — the dashboard's debug overlay should report the empty
    /// string (no payload observed). This protects against a regression
    /// where the helper crashes the app on an unknown kind, which would
    /// be a far worse failure mode than silently no-op'ing.
    func testUnrecognizedPayloadKindIsSilentlyIgnored() throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-PostFakeWatchPayload", "this-kind-does-not-exist"]
        )
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground despite unknown payload kind"
        )

        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 15),
            "Dashboard should render normally when an unknown payload kind is requested"
        )

        // Sleep briefly to allow any (incorrect) handler invocation to
        // mutate state, so the assertion below is meaningful.
        Thread.sleep(forTimeInterval: 1.0)

        let debugOverlay = app.descendants(matching: .any)
            .matching(identifier: "debug.watch.last-payload-kind")
            .firstMatch
        XCTAssertTrue(
            debugOverlay.waitForExistence(timeout: 5),
            "Debug overlay should be present in deterministic mode"
        )
        XCTAssertEqual(
            debugOverlay.label, "",
            "No payload should have been observed for an unrecognized kind"
        )
    }

    // MARK: - Helpers

    /// Boot the app with the named payload kind, wait for the dashboard,
    /// then confirm the debug overlay's accessibility label reflects the
    /// posted kind. The overlay is a hidden `Text` whose `label` is the
    /// most-recent observed `WatchPayloadKind.rawValue` — XCUITest's
    /// `.label` accessor reads the SwiftUI accessibility label.
    private func assertSimulatedPayloadIsObservedByDashboard(kind: String) throws {
        let app = VolumeArcAppUITestSupport.makeSeededApp(
            extra: ["-PostFakeWatchPayload", kind]
        )
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "App should reach foreground for kind=\(kind)"
        )

        let dashboard = app.otherElements["root.dashboard"]
        XCTAssertTrue(
            dashboard.waitForExistence(timeout: 15),
            "Dashboard should appear within 15s for kind=\(kind)"
        )

        // The debug overlay is gated on deterministic mode AND populated
        // asynchronously after the `.task` modifier posts the notification
        // and the receiver runs `handleWatchPayload`. Use a poll loop
        // rather than a single `waitForExistence` so we can match on the
        // .label content (XCUITest's existence check returns true the
        // moment the element appears, even before its label updates).
        let debugOverlay = app.descendants(matching: .any)
            .matching(identifier: "debug.watch.last-payload-kind")
            .firstMatch
        XCTAssertTrue(
            debugOverlay.waitForExistence(timeout: 10),
            "Debug overlay should appear in deterministic mode for kind=\(kind)"
        )

        // Poll for the label to reach the expected value. 5s budget —
        // the handler is local + synchronous up to the @Published
        // mutation, so this should complete within milliseconds; the
        // budget exists only for runner contention.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if debugOverlay.label == kind {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTFail(
            "Expected debug overlay label to equal \(kind) within 5s; got '\(debugOverlay.label)'"
        )
    }
}
