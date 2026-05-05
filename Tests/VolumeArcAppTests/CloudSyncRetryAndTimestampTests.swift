#if canImport(SwiftData)
import XCTest
import VolumeArcCore
#if canImport(CloudKit)
import CloudKit
#endif

// VOL-137 + VOL-130: hermetic tests for the cloud-sync retry/backoff
// contract, recovery telemetry, the `Timestamp` newtype, and the
// `InMemoryCloudSyncTransport` test fake. Each test in this file
// exercises behavior that previously had no unit coverage; the longer
// integration suite lives in `VolumeArcCloudSyncTests.swift`.

final class CloudSyncRetryAndTimestampTests: XCTestCase {

    // MARK: - Timestamp newtype (VOL-130)

    /// Property-style table covering the edge cases called out in
    /// VOL-130's acceptance criteria: epoch boundary, leap-second
    /// adjacent, future date 100 years out, negative (pre-epoch).
    func testTimestampSecondsRoundTrip() {
        let cases: [Double] = [
            0,                              // epoch
            1,                              // 1 second after epoch
            -1,                             // 1 second before epoch
            -86_400,                        // negative date (1969-12-31)
            1_435_708_799,                  // 2015-06-30 23:59:59 UTC (last second before the 2015 leap-second insertion)
            1_435_708_800,                  // 2015-07-01 00:00:00 UTC (immediately after)
            4_733_510_400,                  // ~2120 (100y out)
            Date.now.timeIntervalSince1970, // current
        ]
        for seconds in cases {
            let ts = Timestamp.seconds(seconds)
            XCTAssertEqual(ts.secondsSinceEpoch, seconds, accuracy: 1e-6, "seconds round-trip failed for \(seconds)")
            XCTAssertEqual(ts.millisecondsSinceEpoch, seconds * 1_000, accuracy: 1e-3, "ms derivation failed for \(seconds)")
        }
    }

    func testTimestampMillisecondsRoundTrip() {
        let cases: [Double] = [
            0,
            1_000,
            -1_000,
            1_435_708_799_000,
            4_733_510_400_000,
        ]
        for ms in cases {
            let ts = Timestamp.milliseconds(ms)
            XCTAssertEqual(ts.millisecondsSinceEpoch, ms, accuracy: 1e-3, "ms round-trip failed for \(ms)")
            XCTAssertEqual(ts.secondsSinceEpoch, ms / 1_000, accuracy: 1e-6, "seconds derivation failed for \(ms)")
        }
    }

    /// `autoDetect` is the legacy heuristic preserved for foreign data
    /// of unknown unit. Verify the threshold behavior at the boundary
    /// — values just above the threshold are interpreted as ms,
    /// values just below as seconds.
    func testTimestampAutoDetectThreshold() throws {
        let secondsBelow = Timestamp.secondsVsMillisecondsThreshold - 1
        let msAbove = Timestamp.secondsVsMillisecondsThreshold + 1

        let asSeconds = try XCTUnwrap(Timestamp.autoDetect(secondsBelow))
        XCTAssertEqual(asSeconds.secondsSinceEpoch, secondsBelow, accuracy: 1e-6)

        let asMs = try XCTUnwrap(Timestamp.autoDetect(msAbove))
        XCTAssertEqual(asMs.secondsSinceEpoch, msAbove / 1_000, accuracy: 1e-6)

        XCTAssertNil(Timestamp.autoDetect(.nan))
        XCTAssertNil(Timestamp.autoDetect(.infinity))
    }

    // MARK: - Retry policy (VOL-130)

    func testRetryPolicyDelayIsExponentialAndCapped() {
        let policy = CloudSyncRetryPolicy(
            maxAttempts: 5,
            baseDelay: 1.0,
            maxDelay: 8.0,
            backoffMultiplier: 2.0
        )
        // Attempt 1 has no delay (it's the initial call).
        XCTAssertEqual(policy.delay(beforeAttempt: 1), 0)
        // Attempt 2 = first retry = baseDelay
        XCTAssertEqual(policy.delay(beforeAttempt: 2), 1.0, accuracy: 1e-6)
        // Attempts 3+ scale exponentially until capped.
        XCTAssertEqual(policy.delay(beforeAttempt: 3), 2.0, accuracy: 1e-6)
        XCTAssertEqual(policy.delay(beforeAttempt: 4), 4.0, accuracy: 1e-6)
        // Capped at maxDelay (8.0) — would otherwise be 16.
        XCTAssertEqual(policy.delay(beforeAttempt: 5), 8.0, accuracy: 1e-6)
    }

    func testRetryPolicyImmediateUsesZeroDelay() {
        let policy = CloudSyncRetryPolicy.immediate(maxAttempts: 3)
        for attempt in 1...10 {
            XCTAssertEqual(policy.delay(beforeAttempt: attempt), 0)
        }
    }

    // MARK: - CKError classification (VOL-130 / VOL-137)

    #if canImport(CloudKit)
    func testRetryClassifierTreatsTransientCKErrorsAsRetryable() {
        XCTAssertTrue(CloudSyncRetryClassifier.isRetryable(CKErrorFactory.networkUnavailable))
        XCTAssertTrue(CloudSyncRetryClassifier.isRetryable(CKErrorFactory.networkFailure))
        XCTAssertTrue(CloudSyncRetryClassifier.isRetryable(CKErrorFactory.serviceUnavailable))
        XCTAssertTrue(CloudSyncRetryClassifier.isRetryable(CKErrorFactory.requestRateLimited))
        XCTAssertTrue(CloudSyncRetryClassifier.isRetryable(CKErrorFactory.zoneBusy))
        XCTAssertTrue(CloudSyncRetryClassifier.isRetryable(CKErrorFactory.accountTemporarilyUnavailable))
    }

    func testRetryClassifierTreatsFatalCKErrorsAsNonRetryable() {
        // VOL-137: zoneNotFound is fatal at the retry-decorator level —
        // recovery requires re-bootstrapping the zone, which is a
        // different mechanic than uniform retry. Filed for follow-up.
        XCTAssertFalse(CloudSyncRetryClassifier.isRetryable(CKErrorFactory.zoneNotFound))
        XCTAssertFalse(CloudSyncRetryClassifier.isRetryable(CKErrorFactory.notAuthenticated))
        XCTAssertFalse(CloudSyncRetryClassifier.isRetryable(CKErrorFactory.permissionFailure))
        XCTAssertFalse(CloudSyncRetryClassifier.isRetryable(CKErrorFactory.quotaExceeded))
    }
    #endif

    func testRetryClassifierTreatsCancellationAsNonRetryable() {
        XCTAssertFalse(CloudSyncRetryClassifier.isRetryable(CancellationError()))
    }

    // MARK: - RetryingCloudSyncTransport (VOL-130)

    /// Push partial failure with retry: transient errors clear, the
    /// underlying push eventually succeeds, and recovery telemetry
    /// records the win.
    func testRetryingTransportEventuallySucceedsOnPush() async throws {
        let inner = InMemoryCloudSyncTransport()
        #if canImport(CloudKit)
        let transientError: Error = CKErrorFactory.networkUnavailable
        #else
        let transientError: Error = NSError(domain: "test", code: 1)
        #endif
        inner.enqueuePushOutcomes([transientError, transientError, nil])

        let sink = CapturingTelemetrySink()
        let transport = RetryingCloudSyncTransport(
            wrapping: inner,
            policy: .immediate(maxAttempts: 5),
            telemetrySink: sink
        )

        let record = makeUpsertRecord()
        try await transport.pushRecords([record])

        XCTAssertEqual(inner.pushBatchCount, 1, "Inner only sees the successful push")
        XCTAssertEqual(inner.pushedRecords.count, 1)
        let names = sink.events.map(\.name)
        XCTAssertEqual(names.filter { $0 == "cloudsync.retry" }.count, 2)
        XCTAssertEqual(names.filter { $0 == "cloudsync.recovery.succeeded" }.count, 1)
        XCTAssertEqual(names.filter { $0 == "cloudsync.recovery.failed" }.count, 0)
    }

    /// Exhausting the retry budget surfaces `recovery.failed` and
    /// re-throws — the original error reaches the caller intact.
    func testRetryingTransportEmitsRecoveryFailedAfterBudgetExhausted() async {
        let inner = InMemoryCloudSyncTransport()
        #if canImport(CloudKit)
        let transientError: Error = CKErrorFactory.serviceUnavailable
        #else
        let transientError: Error = NSError(domain: "test", code: 1)
        #endif
        inner.enqueuePushOutcomes([transientError, transientError, transientError])

        let sink = CapturingTelemetrySink()
        let transport = RetryingCloudSyncTransport(
            wrapping: inner,
            policy: .immediate(maxAttempts: 3),
            telemetrySink: sink
        )

        do {
            try await transport.pushRecords([makeUpsertRecord()])
            XCTFail("Expected push to throw after exhausting retries")
        } catch {
            // Pass — error propagated.
        }

        let names = sink.events.map(\.name)
        XCTAssertEqual(names.filter { $0 == "cloudsync.retry" }.count, 2)
        XCTAssertEqual(names.filter { $0 == "cloudsync.recovery.failed" }.count, 1)
        XCTAssertEqual(names.filter { $0 == "cloudsync.recovery.succeeded" }.count, 0)
    }

    /// Non-retryable errors (auth, permissions, malformed schema)
    /// short-circuit the retry loop — no wasted attempts, single
    /// `recovery.failed` event.
    #if canImport(CloudKit)
    func testRetryingTransportShortCircuitsOnNonRetryableError() async {
        let inner = InMemoryCloudSyncTransport()
        inner.enqueuePushOutcomes([CKErrorFactory.notAuthenticated])

        let sink = CapturingTelemetrySink()
        let transport = RetryingCloudSyncTransport(
            wrapping: inner,
            policy: .immediate(maxAttempts: 5),
            telemetrySink: sink
        )

        do {
            try await transport.pushRecords([makeUpsertRecord()])
            XCTFail("Expected non-retryable error to throw")
        } catch {
            XCTAssertTrue(error is CKError)
        }

        let names = sink.events.map(\.name)
        XCTAssertEqual(names.filter { $0 == "cloudsync.retry" }.count, 0,
                       "Non-retryable errors should not produce retry events")
        XCTAssertEqual(names.filter { $0 == "cloudsync.recovery.failed" }.count, 1)
    }
    #endif

    // MARK: - InMemoryCloudSyncTransport (VOL-137)

    /// Pull cursor advance: each pull returns the queued result with
    /// its declared `nextCursor`, and the fake's call counter keeps
    /// the synthetic default cursor monotonic.
    func testInMemoryTransportAdvancesCursorAcrossPulls() async throws {
        let transport = InMemoryCloudSyncTransport()
        transport.enqueuePullResults([
            CloudSyncPullResult(changedRecords: [], deletedRecordIDs: [], nextCursor: "A"),
            CloudSyncPullResult(changedRecords: [], deletedRecordIDs: [], nextCursor: "B"),
        ])

        let first = try await transport.pullChanges(since: nil)
        XCTAssertEqual(first.nextCursor, "A")

        let second = try await transport.pullChanges(since: first.nextCursor)
        XCTAssertEqual(second.nextCursor, "B")

        // After the script empties, the fake synthesizes a cursor
        // from the call count so callers don't see nil.
        let third = try await transport.pullChanges(since: second.nextCursor)
        XCTAssertEqual(third.nextCursor, "cursor-3")
    }

    /// Push success path: the fake records each batch and the
    /// stored map ends with one entry per logical record.
    func testInMemoryTransportRecordsPushedBatches() async throws {
        let transport = InMemoryCloudSyncTransport()
        let one = makeUpsertRecord(identifier: "w-1")
        let two = makeUpsertRecord(identifier: "w-2")

        try await transport.pushRecords([one, two])
        try await transport.pushRecords([one])

        XCTAssertEqual(transport.pushBatchCount, 2)
        XCTAssertEqual(transport.pushedRecords.count, 3)
        XCTAssertEqual(transport.storedRecordCount, 2,
                       "Re-pushing the same record overwrites; storage holds one per (kind, id).")
    }

    // MARK: - Helpers

    private func makeUpsertRecord(identifier: String = "w-1") -> CloudSyncRecord {
        CloudSyncRecord(
            kind: .workout,
            identifier: identifier,
            operation: .upsert,
            payloadJSON: "{}",
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
#endif
