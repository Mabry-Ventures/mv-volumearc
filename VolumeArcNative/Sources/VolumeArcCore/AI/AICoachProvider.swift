import Foundation

public struct AIModelIdentifier: Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct VoiceSessionPolicy: Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public enum AIRuntimeIntegrationError: Error, LocalizedError, Sendable {
    case relayUnavailable(reason: String)
    case invalidHTTPResponse
    case relayRequestFailed(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case let .relayUnavailable(reason): return reason
        case .invalidHTTPResponse: return "Invalid HTTP response from relay."
        case let .relayRequestFailed(code, message): return "Relay request failed (\(code)): \(message)"
        }
    }
}

public protocol AICoachProvider: Sendable {
    func coachResponse(for prompt: String, context: String) async throws -> String

    /// Stream a coach response token-by-token.
    /// Default implementation returns the whole response as a single chunk.
    func streamCoachResponse(for prompt: String, context: String) -> AsyncThrowingStream<String, Error>
}

public extension AICoachProvider {
    /// Default streaming implementation: call the non-streaming response and yield it as chunks.
    /// Providers that support native streaming (like a real OpenAI relay) should override this.
    func streamCoachResponse(for prompt: String, context: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let full = try await coachResponse(for: prompt, context: context)
                    // Chunk the response by words for a typing feel.
                    let words = full.split(separator: " ", omittingEmptySubsequences: false)
                    for (index, word) in words.enumerated() {
                        continuation.yield(index == 0 ? String(word) : " \(word)")
                        try? await Task.sleep(nanoseconds: 30_000_000) // 30ms per word
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

public struct OpenAIRelayConfiguration: Sendable {
    public let baseURL: URL
    public let bearerToken: String
    public var applicationID: String { baseURL.host ?? "com.mabryventures.VolumeArc" }

    public init(baseURL: URL, bearerToken: String) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
    }
}

public protocol OpenAIRelayCredentialsProviding: Sendable {
    func authorizationHeaderValue() async throws -> String
}

public enum CoachTier: String, Sendable {
    case flashLite = "flash-lite"
    case pro = "pro"
}

/// Relay-backed coach provider that talks to `volumearc-ai-relay` via SSE.
///
/// VOL-66: real progressive streaming. `streamCoachResponse(for:context:)`
/// now consumes `text/event-stream` from the Worker and yields token chunks
/// as Gemini emits them. The non-streaming `coachResponse` joins the stream
/// to a single string for callers that don't need progressive UI.
///
/// Despite the `OpenAI` in the name (kept for stability against in-flight
/// branches), the Worker now proxies to Gemini 3.1 Flash Lite / Pro. The
/// type name is intentionally model-agnostic and will be renamed to
/// `CloudRelayCoachProvider` in a separate churn-free cleanup pass.
public struct OpenAIRelayCoachProvider: AICoachProvider {
    private let configuration: OpenAIRelayConfiguration
    private let credentialsProvider: OpenAIRelayCredentialsProviding
    private let coachingStyle: CoachingStyle
    private let tier: CoachTier
    private let session: URLSession

    public init(
        configuration: OpenAIRelayConfiguration,
        credentialsProvider: OpenAIRelayCredentialsProviding,
        coachingStyle: CoachingStyle = .motivational,
        tier: CoachTier = .flashLite,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.credentialsProvider = credentialsProvider
        self.coachingStyle = coachingStyle
        self.tier = tier
        self.session = session
    }

    public func coachResponse(for prompt: String, context: String) async throws -> String {
        var full = ""
        for try await chunk in streamCoachResponse(for: prompt, context: context) {
            full += chunk
        }
        return full
    }

    public func streamCoachResponse(for prompt: String, context: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let auth = try await credentialsProvider.authorizationHeaderValue()
                    var request = URLRequest(url: configuration.baseURL.appending(path: "v1/coach"))
                    request.httpMethod = "POST"
                    request.setValue(auth, forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(tier.rawValue, forHTTPHeaderField: "X-Coach-Tier")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 60

                    // VOL-64: render the prompt on-device and send it
                    // pre-rendered so the template marker + system prompt
                    // are the single source of truth. Worker uses these
                    // verbatim and layers Gemini safety settings on top.
                    let intent = CoachPromptTemplate.inferIntent(from: prompt)
                    let renderedPrompt = CoachPromptTemplate.render(
                        intent: intent,
                        contextBlock: context,
                        question: prompt,
                        style: coachingStyle
                    )
                    let systemPrompt = CoachPromptTemplate.systemPrompt(style: coachingStyle)
                    let body: [String: String] = [
                        "intent": intent.rawValue,
                        "question": prompt,
                        "contextBlock": context,
                        "style": coachingStyle.rawValue,
                        "prompt": renderedPrompt,
                        "system": systemPrompt
                    ]
                    request.httpBody = try JSONEncoder().encode(body)

                    let (stream, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIRuntimeIntegrationError.invalidHTTPResponse)
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        continuation.finish(
                            throwing: AIRuntimeIntegrationError.relayRequestFailed(
                                statusCode: http.statusCode,
                                message: "Relay returned HTTP \(http.statusCode)"
                            )
                        )
                        return
                    }

                    var buffer = ""
                    for try await line in stream.lines {
                        if Task.isCancelled { break }
                        if line.isEmpty {
                            // Event terminator — process accumulated data line if any.
                            if !buffer.isEmpty {
                                let trimmed = buffer
                                buffer = ""
                                if let text = Self.extractText(from: trimmed) {
                                    continuation.yield(text)
                                }
                            }
                            continue
                        }
                        if line.hasPrefix("data:") {
                            buffer = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("event: done") {
                            break
                        } else if line.hasPrefix("event: error") {
                            continuation.finish(
                                throwing: AIRuntimeIntegrationError.relayRequestFailed(
                                    statusCode: http.statusCode,
                                    message: "Relay emitted error event"
                                )
                            )
                            return
                        }
                    }
                    // Flush any trailing data line without a blank terminator.
                    if !buffer.isEmpty, let text = Self.extractText(from: buffer) {
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func extractText(from dataLine: String) -> String? {
        guard let data = dataLine.data(using: .utf8) else { return nil }
        struct Chunk: Decodable { let text: String? }
        return (try? JSONDecoder().decode(Chunk.self, from: data))?.text
    }
}

/// On-device heuristic coach that pattern-matches the user's prompt against
/// common questions and pulls from the context block for grounding.
///
/// This is the offline fallback — rule-based, not generative. A user without
/// network connectivity still gets a useful, contextual response instead of
/// canned filler.
///
/// VOL-64: still routes every input through `CoachPromptTemplate.render(...)`
/// before dispatching, even though the response itself is rule-based. The
/// rendered prompt is what the heuristic dispatch and the readiness extractor
/// read, so the same intent classification and same context shape feed both
/// the offline path and the cloud relay path. A regression that bypasses the
/// template here drops the template marker and trips the integration test.
public struct LocalHeuristicAICoachProvider: AICoachProvider {
    private let coachingStyle: CoachingStyle

    public init(coachingStyle: CoachingStyle = .motivational) {
        self.coachingStyle = coachingStyle
    }

    public func coachResponse(for prompt: String, context: String) async throws -> String {
        // Route through the template so the same intent classification and
        // context shape used by the cloud path also drive the offline path.
        let intent = CoachPromptTemplate.inferIntent(from: prompt)
        let rendered = CoachPromptTemplate.render(
            intent: intent,
            contextBlock: context,
            question: prompt,
            style: coachingStyle
        )

        // The rendered prompt embeds the original context block verbatim, so
        // `extractReadinessScore` keeps working against the rendered string.
        switch intent {
        case .recovery:
            return readinessResponse(from: rendered)
        case .progression:
            return progressionResponse(from: rendered)
        case .form:
            return cueResponse(from: rendered)
        case .deload:
            return deloadResponse(from: rendered)
        case .substitution, .free:
            return defaultResponse(from: rendered)
        }
    }

    private func readinessResponse(from context: String) -> String {
        if let score = extractReadinessScore(from: context) {
            switch score {
            case 80...: return "Readiness is \(score) — you're ready to push. Hit your targets and don't second-guess."
            case 60..<80: return "Readiness is \(score). Moderate recovery. Stick to the plan, skip the heroics."
            case 40..<60: return "Readiness is \(score) — fatigue is accumulating. Hold load and focus on bar speed."
            default: return "Readiness is \(score). Strong case for a lighter session today. Move well, don't grind."
            }
        }
        return "Log a set or two and I'll gauge how the bar is moving."
    }

    private func progressionResponse(from context: String) -> String {
        if let score = extractReadinessScore(from: context), score >= 75 {
            return "Green light — if the last set moved cleanly at target RPE, add a small jump. If it was a grind, hold and earn it."
        }
        return "Hold the load. Progression needs a clean baseline — own today, push next session."
    }

    private func cueResponse(from context: String) -> String {
        "Brace hard before the rep starts. Move with intent. If the last set drifted, dial back 5-10% and rebuild."
    }

    private func deloadResponse(from context: String) -> String {
        if let score = extractReadinessScore(from: context), score < 60 {
            return "Readiness is \(score) — deload makes sense. Drop intensity 10-15% and cut volume in half."
        }
        return "You might not need a full deload yet. Try a lighter top set today and reassess tomorrow."
    }

    private func defaultResponse(from context: String) -> String {
        if context.contains("Readiness") {
            return """
                Based on what I'm seeing, hold the target load and move each \
                rep well. Ask me something specific and I'll give you a \
                sharper read.
                """
        }
        return "Log a couple of sets so I have something to work with, then ask me again."
    }

    private func extractReadinessScore(from context: String) -> Int? {
        guard let range = context.range(of: "Readiness: ") else { return nil }
        let remainder = context[range.upperBound...]
        guard let slashRange = remainder.range(of: "/") else { return nil }
        let scoreString = String(remainder[remainder.startIndex..<slashRange.lowerBound])
        return Int(scoreString)
    }
}

#if canImport(FoundationModels) && !os(watchOS)
import FoundationModels

@available(iOS 26.0, visionOS 26.0, *)
public struct FoundationModelCoachProvider: AICoachProvider {
    private let fallback: AICoachProvider
    private let coachingStyle: CoachingStyle

    public init(fallback: AICoachProvider, coachingStyle: CoachingStyle = .motivational) {
        self.fallback = fallback
        self.coachingStyle = coachingStyle
    }

    public func coachResponse(for prompt: String, context: String) async throws -> String {
        do {
            let session = LanguageModelSession()
            // VOL-64: hand the on-device session the same templated prompt
            // the cloud relay sees — system prompt, intent envelope, context
            // block, and template marker — so on-device responses match the
            // shape of cloud responses for the same input.
            let rendered = CoachPromptTemplate.render(
                intent: CoachPromptTemplate.inferIntent(from: prompt),
                contextBlock: context,
                question: prompt,
                style: coachingStyle
            )
            let response = try await session.respond(to: rendered)
            return response.content
        } catch {
            return try await fallback.coachResponse(for: prompt, context: context)
        }
    }
}
#endif
