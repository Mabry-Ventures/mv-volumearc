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

    func testPainInChestPromptMedicalRedFlagOverridesGeneratedAdvice() {
        let response = CoachSafetyFilter.filteredResponse(
            prompt: "I have pain in my chest after deadlifts. Should I finish?",
            context: "Readiness: 90/100 - peak recovery",
            response: "Finish the workout with lighter sets."
        )
        let lowered = response.lowercased()

        XCTAssertTrue(lowered.contains("stop the session"))
        XCTAssertTrue(lowered.contains("medical care"))
        XCTAssertFalse(lowered.contains("finish the workout"))
    }

    func testMedicalRedFlagFromCurrentContextOverridesGeneratedAdvice() {
        let response = CoachSafetyFilter.filteredResponse(
            prompt: "Should I push today?",
            context: """
            Readiness: 92/100 - peak recovery
            - Recent coaching notes: chest pain showed up during the top set today.
            """,
            response: "Readiness is high, so add weight and finish the workout."
        )
        let lowered = response.lowercased()

        XCTAssertTrue(lowered.contains("stop the session"))
        XCTAssertTrue(lowered.contains("medical care"))
        XCTAssertFalse(lowered.contains("add weight"))
        XCTAssertFalse(lowered.contains("finish the workout"))
    }

    func testNegatedContextMedicalRedFlagDoesNotEscalate() {
        let response = CoachSafetyFilter.medicalRedFlagResponse(
            prompt: "Should I add five pounds next week?",
            context: """
            Readiness: 86/100 - strong recovery
            - Check-in: no chest pain, no dizziness, and no shortness of breath.
            """
        )

        XCTAssertNil(response)
    }

    func testExpandedNegatedContextMedicalRedFlagsDoNotEscalate() {
        let response = CoachSafetyFilter.medicalRedFlagResponse(
            prompt: "Should I train today?",
            context: """
            Readiness: 86/100 - strong recovery
            - Check-in: not pregnant now; denies syncope; no fainting; not having chest pain or palpitations; not restricting; not purging.
            """
        )

        XCTAssertNil(response)
    }

    func testMixedNegatedAndCurrentContextMedicalRedFlagsStillEscalate() {
        let response = CoachSafetyFilter.medicalRedFlagResponse(
            prompt: "Should I train today?",
            context: """
            Readiness: 86/100 - strong recovery
            - Check-in: no chest pain, but passed out after squats today.
            """
        )

        XCTAssertNotNil(response)
        XCTAssertTrue(response?.lowercased().contains("medical care") == true)
    }

    func testCommaMixedNegatedAndCurrentContextMedicalRedFlagsStillEscalate() {
        let response = CoachSafetyFilter.medicalRedFlagResponse(
            prompt: "Should I train today?",
            context: """
            Readiness: 86/100 - strong recovery
            - Check-in: no chest pain, passed out after squats today.
            """
        )

        XCTAssertNotNil(response)
        XCTAssertTrue(response?.lowercased().contains("medical care") == true)
    }

    func testAndMixedNegatedAndCurrentContextMedicalRedFlagsStillEscalate() {
        let response = CoachSafetyFilter.medicalRedFlagResponse(
            prompt: "Should I train today?",
            context: """
            Readiness: 86/100 - strong recovery
            - Check-in: no chest pain and passed out after squats today.
            """
        )

        XCTAssertNotNil(response)
        XCTAssertTrue(response?.lowercased().contains("medical care") == true)
    }

    func testPainInChestContextMedicalRedFlagStillEscalates() {
        let response = CoachSafetyFilter.medicalRedFlagResponse(
            prompt: "Should I keep training?",
            context: """
            Readiness: 88/100 - strong recovery
            - Recent coaching notes: athlete reported pain in the chest during squats today.
            """
        )

        XCTAssertNotNil(response)
        XCTAssertTrue(response?.lowercased().contains("medical care") == true)
    }

    func testStaleContextMedicalRedFlagDoesNotEscalate() {
        let response = CoachSafetyFilter.medicalRedFlagResponse(
            prompt: "Should I train today?",
            context: """
            Readiness: 86/100 - strong recovery
            - Historical note: chest pain during a workout last year, cleared by clinician.
            """
        )

        XCTAssertNil(response)
    }

    func testMedicalRedFlagsShortCircuitNonStreamingProvider() async throws {
        let provider = SafetyFilteredCoachProvider(base: FailingIfCalledProvider())

        let response = try await provider.coachResponse(
            for: "I feel lightheaded and blacked out after squats. Can I keep going?",
            context: "Readiness: 90/100 - peak recovery"
        )
        let lowered = response.lowercased()

        XCTAssertTrue(lowered.contains("stop the session"))
        XCTAssertTrue(lowered.contains("medical care"))
    }

    func testContextMedicalRedFlagsShortCircuitNonStreamingProvider() async throws {
        let provider = SafetyFilteredCoachProvider(base: FailingIfCalledProvider())

        let response = try await provider.coachResponse(
            for: "Readiness looks high. Should I train?",
            context: """
            Readiness: 94/100 - peak recovery
            - Recent coaching notes: athlete got dizzy under load today.
            """
        )
        let lowered = response.lowercased()

        XCTAssertTrue(lowered.contains("stop the session"))
        XCTAssertTrue(lowered.contains("medical care"))
    }

    func testMedicalRedFlagsShortCircuitStreamingProvider() async throws {
        let provider = SafetyFilteredCoachProvider(base: FailingIfCalledProvider())

        var collected = ""
        for try await chunk in provider.streamCoachResponse(
            for: "I can't breathe after a set. What should I do?",
            context: "Readiness: 90/100 - peak recovery"
        ) {
            collected += chunk
        }
        let lowered = collected.lowercased()

        XCTAssertTrue(lowered.contains("stop the session"))
        XCTAssertTrue(lowered.contains("medical care"))
    }

    func testContextMedicalRedFlagsShortCircuitStreamingProvider() async throws {
        let provider = SafetyFilteredCoachProvider(base: FailingIfCalledProvider())

        var collected = ""
        for try await chunk in provider.streamCoachResponse(
            for: "Should I finish the session?",
            context: """
            Readiness: 88/100 - strong recovery
            - Recent coaching notes: severe shortness of breath after the last set.
            """
        ) {
            collected += chunk
        }
        let lowered = collected.lowercased()

        XCTAssertTrue(lowered.contains("stop the session"))
        XCTAssertTrue(lowered.contains("medical care"))
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

private enum UnexpectedProviderCall: Error {
    case called
}

private struct FailingIfCalledProvider: AICoachProvider {
    func coachResponse(for prompt: String, context: String) async throws -> String {
        _ = prompt
        _ = context
        throw UnexpectedProviderCall.called
    }

    func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        _ = prompt
        _ = context
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: UnexpectedProviderCall.called)
        }
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
