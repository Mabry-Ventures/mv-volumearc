// VOL-224: unit tests for the App Attest coordinator. The real
// `DCAppAttestService` is replaced with a deterministic in-memory
// mock so we can assert the coordinator's lifecycle:
//
//   * Skips bootstrap when the device doesn't support App Attest.
//   * Generates + attests a fresh key on first call.
//   * Reuses the persisted keyID on subsequent calls.
//   * Produces an assertion over (requestBody || nonce) hash.
//   * Recovers from `reset()` by re-bootstrapping a fresh key.

import CryptoKit
import Foundation
import VolumeArcCore
import XCTest

// VOL-224: the App target's internals (`AppAttestServiceProtocol`,
// `VolumeArcAppAttestCoordinator`, `LiveAppAttestService`) are reachable
// to `VolumeArcAppTests` without `@testable import VolumeArc` — the
// test target compiles against the App target's product.

private actor MockAppAttestService: AppAttestServiceProtocol {
    nonisolated let isSupported: Bool

    private(set) var generateKeyCalls: Int = 0
    private(set) var attestCalls: Int = 0
    private(set) var assertionCalls: Int = 0
    private(set) var lastAttestKeyID: String?
    private(set) var lastAssertionKeyID: String?
    private(set) var lastAttestClientDataHash: Data?
    private(set) var lastAssertionClientDataHash: Data?

    private let nextKeyID: String
    private let attestationBlob: Data
    private let assertionBlob: Data

    init(
        isSupported: Bool = true,
        nextKeyID: String = "test-key-id-abc123",
        attestationBlob: Data = Data("test-attestation-cbor".utf8),
        assertionBlob: Data = Data("test-assertion-cbor".utf8)
    ) {
        self.isSupported = isSupported
        self.nextKeyID = nextKeyID
        self.attestationBlob = attestationBlob
        self.assertionBlob = assertionBlob
    }

    func generateKey() async throws -> String {
        generateKeyCalls += 1
        return nextKeyID
    }

    func attestKey(keyID: String, clientDataHash: Data) async throws -> Data {
        attestCalls += 1
        lastAttestKeyID = keyID
        lastAttestClientDataHash = clientDataHash
        return attestationBlob
    }

    func generateAssertion(keyID: String, clientDataHash: Data) async throws -> Data {
        assertionCalls += 1
        lastAssertionKeyID = keyID
        lastAssertionClientDataHash = clientDataHash
        return assertionBlob
    }
}

@MainActor
final class VolumeArcAppAttestCoordinatorTests: XCTestCase {
    /// Unique Keychain key namespace per test so the coordinator's
    /// persisted keyID doesn't leak across runs. The coordinator hard-
    /// codes `"ai.relay.appattest.keyID"` so we have to scope by
    /// resetting the keychain entry before/after each test rather than
    /// changing the key name.
    private let storeKey = "ai.relay.appattest.keyID"
    private let attestationStoreKey = "ai.relay.appattest.attestationObject"

    override func setUpWithError() throws {
        let store = VolumeArcSecureStore()
        try? store.save("", for: storeKey)
        try? store.save("", for: attestationStoreKey)
    }

    override func tearDownWithError() throws {
        let store = VolumeArcSecureStore()
        try? store.save("", for: storeKey)
        try? store.save("", for: attestationStoreKey)
    }

    // MARK: - notSupported short-circuit

    func testBootstrapThrowsNotSupportedWhenDeviceUnsupported() async throws {
        let mock = MockAppAttestService(isSupported: false)
        let coordinator = VolumeArcAppAttestCoordinator(service: mock)

        do {
            _ = try await coordinator.bootstrapKeyIfNeeded(challenge: Data("hello".utf8))
            XCTFail("Expected notSupported error")
        } catch let error as VolumeArcAppAttestError {
            guard case .notSupported = error else {
                XCTFail("Expected .notSupported, got \(error)")
                return
            }
        }

        let generateCalls = await mock.generateKeyCalls
        XCTAssertEqual(generateCalls, 0, "Should not generate key when unsupported")
    }

    func testAssertionThrowsNotSupportedWhenDeviceUnsupported() async throws {
        let mock = MockAppAttestService(isSupported: false)
        let coordinator = VolumeArcAppAttestCoordinator(service: mock)

        do {
            _ = try await coordinator.assertion(
                over: Data("body".utf8),
                nonce: Data("nonce".utf8)
            )
            XCTFail("Expected notSupported error")
        } catch let error as VolumeArcAppAttestError {
            guard case .notSupported = error else {
                XCTFail("Expected .notSupported, got \(error)")
                return
            }
        }
    }

    // MARK: - bootstrap lifecycle

    func testBootstrapGeneratesAndAttestsKeyOnFirstCall() async throws {
        let mock = MockAppAttestService()
        let coordinator = VolumeArcAppAttestCoordinator(service: mock)
        let challenge = Data("server-nonce".utf8)

        let keyID = try await coordinator.bootstrapKeyIfNeeded(challenge: challenge)

        XCTAssertEqual(keyID, "test-key-id-abc123")
        let generateCalls = await mock.generateKeyCalls
        let attestCalls = await mock.attestCalls
        XCTAssertEqual(generateCalls, 1)
        XCTAssertEqual(attestCalls, 1)

        let attestKeyID = await mock.lastAttestKeyID
        XCTAssertEqual(attestKeyID, keyID)

        let cached = await coordinator.cachedAttestation()
        XCTAssertEqual(cached, Data("test-attestation-cbor".utf8))
    }

    func testBootstrapHashesChallengeWithSHA256() async throws {
        let mock = MockAppAttestService()
        let coordinator = VolumeArcAppAttestCoordinator(service: mock)
        let challenge = Data("server-nonce".utf8)

        _ = try await coordinator.bootstrapKeyIfNeeded(challenge: challenge)

        let recordedHash = await mock.lastAttestClientDataHash
        let expectedHash = Data(SHA256.hash(data: challenge))
        XCTAssertEqual(recordedHash, expectedHash)
    }

    func testBootstrapReusesPersistedKeyIDOnSubsequentCalls() async throws {
        let mock = MockAppAttestService()
        let coordinator = VolumeArcAppAttestCoordinator(service: mock)

        let first = try await coordinator.bootstrapKeyIfNeeded(challenge: Data("a".utf8))
        let second = try await coordinator.bootstrapKeyIfNeeded(challenge: Data("b".utf8))

        XCTAssertEqual(first, second)
        let generateCalls = await mock.generateKeyCalls
        let attestCalls = await mock.attestCalls
        XCTAssertEqual(generateCalls, 1, "generateKey runs exactly once across bootstrap calls")
        XCTAssertEqual(attestCalls, 1, "attestKey runs exactly once across bootstrap calls")
    }

    // MARK: - assertion

    func testAssertionRequiresExistingKeyID() async throws {
        // Bootstrap-only mock so `isSupported = true` but no key
        // persisted yet (test setUp clears the keychain).
        let mock = MockAppAttestService()
        let coordinator = VolumeArcAppAttestCoordinator(service: mock)

        do {
            _ = try await coordinator.assertion(
                over: Data("body".utf8),
                nonce: Data("nonce".utf8)
            )
            XCTFail("Expected notSupported error for missing key")
        } catch let error as VolumeArcAppAttestError {
            guard case .notSupported = error else {
                XCTFail("Expected .notSupported, got \(error)")
                return
            }
        }
    }

    func testAssertionHashesBodyConcatenatedWithNonce() async throws {
        let mock = MockAppAttestService()
        let coordinator = VolumeArcAppAttestCoordinator(service: mock)
        _ = try await coordinator.bootstrapKeyIfNeeded(challenge: Data("init".utf8))

        let body = Data("request-body".utf8)
        let nonce = Data("fresh-nonce".utf8)

        let assertion = try await coordinator.assertion(over: body, nonce: nonce)

        XCTAssertEqual(assertion.keyID, "test-key-id-abc123")
        XCTAssertEqual(assertion.assertion, Data("test-assertion-cbor".utf8))
        XCTAssertEqual(assertion.nonce, nonce)

        // Verify the hash inputs match what the relay will need to
        // reproduce. Server side: SHA256(body || nonce). If we ever
        // change the concat order or the hash domain, this test
        // breaks and the relay verifier needs an update in lockstep.
        var expectedClientData = Data()
        expectedClientData.append(body)
        expectedClientData.append(nonce)
        let expectedHash = Data(SHA256.hash(data: expectedClientData))
        let recordedHash = await mock.lastAssertionClientDataHash
        XCTAssertEqual(recordedHash, expectedHash)
    }

    // MARK: - reset

    func testResetClearsPersistedKeyAndCachedAttestation() async throws {
        let mock = MockAppAttestService()
        let coordinator = VolumeArcAppAttestCoordinator(service: mock)

        _ = try await coordinator.bootstrapKeyIfNeeded(challenge: Data("first".utf8))
        let cachedBeforeReset = await coordinator.cachedAttestation()
        XCTAssertNotNil(cachedBeforeReset)

        await coordinator.reset()

        let cachedAfterReset = await coordinator.cachedAttestation()
        XCTAssertNil(cachedAfterReset)

        // Next bootstrap regenerates from scratch.
        _ = try await coordinator.bootstrapKeyIfNeeded(challenge: Data("second".utf8))
        let generateCalls = await mock.generateKeyCalls
        XCTAssertEqual(generateCalls, 2, "Reset should let the next bootstrap call generate a fresh key")
    }
}
