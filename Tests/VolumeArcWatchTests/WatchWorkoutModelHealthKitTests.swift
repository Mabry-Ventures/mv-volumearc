import Foundation
import XCTest
@testable import VolumeArcCore

@MainActor
final class WatchWorkoutModelHealthKitTests: XCTestCase {
    func test_startSessionStartsNativeHealthSessionAndUsesSameWorkoutIDForPhonePayload() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let model = makeModel(transport: transport, healthStore: healthStore)

        await model.startSession()

        let calls = await healthStore.calls
        let startCall = try XCTUnwrap(calls.firstStart)
        XCTAssertEqual(startCall.activityType, .strengthTraining)
        XCTAssertTrue(startCall.workoutID.hasPrefix("watch-"))

        let sentPayloads = await transport.sent
        let startPayload = try XCTUnwrap(sentPayloads.first)
        XCTAssertEqual(startPayload.kind, .startSession)
        XCTAssertEqual(startPayload.workoutID, startCall.workoutID)
        XCTAssertTrue(model.sessionActive)
    }

    func test_startSessionContinuesWithoutNativeCaptureWhenHealthAuthorizationIsDenied() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        await healthStore.setAuthorized(false)
        let model = makeModel(transport: transport, healthStore: healthStore)

        await model.startSession()

        let calls = await healthStore.calls
        XCTAssertTrue(calls.contains(.requestAuthorization))
        XCTAssertNil(calls.firstStart)

        let sentPayloads = await transport.sent
        XCTAssertEqual(sentPayloads.first?.kind, .startSession)
        XCTAssertTrue(model.sessionActive)
        XCTAssertEqual(model.statusMessage, "Live session started. Health capture unavailable.")
    }

    func test_liveWorkoutMetricsUpdateVisibleHeartRateForActiveWorkoutOnly() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let model = makeModel(transport: transport, healthStore: healthStore)

        await model.startSession()
        let calls = await healthStore.calls
        let workoutID = try XCTUnwrap(calls.firstStart?.workoutID)
        await healthStore.waitForSubscriber()

        await healthStore.emit(
            LiveWorkoutMetrics(
                workoutID: "other-workout",
                heartRateBPM: 99,
                activeEnergyKilocalories: 3,
                elapsedTime: 12,
                capturedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )
        try await waitUntil { model.liveMetricEventCount == 1 }
        XCTAssertNil(model.currentHeartRateBPM)

        await healthStore.emit(
            LiveWorkoutMetrics(
                workoutID: workoutID,
                heartRateBPM: 123,
                activeEnergyKilocalories: 8,
                elapsedTime: 42,
                capturedAt: Date(timeIntervalSinceReferenceDate: 120)
            )
        )

        try await waitUntil { model.currentHeartRateBPM == 123 }
    }

    func test_completeWorkoutFinishesNativeHealthSessionAndLinksSummaryPayload() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let model = makeModel(transport: transport, healthStore: healthStore)

        await model.startSession()
        let startCalls = await healthStore.calls
        let workoutID = try XCTUnwrap(startCalls.firstStart?.workoutID)
        await healthStore.waitForSubscriber()
        await healthStore.emit(
            LiveWorkoutMetrics(
                workoutID: workoutID,
                heartRateBPM: 117,
                activeEnergyKilocalories: 6,
                elapsedTime: 30,
                capturedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )
        try await waitUntil { model.currentHeartRateBPM == 117 }

        await model.completeWorkout()

        let calls = await healthStore.calls
        XCTAssertTrue(calls.contains(.end))
        XCTAssertFalse(model.sessionActive)
        XCTAssertNil(model.currentHeartRateBPM)

        let sentPayloads = await transport.sent
        let completedPayload = try XCTUnwrap(sentPayloads.last { $0.kind == .completedWorkout })
        XCTAssertEqual(completedPayload.workoutID, workoutID)

        let summary = try XCTUnwrap(SyncPayloadCodec.decode(WatchWorkoutSyncPayload.self, from: completedPayload.body))
        XCTAssertEqual(summary.workoutID, workoutID)
    }

    private func makeModel(
        transport: RecordingWatchTransport,
        healthStore: FakeLiveHealthStore
    ) -> WatchWorkoutModel {
        WatchWorkoutModel(
            coordinator: WatchConnectivityCoordinator(
                transport: transport,
                payloadStore: InMemoryPendingPayloadStore()
            ),
            stateStore: InMemoryWatchSessionStateStore(),
            healthStore: healthStore,
            workoutID: "watch-seeded"
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

private extension [FakeLiveHealthStore.Call] {
    var firstStart: (activityType: WorkoutActivityType, workoutID: String)? {
        for call in self {
            if case let .start(activityType, workoutID) = call {
                return (activityType, workoutID)
            }
        }
        return nil
    }
}

private actor FakeLiveHealthStore: HealthStore {
    enum Call: Equatable {
        case requestAuthorization
        case start(WorkoutActivityType, String)
        case end
    }

    private var continuation: AsyncStream<LiveWorkoutMetrics>.Continuation?
    private(set) var calls: [Call] = []
    var authorized = true

    var isAuthorized: Bool {
        get async { authorized }
    }

    func requestAuthorization() async throws -> Bool {
        calls.append(.requestAuthorization)
        return true
    }

    func startWorkoutSession(activityType: WorkoutActivityType) async throws {
        try await startWorkoutSession(activityType: activityType, workoutID: "legacy-workout")
    }

    func startWorkoutSession(activityType: WorkoutActivityType, workoutID: String) async throws {
        calls.append(.start(activityType, workoutID))
    }

    func endWorkoutSession() async throws {
        calls.append(.end)
        let continuation = continuation
        self.continuation = nil
        continuation?.finish()
    }

    func liveWorkoutMetrics() async -> AsyncStream<LiveWorkoutMetrics> {
        AsyncStream { continuation in
            Task { self.setContinuation(continuation) }
        }
    }

    func emit(_ metrics: LiveWorkoutMetrics) {
        continuation?.yield(metrics)
    }

    func waitForSubscriber() async {
        for _ in 0..<50 {
            if continuation != nil { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func setAuthorized(_ authorized: Bool) {
        self.authorized = authorized
    }

    private func setContinuation(_ continuation: AsyncStream<LiveWorkoutMetrics>.Continuation) {
        self.continuation = continuation
    }
}

private actor InMemoryPendingPayloadStore: WatchPendingPayloadStore {
    private var payloads: [WatchPayload] = []

    func enqueue(_ payload: WatchPayload) async {
        payloads.append(payload)
    }

    func dequeueAll() async -> [WatchPayload] {
        defer { payloads.removeAll() }
        return payloads
    }

    func count() async -> Int {
        payloads.count
    }
}

private actor InMemoryWatchSessionStateStore: WatchSessionStateStore {
    private var snapshot: WatchSessionSnapshot?

    func load() async -> WatchSessionSnapshot? {
        snapshot
    }

    func save(_ snapshot: WatchSessionSnapshot) async {
        self.snapshot = snapshot
    }

    func clear() async {
        snapshot = nil
    }
}

private actor RecordingWatchTransport: WatchSessionTransport {
    private(set) var sent: [WatchPayload] = []
    private let reachable: Bool

    init(reachable: Bool) {
        self.reachable = reachable
    }

    func activate() async {}

    func isReachable() async -> Bool {
        reachable
    }

    func send(_ payload: WatchPayload) async throws {
        sent.append(payload)
    }
}
