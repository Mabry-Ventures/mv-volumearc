import XCTest
import VolumeArcCore

/// Tests for relay-adjacent support types.
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
