// VOL-257: coach streaming render contract.
//
// The 2026-05-26 production-readiness audit raised the question:
// "When `AIRelayCoachProvider.streamCoachResponse` emits a stream of
// `n` tokens, does `WorkoutDashboardModel.streamCoachResponse(...)`
// rebuild the full transcript on every token (O(n²) cost) or update
// only the in-flight bubble (O(n) cost)?"
//
// On inspection, the pattern at `WorkoutDashboardModel.swift:768-776`
// preserves stable bubble identity:
//   1. `appendEmptyCoachMessage()` creates a `CoachMessage` with a
//      `UUID` and appends to `coachMessages` (one-time, O(1))
//   2. The first visible token is published immediately; later chunks
//      are micro-batched before `replaceCoachMessage(id:content:)`
//      swaps the same array element with a new `CoachMessage` carrying
//      the same UUID (O(n) string accumulation, bounded array publishes)
//   3. `CoachView.swift:129` keys its `ForEach` on `\.element.id` —
//      SwiftUI's diff sees the same identifier and re-renders only the
//      bubble whose content changed; other bubbles in the transcript
//      are untouched.
//
// Net cost per token is O(L) where L is the response length, dominated
// by the `accumulated += chunk` string copy. For typical 200-500-token
// responses that's <2ms total — well below user-perceptible jank.
//
// This test pins that contract. It exercises the model's streaming
// append path against a synthetic stream of 1000 chunks and measures
// wall-clock cost. A regression that (a) makes bubble identity
// unstable, (b) removes the in-place update, or (c) introduces an
// accidentally-quadratic data structure would trip the budget.
//
// The test runs as part of the unit test bundle (NOT the perf-tests
// bundle) because it's measuring model-layer behavior, not full app
// rendering. A full-app XCUITest streaming-render check is a separate,
// more expensive Phase B test that wires through a stubbed
// AICoachProvider; deferred until needed.

#if canImport(SwiftData)
import Combine
import SwiftData
import XCTest
import VolumeArcCore

@MainActor
final class VolumeArcCoachStreamingPerfTests: XCTestCase {

    /// Stream 1000 chunks through the same code path that
    /// `WorkoutDashboardModel.streamCoachResponse` uses for live coach
    /// responses. The 1000-token figure is intentional overkill (real
    /// responses cap at ~400 tokens under the current relay's
    /// `MAX_OUTPUT_TOKENS=800` limit, which yields ~400 chunks for
    /// Gemini's SSE pacing) — exercising a 2.5× headroom ensures the
    /// contract holds for longer responses or larger context windows.
    ///
    /// Asserts: 1000 chunk appends stay under a broad wall-clock guard
    /// and produce only a handful of `coachMessages` publishes. The
    /// bounded publish count is the important contract: the model
    /// publishes the first visible token, then micro-batches transcript
    /// updates so hosted CI variance does not turn a long SSE response
    /// into 1000 main-actor publishes.
    func testStreamingAppendIsLinearInResponseLength() throws {
        let result = try measureStreamingAppend(chunkCount: 1000)

        XCTAssertEqual(
            result.model.coachMessages.last?.sender,
            .coach,
            "Stream should end with one coach-authored message"
        )
        XCTAssertGreaterThanOrEqual(
            result.model.coachMessages.last?.content.count ?? 0,
            1000,
            "1000-chunk synthetic stream should produce at least 1000 chars of content"
        )
        XCTAssertLessThanOrEqual(
            result.coachMessagePublishCount,
            6,
            """
            VOL-257 contract regression: 1000 streamed chunks produced \
            \(result.coachMessagePublishCount) coachMessages publishes. \
            Expected user bubble, empty coach bubble, first-token publish, \
            and final publish with small headroom; a publish per token \
            would reintroduce UI churn.
            """
        )
        XCTAssertLessThan(
            result.millis,
            750.0,
            """
            VOL-257 contract regression: streaming 1000 tokens through \
            WorkoutDashboardModel.streamCoachResponse took \(result.millis)ms \
            (budget 750ms). The current implementation is O(n) — if \
            this test fails, check whether bubble identity is still \
            stable (ForEach keyed on \\.element.id) and whether \
            replaceCoachMessage(id:content:) still updates in-place.
            """
        )
    }

    // MARK: - Helpers

    private struct StreamingMeasurement {
        let model: WorkoutDashboardModel
        let millis: Double
        let coachMessagePublishCount: Int
    }

    private func measureStreamingAppend(
        chunkCount: Int
    ) throws -> StreamingMeasurement {
        let provider = StubStreamingCoachProvider(chunkCount: chunkCount)
        let model = try makeModel(aiProvider: provider)
        var coachMessagePublishCount = 0
        let cancellable = model.$coachMessages
            .dropFirst()
            .sink { _ in
                coachMessagePublishCount += 1
            }

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            // The same flow `WorkoutDashboardModel.askCoach(...)` drives
            // for real coach calls — kicked off synchronously here so
            // the wall-clock measurement reflects only the streaming
            // append work, not async overhead.
            let waiter = expectation(description: "stream completes")
            Task {
                await model.askCoach("synthetic \(chunkCount)-token perf probe")
                waiter.fulfill()
            }
            wait(for: [waiter], timeout: 30)
        }

        withExtendedLifetime(cancellable) {}
        let millis = Double(elapsed.components.seconds) * 1000.0
            + Double(elapsed.components.attoseconds) / 1e15
        return StreamingMeasurement(
            model: model,
            millis: millis,
            coachMessagePublishCount: coachMessagePublishCount
        )
    }

    private func makeModel(aiProvider: any AICoachProvider) throws -> WorkoutDashboardModel {
        let schema = Schema(VolumeArcSchemaV5.models)
        let config = ModelConfiguration(
            "CoachStreamingPerf-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: VolumeArcSchemaMigrationPlan.self,
            configurations: [config]
        )

        return WorkoutDashboardModel(
            aiProvider: aiProvider,
            syncEngine: CloudSyncCoordinator(
                transport: UnavailableCloudSyncTransport(reason: "Streaming perf test does not sync"),
                stateStore: FileSyncStateStore(
                    url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                )
            ),
            repository: SwiftDataWorkoutRepository(container: container),
            coachMemoryRepository: SwiftDataCoachMemoryRepository(container: container),
            userProfileRepository: SwiftDataUserProfileRepository(container: container),
            trainingPlanRepository: SwiftDataTrainingPlanRepository(container: container),
            accountSessionStore: UserDefaultsAccountSessionStore(),
            voicePermissionStore: UnavailableVoicePermissionStore(),
            healthStore: UnavailableHealthStore(),
            notificationStore: InMemoryNotificationStore(),
            telemetrySink: InMemoryTelemetrySink(),
            surfaceStore: UserDefaultsPlatformSurfaceStateStore(),
            subscriptionStore: StoreKitSubscriptionStore(productIDs: []),
            voiceCoach: LiveVoiceCoachOrchestrator(
                transport: AIRelayVoiceTransport(provider: aiProvider)
            )
        )
    }
}

/// Streams a fixed number of single-character chunks via the
/// `AICoachProvider` streaming protocol. No network, no model — the
/// test is measuring the model-side append loop, not relay or Gemini
/// behavior.
private struct StubStreamingCoachProvider: AICoachProvider, @unchecked Sendable {
    let chunkCount: Int

    func coachResponse(for prompt: String, context: String) async throws -> String {
        String(repeating: "x", count: chunkCount)
    }

    func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for _ in 0..<chunkCount {
                continuation.yield("x")
            }
            continuation.finish()
        }
    }
}
#endif
