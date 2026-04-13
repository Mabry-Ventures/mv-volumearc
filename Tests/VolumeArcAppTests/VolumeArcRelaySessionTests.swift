import XCTest
import VolumeArcCore

final class VolumeArcRelaySessionTests: XCTestCase {

    // MARK: - Secure Store round-trip (device ID stability)

    func testSecureStoreRoundTripForDeviceID() throws {
        let store = VolumeArcSecureStore()
        let key = "test.device-id.\(UUID().uuidString)"

        let firstID = UUID().uuidString.lowercased()
        try store.save(firstID, for: key)
        XCTAssertEqual(try store.load(key), firstID)

        // Subsequent loads return the same value (not a new UUID)
        XCTAssertEqual(try store.load(key), firstID)
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

    // MARK: - Token expiration logic

    func testTokenExpirationSkewRejectsExpiredTokens() {
        let formatter = ISO8601DateFormatter()

        // Token expired 10 seconds ago
        let expired = formatter.string(from: Date.now.addingTimeInterval(-10))
        XCTAssertTrue(isExpiredWithSkew(expiresAt: expired, skew: 60))

        // Token expires in 30 seconds (within 60s skew)
        let soonExpiring = formatter.string(from: Date.now.addingTimeInterval(30))
        XCTAssertTrue(isExpiredWithSkew(expiresAt: soonExpiring, skew: 60))

        // Token expires in 120 seconds (outside 60s skew)
        let valid = formatter.string(from: Date.now.addingTimeInterval(120))
        XCTAssertFalse(isExpiredWithSkew(expiresAt: valid, skew: 60))
    }

    func testInvalidDateStringTreatsTokenAsExpired() {
        XCTAssertTrue(isExpiredWithSkew(expiresAt: "not-a-date", skew: 60))
        XCTAssertTrue(isExpiredWithSkew(expiresAt: "", skew: 60))
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

    // MARK: - Helpers

    /// Mimics the token validation logic in VolumeArcRelaySessionProvider.cachedTokenIfValid()
    private func isExpiredWithSkew(expiresAt: String, skew: TimeInterval) -> Bool {
        guard let date = ISO8601DateFormatter().date(from: expiresAt) else { return true }
        return date.timeIntervalSinceNow <= skew
    }
}
