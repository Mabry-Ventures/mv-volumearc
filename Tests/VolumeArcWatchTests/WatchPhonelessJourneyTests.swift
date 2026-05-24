import XCTest
@testable import VolumeArcCore

/// VOL-235: prove the watch can complete a full strength session with
/// the phone unreachable.
///
/// Why this matters: "deepest Apple-ecosystem strength coach" positioning
/// requires that an Apple Watch user can leave their iPhone at home (or
/// in their gym bag with no cellular service) and complete a full
/// session from the wrist alone. A regression that introduces a
/// phone-required code path during an active session is a positioning-
/// breaking bug.
///
/// What the test verifies (the contract `Watch/WatchWorkoutView.swift`'s
/// `WatchWorkoutModel` relies on):
///   1. Every `WatchConnectivityCoordinator.send` while the transport
///      is unreachable enqueues the payload + throws — the model's
///      `do/catch` wrappers then keep local state moving regardless.
///   2. After the four-step session (start → decision → rest reset →
///      completion), the queue contains all four payloads in order.
///   3. Once the phone is reachable and `flushPendingIfReachable()`
///      runs, the queue drains and the transport observes every payload
///      exactly once, in the order produced.
///
/// The test stays at the coordinator boundary rather than driving
/// `WatchWorkoutModel` directly because the model lives in the
/// watchOS app target (`Watch/WatchWorkoutView.swift`), which is not
/// linked by `VolumeArcWatchTests`. The model's Phase B extraction
/// into `VolumeArcCoreWatch`-only sources is tracked as a follow-on
/// to VOL-138 — once that lands, this test grows a sibling that
/// drives `WatchWorkoutModel.startSession()` /
/// `.choose(.increase)` / etc. directly and asserts the same payload
/// shapes appear in the queue.
final class WatchPhonelessJourneyTests: XCTestCase {

    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "vol-235.phoneless.\(UUID().uuidString)"
    }

    override func tearDown() {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        super.tearDown()
    }

    // MARK: -

    /// Replays the four-step active workout flow that
    /// `WatchWorkoutModel` issues during a session — start, decision,
    /// rest-timer reset, completion — against an
    /// `UnavailableWatchSessionTransport`. Every send must throw and
    /// enqueue, the queue must hold all four payloads in order, and
    /// switching to a reachable transport must drain them exactly once.
    func test_watchCompletesWorkoutWithoutPhone_thenDrainsOnReconnect() async throws {
        // The four payloads `WatchWorkoutModel` issues during the
        // active session, in the order issued. Bodies are
        // deterministic strings (not the real codec output) so the
        // test stays focused on the queue contract rather than
        // payload-codec edge cases (those are covered by
        // `WatchPayloadCodecTests`).
        let startPayload = makePayload(kind: .startSession, body: "back-squat")
        let decisionPayload = makePayload(kind: .liveState, body: "increase")
        let restPayload = makePayload(kind: .restTimer, body: "reset:90")
        let completePayload = makePayload(kind: .completedWorkout, body: "completed:summary")

        // Phase 1: phone unreachable. Every send must throw and enqueue.
        let unreachableTransport = UnavailableWatchSessionTransport()
        let store = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        let coordinator = WatchConnectivityCoordinator(
            transport: unreachableTransport,
            payloadStore: store
        )

        // Audit-doc contract: WatchWorkoutModel wraps each send in
        // do/catch and continues updating local state on throw. The
        // try? form here matches that pattern — we're verifying the
        // throw happens AND the payload lands in the queue.
        for payload in [startPayload, decisionPayload, restPayload, completePayload] {
            do {
                try await coordinator.send(payload)
                XCTFail("Unreachable transport must throw on send (kind: \(payload.kind))")
            } catch let error as WatchTransportError {
                XCTAssertEqual(
                    error,
                    .notReachable,
                    "UnavailableWatchSessionTransport always reports .notReachable"
                )
            } catch {
                XCTFail("Unexpected error type for kind \(payload.kind): \(error)")
            }
        }

        // All four payloads must be queued. This is the property that
        // makes phone-less completion possible — without it, a
        // refunded session would vaporize.
        let queuedDuringOffline = await coordinator.pendingPayloadCount()
        XCTAssertEqual(queuedDuringOffline, 4, "All four payloads should queue while phone unreachable")

        // Phase 2: reachable transport handed in via a fresh
        // coordinator pointed at the same store. This models the
        // post-reconnect path (`refreshConnectivity()` calls
        // `flushPendingIfReachable()` once the phone returns).
        let reachableTransport = RecordingTransport(reachable: true)
        let reconnectedCoordinator = WatchConnectivityCoordinator(
            transport: reachableTransport,
            payloadStore: store
        )

        try await reconnectedCoordinator.flushPendingIfReachable()

        // Drain semantics: queue is empty, transport observed every
        // payload exactly once, in the order produced.
        let queuedAfterDrain = await reconnectedCoordinator.pendingPayloadCount()
        XCTAssertEqual(queuedAfterDrain, 0, "Queue must drain on reconnect flush")

        let sentPayloads = await reachableTransport.sent
        XCTAssertEqual(sentPayloads.count, 4)
        XCTAssertEqual(sentPayloads[0].kind, .startSession, "Order: 1) startSession")
        XCTAssertEqual(sentPayloads[1].kind, .liveState, "Order: 2) liveState (decision)")
        XCTAssertEqual(sentPayloads[2].kind, .restTimer, "Order: 3) restTimer")
        XCTAssertEqual(sentPayloads[3].kind, .completedWorkout, "Order: 4) completedWorkout")
        XCTAssertEqual(sentPayloads[0].body, "back-squat")
        XCTAssertEqual(sentPayloads[1].body, "increase")
        XCTAssertEqual(sentPayloads[2].body, "reset:90")
        XCTAssertEqual(sentPayloads[3].body, "completed:summary")
    }

    /// Independent check on the coach-cue degradation contract.
    /// `WatchWorkoutModel.requestCoachCue()` issues a `.coachCue`
    /// payload — when the phone is unreachable, the prompt queues for
    /// replay rather than failing the user with an error. The session
    /// continues; only the live coach response is deferred.
    ///
    /// The acceptance criteria call this out as "Replay any HR/coach
    /// feedback queued for the next phone reconnect." The queue
    /// behavior here is identical to the workout payloads but the
    /// test names the behavior explicitly so a regression to the
    /// coach-cue path (e.g., someone adds a `throw` outside the
    /// existing do/catch) gets a specific test failure.
    func test_coachCueQueuesAndReplaysOnReconnect() async throws {
        let cuePayload = makePayload(kind: .coachCue, body: "Rack is taken. Best fallback?")

        let unreachableTransport = UnavailableWatchSessionTransport()
        let store = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        let coordinator = WatchConnectivityCoordinator(
            transport: unreachableTransport,
            payloadStore: store
        )

        try? await coordinator.send(cuePayload)
        let queuedCount = await coordinator.pendingPayloadCount()
        XCTAssertEqual(queuedCount, 1, "Coach cue must queue when phone is unreachable")

        let reachableTransport = RecordingTransport(reachable: true)
        let reconnected = WatchConnectivityCoordinator(
            transport: reachableTransport,
            payloadStore: store
        )
        try await reconnected.flushPendingIfReachable()

        let sent = await reachableTransport.sent
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.kind, .coachCue)
        XCTAssertEqual(sent.first?.body, "Rack is taken. Best fallback?")
    }

    /// Pending payload count survives an actor restart (which models
    /// the watch app being killed mid-session — out-of-memory, force
    /// quit, or a watchOS reboot). The acceptance criteria require
    /// the queue to retain "any HR/coach feedback" across the
    /// session boundary, which only works because the queue is
    /// `UserDefaults`-backed.
    func test_queuedPayloadsSurviveWatchProcessRestart() async throws {
        let payload = makePayload(kind: .completedWorkout, body: "completed:summary")

        // Round 1: watch process is alive, queues a completion
        // payload while offline.
        do {
            let transport = UnavailableWatchSessionTransport()
            let store = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
            let coordinator = WatchConnectivityCoordinator(transport: transport, payloadStore: store)
            try? await coordinator.send(payload)
            let queued = await coordinator.pendingPayloadCount()
            XCTAssertEqual(queued, 1)
        }

        // Round 2: simulate watch process restart by reconstructing
        // the store from the same UserDefaults suite. The queued
        // payload must still be there.
        let restartedStore = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        let restartedCoordinator = WatchConnectivityCoordinator(
            transport: UnavailableWatchSessionTransport(),
            payloadStore: restartedStore
        )
        let countAfterRestart = await restartedCoordinator.pendingPayloadCount()
        XCTAssertEqual(
            countAfterRestart,
            1,
            "Queued payload must survive watch process restart for the replay contract to hold"
        )
    }

    // MARK: - Helpers

    private func ephemeralDefaults() -> sending UserDefaults {
        guard let suiteName, let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Failed to allocate UserDefaults suite for test")
        }
        return defaults
    }

    private func makePayload(kind: WatchPayloadKind, body: String) -> WatchPayload {
        WatchPayload(
            kind: kind,
            workoutID: "active-strength-session",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: body
        )
    }
}

// MARK: - Test doubles

/// Reachable transport that records every payload it sees. Used in
/// `test_watchCompletesWorkoutWithoutPhone_thenDrainsOnReconnect` to
/// assert the post-reconnect drain order matches the payload
/// production order. Separate from `WatchConnectivityCoordinatorTests`'
/// `FakeTransport` (which is `fileprivate` to that file) so each
/// test bundle owns its own boundary doubles.
private actor RecordingTransport: WatchSessionTransport {
    private(set) var sent: [WatchPayload] = []
    private let reachable: Bool

    init(reachable: Bool) {
        self.reachable = reachable
    }

    func activate() async {}
    func isReachable() async -> Bool { reachable }
    func send(_ payload: WatchPayload) async throws {
        sent.append(payload)
    }
}
