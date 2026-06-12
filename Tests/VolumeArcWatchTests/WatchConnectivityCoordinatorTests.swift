import XCTest
@testable import VolumeArcCore

/// VOL-138 Phase A: `WatchConnectivityCoordinator` is the actor that
/// owns the send-or-queue contract between the watch and the phone.
/// The shipping coordinator is wired up to `WatchConnectivitySessionTransport`
/// which holds a real `WCSession`; these tests substitute a fake
/// transport so the assertions stay deterministic + hermetic.
///
/// Three core behaviors under test:
///   1. Happy path — when the peer is reachable, send succeeds and the
///      queue stays empty.
///   2. Unreachable peer — when send throws, the payload is enqueued
///      and the throw propagates.
///   3. Flush — when called after a reconnect, queued payloads are
///      drained and replayed in order, even partial-failure modes
///      re-enqueue cleanly.
///
/// UserDefaults is allocated locally inside each test (not as a stored
/// property) for the same Swift 6 strict-concurrency reason documented
/// in `WatchPendingPayloadStoreTests`.
final class WatchConnectivityCoordinatorTests: XCTestCase {

    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "vol-138.coord.\(UUID().uuidString)"
    }

    override func tearDown() {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Happy path

    func test_send_succeeds_when_transport_is_reachable() async throws {
        let transport = FakeTransport(reachable: true)
        let store = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        let coordinator = WatchConnectivityCoordinator(
            transport: transport,
            payloadStore: store
        )

        try await coordinator.send(samplePayload())

        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.kind, .restTimer)
        let queueCount = await coordinator.pendingPayloadCount()
        XCTAssertEqual(queueCount, 0)
    }

    func test_isReachable_proxies_to_transport() async {
        let reachable = FakeTransport(reachable: true)
        let unreachable = FakeTransport(reachable: false)

        let coord1 = WatchConnectivityCoordinator(
            transport: reachable,
            payloadStore: UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        )
        let coord2 = WatchConnectivityCoordinator(
            transport: unreachable,
            payloadStore: UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        )

        let reachable1 = await coord1.isReachable()
        let reachable2 = await coord2.isReachable()
        XCTAssertTrue(reachable1)
        XCTAssertFalse(reachable2)
    }

    // MARK: - Offline queue

    func test_send_enqueues_on_failure_and_propagates_error() async {
        let transport = FakeTransport(reachable: false, error: .notReachable)
        let store = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        let telemetry = InMemoryTelemetrySink()
        let coordinator = WatchConnectivityCoordinator(
            transport: transport,
            payloadStore: store,
            telemetrySink: telemetry
        )

        do {
            try await coordinator.send(samplePayload())
            XCTFail("Expected throw")
        } catch let error as WatchTransportError {
            XCTAssertEqual(error, .notReachable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let queueCount = await coordinator.pendingPayloadCount()
        XCTAssertEqual(queueCount, 1)

        let event = telemetry.currentEvents.first { $0.category == "watch" && $0.name == "payload.queued" }
        XCTAssertEqual(event?.metadata["kind"], WatchPayloadKind.restTimer.rawValue)
        XCTAssertEqual(event?.metadata["reason"], "send_failed")
    }

    func test_multiple_failed_sends_all_enqueue() async {
        let transport = FakeTransport(reachable: false, error: .notReachable)
        let store = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        let coordinator = WatchConnectivityCoordinator(
            transport: transport,
            payloadStore: store
        )

        for i in 0..<3 {
            try? await coordinator.send(samplePayload(workoutID: "w-\(i)"))
        }

        let count = await coordinator.pendingPayloadCount()
        XCTAssertEqual(count, 3)
    }

    // MARK: - flushPendingIfReachable

    func test_flushPendingIfReachable_is_noop_when_unreachable() async throws {
        let store = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        await store.enqueue(samplePayload(workoutID: "w-1"))

        let transport = FakeTransport(reachable: false)
        let coordinator = WatchConnectivityCoordinator(transport: transport, payloadStore: store)

        try await coordinator.flushPendingIfReachable()

        let stillQueued = await coordinator.pendingPayloadCount()
        XCTAssertEqual(stillQueued, 1)
        let sent = await transport.sent
        XCTAssertTrue(sent.isEmpty)
    }

    func test_flushPendingIfReachable_drains_queue_when_reachable() async throws {
        let store = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        await store.enqueue(samplePayload(workoutID: "w-1", body: "first"))
        await store.enqueue(samplePayload(workoutID: "w-2", body: "second"))

        let transport = FakeTransport(reachable: true)
        let telemetry = InMemoryTelemetrySink()
        let coordinator = WatchConnectivityCoordinator(
            transport: transport,
            payloadStore: store,
            telemetrySink: telemetry
        )

        try await coordinator.flushPendingIfReachable()

        let remaining = await coordinator.pendingPayloadCount()
        XCTAssertEqual(remaining, 0)

        let sent = await transport.sent
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0].body, "first")
        XCTAssertEqual(sent[1].body, "second")

        let replayEvents = telemetry.currentEvents.filter {
            $0.category == "watch" && $0.name == "payload.replayed"
        }
        XCTAssertEqual(replayEvents.count, 2)
        XCTAssertEqual(replayEvents[0].metadata["kind"], WatchPayloadKind.restTimer.rawValue)
        XCTAssertEqual(replayEvents[1].metadata["kind"], WatchPayloadKind.restTimer.rawValue)
    }

    func test_flushPendingIfReachable_reenqueues_on_partial_failure() async {
        let store = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        await store.enqueue(samplePayload(workoutID: "w-1", body: "first"))
        await store.enqueue(samplePayload(workoutID: "w-2", body: "second"))
        await store.enqueue(samplePayload(workoutID: "w-3", body: "third"))

        // Transport reports reachable but the second send throws —
        // simulates a reconnect that goes flaky mid-flush. The
        // throwing payload and untouched suffix should be re-queued
        // so a subsequent flush retries them; payloads already drained
        // ahead of the failure are gone (the transport accepted them).
        let transport = FakeTransport(reachable: true, failingAfter: 1)
        let telemetry = InMemoryTelemetrySink()
        let coordinator = WatchConnectivityCoordinator(
            transport: transport,
            payloadStore: store,
            telemetrySink: telemetry
        )

        do {
            try await coordinator.flushPendingIfReachable()
            XCTFail("Expected throw on second send")
        } catch {
            // expected
        }

        let remaining = await coordinator.pendingPayloadCount()
        XCTAssertEqual(remaining, 2, "Failed and untouched payloads should be re-queued for the next flush")
        let queuedBodies = await store.dequeueAll().map(\.body)
        XCTAssertEqual(queuedBodies, ["second", "third"])

        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.body, "first")

        let replayEvents = telemetry.currentEvents.filter {
            $0.category == "watch" && $0.name == "payload.replayed"
        }
        XCTAssertEqual(replayEvents.count, 1)
        let requeueEvents = telemetry.currentEvents.filter {
            $0.category == "watch" && $0.name == "payload.queued"
        }
        XCTAssertEqual(requeueEvents.map { $0.metadata["reason"] }, ["replay_failed", "replay_failed"])
    }

    // MARK: - UnavailableWatchSessionTransport (real type, not a fake)

    func test_unavailable_transport_always_throws_not_reachable() async {
        let transport = UnavailableWatchSessionTransport()
        let store = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        let coordinator = WatchConnectivityCoordinator(transport: transport, payloadStore: store)

        let reachable = await coordinator.isReachable()
        XCTAssertFalse(reachable)

        do {
            try await coordinator.send(samplePayload())
            XCTFail("UnavailableWatchSessionTransport must always throw")
        } catch let error as WatchTransportError {
            XCTAssertEqual(error, .notReachable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let queued = await coordinator.pendingPayloadCount()
        XCTAssertEqual(queued, 1, "Payload must be enqueued for replay")
    }

    // MARK: - Error descriptions

    func test_watch_transport_error_descriptions_are_localized() {
        // LocalizedError errorDescription drives the user-visible
        // surface in Settings / diagnostic screens. Empty / nil
        // descriptions ship a confusing "Operation failed" string.
        XCTAssertNotNil(WatchTransportError.notActivated.errorDescription)
        XCTAssertNotNil(WatchTransportError.notReachable.errorDescription)
        XCTAssertFalse(WatchTransportError.notActivated.errorDescription!.isEmpty)
        XCTAssertFalse(WatchTransportError.notReachable.errorDescription!.isEmpty)
    }

    // MARK: - Helpers

    /// `sending` return signals that the produced `UserDefaults` is
    /// freshly constructed and has no aliases at the call site, so
    /// Swift 6 strict-concurrency lets it cross into the actor's
    /// `init(defaults: sending UserDefaults)` parameter without a
    /// "risks causing data races" diagnostic.
    private func ephemeralDefaults() -> sending UserDefaults {
        guard let suiteName, let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Failed to allocate UserDefaults suite for test")
        }
        return defaults
    }

    private func samplePayload(
        workoutID: String = "w-1",
        kind: WatchPayloadKind = .restTimer,
        body: String = "{}"
    ) -> WatchPayload {
        WatchPayload(
            kind: kind,
            workoutID: workoutID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: body
        )
    }
}

// MARK: - VOL-275 scheduled-plan payload

final class WatchScheduledPlanPayloadTests: XCTestCase {
    func test_round_trip_preserves_clamped_prescription() throws {
        let payload = WatchScheduledPlanPayload(
            title: "Co-Designed Lower",
            dayOfWeek: 3,
            scheduledFor: Date(timeIntervalSince1970: 1_765_000_000),
            durationMinutes: 52,
            targetRPE: 8,
            exercises: [
                .init(name: "Back Squat", sets: 4, reps: 6, weight: 225),
                .init(name: "Romanian Deadlift", sets: 3, reps: 10, weight: 185),
            ]
        )

        let decoded = try XCTUnwrap(
            WatchScheduledPlanPayload.decode(from: WatchScheduledPlanPayload.encode(payload))
        )

        XCTAssertEqual(decoded, payload)
    }

    func test_decode_rejects_garbage_body() {
        XCTAssertNil(WatchScheduledPlanPayload.decode(from: "not json"))
    }

    /// Pre-VOL-275 snapshots have no `scheduledPlanBody`; decoding them
    /// must keep working so a watch app update never loses session state.
    func test_legacy_session_snapshot_decodes_without_plan_body() throws {
        let legacyJSON = """
        {"workoutID":"w1","selectedAction":"hold","restEndsAt":730000000,        "coachPrompt":"p","sessionActive":true,"statusMessage":"s","loggedSetCount":2}
        """
        let snapshot = SyncPayloadCodec.decode(WatchSessionSnapshot.self, from: legacyJSON)

        XCTAssertNotNil(snapshot)
        XCTAssertNil(snapshot?.scheduledPlanBody)
        XCTAssertEqual(snapshot?.loggedSetCount, 2)
    }
}

// MARK: - Test doubles

/// Hermetic fake transport: records every sent payload, can be set to
/// any reachability state, and can be configured to throw on a chosen
/// send (counted from zero) to simulate flaky-reconnect behavior.
private actor FakeTransport: WatchSessionTransport {
    private(set) var sent: [WatchPayload] = []
    private let reachable: Bool
    private let error: WatchTransportError?
    private let failingAfter: Int?

    init(
        reachable: Bool,
        error: WatchTransportError? = nil,
        failingAfter: Int? = nil
    ) {
        self.reachable = reachable
        self.error = error
        self.failingAfter = failingAfter
    }

    func activate() async {}

    func isReachable() async -> Bool {
        reachable
    }

    func send(_ payload: WatchPayload) async throws {
        if let failingAfter, sent.count >= failingAfter {
            throw WatchTransportError.notReachable
        }
        if let error {
            throw error
        }
        sent.append(payload)
    }
}
