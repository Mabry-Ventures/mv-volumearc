import Foundation
import VolumeArcCore

// MARK: - AI

final class MockAICoachProvider: AICoachProvider, @unchecked Sendable {
    var responses: [String] = ["Hold the current load and focus on rep quality."]
    var callCount = 0

    func coachResponse(for prompt: String, context: String) async throws -> String {
        callCount += 1
        return responses.indices.contains(callCount - 1) ? responses[callCount - 1] : responses.last ?? ""
    }
}

/// Generic sentinel error for mocks that want a configurable failure reason
/// without pulling in a production error type.
struct MockError: Error, Equatable, LocalizedError {
    let reason: String

    init(_ reason: String = "mock failure") {
        self.reason = reason
    }

    var errorDescription: String? { reason }
}

/// AI coach provider that always fails. Use to cover the "fallback chain
/// triggered" branches where a primary provider throws and callers must
/// degrade to the local heuristic.
final class FailingAICoachProvider: AICoachProvider, @unchecked Sendable {
    var error: Error
    private(set) var callCount = 0

    init(error: Error = MockError("coach unavailable")) {
        self.error = error
    }

    func coachResponse(for prompt: String, context: String) async throws -> String {
        callCount += 1
        throw error
    }
}

/// AI coach provider that sleeps before delegating. Use to drive timeout /
/// cancellation paths — wrap a real provider and measure whether callers
/// cancel or wait.
final class DelayedAICoachProvider: AICoachProvider, @unchecked Sendable {
    let delay: Duration
    let inner: any AICoachProvider

    init(delay: Duration, wrapping inner: any AICoachProvider) {
        self.delay = delay
        self.inner = inner
    }

    func coachResponse(for prompt: String, context: String) async throws -> String {
        try await Task.sleep(for: delay)
        return try await inner.coachResponse(for: prompt, context: context)
    }
}

/// AI coach provider that records every call made against it before delegating
/// to an inner provider. Use when a test needs to assert on prompt/context
/// arguments without coupling to the inner provider's behavior.
final class RecordingAICoachProvider: AICoachProvider, @unchecked Sendable {
    struct Call: Equatable {
        let prompt: String
        let context: String
    }

    private(set) var calls: [Call] = []
    let inner: any AICoachProvider

    init(wrapping inner: any AICoachProvider) {
        self.inner = inner
    }

    func coachResponse(for prompt: String, context: String) async throws -> String {
        calls.append(Call(prompt: prompt, context: context))
        return try await inner.coachResponse(for: prompt, context: context)
    }
}

// MARK: - Cloud Sync

struct MockCloudSyncTransport: CloudSyncTransport {
    var available: Bool = true
    var pushedRecords: [CloudSyncRecord] = []
    var pullResult: CloudSyncPullResult = CloudSyncPullResult(
        changedRecords: [],
        deletedRecordIDs: [],
        nextCursor: nil
    )

    var isAvailable: Bool { available }

    func pushRecords(_ records: [CloudSyncRecord]) async throws {}

    func pullChanges(since cursor: String?) async throws -> CloudSyncPullResult {
        pullResult
    }
}

/// Cloud sync transport that throws for push / pull independently. Use to
/// drive the "transport down on one leg" branches in the coordinator —
/// e.g., pull succeeds but push fails.
final class FailingCloudSyncTransport: CloudSyncTransport, @unchecked Sendable {
    var available: Bool
    var pushError: Error?
    var pullError: Error?

    init(
        available: Bool = true,
        pushError: Error? = MockError("push failed"),
        pullError: Error? = MockError("pull failed")
    ) {
        self.available = available
        self.pushError = pushError
        self.pullError = pullError
    }

    var isAvailable: Bool { available }

    func pushRecords(_ records: [CloudSyncRecord]) async throws {
        if let pushError { throw pushError }
    }

    func pullChanges(since cursor: String?) async throws -> CloudSyncPullResult {
        if let pullError { throw pullError }
        return CloudSyncPullResult(changedRecords: [], deletedRecordIDs: [], nextCursor: nil)
    }
}

// VOL-130: the retry-N-times test stub that previously lived here was
// superseded by the production `RetryingCloudSyncTransport` decorator
// (with proper exponential backoff + recovery telemetry) plus the
// scripted `InMemoryCloudSyncTransport` fake. Tests that need transient-
// failure simulation should use those instead.

// MARK: - Health

struct MockHealthStore: HealthStore {
    var authorized: Bool = true

    var isAuthorized: Bool {
        get async { authorized }
    }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        HealthAuthorizationResult(canShareWorkouts: authorized, requestedReadIdentifiers: [])
    }
    func startWorkoutSession(activityType: WorkoutActivityType) async throws {}
    func endWorkoutSession() async throws {}
}

/// Health store that denies authorization and rejects every session call.
/// Use for tests that simulate the user tapping "Don't Allow" on the
/// HealthKit prompt.
struct DenyingHealthStore: HealthStore {
    let authorizationError: Error?
    let sessionError: Error

    init(
        authorizationError: Error? = nil,
        sessionError: Error = MockError("health authorization denied")
    ) {
        self.authorizationError = authorizationError
        self.sessionError = sessionError
    }

    var isAuthorized: Bool {
        get async { false }
    }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        if let authorizationError { throw authorizationError }
        return HealthAuthorizationResult(canShareWorkouts: false, requestedReadIdentifiers: [])
    }

    func startWorkoutSession(activityType: WorkoutActivityType) async throws {
        throw sessionError
    }

    func endWorkoutSession() async throws {
        throw sessionError
    }
}

/// Health store that records every authorization request and session call
/// for later assertion. Start / end calls capture the activity type so tests
/// can confirm the correct workout classification is pushed to HealthKit.
final class RecordingHealthStore: HealthStore, @unchecked Sendable {
    enum Call: Equatable {
        case requestAuthorization
        case start(WorkoutActivityType)
        case end
    }

    private(set) var calls: [Call] = []
    var authorized: Bool = true

    var isAuthorized: Bool {
        get async { authorized }
    }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        calls.append(.requestAuthorization)
        return HealthAuthorizationResult(canShareWorkouts: authorized, requestedReadIdentifiers: [])
    }

    func startWorkoutSession(activityType: WorkoutActivityType) async throws {
        calls.append(.start(activityType))
    }

    func endWorkoutSession() async throws {
        calls.append(.end)
    }
}

// MARK: - Telemetry

final class MockTelemetrySink: TelemetrySink, @unchecked Sendable {
    var recordedEvents: [TelemetryEvent] = []

    func record(_ event: TelemetryEvent) {
        recordedEvents.append(event)
    }
}

/// Thread-safe telemetry sink that retains every event for later inspection.
/// Use when a test needs to assert on telemetry emitted from a concurrent
/// callsite (the `NSLock` shields against data races that `MockTelemetrySink`
/// would tolerate).
final class CapturingTelemetrySink: TelemetrySink, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [TelemetryEvent] = []

    var events: [TelemetryEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    func record(_ event: TelemetryEvent) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(event)
    }

    func events(named name: String) -> [TelemetryEvent] {
        events.filter { $0.name == name }
    }

    func events(category: String) -> [TelemetryEvent] {
        events.filter { $0.category == category }
    }
}

/// Telemetry sink that silently discards every event. Use in tests that
/// don't care about telemetry but still need to supply a sink dependency.
struct DroppingTelemetrySink: TelemetrySink {
    func record(_ event: TelemetryEvent) {}
}

// MARK: - Notifications

struct MockNotificationStore: NotificationStore {}

// MARK: - Voice

actor MockVoicePermissionStore: VoicePermissionStore {
    var statusToReturn = VoicePermissionStatus(microphone: .authorized, speechRecognition: .authorized)

    func currentStatus() async -> VoicePermissionStatus { statusToReturn }
    func requestPermissions() async throws -> VoicePermissionStatus { statusToReturn }
}

// MARK: - Account

struct MockAccountSessionStore: AccountSessionStore {}

// MARK: - Voice Transport

actor MockRealtimeVoiceTransport: RealtimeVoiceTransport {
    var connected = false

    func connect(model: AIModelIdentifier, policy: VoiceSessionPolicy) async throws {
        connected = true
    }

    func send(context: String, userText: String) async throws -> String { "" }
    func interrupt() async { connected = false }
    func disconnect() async { connected = false }
}

/// Voice transport that records every lifecycle call and every `send`
/// invocation. Use when a test needs to confirm the orchestrator issued
/// the expected session transitions (connect → send → disconnect).
actor RecordingVoiceTransport: RealtimeVoiceTransport {
    enum Call: Equatable {
        case connect(model: String, policy: String)
        case send(context: String, userText: String)
        case interrupt
        case disconnect
    }

    private(set) var calls: [Call] = []
    var response: String

    init(response: String = "") {
        self.response = response
    }

    func connect(model: AIModelIdentifier, policy: VoiceSessionPolicy) async throws {
        calls.append(.connect(model: model.rawValue, policy: policy.rawValue))
    }

    func send(context: String, userText: String) async throws -> String {
        calls.append(.send(context: context, userText: userText))
        return response
    }

    func interrupt() async {
        calls.append(.interrupt)
    }

    func disconnect() async {
        calls.append(.disconnect)
    }
}
