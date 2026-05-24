// VOL-168 Phase 1: launch-argument-driven chaos / fault-injection
// flags. XCUITest journeys flip these on by launching the app with
// the matching `-CHAOS_*` argument, exercising graceful-degradation
// paths without needing a paired physical device.
//
// Subsystems covered today (Phase 1): HealthKit.
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
// `App/VolumeArcAppFactories.swift` always sees disabled chaos and
// wires the un-decorated real subsystem implementations. The
// `ChaosController` symbol itself is preserved across configs so
// callers don't need their own preprocessor gates, but no flag
// returns true in Release. That keeps shipping binaries free of
// any code path that could be triggered by an unexpected argv at
// runtime (e.g., a URL-scheme exploit or jailbroken environment).
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
}

#if DEBUG
struct ChaosAICoachProvider: AICoachProvider {
    let error: AIRuntimeIntegrationError

    func coachResponse(for prompt: String, context: String) async throws -> String {
        _ = prompt
        _ = context
        throw error
    }

    func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        _ = prompt
        _ = context
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}
#endif
