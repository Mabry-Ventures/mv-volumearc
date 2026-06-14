import XCTest
import VolumeArcCore

// VOL-283: provider-agnostic coach safety boundary — composition proofs.
//
// `CoachSafetyFilterTests` proves the wrapper itself short-circuits
// medical red flags without invoking its base provider. These tests
// lock the COMPOSITION so the guarantee survives provider swaps:
//
//  * every chain `VolumeArcAIRuntimeFactory.makeCoachProvider` returns
//    has `SafetyFilteredCoachProvider` as its outermost layer, so no
//    brain — Apple Foundation Models, the cloud relay tiers, or the
//    local heuristic — is reachable by a red-flag prompt;
//  * the voice path is built from the same factory and therefore sits
//    behind the same gate;
//  * strict-mode privacy redaction cannot defeat red-flag detection
//    (it strips PII, never medical language).
@MainActor
final class CoachSafetyChainTests: XCTestCase {
    private var previousDeterministicMode = false
    private var previousPerformanceMode = false

    override func setUp() async throws {
        try await super.setUp()
        previousDeterministicMode = VolumeArcRuntimeFlags.isDeterministicMode
        previousPerformanceMode = VolumeArcRuntimeFlags.isPerformanceTestMode
    }

    override func tearDown() async throws {
        VolumeArcRuntimeFlags.isDeterministicMode = previousDeterministicMode
        VolumeArcRuntimeFlags.isPerformanceTestMode = previousPerformanceMode
        try await super.tearDown()
    }

    // MARK: - Factory composition

    func testDeterministicChainIsSafetyWrapped() {
        VolumeArcRuntimeFlags.isDeterministicMode = true

        let provider = VolumeArcAIRuntimeFactory.makeCoachProvider()

        XCTAssertTrue(
            provider is SafetyFilteredCoachProvider,
            "Deterministic/perf launches must keep the safety wrapper outermost"
        )
    }

    func testDefaultChainIsSafetyWrapped() {
        VolumeArcRuntimeFlags.isDeterministicMode = false
        VolumeArcRuntimeFlags.isPerformanceTestMode = false

        let provider = VolumeArcAIRuntimeFactory.makeCoachProvider()

        XCTAssertTrue(
            provider is SafetyFilteredCoachProvider,
            "The production chain (FM/relay/local, whichever resolves) must keep the safety wrapper outermost"
        )
    }

    func testRelayLocalChainWithFoundationModelFlagOffIsSafetyWrapped() {
        VolumeArcRuntimeFlags.isDeterministicMode = false
        VolumeArcRuntimeFlags.isPerformanceTestMode = false
        let flags = LocalFeatureFlagProvider()
        flags.setOverride(.foundationModelCoach, enabled: false)
        defer { flags.clearOverride(.foundationModelCoach) }

        let provider = VolumeArcAIRuntimeFactory.makeCoachProvider(
            flagGate: FlagGateTelemetry(flags: flags, telemetry: InMemoryTelemetrySink())
        )

        XCTAssertTrue(
            provider is SafetyFilteredCoachProvider,
            "The relay-to-local chain with FM disabled must keep the safety wrapper outermost"
        )
    }

    // MARK: - Voice path

    func testVoicePathShortCircuitsMedicalRedFlags() async throws {
        VolumeArcRuntimeFlags.isDeterministicMode = true

        let coach = VolumeArcAIRuntimeFactory.makeVoiceCoach(
            subscriptionStore: StubPremiumEntitlements()
        )
        let response = try await coach.speak(
            prompt: "I felt chest pain on the last set. Should I push through?",
            context: "Readiness: 92/100 - peak recovery"
        )

        let lowered = response.lowercased()
        XCTAssertTrue(lowered.contains("stop the session"))
        XCTAssertTrue(lowered.contains("medical care"))
    }

    // MARK: - VOL-286 — safety telemetry + kill switch

    func testSafetyGateEmitsShortCircuitTelemetry() async throws {
        let sink = InMemoryTelemetrySink()
        let provider = SafetyFilteredCoachProvider(base: UnsafeMarkerProvider(), telemetrySink: sink)

        _ = try await provider.coachResponse(
            for: "I have chest pain during my top set. Should I push through?",
            context: "Readiness: 90/100 - peak recovery"
        )

        XCTAssertTrue(sink.currentEvents.contains {
            $0.category == "coach.safety" && $0.name == "gate.short_circuit"
        })
    }

    #if canImport(FoundationModels) && !os(watchOS)
    func testFoundationModelRemoteKillSwitchRoutesToFallback() async throws {
        guard #available(iOS 26.0, visionOS 26.0, *) else {
            throw XCTSkip("FoundationModels requires iOS 26")
        }
        let sink = InMemoryTelemetrySink()
        let provider = FoundationModelCoachProvider(
            fallback: FallbackMarkerProvider(),
            telemetrySink: sink,
            isRemotelyDisabled: { true }
        )

        let response = try await provider.coachResponse(
            for: "How should I approach today's session?",
            context: "Readiness: 82/100 - strong"
        )

        XCTAssertEqual(response, FallbackMarkerProvider.marker)
        XCTAssertTrue(sink.currentEvents.contains {
            $0.category == "coach.safety" && $0.name == "killswitch.active"
        })
    }
    #endif

    func testRemoteKillSwitchStoreRoundtrip() {
        RemoteCoachKillSwitchStore.reset()
        XCTAssertFalse(RemoteCoachKillSwitchStore.isFoundationModelCoachKilled)

        RemoteCoachKillSwitchStore.update(foundationModelCoachKilled: true)
        XCTAssertTrue(RemoteCoachKillSwitchStore.isFoundationModelCoachKilled)

        RemoteCoachKillSwitchStore.reset()
        XCTAssertFalse(RemoteCoachKillSwitchStore.isFoundationModelCoachKilled)
    }

    // MARK: - Safety acknowledgment re-prompt

    /// PR #363 (Codex P1): users who completed onboarding before the
    /// safety disclaimer shipped have no recorded acceptance, so the
    /// root-level `SafetyAcknowledgmentGateView` must re-prompt them. This
    /// pins the store invariant the gate keys on — an unrecorded (or
    /// stale-version) acceptance reads as not accepted, and recording the
    /// current version clears it without touching the athlete profile.
    func testSafetyDisclaimerRePromptsUntilAccepted() {
        // Snapshot + restore: the store writes through UserDefaults.standard,
        // so leaving it mutated would make a later test that seeds an
        // accepted disclaimer start from isAccepted == false, making the
        // suite order-dependent (PR #363 review, CodeRabbit).
        let wasAccepted = SafetyDisclaimerAcknowledgmentStore.isAccepted
        defer {
            if wasAccepted {
                SafetyDisclaimerAcknowledgmentStore.recordAccepted()
            } else {
                SafetyDisclaimerAcknowledgmentStore.reset()
            }
        }

        SafetyDisclaimerAcknowledgmentStore.reset()
        XCTAssertFalse(
            SafetyDisclaimerAcknowledgmentStore.isAccepted,
            "An existing user with no recorded acceptance must be re-prompted."
        )

        SafetyDisclaimerAcknowledgmentStore.recordAccepted()
        XCTAssertTrue(SafetyDisclaimerAcknowledgmentStore.isAccepted)
    }

    // MARK: - Privacy redaction interaction

    func testStrictRedactionPreservesMedicalRedFlagDetection() {
        let prompt = "My name is Sam Smith and my email is sam@example.com. " +
            "I have chest pain and feel dizzy. Should I keep lifting?"

        let redacted = PromptPrivacyRedactor.redactQuestion(prompt, privacyMode: .strict)

        XCTAssertTrue(redacted.contains(PromptPrivacyRedactor.redactionMarker))
        XCTAssertFalse(redacted.contains("sam@example.com"))
        XCTAssertNotNil(
            CoachSafetyFilter.medicalRedFlagResponse(prompt: redacted, context: ""),
            "Privacy redaction must strip PII without stripping the medical language the safety gate matches on"
        )
    }
}

@MainActor
private final class StubPremiumEntitlements: PremiumEntitlementProviding {
    let isPremium = true
}

/// Returns recognizably unsafe text so a leaked call is loud in assertions.
private struct UnsafeMarkerProvider: AICoachProvider {
    func coachResponse(for prompt: String, context: String) async throws -> String {
        "Push through and go heavy."
    }
}

private struct FallbackMarkerProvider: AICoachProvider {
    static let marker = "fallback-provider-response"

    func coachResponse(for prompt: String, context: String) async throws -> String {
        Self.marker
    }
}
