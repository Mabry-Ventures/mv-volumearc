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

        let relayProvider = makeRelayProvider(tier: tier, telemetrySink: telemetrySink)

        #if DEBUG
        if let chaosProvider = makeChaosCoachProvider(relayProvider: relayProvider, telemetrySink: telemetrySink) {
            return safetyFiltered(chaosProvider, telemetrySink: telemetrySink)
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
            return safetyFiltered(LocalHeuristicAICoachProvider(), telemetrySink: telemetrySink)
        }

        #if canImport(FoundationModels) && !os(watchOS)
        if #available(iOS 26.0, visionOS 26.0, *) {
            // VOL-61: Gate the FM provider on the `.foundationModelCoach` flag.
            // When off, drop the wrapper so the chain falls through to
            // relay → local without the FM entry. `flagGate == nil`
            // preserves legacy unconditional behavior.
            let fmEnabled = flagGate?.recordIfFirst(.foundationModelCoach) ?? true
            if fmEnabled {
                return safetyFiltered(FoundationModelCoachProvider(
                    fallback: relayProvider ?? LocalHeuristicAICoachProvider(),
                    telemetrySink: telemetrySink,
                    // VOL-286: relay-served kill switch for the on-device
                    // brain, cached in UserDefaults and checked per turn.
                    isRemotelyDisabled: { RemoteCoachKillSwitchStore.isFoundationModelCoachKilled }
                ), telemetrySink: telemetrySink)
            }
        } else {
            recordFoundationModelsUnavailable(
                telemetrySink: telemetrySink,
                reason: "os_unsupported",
                fallbackPath: relayProvider == nil ? "local" : "relay_or_local"
            )
        }
        #else
        recordFoundationModelsUnavailable(
            telemetrySink: telemetrySink,
            reason: "framework_unavailable",
            fallbackPath: relayProvider == nil ? "local" : "relay_or_local"
        )
        #endif

        return safetyFiltered(relayProvider ?? LocalHeuristicAICoachProvider(), telemetrySink: telemetrySink)
    }

    /// VOL-199: when the relay is configured, wrap it in a fallback provider
    /// so transient relay failures route through the local heuristic coach.
    private static func makeRelayProvider(
        tier: CoachTier,
        telemetrySink: (any TelemetrySink)?
    ) -> AICoachProvider? {
        VolumeArcAIConfiguration.relayConfiguration.map { configuration in
            let sessionProvider = VolumeArcAppAttestRelaySessionProvider(
                baseURL: configuration.baseURL,
                telemetrySink: telemetrySink
            )
            let direct = AIRelayCoachProvider(
                configuration: configuration,
                credentialsProvider: sessionProvider,
                tier: tier
            )
            let retrying = RelayUnauthorizedRetryCoachProvider(
                primary: direct,
                sessionRefresher: sessionProvider,
                telemetrySink: telemetrySink
            )
            return FallbackCoachProvider(
                primary: retrying,
                fallback: LocalHeuristicAICoachProvider(),
                telemetrySink: telemetrySink
            )
        }
    }

    #if DEBUG
    private static func makeChaosCoachProvider(
        relayProvider: AICoachProvider?,
        telemetrySink: (any TelemetrySink)?
    ) -> AICoachProvider? {
        if ChaosController.injectCoachSlowStream {
            return ChaosSlowStreamingCoachProvider()
        }
        if ChaosController.injectAIRelay401ThenSuccess {
            return retryingChaos401Provider(telemetrySink: telemetrySink)
        }
        if let aiRelayFailure = ChaosController.aiRelayFailure {
            return failingChaosRelayProvider(aiRelayFailure, telemetrySink: telemetrySink)
        }
        if ChaosController.injectFoundationModelsUnavailable {
            let hermetic = VolumeArcRuntimeFlags.isDeterministicMode || VolumeArcRuntimeFlags.isPerformanceTestMode
            return FMUnavailableChaosCoachProvider(
                fallback: hermetic ? LocalHeuristicAICoachProvider() : (relayProvider ?? LocalHeuristicAICoachProvider()),
                telemetrySink: telemetrySink,
                fallbackPath: hermetic || relayProvider == nil ? "local" : "relay_or_local"
            )
        }
        return nil
    }

    private static func retryingChaos401Provider(telemetrySink: (any TelemetrySink)?) -> AICoachProvider {
        let retryingPrimary = RelayUnauthorizedRetryCoachProvider(
            primary: ChaosAICoach401ThenSuccessProvider(),
            sessionRefresher: ChaosRelaySessionRefresher(),
            telemetrySink: telemetrySink
        )
        return FallbackCoachProvider(
            primary: retryingPrimary,
            fallback: LocalHeuristicAICoachProvider(),
            telemetrySink: telemetrySink
        )
    }

    private static func failingChaosRelayProvider(
        _ failure: ChaosAICoachFailure,
        telemetrySink: (any TelemetrySink)?
    ) -> AICoachProvider {
        let chaosPrimary = ChaosAICoachProvider(failure: failure)
        let primary: AICoachProvider
        switch failure {
        case .relayRequestFailed(statusCode: 401, message: _):
            primary = RelayUnauthorizedRetryCoachProvider(
                primary: chaosPrimary,
                sessionRefresher: ChaosRelaySessionRefresher(),
                telemetrySink: telemetrySink
            )
        case .relayRequestFailed, .relayUnavailable:
            primary = chaosPrimary
        }
        return FallbackCoachProvider(
            primary: primary,
            fallback: LocalHeuristicAICoachProvider(),
            telemetrySink: telemetrySink
        )
    }
    #endif

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
        if voiceEnabled, isPremium,
           VolumeArcRuntimeFlags.isDeterministicMode || VolumeArcRuntimeFlags.isPerformanceTestMode {
            transport = AIRelayVoiceTransport(
                provider: makeCoachProvider(
                    flagGate: flagGate,
                    subscriptionStore: subscriptionStore,
                    premiumGate: premiumGate
                )
            )
        } else if voiceEnabled, isPremium, VolumeArcAIConfiguration.relayConfiguration != nil {
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

    private static func recordFoundationModelsUnavailable(
        telemetrySink: (any TelemetrySink)?,
        reason: String,
        fallbackPath: String,
        errorType: String? = nil
    ) {
        var metadata = [
            "reason": reason,
            "fallback_path": fallbackPath,
        ]
        if let errorType {
            metadata["error_type"] = errorType
        }
        telemetrySink?.record(TelemetryEvent(
            category: "ai",
            name: "fm.unavailable",
            severity: .warning,
            message: "Foundation Models coach unavailable; falling back to relay or local provider.",
            metadata: metadata
        ))
    }

    private static func safetyFiltered(
        _ provider: AICoachProvider,
        telemetrySink: (any TelemetrySink)? = nil
    ) -> AICoachProvider {
        SafetyFilteredCoachProvider(base: provider, telemetrySink: telemetrySink)
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
