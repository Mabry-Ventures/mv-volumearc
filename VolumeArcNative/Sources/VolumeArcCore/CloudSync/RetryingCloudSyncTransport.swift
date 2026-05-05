import Foundation
#if canImport(CloudKit)
import CloudKit
#endif

// VOL-130: bounded exponential-backoff retry contract for cloud sync.
//
// Wraps any `CloudSyncTransport` with retry-on-transient-error logic so
// the coordinator doesn't have to re-implement backoff per call site.
// Recovery telemetry surfaces every retry attempt and the final
// outcome so a flaky-network user shows up on the dashboard before
// they file a sync-stuck support ticket.
//
// Out of scope (filed as a follow-up):
// - Zone-not-found auto-bootstrap inside the real CloudKit transport.
//   That recovery requires re-creating the zone and replaying the
//   operation, which is a different mechanic than uniform retry.
// - Account-status precheck. Same reasoning — needs `CKContainer.accountStatus`
//   and a coordinator-level "transport temporarily unavailable" branch.

/// Bounded exponential-backoff retry parameters.
///
/// Defaults follow Apple's CloudKit guidance: cap attempts at 5, cap
/// the delay at 60s, and start with 1s of base delay. Construct
/// `immediate()` in tests to make retry behavior deterministic without
/// real wall-clock waits.
public struct CloudSyncRetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let backoffMultiplier: Double

    public init(
        maxAttempts: Int = 5,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        backoffMultiplier: Double = 2.0
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
    }

    public static let `default` = CloudSyncRetryPolicy()

    /// Zero-delay policy for tests that want to exercise the retry loop
    /// without sleeping.
    public static func immediate(maxAttempts: Int = 5) -> CloudSyncRetryPolicy {
        CloudSyncRetryPolicy(
            maxAttempts: maxAttempts,
            baseDelay: 0,
            maxDelay: 0,
            backoffMultiplier: 1
        )
    }

    /// Delay before attempt N (1-indexed). Capped at `maxDelay`.
    public func delay(beforeAttempt attempt: Int) -> TimeInterval {
        guard attempt > 1, baseDelay > 0 else { return 0 }
        let exponent = Double(attempt - 2)
        let raw = baseDelay * pow(backoffMultiplier, exponent)
        return min(raw, maxDelay)
    }
}

/// Classifier for whether a thrown error is worth retrying. CloudKit
/// `CKError` codes split cleanly into "transient" (network blips,
/// rate-limiting, server unavailability) and "fatal" (auth,
/// permission, schema, malformed payload). Non-CKError throws default
/// to retryable so generic transport layers (e.g. URLSession-backed
/// fakes) get retried — flip to non-retryable by surfacing a typed
/// error.
public enum CloudSyncRetryClassifier {
    public static func isRetryable(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        #if canImport(CloudKit)
        if let ckError = error as? CKError {
            return isRetryable(ckError)
        }
        #endif
        return true
    }

    #if canImport(CloudKit)
    public static func isRetryable(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable,
             .networkFailure,
             .serviceUnavailable,
             .requestRateLimited,
             .zoneBusy,
             .internalError,
             .serverResponseLost,
             .accountTemporarilyUnavailable,
             .batchRequestFailed:
            return true
        case .notAuthenticated,
             .permissionFailure,
             .quotaExceeded,
             .invalidArguments,
             .badContainer,
             .badDatabase,
             .incompatibleVersion,
             .constraintViolation,
             .missingEntitlement,
             .userDeletedZone,
             .managedAccountRestricted,
             .zoneNotFound,
             .unknownItem,
             .serverRejectedRequest:
            return false
        default:
            return true
        }
    }
    #endif
}

/// Wraps a `CloudSyncTransport` with bounded exponential-backoff retry
/// for transient errors. Emits `cloudsync.retry`,
/// `cloudsync.recovery.succeeded`, and `cloudsync.recovery.failed`
/// telemetry events so observability captures the difference between
/// "user has flaky LTE" and "sync is broken."
public final class RetryingCloudSyncTransport: CloudSyncTransport, @unchecked Sendable {
    private let inner: any CloudSyncTransport
    private let policy: CloudSyncRetryPolicy
    private let telemetrySink: (any TelemetrySink)?
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        wrapping inner: any CloudSyncTransport,
        policy: CloudSyncRetryPolicy = .default,
        telemetrySink: (any TelemetrySink)? = nil,
        sleep: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) {
        self.inner = inner
        self.policy = policy
        self.telemetrySink = telemetrySink
        self.sleep = sleep ?? { interval in
            guard interval > 0 else { return }
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    public var isAvailable: Bool { inner.isAvailable }

    public func pushRecords(_ records: [CloudSyncRecord]) async throws {
        try await runWithRetry(operation: "push") {
            try await self.inner.pushRecords(records)
        }
    }

    public func pullChanges(since cursor: String?) async throws -> CloudSyncPullResult {
        try await runWithRetry(operation: "pull") {
            try await self.inner.pullChanges(since: cursor)
        }
    }

    private func runWithRetry<T>(
        operation: String,
        body: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                let result = try await body()
                if attempt > 1 {
                    telemetrySink?.record(TelemetryEvent(
                        category: "sync",
                        name: "cloudsync.recovery.succeeded",
                        severity: .info,
                        message: "Recovered after \(attempt - 1) retry attempts",
                        metadata: [
                            "operation": operation,
                            "attempts": String(attempt),
                        ]
                    ))
                }
                return result
            } catch {
                let retryable = CloudSyncRetryClassifier.isRetryable(error)
                let attemptsRemaining = policy.maxAttempts - attempt
                if !retryable || attemptsRemaining <= 0 {
                    telemetrySink?.record(TelemetryEvent(
                        category: "sync",
                        name: "cloudsync.recovery.failed",
                        severity: .error,
                        message: "Giving up after \(attempt) attempts: \(error)",
                        metadata: [
                            "operation": operation,
                            "attempts": String(attempt),
                            "retryable": String(retryable),
                        ]
                    ))
                    throw error
                }

                let nextAttempt = attempt + 1
                let delay = policy.delay(beforeAttempt: nextAttempt)
                telemetrySink?.record(TelemetryEvent(
                    category: "sync",
                    name: "cloudsync.retry",
                    severity: .warning,
                    message: "Retrying \(operation) (attempt \(nextAttempt)/\(policy.maxAttempts)) after \(error)",
                    metadata: [
                        "operation": operation,
                        "attempt": String(attempt),
                        "next_attempt": String(nextAttempt),
                        "delay_seconds": String(format: "%.3f", delay),
                    ]
                ))
                try await sleep(delay)
                attempt = nextAttempt
            }
        }
    }
}
