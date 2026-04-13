import Foundation
import VolumeArcCore

actor VolumeArcRelaySessionProvider: OpenAIRelayCredentialsProviding {
    private struct SessionResponse: Decodable {
        let bearerToken: String
        let expiresAt: String
    }

    private let baseURL: URL
    private let applicationID: String
    private let secureStore = VolumeArcSecureStore()
    private let sessionTokenKey = "ai.relay.session.bearerToken"
    private let sessionExpirationKey = "ai.relay.session.expiresAt"
    private let deviceIDKey = "ai.relay.deviceID"
    private let sessionRefreshSkew: TimeInterval = 60

    init(baseURL: URL, applicationID: String) {
        self.baseURL = baseURL
        self.applicationID = applicationID
    }

    func authorizationHeaderValue() async throws -> String {
        if let token = try cachedTokenIfValid() {
            return "Bearer \(token)"
        }

        let session = try await fetchSession()
        try secureStore.save(session.bearerToken, for: sessionTokenKey)
        try secureStore.save(session.expiresAt, for: sessionExpirationKey)
        return "Bearer \(session.bearerToken)"
    }

    private func cachedTokenIfValid() throws -> String? {
        guard let token = try secureStore.load(sessionTokenKey),
              let expiresAtString = try secureStore.load(sessionExpirationKey),
              let expiresAt = ISO8601DateFormatter().date(from: expiresAtString)
        else {
            return nil
        }

        guard expiresAt.timeIntervalSinceNow > sessionRefreshSkew else {
            return nil
        }

        return token
    }

    private func fetchSession() async throws -> SessionResponse {
        var request = URLRequest(url: baseURL.appending(path: "relay/session"))
        request.httpMethod = "POST"
        request.setValue(deviceID(), forHTTPHeaderField: "x-device-id")
        request.setValue(applicationID, forHTTPHeaderField: "x-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIRuntimeIntegrationError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown relay session failure"
            throw AIRuntimeIntegrationError.relayRequestFailed(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        return try JSONDecoder().decode(SessionResponse.self, from: data)
    }

    private func deviceID() -> String {
        if let existing = try? secureStore.load(deviceIDKey), existing.isEmpty == false {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        try? secureStore.save(generated, for: deviceIDKey)
        return generated
    }
}
