import Foundation

public protocol RealtimeVoiceTransport: Sendable {
    func connect(model: AIModelIdentifier, policy: VoiceSessionPolicy) async throws
    func send(context: String, userText: String) async throws -> String
    func interrupt() async
    func disconnect() async
}

public struct OpenAIRealtimeVoiceTransport: RealtimeVoiceTransport {
    private let configuration: OpenAIRelayConfiguration
    private let credentialsProvider: OpenAIRelayCredentialsProviding

    public init(configuration: OpenAIRelayConfiguration, credentialsProvider: OpenAIRelayCredentialsProviding) {
        self.configuration = configuration
        self.credentialsProvider = credentialsProvider
    }

    public func connect(model: AIModelIdentifier, policy: VoiceSessionPolicy) async throws {}
    public func send(context: String, userText: String) async throws -> String { "" }
    public func interrupt() async {}
    public func disconnect() async {}
}

public final class LiveVoiceCoachOrchestrator: Sendable {
    private let transport: RealtimeVoiceTransport

    public init(transport: RealtimeVoiceTransport) {
        self.transport = transport
    }
}
