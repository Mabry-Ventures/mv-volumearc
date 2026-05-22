import XCTest
@testable import VolumeArcCore

/// VOL-138 Phase A: `UserDefaultsWatchPendingPayloadStore` covers the
/// offline-replay queue that protects workout payloads when
/// `WCSession.isReachable == false` (the phone is locked, the user is at
/// the gym without phone access on a cellular watch, etc.). A regression
/// here means a workout completes but the corresponding `completedWorkout`
/// payload silently disappears — a silent-failure mode the Watch
/// positioning cannot afford.
///
/// Each test allocates its own `UserDefaults(suiteName:)` so the
/// assertions are hermetic and never touch the host's standard defaults.
/// The store is an `actor`, so all interactions go through `await`. The
/// `UserDefaults` is allocated **inside** each test (not as a stored
/// property) because Swift 6 strict-concurrency forbids sending a
/// non-`Sendable` reference (UserDefaults is `@unchecked Sendable` only
/// in subclasses, and re-acquiring via the suiteName is the project
/// convention — see `Tests/VolumeArcAppTests/VolumeArcPersistenceTests.swift`).
final class WatchPendingPayloadStoreTests: XCTestCase {

    // Suite name is the only piece worth carrying as a stored property —
    // a plain String is Sendable. Each test rehydrates the defaults from
    // it locally, then tearDown removes the persistent domain.
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "vol-138.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        super.tearDown()
    }

    // MARK: -

    func test_count_on_empty_store_is_zero() async {
        let defaults = ephemeralDefaults()
        let store = UserDefaultsWatchPendingPayloadStore(defaults: defaults)
        let count = await store.count()
        XCTAssertEqual(count, 0)
    }

    func test_dequeueAll_on_empty_store_returns_empty() async {
        let defaults = ephemeralDefaults()
        let store = UserDefaultsWatchPendingPayloadStore(defaults: defaults)
        let drained = await store.dequeueAll()
        XCTAssertTrue(drained.isEmpty)
    }

    func test_enqueue_then_count_reflects_size() async {
        let defaults = ephemeralDefaults()
        let store = UserDefaultsWatchPendingPayloadStore(defaults: defaults)
        await store.enqueue(payload(kind: .restTimer, id: "w-1"))
        await store.enqueue(payload(kind: .coachCue, id: "w-2"))
        let count = await store.count()
        XCTAssertEqual(count, 2)
    }

    func test_enqueue_preserves_insertion_order_on_dequeue() async {
        let defaults = ephemeralDefaults()
        let store = UserDefaultsWatchPendingPayloadStore(defaults: defaults)
        let first = payload(kind: .startSession, id: "w-1", body: "first")
        let second = payload(kind: .liveState, id: "w-1", body: "second")
        let third = payload(kind: .completedWorkout, id: "w-1", body: "third")

        await store.enqueue(first)
        await store.enqueue(second)
        await store.enqueue(third)

        let drained = await store.dequeueAll()
        XCTAssertEqual(drained.count, 3)
        XCTAssertEqual(drained[0].body, "first")
        XCTAssertEqual(drained[1].body, "second")
        XCTAssertEqual(drained[2].body, "third")
    }

    func test_dequeueAll_empties_the_store() async {
        let defaults = ephemeralDefaults()
        let store = UserDefaultsWatchPendingPayloadStore(defaults: defaults)
        await store.enqueue(payload(kind: .restTimer, id: "w-1"))
        await store.enqueue(payload(kind: .coachCue, id: "w-1"))

        let drained = await store.dequeueAll()
        XCTAssertEqual(drained.count, 2)

        let leftoverCount = await store.count()
        XCTAssertEqual(leftoverCount, 0)

        let leftoverDrain = await store.dequeueAll()
        XCTAssertTrue(leftoverDrain.isEmpty)
    }

    func test_store_survives_actor_restart_via_userdefaults() async {
        // Phone or watch process restart: the existing store goes
        // away, a fresh `UserDefaultsWatchPendingPayloadStore` is
        // built against the same defaults, the queued payloads
        // should still be there. This is the whole point of the
        // UserDefaults-backed implementation vs an in-memory one.
        let writer = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        await writer.enqueue(payload(kind: .completedWorkout, id: "w-survives"))

        let reader = UserDefaultsWatchPendingPayloadStore(defaults: ephemeralDefaults())
        let count = await reader.count()
        XCTAssertEqual(count, 1)

        let drained = await reader.dequeueAll()
        XCTAssertEqual(drained.first?.workoutID, "w-survives")
    }

    func test_store_handles_corrupt_userdefaults_blob_as_empty() async {
        // If the on-disk JSON gets garbled (cross-version upgrade,
        // truncated write during a power loss, manual tampering),
        // the store treats it as empty rather than crashing the
        // process. Belt-and-suspenders against a silent crash
        // shape that would manifest as "watch app dies on launch".
        let defaults = ephemeralDefaults()
        defaults.set(Data([0xff, 0xfe, 0xfd]), forKey: "com.mabryventures.VolumeArc.watch.pendingPayloads")

        let store = UserDefaultsWatchPendingPayloadStore(defaults: defaults)
        let count = await store.count()
        XCTAssertEqual(count, 0)

        let drained = await store.dequeueAll()
        XCTAssertTrue(drained.isEmpty)
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

    private func payload(kind: WatchPayloadKind, id: String, body: String = "{}") -> WatchPayload {
        WatchPayload(
            kind: kind,
            workoutID: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: body
        )
    }
}
