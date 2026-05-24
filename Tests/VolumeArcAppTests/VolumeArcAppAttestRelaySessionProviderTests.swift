import CryptoKit
import Foundation
import VolumeArcCore
import XCTest

private actor SupportedAppAttestService: AppAttestServiceProtocol {
    nonisolated let isSupported = true

    private(set) var generateKeyCalls = 0
    private(set) var attestCalls = 0
    private(set) var assertionCalls = 0
    private(set) var lastAttestClientDataHash: Data?
    private(set) var lastAssertionClientDataHash: Data?

    func generateKey() async throws -> String {
        generateKeyCalls += 1
        return "fresh-key-id"
    }

    func attestKey(keyID: String, clientDataHash: Data) async throws -> Data {
        _ = keyID
        attestCalls += 1
        lastAttestClientDataHash = clientDataHash
        return Data("fresh-attestation".utf8)
    }

    func generateAssertion(keyID: String, clientDataHash: Data) async throws -> Data {
        _ = keyID
        assertionCalls += 1
        lastAssertionClientDataHash = clientDataHash
        return Data("fresh-assertion".utf8)
    }
}

private struct UnsupportedAppAttestService: AppAttestServiceProtocol {
    nonisolated let isSupported = false

    func generateKey() async throws -> String {
        throw VolumeArcAppAttestError.notSupported
    }

    func attestKey(keyID: String, clientDataHash: Data) async throws -> Data {
        _ = keyID
        _ = clientDataHash
        throw VolumeArcAppAttestError.notSupported
    }

    func generateAssertion(keyID: String, clientDataHash: Data) async throws -> Data {
        _ = keyID
        _ = clientDataHash
        throw VolumeArcAppAttestError.notSupported
    }
}

private actor StaticRelayCredentials: AIRelayCredentialsProviding {
    private let header: String

    init(header: String = "Bearer test-device.0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef") {
        self.header = header
    }

    func authorizationHeaderValue() async throws -> String {
        header
    }
}

final class VolumeArcAppAttestRelayTests: XCTestCase {
    private let appAttestKeys = [
        "ai.relay.appattest.keyID",
        "ai.relay.appattest.attestationObject",
        "ai.relay.appattest.confirmedKeyID",
        "ai.relay.appattest.pendingChallenge",
        "ai.relay.appattest.pendingChallengeExpiresAt"
    ]

    override func setUpWithError() throws {
        try clearAppAttestState()
    }

    override func tearDownWithError() throws {
        try clearAppAttestState()
    }

    func testPreferModeFallsBackToHMACWhenAppAttestUnsupported() async throws {
        let telemetry = CapturingTelemetrySink()
        let provider = makeProvider(mode: .appAttestPreferHMACFallback, telemetry: telemetry)

        let headers = try await provider.authenticationHeaders(for: Data("{}".utf8))
        let expectedHeader = try await StaticRelayCredentials().authorizationHeaderValue()

        XCTAssertEqual(headers["Authorization"], expectedHeader)
        XCTAssertNil(headers["X-VA-Attest-Key-ID"])
        XCTAssertNil(headers["X-VA-Attest-Assertion"])
        XCTAssertNil(headers["X-VA-Attest-Nonce"])
        XCTAssertEqual(telemetry.events(named: "app_attest_failed").first?.metadata["reason"], "unsupported_device")
        XCTAssertEqual(telemetry.events(named: "hmac_fallback_used").count, 1)
    }

    func testAppAttestOnlyModeDoesNotSilentlyUseHMACWhenUnsupported() async throws {
        let telemetry = CapturingTelemetrySink()
        let provider = makeProvider(mode: .appAttest, telemetry: telemetry)

        do {
            _ = try await provider.authenticationHeaders(for: Data("{}".utf8))
            XCTFail("Expected appAttest mode to throw when App Attest is unsupported")
        } catch AIRuntimeIntegrationError.relayUnavailable(let reason) {
            XCTAssertTrue(reason.contains("App Attest relay auth failed"))
        } catch {
            XCTFail("Expected relayUnavailable; got \(error)")
        }

        XCTAssertEqual(telemetry.events(named: "app_attest_failed").first?.metadata["reason"], "unsupported_device")
        XCTAssertTrue(telemetry.events(named: "hmac_fallback_used").isEmpty)
    }

    func testHMACModeBypassesAppAttestCompletely() async throws {
        let telemetry = CapturingTelemetrySink()
        let provider = makeProvider(mode: .hmac, telemetry: telemetry)

        let headers = try await provider.authenticationHeaders(for: Data("{}".utf8))
        let expectedHeader = try await StaticRelayCredentials().authorizationHeaderValue()

        XCTAssertEqual(Array(headers.keys), ["Authorization"])
        XCTAssertEqual(headers["Authorization"], expectedHeader)
        XCTAssertTrue(telemetry.events.isEmpty)
    }

    func testSupportedModeBootstrapsFreshKeyWhenPersistedKeyIsUnconfirmed() async throws {
        let store = VolumeArcSecureStore()
        try store.save("stale-key-id", for: "ai.relay.appattest.keyID")
        try store.save(Data("stale-attestation".utf8).base64EncodedString(), for: "ai.relay.appattest.attestationObject")

        let bootstrapNonce = Data("fresh-bootstrap-nonce".utf8)
        let assertionNonce = Data("fresh-assertion-nonce".utf8)
        MockAppAttestRelayState.shared.reset(challenges: [
            bootstrapNonce.base64EncodedString(),
            assertionNonce.base64EncodedString()
        ])

        let service = SupportedAppAttestService()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAppAttestRelayURLProtocol.self]
        let provider = VolumeArcAppAttestRelaySessionProvider(
            baseURL: URL(string: "https://relay.test.invalid")!,
            mode: .appAttest,
            fallbackProvider: StaticRelayCredentials(),
            coordinator: VolumeArcAppAttestCoordinator(service: service),
            telemetrySink: CapturingTelemetrySink(),
            session: URLSession(configuration: configuration)
        )

        let body = Data("{\"question\":\"ready?\"}".utf8)
        let headers = try await provider.authenticationHeaders(for: body)

        XCTAssertEqual(headers["X-VA-Attest-Key-ID"], "fresh-key-id")
        XCTAssertEqual(headers["X-VA-Attest-Assertion"], Data("fresh-assertion".utf8).base64EncodedString())
        XCTAssertEqual(headers["X-VA-Attest-Nonce"], assertionNonce.base64EncodedString())
        XCTAssertEqual(try store.load("ai.relay.appattest.confirmedKeyID"), "fresh-key-id")

        let generateCalls = await service.generateKeyCalls
        let attestCalls = await service.attestCalls
        let assertionCalls = await service.assertionCalls
        XCTAssertEqual(generateCalls, 1)
        XCTAssertEqual(attestCalls, 1)
        XCTAssertEqual(assertionCalls, 1)

        let expectedAttestHash = Data(SHA256.hash(data: bootstrapNonce))
        let recordedAttestHash = await service.lastAttestClientDataHash
        XCTAssertEqual(recordedAttestHash, expectedAttestHash)

        var assertionClientData = Data()
        assertionClientData.append(body)
        assertionClientData.append(assertionNonce)
        let expectedAssertionHash = Data(SHA256.hash(data: assertionClientData))
        let recordedAssertionHash = await service.lastAssertionClientDataHash
        XCTAssertEqual(recordedAssertionHash, expectedAssertionHash)

        let bootstrapRequests = MockAppAttestRelayState.shared.bootstrapRequests
        XCTAssertEqual(bootstrapRequests.count, 1)
        XCTAssertEqual(bootstrapRequests.first?.keyID, "fresh-key-id")
        XCTAssertEqual(bootstrapRequests.first?.challenge, bootstrapNonce.base64EncodedString())
    }

    func testSupportedModeRetriesPendingUnconfirmedBootstrapBeforeGeneratingNewKey() async throws {
        let store = VolumeArcSecureStore()
        let pendingChallenge = Data("pending-bootstrap-nonce".utf8).base64EncodedString()
        try store.save("pending-key-id", for: "ai.relay.appattest.keyID")
        try store.save(Data("pending-attestation".utf8).base64EncodedString(), for: "ai.relay.appattest.attestationObject")
        try store.save(pendingChallenge, for: "ai.relay.appattest.pendingChallenge")
        try store.save("2027-01-01T00:00:00.000Z", for: "ai.relay.appattest.pendingChallengeExpiresAt")

        let assertionNonce = Data("fresh-assertion-nonce".utf8)
        MockAppAttestRelayState.shared.reset(challenges: [
            assertionNonce.base64EncodedString()
        ])

        let service = SupportedAppAttestService()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAppAttestRelayURLProtocol.self]
        let provider = VolumeArcAppAttestRelaySessionProvider(
            baseURL: URL(string: "https://relay.test.invalid")!,
            mode: .appAttest,
            fallbackProvider: StaticRelayCredentials(),
            coordinator: VolumeArcAppAttestCoordinator(service: service),
            telemetrySink: CapturingTelemetrySink(),
            session: URLSession(configuration: configuration)
        )

        let headers = try await provider.authenticationHeaders(for: Data("{}".utf8))

        XCTAssertEqual(headers["X-VA-Attest-Key-ID"], "pending-key-id")
        XCTAssertEqual(try store.load("ai.relay.appattest.confirmedKeyID"), "pending-key-id")
        XCTAssertEqual(try store.load("ai.relay.appattest.pendingChallenge"), "")

        let generateCalls = await service.generateKeyCalls
        let attestCalls = await service.attestCalls
        let assertionCalls = await service.assertionCalls
        XCTAssertEqual(generateCalls, 0)
        XCTAssertEqual(attestCalls, 0)
        XCTAssertEqual(assertionCalls, 1)

        let bootstrapRequests = MockAppAttestRelayState.shared.bootstrapRequests
        XCTAssertEqual(bootstrapRequests.count, 1)
        XCTAssertEqual(bootstrapRequests.first?.keyID, "pending-key-id")
        XCTAssertEqual(bootstrapRequests.first?.challenge, pendingChallenge)
    }

    private func makeProvider(
        mode: VolumeArcRelayAuthMode,
        telemetry: CapturingTelemetrySink
    ) -> VolumeArcAppAttestRelaySessionProvider {
        VolumeArcAppAttestRelaySessionProvider(
            baseURL: URL(string: "https://relay.test.invalid")!,
            mode: mode,
            fallbackProvider: StaticRelayCredentials(),
            coordinator: VolumeArcAppAttestCoordinator(service: UnsupportedAppAttestService()),
            telemetrySink: telemetry,
            session: URLSession(configuration: .ephemeral)
        )
    }

    private func clearAppAttestState() throws {
        let store = VolumeArcSecureStore()
        for key in appAttestKeys {
            try? store.save("", for: key)
        }
        MockAppAttestRelayState.shared.reset(challenges: [])
    }
}

private final class MockAppAttestRelayState: @unchecked Sendable {
    struct BootstrapRequest: Decodable {
        let keyID: String
        let attestationObject: String
        let challenge: String
    }

    static let shared = MockAppAttestRelayState()

    private let lock = NSLock()
    private var challenges: [String] = []
    private var bootstrapBodies: [BootstrapRequest] = []

    var bootstrapRequests: [BootstrapRequest] {
        lock.lock()
        defer { lock.unlock() }
        return bootstrapBodies
    }

    func reset(challenges: [String]) {
        lock.lock()
        defer { lock.unlock() }
        self.challenges = challenges
        bootstrapBodies = []
    }

    func nextChallenge() -> String {
        lock.lock()
        defer { lock.unlock() }
        if challenges.isEmpty {
            return Data("fallback-nonce".utf8).base64EncodedString()
        }
        return challenges.removeFirst()
    }

    func recordBootstrap(_ request: BootstrapRequest) {
        lock.lock()
        defer { lock.unlock() }
        bootstrapBodies.append(request)
    }
}

private final class MockAppAttestRelayURLProtocol: URLProtocol, @unchecked Sendable {
    // swiftlint:disable static_over_final_class
    // `URLProtocol` declares these override points as `class func`.
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "relay.test.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        let path = request.url?.path ?? ""
        switch path {
        case "/v1/attest/challenge":
            guard Self.hasValidAuthorization(request) else {
                respond(statusCode: 401, body: ["error": "unauthorized"])
                return
            }
            let challenge = MockAppAttestRelayState.shared.nextChallenge()
            respond(statusCode: 200, body: [
                "challenge": challenge,
                "expiresAt": "2027-01-01T00:00:00Z"
            ])
        case "/v1/attest/bootstrap":
            guard Self.hasValidAuthorization(request) else {
                respond(statusCode: 401, body: ["error": "unauthorized"])
                return
            }
            if let body = bodyData(from: request),
               let decoded = try? JSONDecoder().decode(MockAppAttestRelayState.BootstrapRequest.self, from: body) {
                MockAppAttestRelayState.shared.recordBootstrap(decoded)
            }
            respond(statusCode: 200, body: [
                "ok": true,
                "attestedAt": "2027-01-01T00:00:00Z",
                "environment": "development"
            ])
        default:
            respond(statusCode: 404, body: ["error": "not_found"])
        }
    }

    override func stopLoading() {}

    private static func hasValidAuthorization(_ request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer test-device.") == true
    }

    private func respond(statusCode: Int, body: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func bodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }
}
