// VOL-168 Phase 1: decorator that injects faults into the wrapped
// HealthStore. Constructed only in DEBUG builds when the matching
// `-CHAOS_HEALTH_*` launch argument is set (see `App/Debug/ChaosController.swift`
// for the entry points and the Release safety guarantee).
//
// Why a decorator instead of mutating `HealthKitRuntimeStore`:
//   The runtime store is the production implementation; chaos must
//   never touch its happy path. Wrapping leaves the real store
//   pristine and centralizes the fault-injection logic in one place
//   that's trivial to audit.
//
// ## Failure model
//
// Each chaos mode targets a specific real-device failure shape:
//
//   - `.authorizationDenied`: simulates the user tapping "Don't
//     Allow" on the HealthKit prompt, but via the
//     `HKError.errorAuthorizationDenied` error (some HealthKit APIs
//     surface denial as a thrown error rather than a `false` return).
//     The dashboard model's `health.auth_failed` telemetry branch is
//     the integration target.
//
// Phase 2 adds:
//   - `.anchoredQueryFailed` for the watchOS sample-collection path
//     once the watch unit-test target lands (VOL-138).
//   - `.dataUnavailable` for the `HKHealthStore.isHealthDataAvailable()`
//     path so onboarding's "no Apple Health on this device" branch is
//     unit-testable.

import Foundation

public final class ChaosHealthStore: HealthStore, @unchecked Sendable {
    public enum InjectedFailure: Sendable {
        case authorizationDenied
    }

    private let wrapped: HealthStore
    private let nextFailure: InjectedFailure?

    public init(wrapping store: HealthStore, nextFailure: InjectedFailure?) {
        self.wrapped = store
        self.nextFailure = nextFailure
    }

    public var isAuthorized: Bool {
        get async { await wrapped.isAuthorized }
    }

    public func requestAuthorization() async throws -> HealthAuthorizationResult {
        if let nextFailure {
            throw ChaosError(failure: nextFailure)
        }
        return try await wrapped.requestAuthorization()
    }

    public func startWorkoutSession(activityType: WorkoutActivityType) async throws {
        try await wrapped.startWorkoutSession(activityType: activityType)
    }

    public func startWorkoutSession(activityType: WorkoutActivityType, workoutID: String) async throws {
        try await wrapped.startWorkoutSession(activityType: activityType, workoutID: workoutID)
    }

    public func endWorkoutSession() async throws {
        try await wrapped.endWorkoutSession()
    }

    public func liveWorkoutMetrics() async -> AsyncStream<LiveWorkoutMetrics> {
        await wrapped.liveWorkoutMetrics()
    }
}

/// The error thrown by `ChaosHealthStore` when a failure was
/// injected. Conforms to `LocalizedError` so the dashboard model's
/// `auth_failed` telemetry surfaces a useful message rather than
/// `Optional("")` — that's the entire test surface the chaos run
/// targets.
public struct ChaosError: Error, LocalizedError {
    public let failure: ChaosHealthStore.InjectedFailure

    public init(failure: ChaosHealthStore.InjectedFailure) {
        self.failure = failure
    }

    public var errorDescription: String? {
        switch failure {
        case .authorizationDenied:
            return "Chaos: HealthKit authorization denied"
        }
    }
}
