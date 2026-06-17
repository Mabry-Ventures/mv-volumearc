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
    /// Providers that support native streaming (like the AI relay) should override this.
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

public struct AIRelayConfiguration: Sendable {
    public let baseURL: URL
    public let bearerToken: String
    public var applicationID: String { baseURL.host ?? "com.mabryventures.VolumeArc" }

    public init(baseURL: URL, bearerToken: String) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
    }
}

public protocol AIRelayCredentialsProviding: Sendable {
    func authorizationHeaderValue() async throws -> String
    func authenticationHeaders(for requestBody: Data) async throws -> [String: String]
}

public extension AIRelayCredentialsProviding {
    func authenticationHeaders(for requestBody: Data) async throws -> [String: String] {
        _ = requestBody
        return ["Authorization": try await authorizationHeaderValue()]
    }
}

public enum CoachTier: String, Sendable {
    case flashLite = "flash-lite"
    case pro = "pro"
}

/// Relay-backed coach provider that talks to `volumearc-ai-relay` via SSE.
///
/// VOL-66: real progressive streaming. `streamCoachResponse(for:context:)`
/// consumes `text/event-stream` from the Worker and yields token chunks as
/// Gemini emits them. The non-streaming `coachResponse` joins the stream to
/// a single string for callers that don't need progressive UI. The Worker
/// proxies to Gemini 3.1 Flash Lite / Pro today; the type name is
/// intentionally provider-agnostic so the upstream model can change without
/// further renames.
public struct AIRelayCoachProvider: AICoachProvider {
    private let configuration: AIRelayConfiguration
    private let credentialsProvider: AIRelayCredentialsProviding
    private let coachingStyle: CoachingStyle
    private let tier: CoachTier
    private let session: URLSession

    public init(
        configuration: AIRelayConfiguration,
        credentialsProvider: AIRelayCredentialsProviding,
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
                    let request = try await buildCoachRequest(prompt: prompt, context: context)
                    try await drainSSEStream(request: request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Build the POST request (auth, headers, body) for the relay `/v1/coach` endpoint.
    private func buildCoachRequest(prompt: String, context: String) async throws -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appending(path: "v1/coach"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(tier.rawValue, forHTTPHeaderField: "X-Coach-Tier")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        // VOL-64: render the prompt on-device and send it pre-rendered so the
        // template marker + system prompt are the single source of truth. Worker
        // uses these verbatim and layers Gemini safety settings on top.
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
            "style": coachingStyle.rawValue,
            "prompt": renderedPrompt,
            "system": systemPrompt
        ]
        let bodyData = try JSONEncoder().encode(body)
        let authHeaders = try await credentialsProvider.authenticationHeaders(for: bodyData)
        for (name, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = bodyData
        return request
    }

    /// Connect to the relay, stream SSE `data:` lines, and yield decoded text
    /// chunks to the supplied continuation. Finishes (normally or with error)
    /// before returning.
    private func drainSSEStream(
        request: URLRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
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
        if let redFlagResponse = CoachSafetyFilter.medicalRedFlagResponse(prompt: prompt, context: context) {
            return redFlagResponse
        }
        if CoachSafetyFilter.shouldBufferResponse(prompt: prompt, context: context) {
            return CoachSafetyFilter.conservativeRecoveryResponse(prompt: prompt, context: context)
        }

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
        case .planning:
            return planningResponse(from: rendered)
        case .substitution, .free:
            return defaultResponse(from: rendered)
        }
    }

    private func readinessResponse(from context: String) -> String {
        if let score = extractReadinessScore(from: context) {
            switch score {
            case 80...:
                return String(
                    localized: "Readiness is \(score). You can train, but keep the first set honest and stop if form or pain changes.",
                    comment: "Offline coach readiness response for high readiness"
                )
            case 60..<80:
                return String(
                    localized: "Readiness is \(score). Keep the plan, skip heroics, and choose clean reps over more load.",
                    comment: "Offline coach readiness response for moderate readiness"
                )
            case 40..<60:
                return String(
                    localized: "Readiness is \(score). Back off today: hold load, trim volume, and leave several reps in reserve.",
                    comment: "Offline coach readiness response for low readiness"
                )
            default:
                return String(
                    localized: "Readiness is \(score). Rest is the best call today; if you need to move, keep it light and easy.",
                    comment: "Offline coach readiness response for very low readiness"
                )
            }
        }
        return String(
            localized: "I need more context before calling intensity. Start easy, log how it feels, and stop if anything hurts.",
            comment: "Offline coach readiness response when context is missing"
        )
    }

    private func progressionResponse(from context: String) -> String {
        if let score = extractReadinessScore(from: context), score >= 75 {
            return String(
                localized: "You can consider a small jump only if the last set moved cleanly at target RPE. If it was a grind, hold.",
                comment: "Offline coach progression response when readiness supports a small increase"
            )
        }
        return String(
            localized: "Hold the load. Progression needs a clean baseline; make today crisp and reassess next session.",
            comment: "Offline coach progression response when readiness is not high enough"
        )
    }

    private func cueResponse(from context: String) -> String {
        String(
            localized: "Brace before the rep starts, move smoothly, and keep every rep pain-free. If form drifts, reduce load 5-10%.",
            comment: "Offline coach form cue response"
        )
    }

    private func deloadResponse(from context: String) -> String {
        if let score = extractReadinessScore(from: context), score < 60 {
            return String(
                localized: "Readiness is \(score) — deload makes sense. Drop intensity 10-15% and cut volume in half.",
                comment: "Offline coach deload response when readiness is low"
            )
        }
        return String(
            localized: "You might not need a full deload yet. Try a lighter top set today and reassess tomorrow.",
            comment: "Offline coach deload response when readiness does not demand deload"
        )
    }

    private func planningResponse(from context: String) -> String {
        let schedule = extractWeeklySchedule(from: context)
        let question = extractAthleteQuestion(from: context).lowercased()
        if question.contains("today") {
            if let nextUp = extractLine(prefix: "- Next up: ", from: context) {
                return String(
                    localized: "Today: \(nextUp). Keep it to that session, adjust by readiness/RPE, and don't add extra days.",
                    comment: "Planning response when today's next known session is available"
                )
            }
            return String(
                localized: """
                I don't have today's next session yet. Use the next known lift when \
                it appears, keep effort around RPE 7-8, and don't add extra days.
                """,
                comment: "Planning response when user asks for today but no next session is available"
            )
        }
        if !schedule.isEmpty {
            let scheduleSummary = schedule.prefix(7).joined(separator: "; ")
            return String(
                localized: "This week: \(scheduleSummary). Keep the next session tied to readiness/RPE and don't add extra days.",
                comment: "Planning response when weekly schedule entries are available"
            )
        }
        if let nextUp = extractLine(prefix: "- Next up: ", from: context) {
            return String(
                localized: "I only have the next known session: \(nextUp). Treat that as today's plan and avoid inventing the rest of the week.",
                comment: "Planning response when only the next known session is available"
            )
        }
        return String(
            localized: """
            I don't have a weekly schedule yet. Start with the next planned lift, \
            keep effort around RPE 7-8, and ask again after a logged set.
            """,
            comment: "Planning response when no schedule or next session context is available"
        )
    }

    private func defaultResponse(from context: String) -> String {
        if context.contains("Readiness") {
            return String(
                localized: """
                Based on what I can see, choose the lowest-risk option: clean reps, \
                no grinding, and stop if pain shows up. Ask me about the exact lift \
                and I can be more specific.
                """,
                comment: "Offline coach default response when readiness context is available"
            )
        }
        return String(
            localized: "Log a couple of sets so I have something to work with, then ask me again.",
            comment: "Offline coach default response when no useful context is available"
        )
    }

    private func extractWeeklySchedule(from context: String) -> [String] {
        guard let sectionRange = context.range(of: "## Weekly schedule") else { return [] }
        let section = context[sectionRange.upperBound...]
        return section
            .split(separator: "\n")
            .prefix { !$0.hasPrefix("## ") }
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("- ") else { return nil }
                return String(trimmed.dropFirst(2))
            }
    }

    private func extractLine(prefix: String, from context: String) -> String? {
        context
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    private func extractAthleteQuestion(from context: String) -> String {
        guard let sectionRange = context.range(of: "## Athlete question") else { return "" }
        return context[sectionRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    private let telemetrySink: (any TelemetrySink)?
    private let isRemotelyDisabled: (@Sendable () -> Bool)?

    public init(
        fallback: AICoachProvider,
        coachingStyle: CoachingStyle = .motivational,
        telemetrySink: (any TelemetrySink)? = nil,
        isRemotelyDisabled: (@Sendable () -> Bool)? = nil
    ) {
        self.fallback = fallback
        self.coachingStyle = coachingStyle
        self.telemetrySink = telemetrySink
        self.isRemotelyDisabled = isRemotelyDisabled
    }

    public func coachResponse(for prompt: String, context: String) async throws -> String {
        // VOL-286: remote kill switch — operations can stop the on-device
        // brain without an app update. Checked per turn so a flag fetched
        // mid-session applies on the next coach question.
        if isRemotelyDisabled?() == true {
            telemetrySink?.record(TelemetryEvent(
                category: "coach.safety",
                name: "killswitch.active",
                severity: .warning,
                message: "On-device FM coach disabled by remote kill switch; using fallback.",
                metadata: ["path": "fm"]
            ))
            return try await fallback.coachResponse(for: prompt, context: context)
        }
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
            recordUnavailableTelemetry(error: error)
            return try await fallback.coachResponse(for: prompt, context: context)
        }
    }

    private func recordUnavailableTelemetry(error: Error) {
        telemetrySink?.record(TelemetryEvent(
            category: "ai",
            name: "fm.unavailable",
            severity: .warning,
            message: "Foundation Models coach unavailable; falling back to configured provider.",
            metadata: [
                "reason": "runtime_error",
                "fallback_path": "configured_fallback",
                "error_type": String(reflecting: Swift.type(of: error)),
            ]
        ))
    }
}
#endif
