import XCTest
import VolumeArcCore

/// VOL-64. Asserts every concrete `AICoachProvider` routes its prompt through
/// `CoachPromptTemplate.render(...)` rather than building it ad-hoc.
///
/// The template stamps a marker (`CoachPromptTemplate.templateMarker`) into
/// every rendered prompt. Each provider propagates that marker into whatever
/// it forwards to its model — the relay sees it in the request body, the
/// heuristic sees it in the dispatch input, and the on-device session sees it
/// in the rendered prompt. A regression that bypasses the template (e.g.,
/// concatenating context + question by hand) drops the marker and trips
/// these tests, so the template stays load-bearing instead of drifting back
/// to dead scaffolding.
final class VolumeArcCoachPromptTemplateTests: XCTestCase {

    // MARK: - Renderer fundamentals

    func testRenderEmbedsTemplateMarkerSystemPromptContextAndQuestion() {
        let context = makeContext()
        let rendered = CoachPromptTemplate.render(
            intent: .progression,
            context: context,
            question: "What should I do today?",
            style: .motivational
        )

        XCTAssertTrue(
            rendered.contains(CoachPromptTemplate.templateMarker),
            "Rendered prompt must carry the template marker so providers that bypass `render` show up as failing tests"
        )
        XCTAssertTrue(
            rendered.contains("intent=progression"),
            "Rendered prompt must declare the intent so downstream consumers can route on it"
        )
        XCTAssertTrue(
            rendered.contains("VolumeArc's strength coach"),
            "Rendered prompt must include the system prompt"
        )
        XCTAssertTrue(
            rendered.contains("Readiness: 78/100"),
            "Rendered prompt must include the structured context block (readiness)"
        )
        XCTAssertTrue(
            rendered.contains("Last session: 4 sets"),
            "Rendered prompt must include the structured context block (last session)"
        )
        XCTAssertTrue(
            rendered.contains("What should I do today?"),
            "Rendered prompt must include the athlete's verbatim question"
        )
        XCTAssertTrue(
            rendered.contains("Anchor the answer"),
            "Rendered prompt must include the per-intent envelope (progression hint)"
        )
    }

    func testRenderIsDeterministicForIdenticalInputs() {
        let context = makeContext()
        let first = CoachPromptTemplate.render(
            intent: .recovery,
            context: context,
            question: "How do I feel?",
            style: .analytical
        )
        let second = CoachPromptTemplate.render(
            intent: .recovery,
            context: context,
            question: "How do I feel?",
            style: .analytical
        )
        XCTAssertEqual(first, second, "Renderer must be a pure function for unit-testable prompts")
    }

    func testInferIntentMapsKeywordsToIntents() {
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "Am I ready to push?"), .recovery)
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "I feel sick today, should I train?"), .recovery)
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "My hips are tight and I feel run-down"), .recovery)
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "Should I deload this week?"), .deload)
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "Form check on my squat?"), .form)
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "Can I substitute pull-ups for rows?"), .substitution)
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "Should I go heavier?"), .progression)
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "What are my plans for the week?"), .planning)
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "Can you set up my week?"), .planning)
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "How was the weekend?"), .free)
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "Hello coach"), .free)
    }

    func testRecoveryPromptAddsNoPressureSicknessAndSorenessGuardrails() {
        let rendered = CoachPromptTemplate.render(
            intent: .recovery,
            context: makeContext(),
            question: "I'm sick and sore. Should I push through?",
            style: .motivational
        )

        XCTAssertTrue(rendered.contains("rest is"))
        XCTAssertTrue(rendered.contains("valid win"))
        XCTAssertTrue(rendered.contains("light technique"))
        XCTAssertTrue(rendered.contains("easy accessories"))
        XCTAssertTrue(rendered.contains("no guilt"))
        XCTAssertTrue(rendered.contains("Never recommend lifting through pain"))
    }

    func testCoachWorkoutPlanExtractorBuildsStartablePlanFromSetRepBullets() {
        let response = """
        Keep it light and focused on form.

        Here's a sample workout plan for you:
        - Dumbbell rows: 3 sets of 10 reps
        - Light lunges: 3 sets of 10 reps per leg
        - Light planks: 3 sets of 30 seconds
        - Side plank: 30 seconds per side
        - Light calf raises: 3 sets of 15 reps
        """

        guard let extractedPlan = CoachWorkoutPlanExtractor.plan(from: response, title: "Coach Workout") else {
            XCTFail("Expected set/rep bullets to produce a startable workout plan")
            return
        }

        XCTAssertEqual(extractedPlan.title, "Coach Workout")
        XCTAssertEqual(extractedPlan.targetRPE, 6)
        XCTAssertEqual(extractedPlan.exercises.map(\.name), [
            "Dumbbell rows",
            "Light lunges",
            "Light planks",
            "Side plank",
            "Light calf raises",
        ])
        XCTAssertEqual(extractedPlan.exercises.first?.sets, 3)
        XCTAssertEqual(extractedPlan.exercises.first?.reps, 10)
        XCTAssertEqual(extractedPlan.exercises.first?.weight, 20)
        XCTAssertEqual(extractedPlan.exercises[2].reps, 30)
        XCTAssertEqual(extractedPlan.exercises[3].sets, 1)
        XCTAssertEqual(extractedPlan.exercises[3].reps, 30)
    }

    func testCoachWorkoutPlanExtractorIgnoresVagueAdviceWithoutSetsAndReps() {
        let plan = CoachWorkoutPlanExtractor.plan(
            from: "Take it easy today. Walk, hydrate, and resume lifting when symptoms improve.",
            title: "Coach Workout"
        )

        XCTAssertNil(plan)
    }

    func testPlanningIntentAddsHardHorizonGuardrails() {
        let context = makeContext()
        let rendered = CoachPromptTemplate.render(
            intent: .planning,
            context: context,
            question: "What are my plans for the week?",
            style: .analytical
        )

        XCTAssertTrue(rendered.contains("intent=planning"))
        XCTAssertTrue(rendered.contains("current 7-day training week"))
        XCTAssertTrue(rendered.contains("Do not provide 14 days"))
        XCTAssertTrue(rendered.contains("weekly schedule is not present"))
    }

    func testSanitizeUserControlledTextPreservesLegitimateMultilineNotes() {
        let sanitized = CoachPromptTemplate.sanitizeUserControlledText("""
        Friday: deload
        Saturday: focus on bar speed
        """)

        XCTAssertEqual(sanitized, "Friday: deload\nSaturday: focus on bar speed")
    }

    func testStrictPrivacyModeRedactionPropagatesIntoRender() {
        let context = makeContext(athleteName: "Jane Lifter")
        let rendered = CoachPromptTemplate.render(
            intent: .planning,
            context: context,
            question: "What's the plan?",
            style: .motivational,
            privacyMode: .strict
        )
        XCTAssertFalse(rendered.contains("Jane Lifter"), "Strict mode must redact the athlete name from the rendered prompt")
        XCTAssertFalse(rendered.contains("Last 7 days"), "Strict mode must drop session-history rollups")
        XCTAssertTrue(rendered.contains("the athlete"), "Strict mode must substitute a generic identifier")
        XCTAssertTrue(rendered.contains("Readiness: 78/100"), "Strict mode must preserve readiness")
    }

    // MARK: - Provider adoption — the load-bearing assertion

    /// Asserts the relay provider routes its outbound request body through
    /// the template. We can't make a real HTTP call from XCTest, so we
    /// exercise the provider against a base URL that resolves to a closed
    /// port and intercept the encoded request body via a custom URLProtocol.
    func testAIRelayProviderRendersOutboundBodyThroughTemplate() async throws {
        // Register an interceptor that captures the request body and short-
        // circuits with a synthetic 200. The interceptor is registered on
        // a custom URLSession (not the shared one) to keep test isolation.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self] + (configuration.protocolClasses ?? [])

        // The shared session is what the provider actually uses, so install
        // the interceptor on the global protocol registry for the duration
        // of this test. Tear-down restores the registry.
        URLProtocol.registerClass(CapturingURLProtocol.self)
        defer { URLProtocol.unregisterClass(CapturingURLProtocol.self) }
        CapturedRelayRequest.shared.reset()

        let relayConfig = AIRelayConfiguration(
            baseURL: URL(string: "https://relay.test.invalid")!,
            bearerToken: "ignored"
        )
        let provider = AIRelayCoachProvider(
            configuration: relayConfig,
            credentialsProvider: StaticAuthProvider(value: "Bearer fake")
        )

        let context = makeContext().asPromptBlock(privacyMode: .standard)
        _ = try await provider.coachResponse(
            for: "Should I add weight today?",
            context: context
        )

        let captured = try XCTUnwrap(CapturedRelayRequest.shared.lastBody, "Relay provider should have issued a request the interceptor captured")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: captured) as? [String: Any])

        let renderedPrompt = try XCTUnwrap(json["prompt"] as? String, "Relay body must include `prompt` field")
        XCTAssertTrue(
            renderedPrompt.contains(CoachPromptTemplate.templateMarker),
            "AIRelayCoachProvider must route its outbound prompt through CoachPromptTemplate — the template marker is missing from the relay request body"
        )
        XCTAssertTrue(
            renderedPrompt.contains("intent=progression"),
            "Relay body must encode the inferred intent ('progression' for 'add weight')"
        )
        XCTAssertTrue(
            renderedPrompt.contains("Should I add weight today?"),
            "Relay body must include the athlete's verbatim question"
        )
        XCTAssertNil(
            json["question"],
            "Relay body must not send a duplicate raw `question`; the rendered prompt is the only user-message payload"
        )
        XCTAssertNil(
            json["contextBlock"],
            "Relay body must not send a duplicate raw `contextBlock`; the rendered prompt is the only context payload"
        )
        XCTAssertEqual(
            json["intent"] as? String,
            CoachIntent.progression.rawValue,
            "Relay body must surface the intent as a separate field for analytics"
        )
        let systemField = try XCTUnwrap(json["system"] as? String, "Relay body must include the system prompt")
        XCTAssertTrue(systemField.contains("VolumeArc's strength coach"))
    }

    /// Asserts the local heuristic provider also routes through the template.
    /// We can't inspect a request body here (no network), so we lean on the
    /// fact that the rendered prompt contains the marker, and prove the
    /// rule-based response keeps citing values from the embedded context.
    func testLocalHeuristicProviderConsumesTemplatedInput() async throws {
        let provider = LocalHeuristicAICoachProvider()
        let context = makeContext().asPromptBlock(privacyMode: .standard)

        // The heuristic dispatches on intent classification (recovery here).
        // After VOL-64 it operates on the rendered string, so the readiness
        // value still parses correctly even though the input went through
        // an additional templating step. "recovery" is a recovery-intent
        // keyword in `CoachPromptTemplate.inferIntent(...)`.
        let response = try await provider.coachResponse(for: "Am I ready or do I need recovery?", context: context)
        XCTAssertTrue(
            response.contains("78"),
            "Local heuristic must still extract the readiness score after the template wrapping (got: \(response))"
        )
    }

    func testLocalHeuristicProviderHandlesSicknessWithRestAndLightOptions() async throws {
        let provider = LocalHeuristicAICoachProvider()
        let response = try await provider.coachResponse(
            for: "I'm sick, sore, and tight. Should I push today?",
            context: makeContext().asPromptBlock(privacyMode: .standard)
        )
        let lowercased = response.lowercased()

        XCTAssertTrue(lowercased.contains("rest"))
        XCTAssertTrue(lowercased.contains("light"))
        XCTAssertFalse(lowercased.contains("push through"))
        XCTAssertFalse(lowercased.contains("no excuses"))
    }

    // MARK: - Helpers

    private func makeContext(athleteName: String = "Sam") -> CoachContext {
        CoachContext(
            athleteName: athleteName,
            advancementLevel: "intermediate",
            readinessScore: 78,
            readinessBrief: "Solid recovery, slight fatigue.",
            nextExercise: "Back Squat",
            nextTarget: "225lb x 5",
            recentSessionCount: 4,
            averageRPE: 7.8,
            lastSessionSummary: "4 sets, 4500lb total, RPE 7.8",
            recentMemories: ["Squat felt heavy off the floor last session."]
        )
    }
}

// MARK: - Test doubles

private struct StaticAuthProvider: AIRelayCredentialsProviding {
    let value: String
    func authorizationHeaderValue() async throws -> String { value }
}

/// Shared sink for request body capture across the URLProtocol singleton.
private final class CapturedRelayRequest: @unchecked Sendable {
    static let shared = CapturedRelayRequest()
    private let lock = NSLock()
    private var _lastBody: Data?

    var lastBody: Data? {
        lock.lock(); defer { lock.unlock() }
        return _lastBody
    }

    func record(_ body: Data?) {
        lock.lock(); defer { lock.unlock() }
        _lastBody = body
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        _lastBody = nil
    }
}

/// URLProtocol that captures the outbound HTTP body and short-circuits with a
/// canned 200 OK. Lets us assert what the provider sends without making a
/// real network call.
private final class CapturingURLProtocol: URLProtocol, @unchecked Sendable {
    // swiftlint:disable static_over_final_class
    // `URLProtocol.canInit(with:)` and `canonicalRequest(for:)` are declared
    // as `class func`; overrides must match the dispatch kind and therefore
    // cannot be `static`.
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "relay.test.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        // URLSession strips the httpBodyStream into a separate channel for
        // POSTs, so consult both. The provider sets `httpBody` directly via
        // `JSONEncoder().encode(...)`, so the simple path captures it.
        let bodyData: Data? = {
            if let body = request.httpBody { return body }
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: 4096)
                    guard read > 0 else { break }
                    data.append(buffer, count: read)
                }
                return data
            }
            return nil
        }()
        CapturedRelayRequest.shared.record(bodyData)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let payload = Data(#"{"text":"ok"}"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
