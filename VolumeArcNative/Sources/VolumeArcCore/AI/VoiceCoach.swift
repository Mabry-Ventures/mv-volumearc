import Foundation

/// Transport used by the voice coaching orchestrator. A "single-turn" transport
/// just takes a context + user utterance and returns a text response — it does
/// not maintain a persistent audio session.
///
/// `connect` / `interrupt` / `disconnect` are intentionally optional and
/// default to no-ops so transports that don't maintain a session (e.g., plain
/// HTTP relay calls) don't need to implement them.
public protocol RealtimeVoiceTransport: Sendable {
    func connect(model: AIModelIdentifier, policy: VoiceSessionPolicy) async throws
    func send(context: String, userText: String) async throws -> String
    func interrupt() async
    func disconnect() async
}

public extension RealtimeVoiceTransport {
    func connect(model: AIModelIdentifier, policy: VoiceSessionPolicy) async throws {}
    func interrupt() async {}
    func disconnect() async {}
}

/// Single-turn voice transport backed by the same text relay used by
/// `AIRelayCoachProvider`. Given a context block and user utterance, it
/// returns the coach's text response, which the caller can then hand to
/// `AVSpeechSynthesizer` for local TTS playback.
///
/// This is deliberately *not* a live duplex audio session — true WebRTC-style
/// streaming duplex audio against the OpenAI Realtime API is tracked as a
/// future feature. The current implementation covers the "ask the coach a
/// question by voice and get a spoken reply" use case without requiring a
/// persistent socket, which is sufficient for most in-gym interactions.
public struct AIRelayVoiceTransport: RealtimeVoiceTransport {
    private let provider: any AICoachProvider

    public init(provider: any AICoachProvider) {
        self.provider = provider
    }

    public func send(context: String, userText: String) async throws -> String {
        try await provider.coachResponse(for: userText, context: context)
    }
}

/// Deprecated name for `AIRelayVoiceTransport`. The struct used to be a
/// stub with empty methods; it is now functional and delegates to an
/// `AICoachProvider`. Kept as a typealias for source compatibility with the
/// Ruby-generated Xcode project's earlier references.
@available(*, deprecated, renamed: "AIRelayVoiceTransport")
public typealias AIRealtimeVoiceTransport = AIRelayVoiceTransport

/// Orchestrates a voice-coaching turn: runs the transport's `send` and returns
/// the text response. Callers are expected to feed that response to
/// `AVSpeechSynthesizer` (or equivalent TTS) for spoken playback.
public final class LiveVoiceCoachOrchestrator: Sendable {
    private let transport: any RealtimeVoiceTransport

    public init(transport: any RealtimeVoiceTransport) {
        self.transport = transport
    }

    /// Ask the coach a question by voice and receive its spoken-response text.
    /// Idempotent — safe to call on every turn.
    public func speak(prompt: String, context: String) async throws -> String {
        try await transport.send(context: context, userText: prompt)
    }

    /// Begin a voice session. For single-turn transports this is a no-op.
    public func start(model: AIModelIdentifier = AIModelIdentifier("gpt-4o-realtime"),
                      policy: VoiceSessionPolicy = VoiceSessionPolicy("conversational")) async throws {
        try await transport.connect(model: model, policy: policy)
    }

    /// Interrupt the current voice turn. For single-turn transports this is a no-op.
    public func interrupt() async {
        await transport.interrupt()
    }

    /// End the voice session. For single-turn transports this is a no-op.
    public func end() async {
        await transport.disconnect()
    }
}
