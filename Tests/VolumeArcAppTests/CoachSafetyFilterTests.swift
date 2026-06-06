import XCTest
import VolumeArcCore

final class CoachSafetyFilterTests: XCTestCase {
    func testReplacesUnsafeSymptomAdvice() {
        let response = CoachSafetyFilter.filteredResponse(
            prompt: "I'm sick and sore. Should I push today?",
            context: "Readiness: 85/100 - strong recovery",
            response: "Push through and go heavy today. No excuses."
        )
        let lowered = response.lowercased()

        XCTAssertTrue(lowered.contains("rest is a valid win"))
        XCTAssertTrue(lowered.contains("light"))
        XCTAssertTrue(lowered.contains("40-60%"))
        XCTAssertTrue(lowered.contains("stop"))
        XCTAssertFalse(lowered.contains("push through"))
        XCTAssertFalse(lowered.contains("no excuses"))
    }

    func testTreatsJointPainAsRecoveryOverride() {
        let response = CoachSafetyFilter.filteredResponse(
            prompt: "My knee hurts and my back feels tight. Should I still squat heavy?",
            context: "Readiness: 85/100 - strong recovery",
            response: "Add weight and grind through the top set."
        )
        let lowered = response.lowercased()

        XCTAssertTrue(lowered.contains("symptoms matter more than the score"))
        XCTAssertTrue(lowered.contains("rest is a valid win"))
        XCTAssertTrue(lowered.contains("40-60%"))
        XCTAssertTrue(lowered.contains("stop"))
        XCTAssertFalse(lowered.contains("add weight"))
        XCTAssertFalse(lowered.contains("grind"))
        XCTAssertFalse(lowered.contains("squat heavy"))
    }

    func testDoesNotTreatWillAsIllness() {
        let response = CoachSafetyFilter.filteredResponse(
            prompt: "Will I add five pounds next week?",
            context: "Readiness: 85/100 - strong recovery",
            response: "Add five pounds only if warmups move cleanly."
        )

        XCTAssertEqual(response, "Add five pounds only if warmups move cleanly.")
    }

    func testUsesCurrentSymptomsFromContext() {
        let response = CoachSafetyFilter.filteredResponse(
            prompt: "Should I push today?",
            context: """
            Readiness: 85/100 - strong recovery
            - Last session: knee soreness and back tightness after squats.
            """,
            response: "Add weight and grind through the top set."
        )
        let lowered = response.lowercased()

        XCTAssertTrue(lowered.contains("symptoms matter more than the score"))
        XCTAssertTrue(lowered.contains("rest is a valid win"))
        XCTAssertTrue(lowered.contains("40-60%"))
        XCTAssertFalse(lowered.contains("add weight"))
        XCTAssertFalse(lowered.contains("grind"))
    }

    func testMedicalRedFlagOverridesGeneratedAdvice() {
        let response = CoachSafetyFilter.filteredResponse(
            prompt: "I have chest pain after deadlifts. Should I finish?",
            context: "Readiness: 90/100 - peak recovery",
            response: "Finish the workout with lighter sets."
        )
        let lowered = response.lowercased()

        XCTAssertTrue(lowered.contains("stop the session"))
        XCTAssertTrue(lowered.contains("medical care"))
        XCTAssertFalse(lowered.contains("finish the workout"))
    }

    func testSafetyFilteredProviderBuffersUnsafeSymptomStream() async throws {
        let provider = SafetyFilteredCoachProvider(base: UnsafeStreamingProvider())
        var collected = ""
        for try await chunk in provider.streamCoachResponse(
            for: "I'm tight, sick, and run-down. Should I train?",
            context: "Readiness: 82/100 - strong"
        ) {
            collected += chunk
        }
        let lowered = collected.lowercased()

        XCTAssertTrue(lowered.contains("rest is a valid win"))
        XCTAssertTrue(lowered.contains("40-60%"))
        XCTAssertFalse(lowered.contains("push through"))
        XCTAssertFalse(lowered.contains("go heavy"))
    }

    func testSafetyFilteredProviderBuffersUnsafeContextSymptomStream() async throws {
        let provider = SafetyFilteredCoachProvider(base: UnsafeContextStreamingProvider())
        var collected = ""
        for try await chunk in provider.streamCoachResponse(
            for: "Should I push today?",
            context: """
            Readiness: 85/100 - strong recovery
            - Recent coaching notes: low-back tightness showed up after deadlifts.
            """
        ) {
            collected += chunk
        }
        let lowered = collected.lowercased()

        XCTAssertTrue(lowered.contains("rest is a valid win"))
        XCTAssertTrue(lowered.contains("40-60%"))
        XCTAssertFalse(lowered.contains("add weight"))
        XCTAssertFalse(lowered.contains("grind"))
    }

    func testSafetyFilteredProviderPassesNormalStreamThrough() async throws {
        let provider = SafetyFilteredCoachProvider(base: NormalStreamingProvider())
        var chunks: [String] = []
        for try await chunk in provider.streamCoachResponse(
            for: "Should I add five pounds next week?",
            context: "Readiness: 82/100 - strong"
        ) {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks, ["alpha", " beta"])
    }
}

private struct UnsafeStreamingProvider: AICoachProvider {
    func coachResponse(for prompt: String, context: String) async throws -> String {
        _ = prompt
        _ = context
        return "Push through and go heavy today."
    }

    func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        _ = prompt
        _ = context
        return AsyncThrowingStream { continuation in
            continuation.yield("Push through")
            continuation.yield(" and go heavy today.")
            continuation.finish()
        }
    }
}

private struct UnsafeContextStreamingProvider: AICoachProvider {
    func coachResponse(for prompt: String, context: String) async throws -> String {
        _ = prompt
        _ = context
        return "Add weight and grind through it."
    }

    func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        _ = prompt
        _ = context
        return AsyncThrowingStream { continuation in
            continuation.yield("Add weight")
            continuation.yield(" and grind through it.")
            continuation.finish()
        }
    }
}

private struct NormalStreamingProvider: AICoachProvider {
    func coachResponse(for prompt: String, context: String) async throws -> String {
        _ = prompt
        _ = context
        return "alpha beta"
    }

    func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        _ = prompt
        _ = context
        return AsyncThrowingStream { continuation in
            continuation.yield("alpha")
            continuation.yield(" beta")
            continuation.finish()
        }
    }
}
