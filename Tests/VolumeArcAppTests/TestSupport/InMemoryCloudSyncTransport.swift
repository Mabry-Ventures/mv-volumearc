import Foundation
import VolumeArcCore
#if canImport(CloudKit)
import CloudKit
#endif

// VOL-137: stateful hermetic fake for `CloudSyncTransport`. Stores
// pushed records keyed by `(kind, identifier)`, advances cursors
// deterministically on each pull, and supports per-call error
// injection scripts so tests can drive the coordinator through
// every transient/fatal error branch without standing up CloudKit.
//
// Designed to coexist with the existing thinner mocks
// (`MockCloudSyncTransport`, `FailingCloudSyncTransport`) — those remain
// useful for micro-tests that don't need state. Reach for this fake
// when a test needs to assert on exact pushed records, cursor
// progression, or a specific error sequence. Pair it with the
// production `RetryingCloudSyncTransport` decorator (in
// `VolumeArcCore`) to drive retry/backoff behavior under controlled
// failure scripts.
//
// Concurrency: all mutable state lives behind `NSLock.withLock`.
// `lock()`/`unlock()` are unavailable from `async` contexts under
// strict concurrency, so every accessor uses the scoped form.
final class InMemoryCloudSyncTransport: CloudSyncTransport, @unchecked Sendable {
    private final class State {
        var stored: [String: CloudSyncRecord] = [:]
        var pushHistory: [[CloudSyncRecord]] = []
        var pullCount = 0
        var pendingPullResults: [CloudSyncPullResult] = []
        var pushErrorScript: [Error?] = []
        var pullErrorScript: [Error?] = []
        var available = true
    }
    private let lock = NSLock()
    private let state = State()

    var isAvailable: Bool {
        lock.withLock { state.available }
    }

    func setAvailable(_ value: Bool) {
        lock.withLock { state.available = value }
    }

    // MARK: - Inspection

    var pushedRecords: [CloudSyncRecord] {
        lock.withLock { state.pushHistory.flatMap { $0 } }
    }

    var pushBatchCount: Int {
        lock.withLock { state.pushHistory.count }
    }

    var pullCallCount: Int {
        lock.withLock { state.pullCount }
    }

    var storedRecordCount: Int {
        lock.withLock { state.stored.count }
    }

    // MARK: - Scripting

    func enqueuePullResults(_ results: [CloudSyncPullResult]) {
        lock.withLock { state.pendingPullResults.append(contentsOf: results) }
    }

    /// Script a sequence of push outcomes. `nil` = success, non-nil
    /// = throw that error on the corresponding call. Calls past the
    /// scripted length succeed.
    func enqueuePushOutcomes(_ outcomes: [Error?]) {
        lock.withLock { state.pushErrorScript.append(contentsOf: outcomes) }
    }

    /// Script a sequence of pull outcomes. `nil` = use the next
    /// pending pull result (or an empty default), non-nil = throw.
    func enqueuePullOutcomes(_ outcomes: [Error?]) {
        lock.withLock { state.pullErrorScript.append(contentsOf: outcomes) }
    }

    // MARK: - CloudSyncTransport

    func pushRecords(_ records: [CloudSyncRecord]) async throws {
        let nextError: Error? = lock.withLock {
            state.pushErrorScript.isEmpty ? nil : state.pushErrorScript.removeFirst()
        }
        if let error = nextError { throw error }

        lock.withLock {
            state.pushHistory.append(records)
            for record in records {
                let key = "\(record.kind.rawValue)|\(record.identifier)"
                state.stored[key] = record
            }
        }
    }

    func pullChanges(since cursor: String?) async throws -> CloudSyncPullResult {
        let nextError: Error? = lock.withLock {
            state.pullCount += 1
            return state.pullErrorScript.isEmpty ? nil : state.pullErrorScript.removeFirst()
        }
        if let error = nextError { throw error }

        return lock.withLock {
            if !state.pendingPullResults.isEmpty {
                return state.pendingPullResults.removeFirst()
            }
            return CloudSyncPullResult(
                changedRecords: [],
                deletedRecordIDs: [],
                nextCursor: "cursor-\(state.pullCount)"
            )
        }
    }
}

// MARK: - CKError factories

#if canImport(CloudKit)
enum CKErrorFactory {
    /// Build a synthetic `CKError` for a specific code. CloudKit's
    /// `CKError` is `NSError`-bridged, so we can manufacture one
    /// without a live CloudKit operation.
    static func make(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> CKError {
        let nsError = NSError(
            domain: CKErrorDomain,
            code: code.rawValue,
            userInfo: userInfo
        )
        return CKError(_nsError: nsError)
    }

    static var networkUnavailable: CKError { make(.networkUnavailable) }
    static var networkFailure: CKError { make(.networkFailure) }
    static var serviceUnavailable: CKError { make(.serviceUnavailable) }
    static var requestRateLimited: CKError { make(.requestRateLimited) }
    static var zoneBusy: CKError { make(.zoneBusy) }
    static var zoneNotFound: CKError { make(.zoneNotFound) }
    static var notAuthenticated: CKError { make(.notAuthenticated) }
    static var quotaExceeded: CKError { make(.quotaExceeded) }
    static var permissionFailure: CKError { make(.permissionFailure) }
    static var accountTemporarilyUnavailable: CKError { make(.accountTemporarilyUnavailable) }
}
#endif
