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

        // Call the auth header twice — both calls MUST throw
        // `relayUnavailable` (no signing key configured in the test
        // environment), and each throw must persist the device ID before
        // surfacing. Asserting the throw explicitly (vs swallowing with
        // `try?`) catches the regression where a stale env var or
        // Info.plist key would let the call succeed and bypass the
        // "device ID is persisted on the failure path" contract entirely.
        try await assertThrowsRelayUnavailable {
            _ = try await provider.authorizationHeaderValue()
        }
        let store = VolumeArcSecureStore()
        let deviceIDKey = "ai.relay.deviceID"
        let deviceIDAfterFirstCall = try store.load(deviceIDKey)

        try await assertThrowsRelayUnavailable {
            _ = try await provider.authorizationHeaderValue()
        }
        let deviceIDAfterSecondCall = try store.load(deviceIDKey)

        XCTAssertNotNil(deviceIDAfterFirstCall, "Device ID must be persisted on first auth attempt even when signing key is unavailable")
        XCTAssertFalse(deviceIDAfterFirstCall?.isEmpty ?? true)
        XCTAssertEqual(deviceIDAfterFirstCall, deviceIDAfterSecondCall, "Device ID must be stable across calls")
    }

    /// Helper: assert that an async operation throws
    /// `AIRuntimeIntegrationError.relayUnavailable`. Used by the device-ID
    /// persistence test to make the failure path explicit instead of
    /// swallowing it with `try?`.
    private func assertThrowsRelayUnavailable(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            try await operation()
            XCTFail("Expected AIRuntimeIntegrationError.relayUnavailable; call returned successfully", file: file, line: line)
        } catch AIRuntimeIntegrationError.relayUnavailable {
            // expected — signing key is unavailable in the test env
        } catch {
            XCTFail("Expected AIRuntimeIntegrationError.relayUnavailable; got \(error)", file: file, line: line)
        }
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
