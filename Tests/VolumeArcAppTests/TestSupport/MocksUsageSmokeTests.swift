import XCTest
import VolumeArcCore

/// Smoke tests that each new test double in `Mocks.swift` exhibits the
/// recording or failure behavior its contract promises. Kept intentionally
/// minimal — one or two assertions per double — so a drift in the mock's
/// shape (e.g., a protocol requirement added in Core) surfaces as a
/// specific compile or test failure here rather than a diffuse regression
/// in a dozen downstream tests.
///
/// VOL-83. No production code is exercised here.
final class MocksUsageSmokeTests: XCTestCase {
    // MARK: - AI provider doubles

    func testFailingAICoachProviderAlwaysThrowsConfiguredError() async {
        let provider = FailingAICoachProvider(error: MockError("stubbed"))

        do {
            _ = try await provider.coachResponse(for: "ready?", context: "ctx")
            XCTFail("Expected failure")
        } catch let error as MockError {
            XCTAssertEqual(error.reason, "stubbed")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        XCTAssertEqual(provider.callCount, 1)
    }

    func testDelayedAICoachProviderSleepsBeforeDelegating() async throws {
        let inner = MockAICoachProvider()
        inner.responses = ["delayed reply"]
        let provider = DelayedAICoachProvider(delay: .milliseconds(20), wrapping: inner)

        let start = ContinuousClock.now
        let reply = try await provider.coachResponse(for: "q", context: "ctx")
        let elapsed = ContinuousClock.now - start

        XCTAssertEqual(reply, "delayed reply")
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(15))
    }

    func testRecordingAICoachProviderCapturesCallsAndForwards() async throws {
        let inner = MockAICoachProvider()
        inner.responses = ["first", "second"]
        let provider = RecordingAICoachProvider(wrapping: inner)

        _ = try await provider.coachResponse(for: "alpha", context: "ctx-a")
        _ = try await provider.coachResponse(for: "beta", context: "ctx-b")

        XCTAssertEqual(provider.calls, [
            .init(prompt: "alpha", context: "ctx-a"),
            .init(prompt: "beta", context: "ctx-b"),
        ])
        XCTAssertEqual(inner.callCount, 2)
    }

    // MARK: - Cloud sync transport doubles

    func testFailingCloudSyncTransportThrowsPerOperationErrors() async {
        let transport = FailingCloudSyncTransport(
            pushError: MockError("push"),
            pullError: MockError("pull")
        )

        do {
            try await transport.pushRecords([])
            XCTFail("Expected push failure")
        } catch let error as MockError {
            XCTAssertEqual(error.reason, "push")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await transport.pullChanges(since: nil)
            XCTFail("Expected pull failure")
        } catch let error as MockError {
            XCTAssertEqual(error.reason, "pull")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }


    // MARK: - Health store doubles

    func testDenyingHealthStoreReturnsFalseAndThrowsOnSessions() async {
        let store = DenyingHealthStore()

        let authorized = try? await store.requestAuthorization()
        XCTAssertEqual(authorized, false)

        do {
            try await store.startWorkoutSession(activityType: .strengthTraining)
            XCTFail("Expected session failure")
        } catch {
            // Expected.
        }
    }

    func testRecordingHealthStoreCapturesAllCallSites() async throws {
        let store = RecordingHealthStore()

        _ = try await store.requestAuthorization()
        try await store.startWorkoutSession(activityType: .strengthTraining)
        try await store.endWorkoutSession()

        XCTAssertEqual(store.calls, [
            .requestAuthorization,
            .start(.strengthTraining),
            .end,
        ])
    }

    // MARK: - Telemetry sink doubles

    func testCapturingTelemetrySinkRetainsEventsAndFiltersByName() {
        let sink = CapturingTelemetrySink()

        sink.record(TelemetryEvent(category: "sync", name: "pull_failed", severity: .warning, message: "m"))
        sink.record(TelemetryEvent(category: "sync", name: "push_failed", severity: .error, message: "m"))
        sink.record(TelemetryEvent(category: "ai", name: "pull_failed", severity: .info, message: "m"))

        XCTAssertEqual(sink.events.count, 3)
        XCTAssertEqual(sink.events(named: "pull_failed").count, 2)
        XCTAssertEqual(sink.events(category: "ai").count, 1)
    }

    func testDroppingTelemetrySinkSilentlyDiscardsEverything() {
        let sink = DroppingTelemetrySink()
        // The only contract is "it compiles, conforms, and doesn't crash"
        // — no stored state exists to assert on.
        sink.record(TestFixtures.telemetryEvent())
        sink.record(TestFixtures.telemetryEvent(name: "another"))
    }

    // MARK: - Voice transport doubles

    func testRecordingVoiceTransportCapturesLifecycleAndSendCalls() async throws {
        let transport = RecordingVoiceTransport(response: "ack")

        try await transport.connect(
            model: AIModelIdentifier("gpt-test"),
            policy: VoiceSessionPolicy("conversational")
        )
        let reply = try await transport.send(context: "ctx", userText: "hi")
        await transport.interrupt()
        await transport.disconnect()

        XCTAssertEqual(reply, "ack")
        let calls = await transport.calls
        XCTAssertEqual(calls, [
            .connect(model: "gpt-test", policy: "conversational"),
            .send(context: "ctx", userText: "hi"),
            .interrupt,
            .disconnect,
        ])
    }

    // MARK: - Fixtures smoke coverage

    func testReadinessInputFixtureProducesSessionsAndProfile() {
        let input = TestFixtures.readinessInput()
        XCTAssertFalse(input.sessions.isEmpty)
        XCTAssertEqual(input.athlete.weeklyTrainingDays, 4)
    }

    func testTrainingPlanThreeDaysFixtureProducesThreeSessions() {
        let plan = TestFixtures.trainingPlanThreeDays()
        XCTAssertEqual(plan.count, 3)
        XCTAssertFalse(plan.allSatisfy { $0.sets.isEmpty })
    }
}
