import Foundation
import VolumeArcCore

actor VolumeArcAppAttestRelaySessionProvider: AIRelayCredentialsProviding {
    private struct ChallengeResponse: Decodable {
        let challenge: String
        let expiresAt: String
    }

    private struct Challenge {
        let encoded: String
        let data: Data
        let expiresAt: Date
    }

    private struct BootstrapRequest: Encodable {
        let keyID: String
        let attestationObject: String
        let challenge: String
    }

    private struct BootstrapResponse: Decodable {
        let ok: Bool
        let attestedAt: String?
        let environment: String?
    }

    private let baseURL: URL
    private let coordinator: VolumeArcAppAttestCoordinator
    private let telemetrySink: (any TelemetrySink)?
    private let session: URLSession
    private let secureStore: VolumeArcSecureStore
    private let confirmedKeyIDKey = "ai.relay.appattest.confirmedKeyID"
    private let pendingChallengeKey = "ai.relay.appattest.pendingChallenge"
    private let pendingChallengeExpiresAtKey = "ai.relay.appattest.pendingChallengeExpiresAt"
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        coordinator: VolumeArcAppAttestCoordinator = VolumeArcAppAttestCoordinator(),
        telemetrySink: (any TelemetrySink)? = nil,
        session: URLSession = .shared,
        secureStore: VolumeArcSecureStore = VolumeArcSecureStore()
    ) {
        self.baseURL = baseURL
        self.coordinator = coordinator
        self.telemetrySink = telemetrySink
        self.session = session
        self.secureStore = secureStore
        self.decoder = JSONDecoder()
    }

    func authorizationHeaderValue() async throws -> String {
        throw AIRuntimeIntegrationError.relayUnavailable(
            reason: "App Attest relay auth requires a signed request body."
        )
    }

    func authenticationHeaders(for requestBody: Data) async throws -> [String: String] {
        do {
            guard await coordinator.supportsAppAttest() else {
                throw VolumeArcAppAttestError.notSupported
            }
            let keyID = try await ensureBootstrapped()
            let challenge = try await fetchChallenge()
            let assertion = try await coordinator.assertion(over: requestBody, nonce: challenge.data)
            record(name: "app_attest_succeeded", severity: .info)
            return [
                "X-VA-Attest-Key-ID": keyID,
                "X-VA-Attest-Assertion": assertion.assertion.base64EncodedString(),
                "X-VA-Attest-Nonce": challenge.encoded
            ]
        } catch {
            record(name: "app_attest_failed", severity: .warning, metadata: [
                "reason": Self.reason(for: error)
            ])
            throw AIRuntimeIntegrationError.relayUnavailable(
                reason: "App Attest relay auth failed: \(error.localizedDescription)"
            )
        }
    }

    private func ensureBootstrapped() async throws -> String {
        if let keyID = await coordinator.cachedKeyID(),
           (try? secureStore.load(confirmedKeyIDKey)) == keyID {
            return keyID
        }

        if let keyID = await coordinator.cachedKeyID(),
           let attestation = await coordinator.cachedAttestation(),
           let pendingChallenge = pendingBootstrapChallenge() {
            do {
                try await postBootstrap(
                    keyID: keyID,
                    attestation: attestation,
                    challenge: pendingChallenge
                )
                markBootstrapConfirmed(keyID: keyID)
                return keyID
            } catch {
                if Self.isPermanentBootstrapFailure(error) {
                    clearPendingBootstrap()
                    await coordinator.reset()
                }
                throw error
            }
        }

        clearPendingBootstrap()
        await coordinator.reset()
        let bootstrapChallenge = try await fetchChallenge()
        let keyID = try await coordinator.bootstrapKeyIfNeeded(challenge: bootstrapChallenge.data)
        let attestation = await coordinator.cachedAttestation()
        savePendingBootstrap(challenge: bootstrapChallenge.encoded, expiresAt: bootstrapChallenge.expiresAt)

        do {
            try await postBootstrap(
                keyID: keyID,
                attestation: try Self.unwrapAttestation(attestation),
                challenge: bootstrapChallenge.encoded
            )
            markBootstrapConfirmed(keyID: keyID)
        } catch {
            if Self.isPermanentBootstrapFailure(error) {
                clearPendingBootstrap()
                await coordinator.reset()
            }
            throw error
        }
        return keyID
    }

    private func fetchChallenge() async throws -> Challenge {
        var request = URLRequest(url: baseURL.appending(path: "v1/attest/challenge"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIRuntimeIntegrationError.invalidHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIRuntimeIntegrationError.relayRequestFailed(
                statusCode: http.statusCode,
                message: "App Attest challenge failed with HTTP \(http.statusCode)"
            )
        }
        let decoded = try decoder.decode(ChallengeResponse.self, from: data)
        guard let challengeData = Data(base64Encoded: decoded.challenge) else {
            throw AIRuntimeIntegrationError.invalidHTTPResponse
        }
        guard let expiresAt = Self.parseISO8601(decoded.expiresAt) else {
            throw AIRuntimeIntegrationError.invalidHTTPResponse
        }
        return Challenge(encoded: decoded.challenge, data: challengeData, expiresAt: expiresAt)
    }

    private func postBootstrap(
        keyID: String,
        attestation: Data,
        challenge: String
    ) async throws {
        var request = URLRequest(url: baseURL.appending(path: "v1/attest/bootstrap"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(BootstrapRequest(
            keyID: keyID,
            attestationObject: attestation.base64EncodedString(),
            challenge: challenge
        ))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIRuntimeIntegrationError.invalidHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIRuntimeIntegrationError.relayRequestFailed(
                statusCode: http.statusCode,
                message: "App Attest bootstrap failed with HTTP \(http.statusCode)"
            )
        }
        let decoded = try decoder.decode(BootstrapResponse.self, from: data)
        guard decoded.ok else {
            throw AIRuntimeIntegrationError.invalidHTTPResponse
        }
        _ = decoded.attestedAt
        _ = decoded.environment
    }

    private func pendingBootstrapChallenge() -> String? {
        guard let challenge = try? secureStore.load(pendingChallengeKey),
              challenge.isEmpty == false,
              let expiresAtString = try? secureStore.load(pendingChallengeExpiresAtKey),
              let expiresAt = Self.parseISO8601(expiresAtString),
              expiresAt > Date().addingTimeInterval(10) else {
            return nil
        }
        return challenge
    }

    private func savePendingBootstrap(challenge: String, expiresAt: Date) {
        try? secureStore.save(challenge, for: pendingChallengeKey)
        try? secureStore.save(Self.formatISO8601(expiresAt), for: pendingChallengeExpiresAtKey)
    }

    private func markBootstrapConfirmed(keyID: String) {
        try? secureStore.save(keyID, for: confirmedKeyIDKey)
        clearPendingBootstrap()
    }

    private func clearPendingBootstrap() {
        try? secureStore.save("", for: pendingChallengeKey)
        try? secureStore.save("", for: pendingChallengeExpiresAtKey)
    }

    private func record(
        name: String,
        severity: TelemetrySeverity,
        metadata: [String: String] = [:]
    ) {
        telemetrySink?.record(TelemetryEvent(
            category: "relay.auth",
            name: name,
            severity: severity,
            message: "Relay auth transition: \(name)",
            metadata: metadata
        ))
    }

    private static func unwrapAttestation(_ attestation: Data?) throws -> Data {
        guard let attestation else {
            throw AIRuntimeIntegrationError.relayUnavailable(
                reason: "App Attest key exists but no attestation object is available."
            )
        }
        return attestation
    }

    private static func isPermanentBootstrapFailure(_ error: Error) -> Bool {
        if case AIRuntimeIntegrationError.relayRequestFailed(let statusCode, _) = error {
            return (400..<500).contains(statusCode)
        }
        if error is VolumeArcAppAttestError {
            return true
        }
        return false
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func reason(for error: Error) -> String {
        if case AIRuntimeIntegrationError.relayRequestFailed(let statusCode, _) = error {
            return "relay_http_\(statusCode)"
        }
        if error is AIRuntimeIntegrationError {
            return "relay_integration_error"
        }
        if let appAttest = error as? VolumeArcAppAttestError {
            switch appAttest {
            case .notSupported: return "unsupported_device"
            case .disabledForTests: return "disabled_for_tests"
            case .generateKeyFailed: return "keygen_failed"
            case .attestationFailed: return "attest_failed"
            case .assertionFailed: return "assertion_failed"
            case .keychainPersistFailed: return "keychain_failed"
            }
        }
        return "unknown"
    }
}
