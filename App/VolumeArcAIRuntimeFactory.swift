import Foundation
import VolumeArcCore

enum VolumeArcAIRuntimeFactory {
    static func makeCoachProvider() -> AICoachProvider {
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
            return FoundationModelCoachProvider(
                fallback: relayProvider ?? LocalHeuristicAICoachProvider()
            )
        }
        #endif

        return relayProvider ?? LocalHeuristicAICoachProvider()
    }

    static func makeVoiceCoach() -> LiveVoiceCoachOrchestrator {
        // Voice coaching is a single-turn text relay wrapped in an
        // orchestrator. Live duplex audio against the OpenAI Realtime API is a
        // planned future feature — the current path covers the "ask a
        // question by voice, hear a text-to-speech reply" loop, which the UI
        // can hand off to `AVSpeechSynthesizer` for playback.
        let transport: RealtimeVoiceTransport
        if VolumeArcAIConfiguration.relayConfiguration != nil {
            transport = OpenAIRelayVoiceTransport(provider: makeCoachProvider())
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
            reason: "Voice coaching relay is not configured for this build."
        )
    }
}
