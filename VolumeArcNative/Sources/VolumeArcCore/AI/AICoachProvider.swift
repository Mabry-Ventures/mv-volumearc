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

public struct OpenAIRelayCoachProvider: AICoachProvider {
    private let configuration: OpenAIRelayConfiguration
    private let credentialsProvider: OpenAIRelayCredentialsProviding

    public init(configuration: OpenAIRelayConfiguration, credentialsProvider: OpenAIRelayCredentialsProviding) {
        self.configuration = configuration
        self.credentialsProvider = credentialsProvider
    }

    public func coachResponse(for prompt: String, context: String) async throws -> String {
        let auth = try await credentialsProvider.authorizationHeaderValue()
        var request = URLRequest(url: configuration.baseURL.appending(path: "relay/coach"))
        request.httpMethod = "POST"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: String] = ["prompt": prompt, "context": context]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown"
            throw AIRuntimeIntegrationError.relayRequestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: message)
        }

        struct CoachResponse: Decodable { let text: String }
        return try JSONDecoder().decode(CoachResponse.self, from: data).text
    }
}

public struct LocalHeuristicAICoachProvider: AICoachProvider {
    public init() {}

    public func coachResponse(for prompt: String, context: String) async throws -> String {
        "Based on your recent training, I'd recommend holding the current load and focusing on rep quality."
    }
}

#if canImport(FoundationModels) && !os(watchOS)
import FoundationModels

@available(iOS 26.0, visionOS 26.0, *)
public struct FoundationModelCoachProvider: AICoachProvider {
    private let fallback: AICoachProvider

    public init(fallback: AICoachProvider) {
        self.fallback = fallback
    }

    public func coachResponse(for prompt: String, context: String) async throws -> String {
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: "\(context)\n\nUser question: \(prompt)")
            return response.content
        } catch {
            return try await fallback.coachResponse(for: prompt, context: context)
        }
    }
}
#endif
