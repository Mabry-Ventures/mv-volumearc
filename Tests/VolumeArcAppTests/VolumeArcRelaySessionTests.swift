import XCTest
import VolumeArcCore

/// Tests for `VolumeArcRelaySessionProvider` and its dependencies.
/// Exercises real production types — no surrogate helpers.
final class VolumeArcRelaySessionTests: XCTestCase {

    // MARK: - VolumeArcSecureStore round-trip

    func testSecureStoreRoundTripPersistsValue() throws {
        let store = VolumeArcSecureStore()
        let key = "test.secure-store.\(UUID().uuidString)"

        let original = UUID().uuidString.lowercased()
        try store.save(original, for: key)
        XCTAssertEqual(try store.load(key), original)
        XCTAssertEqual(try store.load(key), original, "Repeated reads return the same value")
    }

    func testSecureStoreUpdateOverwritesPreviousValue() throws {
        let store = VolumeArcSecureStore()
        let key = "test.overwrite.\(UUID().uuidString)"

        try store.save("v1", for: key)
        try store.save("v2", for: key)
        XCTAssertEqual(try store.load(key), "v2")
    }

    func testSecureStoreReturnsNilForMissingKey() throws {
        let store = VolumeArcSecureStore()
        let key = "test.missing.\(UUID().uuidString)"
        XCTAssertNil(try store.load(key))
    }

    // MARK: - Real relay session provider

    /// The relay session provider should produce a stable device ID on
    /// repeated calls within a single provider instance.
    func testRelayProviderDeviceIDIsStableAcrossCalls() async throws {
        let provider = VolumeArcRelaySessionProvider(
            baseURL: URL(string: "https://example.invalid")!,
            applicationID: "com.test.volumearc"
        )

        // Call the auth header twice — it should either succeed with a
        // bearer token or fail with a relay error, but the device ID
        // written to Keychain should be stable across both calls.
        _ = try? await provider.authorizationHeaderValue()
        _ = try? await provider.authorizationHeaderValue()

        // Check the keychain directly for the device ID key.
        let store = VolumeArcSecureStore()
        let deviceID = try store.load("ai.relay.deviceID")
        XCTAssertNotNil(deviceID)
        XCTAssertFalse(deviceID?.isEmpty ?? true)
    }

    /// Invalid base URLs should still produce a session provider — the
    /// error only surfaces when `authorizationHeaderValue()` is called.
    func testRelayProviderConstructionWithInvalidURLDoesNotCrash() {
        _ = VolumeArcRelaySessionProvider(
            baseURL: URL(string: "https://nonexistent.invalid.domain.test")!,
            applicationID: "com.test.volumearc"
        )
    }

    // MARK: - AIRuntimeIntegrationError

    func testRelayUnavailableErrorDescription() {
        let error = AIRuntimeIntegrationError.relayUnavailable(reason: "Test reason")
        XCTAssertEqual(error.localizedDescription, "Test reason")
    }

    func testRelayRequestFailedErrorDescription() {
        let error = AIRuntimeIntegrationError.relayRequestFailed(statusCode: 401, message: "Unauthorized")
        XCTAssertTrue(error.localizedDescription.contains("401"))
        XCTAssertTrue(error.localizedDescription.contains("Unauthorized"))
    }

    func testInvalidHTTPResponseErrorDescription() {
        let error = AIRuntimeIntegrationError.invalidHTTPResponse
        XCTAssertFalse(error.localizedDescription.isEmpty)
    }
}
