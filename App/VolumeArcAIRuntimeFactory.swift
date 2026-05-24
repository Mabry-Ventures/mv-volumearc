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
        premiumGate: PremiumGateTelemetry? = nil,
        telemetrySink: (any TelemetrySink)? = nil
    ) -> AICoachProvider {
        let isPremium = subscriptionStore?.isPremium ?? false
        premiumGate?.recordIfFirst("coach_tier", isPremium: isPremium)
        let tier: CoachTier = isPremium ? .pro : .flashLite

        // VOL-199: when the relay is configured, wrap the
        // `AIRelayCoachProvider` in a `FallbackCoachProvider` that
        // routes through to a `LocalHeuristicAICoachProvider` on
        // transient relay failures (5xx, 401, network drop). Before
        // this change, a relay outage produced a hard user-visible
        // error; the docs and journey catalog promised local fallback
        // but the implementation didn't run it. `telemetrySink` is
        // threaded through so each fallback emits the
        // `coach.fallback_used` event for operator visibility.
        let relayProvider: AICoachProvider? = VolumeArcAIConfiguration.relayConfiguration.map { configuration in
            let hmacProvider = VolumeArcRelaySessionProvider(
                baseURL: configuration.baseURL,
                applicationID: configuration.applicationID
            )
            let sessionProvider: any AIRelayCredentialsProviding
            if VolumeArcRelayAuthMode.current() == .hmac {
                sessionProvider = hmacProvider
            } else {
                sessionProvider = VolumeArcAppAttestRelaySessionProvider(
                    baseURL: configuration.baseURL,
                    fallbackProvider: hmacProvider,
                    telemetrySink: telemetrySink
                )
            }
            let direct = AIRelayCoachProvider(
                configuration: configuration,
                credentialsProvider: sessionProvider,
                tier: tier
            )
            return FallbackCoachProvider(
                primary: direct,
                fallback: LocalHeuristicAICoachProvider(),
                telemetrySink: telemetrySink
            )
        }

        #if DEBUG
        if ChaosController.injectAIRelay5xx {
            return FallbackCoachProvider(
                primary: ChaosAICoachProvider(error: .relayRequestFailed(
                    statusCode: 503,
                    message: "Chaos AIRelay 5xx"
                )),
                fallback: LocalHeuristicAICoachProvider(),
                telemetrySink: telemetrySink
            )
        }
        #endif

        // VOL-162 / VOL-227: deterministic UI and perf launches need a
        // hermetic provider. `LocalHeuristicAICoachProvider` streams one
        // word every 30ms with no network or model dependency. Without
        // this short-circuit the factory can install
        // `FoundationModelCoachProvider`, which on the simulator may not
        // respond at all (the FoundationModels framework has limited
        // simulator support on Xcode 26), so the streamed
        // `coach.firstResponse` accessibility identifier never appears.
        //
        // `-UITestMode 1` and `-PerfTestMode 1` are mirrored onto
        // `VolumeArcRuntimeFlags` in `VolumeArcApp.init`, keeping call
        // sites free of test-aware plumbing. The chaos relay branch above
        // remains first so the fallback journey still exercises the
        // production fallback wrapper.
        if VolumeArcRuntimeFlags.isDeterministicMode || VolumeArcRuntimeFlags.isPerformanceTestMode {
            return LocalHeuristicAICoachProvider()
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
            transport = AIRelayVoiceTransport(
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
