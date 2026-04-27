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

    /// VOL-116: even when signing key resolution fails (CI runner has no
    /// `VOLUMEARC_RELAY_SIGNING_KEY` env var, no `VolumeArcRelaySigningKey`
    /// Info.plist key, no prior keychain entry), the device ID must still
    /// be generated and persisted on the first auth attempt. The relay's
    /// rate-limiting, telemetry, and abuse signals all key on this ID, so
    /// it must be stable across the lifetime of the install — including
    /// across signing-key bootstrapping.
    ///
    /// Two calls must observe the same persisted value.
    func testRelayProviderDeviceIDIsStableAcrossCalls() async throws {
        let provider = VolumeArcRelaySessionProvider(
            baseURL: URL(string: "https://example.invalid")!,
            applicationID: "com.test.volumearc"
        )

        // Call the auth header twice — both calls fail (no signing key
        // configured) but each call must persist the device ID, and both
        // calls must observe the same persisted value.
        _ = try? await provider.authorizationHeaderValue()
        let store = VolumeArcSecureStore()
        let deviceIDKey = "ai.relay.deviceID"
        let deviceIDAfterFirstCall = try store.load(deviceIDKey)

        _ = try? await provider.authorizationHeaderValue()
        let deviceIDAfterSecondCall = try store.load(deviceIDKey)

        XCTAssertNotNil(deviceIDAfterFirstCall, "Device ID must be persisted on first auth attempt even when signing key is unavailable")
        XCTAssertFalse(deviceIDAfterFirstCall?.isEmpty ?? true)
        XCTAssertEqual(deviceIDAfterFirstCall, deviceIDAfterSecondCall, "Device ID must be stable across calls")
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
