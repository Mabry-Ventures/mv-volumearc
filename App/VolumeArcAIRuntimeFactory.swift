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
        let transport: RealtimeVoiceTransport
        if let relayConfiguration = VolumeArcAIConfiguration.relayConfiguration {
            transport = OpenAIRealtimeVoiceTransport(
                configuration: relayConfiguration,
                credentialsProvider: VolumeArcRelaySessionProvider(
                    baseURL: relayConfiguration.baseURL,
                    applicationID: relayConfiguration.applicationID
                )
            )
        } else {
            transport = UnavailableRealtimeVoiceTransport()
        }

        return LiveVoiceCoachOrchestrator(transport: transport)
    }
}

private actor UnavailableRealtimeVoiceTransport: RealtimeVoiceTransport {
    func connect(model: AIModelIdentifier, policy: VoiceSessionPolicy) async throws {
        _ = model
        _ = policy
        throw AIRuntimeIntegrationError.relayUnavailable(
            reason: "Live voice relay is not configured for this build."
        )
    }

    func send(context: String, userText: String) async throws -> String {
        _ = context
        _ = userText
        throw AIRuntimeIntegrationError.relayUnavailable(
            reason: "Live voice relay is not configured for this build."
        )
    }

    func interrupt() async {}

    func disconnect() async {}
}
