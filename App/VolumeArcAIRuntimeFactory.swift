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
    static func makeCoachProvider(flagGate: FlagGateTelemetry? = nil) -> AICoachProvider {
        let relayProvider = VolumeArcAIConfiguration.relayConfiguration.map { configuration in
            let sessionProvider = VolumeArcRelaySessionProvider(
                baseURL: configuration.baseURL,
                applicationID: configuration.applicationID
            )
            return OpenAIRelayCoachProvider(
                configuration: configuration,
                credentialsProvider: sessionProvider
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

    /// Build the voice-coaching orchestrator. The `.voiceCoaching` flag
    /// short-circuits the relay-backed transport and installs
    /// `UnavailableVoiceTransport` so every call throws
    /// `AIRuntimeIntegrationError.relayUnavailable`. The coach object
    /// remains alive (callers can still construct it) — flipping the flag
    /// back on at runtime is a no-op until the next `makeVoiceCoach()`
    /// invocation, which is acceptable since the factory runs once at
    /// launch.
    static func makeVoiceCoach(flagGate: FlagGateTelemetry? = nil) -> LiveVoiceCoachOrchestrator {
        // Voice coaching is a single-turn text relay wrapped in an
        // orchestrator. Live duplex audio against the OpenAI Realtime API is a
        // planned future feature — the current path covers the "ask a
        // question by voice, hear a text-to-speech reply" loop, which the UI
        // can hand off to `AVSpeechSynthesizer` for playback.
        let voiceEnabled = flagGate?.recordIfFirst(.voiceCoaching) ?? true

        let transport: RealtimeVoiceTransport
        if voiceEnabled, VolumeArcAIConfiguration.relayConfiguration != nil {
            transport = OpenAIRelayVoiceTransport(provider: makeCoachProvider(flagGate: flagGate))
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
            reason: "Voice coaching relay is not configured or disabled by feature flag."
        )
    }
}
