import Foundation
import VolumeArcCore

enum VolumeArcAIRuntimeFactory {
    /// Build the shared `AICoachProvider` used by the dashboard's streaming
    /// coach. The `.foundationModelCoach` feature flag controls whether the
    /// on-device Foundation Models provider is inserted at the front of the
    /// chain. When off, the chain collapses to `relay → local`, mirroring
    /// the pre-FM architecture.
    ///
    /// VOL-61: `flagGate` is optional for backwards compatibility with
    /// existing test setups; when nil, the factory falls back to its prior
    /// unconditional behavior (FM provider enabled when available).
    ///
    /// VOL-91: `subscriptionStore` decides which relay tier to install.
    /// Premium entitlement → Gemini Pro (`X-Coach-Tier: pro`); free →
    /// Gemini Flash Lite (`X-Coach-Tier: flash-lite`). Nil defaults to
    /// flash-lite for legacy test call sites that predate the gating.
    /// `premiumGate` records a one-shot `.info` event the first time the
    /// gate resolves so dashboards can observe the tier distribution.
    @MainActor
    static func makeCoachProvider(
        flagGate: FlagGateTelemetry? = nil,
        subscriptionStore: (any PremiumEntitlementProviding)? = nil,
        premiumGate: PremiumGateTelemetry? = nil
    ) -> AICoachProvider {
        let isPremium = subscriptionStore?.isPremium ?? false
        premiumGate?.recordIfFirst("coach_tier", isPremium: isPremium)
        let tier: CoachTier = isPremium ? .pro : .flashLite

        let relayProvider = VolumeArcAIConfiguration.relayConfiguration.map { configuration in
            let sessionProvider = VolumeArcRelaySessionProvider(
                baseURL: configuration.baseURL,
                applicationID: configuration.applicationID
            )
            return OpenAIRelayCoachProvider(
                configuration: configuration,
                credentialsProvider: sessionProvider,
                tier: tier
            )
        }

        #if canImport(FoundationModels) && !os(watchOS)
        if #available(iOS 26.0, visionOS 26.0, *) {
            // VOL-61: Gate the FM provider on the `.foundationModelCoach` flag.
            // When off, drop the wrapper so the chain falls through to
            // relay → local without the FM entry. `flagGate == nil`
            // preserves legacy unconditional behavior.
            let fmEnabled = flagGate?.recordIfFirst(.foundationModelCoach) ?? true
            if fmEnabled {
                return FoundationModelCoachProvider(
                    fallback: relayProvider ?? LocalHeuristicAICoachProvider()
                )
            }
        }
        #endif

        return relayProvider ?? LocalHeuristicAICoachProvider()
    }

    /// Build the voice-coaching orchestrator.
    ///
    /// VOL-61: the `.voiceCoaching` feature flag short-circuits the
    /// relay-backed transport and installs `UnavailableVoiceTransport`
    /// so every call throws `AIRuntimeIntegrationError.relayUnavailable`.
    ///
    /// VOL-91: live voice is a premium feature. The relay transport is
    /// installed ONLY when `isPremium == true` AND `.voiceCoaching` is
    /// on. Free users — and premium users with the flag toggled off —
    /// get `UnavailableVoiceTransport`. The premium check gets a one-shot
    /// `.info` event on `premium.entitlement.gated` / name `live_voice`.
    ///
    /// The coach object remains alive (callers can still construct it) —
    /// flipping the flag or entitlement back on at runtime is a no-op
    /// until the next `makeVoiceCoach()` invocation, which is acceptable
    /// since the factory runs once at launch.
    @MainActor
    static func makeVoiceCoach(
        flagGate: FlagGateTelemetry? = nil,
        subscriptionStore: (any PremiumEntitlementProviding)? = nil,
        premiumGate: PremiumGateTelemetry? = nil
    ) -> LiveVoiceCoachOrchestrator {
        // Voice coaching is a single-turn text relay wrapped in an
        // orchestrator. Live duplex audio against the OpenAI Realtime API is a
        // planned future feature — the current path covers the "ask a
        // question by voice, hear a text-to-speech reply" loop, which the UI
        // can hand off to `AVSpeechSynthesizer` for playback.
        let voiceEnabled = flagGate?.recordIfFirst(.voiceCoaching) ?? true
        let isPremium = subscriptionStore?.isPremium ?? false
        premiumGate?.recordIfFirst("live_voice", isPremium: isPremium)

        let transport: RealtimeVoiceTransport
        if voiceEnabled, isPremium, VolumeArcAIConfiguration.relayConfiguration != nil {
            transport = OpenAIRelayVoiceTransport(
                provider: makeCoachProvider(
                    flagGate: flagGate,
                    subscriptionStore: subscriptionStore,
                    premiumGate: premiumGate
                )
            )
        } else {
            transport = UnavailableVoiceTransport()
        }

        return LiveVoiceCoachOrchestrator(transport: transport)
    }
}

private actor UnavailableVoiceTransport: RealtimeVoiceTransport {
    func send(context: String, userText: String) async throws -> String {
        _ = context
        _ = userText
        throw AIRuntimeIntegrationError.relayUnavailable(
            reason: "Voice coaching relay is not configured, disabled by feature flag, or unavailable without a premium entitlement."
        )
    }
}
