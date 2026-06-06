// VOL-168 Phase 1: launch-argument-driven chaos / fault-injection
// flags. XCUITest journeys flip these on by launching the app with
// the matching `-CHAOS_*` argument, exercising graceful-degradation
// paths without needing a paired physical device.
//
// Subsystems covered today (Phase 1): HealthKit, AIRelay first-chunk failures,
// and Foundation Models unavailability.
// Subsystems on Phase 2+ roadmap (per VOL-168 acceptance criteria):
//   - WatchConnectivity (drop next N payloads, simulate session interruption)
//   - StoreKit (purchase userCancelled / notEntitled / billing retry)
//   - BGTaskScheduler (unsubmit mid-task)
//   - AIRelay (network timeouts, malformed SSE, rate-limit responses)
//
// ## Production safety
//
// Every accessor in this enum has a single `#if DEBUG` gate.
// Release builds compile every chaos check to `return false`, so
// app factory code always sees disabled chaos and wires the
// un-decorated real subsystem implementations. The `ChaosController`
// symbol itself is preserved across configs so callers don't need
// their own preprocessor gates, but no flag returns true in Release.
// That keeps shipping binaries free of any code path that could be
// triggered by an unexpected argv at runtime (e.g., a URL-scheme
// exploit or jailbroken environment).
//
// ## Naming
//
// `-CHAOS_<SUBSYSTEM>_<MODE>`. Underscores not hyphens so
// `XCUIApplication.launchArguments.contains(...)` matches exactly.
// All upper-case to telegraph "test-only" at the launch-argument
// boundary. Add new flags as `public static var` on this enum and
// the call site flips them via `CommandLine.arguments.contains(...)`.
//
// ## Discoverability
//
// `docs/CHAOS.md` is the source of truth for the full flag list,
// what each one does, and the XCUITest journey that exercises it.

import Foundation
import VolumeArcCore

public enum ChaosController {

    // MARK: - HealthKit

    /// `-CHAOS_HEALTH_AUTH_DENIED`: the next `requestAuthorization`
    /// call on the wrapped HealthStore throws
    /// `HKError.errorAuthorizationDenied`. Wraps real HealthKit in a
    /// `ChaosHealthStore` decorator that intercepts the call.
    ///
    /// Used by `VolumeArcChaosJourneyTests` to assert that the
    /// Profile-tab Apple Health row handles the error gracefully —
    /// surfaces a user-visible "Connect" state, records
    /// `health.auth_failed` telemetry, and doesn't crash.
    public static var injectHealthAuthDenied: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-CHAOS_HEALTH_AUTH_DENIED")
        #else
        return false
        #endif
    }

    /// `-UseAuthorizedHealthFixture`: installs a debug-only HealthStore
    /// that reports Apple Health as connected. Used by XCUITests that
    /// need the connected-state Today readiness behavior without
    /// driving the system Health permission sheet.
    public static var useAuthorizedHealthFixture: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-UseAuthorizedHealthFixture")
        #else
        return false
        #endif
    }

    /// `-UseAuthorizedVoiceFixture`: installs a debug-only
    /// VoicePermissionStore that reports microphone + speech recognition
    /// as granted. Used by XCUITests that need to prove the Coach voice
    /// request boundary without surfacing simulator permission sheets.
    public static var useAuthorizedVoiceFixture: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-UseAuthorizedVoiceFixture")
        #else
        return false
        #endif
    }

    // MARK: - AIRelay

    /// `-CHAOS_AIRELAY_5XX`: the coach provider's primary relay path
    /// fails before yielding a token with a deterministic 503. The
    /// fallback wrapper must switch to `LocalHeuristicAICoachProvider`
    /// and emit `coach.fallback_used`.
    ///
    /// Used by `VolumeArcCoachJourneyTests.testCoachRelay5xxFallsBackToLocalHeuristic`.
    public static var injectAIRelay5xx: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-CHAOS_AIRELAY_5XX")
        #else
        return false
        #endif
    }

    /// `-CHAOS_AIRELAY_OFFLINE`: the coach provider's primary relay path
    /// fails before yielding a token with a deterministic offline error.
    /// The fallback wrapper must switch to `LocalHeuristicAICoachProvider`,
    /// show the offline coach banner, and emit `coach.fallback_used`.
    ///
    /// Used by `VolumeArcCoachJourneyTests.testCoachOfflineFallsBackToLocalHeuristicAndShowsBanner`.
    public static var injectAIRelayOffline: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-CHAOS_AIRELAY_OFFLINE")
        #else
        return false
        #endif
    }

    /// `-CHAOS_AIRELAY_401`: the coach provider's primary relay path
    /// fails before yielding a token with a deterministic 401.
    ///
    /// Used by `VolumeArcCoachJourneyTests.testCoachRelay401FallsBackToLocalHeuristic`.
    public static var injectAIRelay401: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-CHAOS_AIRELAY_401")
        #else
        return false
        #endif
    }

    /// `-CHAOS_AIRELAY_401_THEN_SUCCESS`: the first relay attempt fails
    /// with 401, then the refreshed retry succeeds. Used to prove the
    /// session-refresh path before local fallback is allowed to run.
    public static var injectAIRelay401ThenSuccess: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-CHAOS_AIRELAY_401_THEN_SUCCESS")
        #else
        return false
        #endif
    }

    /// `-CHAOS_COACH_SLOW_STREAM`: installs a deterministic provider that
    /// yields slowly enough for force-quit recovery journeys to kill the app
    /// with a coach turn still in flight.
    public static var injectCoachSlowStream: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-CHAOS_COACH_SLOW_STREAM")
        #else
        return false
        #endif
    }

    #if DEBUG
    static var aiRelayFailure: ChaosAICoachFailure? {
        if injectAIRelay5xx {
            return .relayRequestFailed(statusCode: 503, message: "Chaos AIRelay 5xx")
        }
        if injectAIRelayOffline {
            return .relayUnavailable(reason: "Chaos AIRelay offline")
        }
        if injectAIRelay401 {
            return .relayRequestFailed(statusCode: 401, message: "Chaos AIRelay 401")
        }
        return nil
    }
    #endif

    // MARK: - Foundation Models

    /// `-CHAOS_FM_UNAVAILABLE`: the app-level coach factory records the
    /// same `ai.fm.unavailable` telemetry it uses when Foundation Models
    /// cannot be installed, then chooses relay or local heuristic fallback.
    ///
    /// Used by `VolumeArcCoachJourneyTests.testCoachFoundationModelsUnavailableFallsBackQuietly`.
    public static var injectFoundationModelsUnavailable: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("-CHAOS_FM_UNAVAILABLE")
        #else
        return false
        #endif
    }
}

#if DEBUG
enum ChaosAICoachFailure: Sendable {
    case relayRequestFailed(statusCode: Int, message: String)
    case relayUnavailable(reason: String)

    var error: AIRuntimeIntegrationError {
        switch self {
        case let .relayRequestFailed(statusCode, message):
            return .relayRequestFailed(statusCode: statusCode, message: message)
        case let .relayUnavailable(reason):
            return .relayUnavailable(reason: reason)
        }
    }
}

struct ChaosAICoachProvider: AICoachProvider {
    let failure: ChaosAICoachFailure

    func coachResponse(for prompt: String, context: String) async throws -> String {
        _ = prompt
        _ = context
        throw failure.error
    }

    func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        _ = prompt
        _ = context
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: failure.error)
        }
    }
}

actor ChaosRelayUnauthorizedOnceState {
    private var shouldFail = true

    func consumeShouldFail() -> Bool {
        defer { shouldFail = false }
        return shouldFail
    }
}

struct ChaosAICoach401ThenSuccessProvider: AICoachProvider {
    private let state = ChaosRelayUnauthorizedOnceState()

    func coachResponse(for prompt: String, context: String) async throws -> String {
        if await state.consumeShouldFail() {
            throw AIRuntimeIntegrationError.relayRequestFailed(
                statusCode: 401,
                message: "Chaos AIRelay 401 before refreshed retry"
            )
        }
        _ = prompt
        _ = context
        return "Session refreshed. Keep the next set crisp, then hold two reps in reserve."
    }

    func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await coachResponse(for: prompt, context: context)
                    for word in response.split(separator: " ") {
                        continuation.yield("\(word) ")
                        try? await Task.sleep(nanoseconds: 20_000_000)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct ChaosRelaySessionRefresher: AIRelaySessionRefreshing {
    func refreshAfterUnauthorized() async {}
}

struct ChaosSlowStreamingCoachProvider: AICoachProvider {
    private let response = """
    Keep this set conservative while the stream is still in flight. Hold \
    two reps in reserve, breathe between reps, and wait for the next cue.
    """

    func coachResponse(for prompt: String, context: String) async throws -> String {
        _ = prompt
        _ = context
        return response
    }

    func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                _ = prompt
                _ = context
                for word in response.split(separator: " ") {
                    if Task.isCancelled { break }
                    continuation.yield("\(word) ")
                    try? await Task.sleep(nanoseconds: 450_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct FoundationModelsUnavailableChaosCoachProvider: AICoachProvider {
    private let fallback: AICoachProvider
    private let telemetrySink: (any TelemetrySink)?
    private let fallbackPath: String

    init(
        fallback: AICoachProvider,
        telemetrySink: (any TelemetrySink)?,
        fallbackPath: String
    ) {
        self.fallback = fallback
        self.telemetrySink = telemetrySink
        self.fallbackPath = fallbackPath
    }

    func coachResponse(for prompt: String, context: String) async throws -> String {
        recordUnavailableTelemetry()
        return try await fallback.coachResponse(for: prompt, context: context)
    }

    func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        recordUnavailableTelemetry()
        return fallback.streamCoachResponse(for: prompt, context: context)
    }

    private func recordUnavailableTelemetry() {
        telemetrySink?.record(TelemetryEvent(
            category: "ai",
            name: "fm.unavailable",
            severity: .warning,
            message: "Foundation Models coach unavailable; falling back to relay or local provider.",
            metadata: [
                "reason": "chaos",
                "fallback_path": fallbackPath,
            ]
        ))
    }
}

struct AuthorizedHealthFixtureStore: HealthStore {
    var isAuthorized: Bool { get async { true } }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        HealthAuthorizationResult(
            canShareWorkouts: true,
            requestedReadIdentifiers: HealthKitAuthorizationScope.phoneReadIdentifiers
        )
    }

    func startWorkoutSession(activityType: WorkoutActivityType) async throws {
        _ = activityType
    }

    func endWorkoutSession() async throws {}
}
#endif
