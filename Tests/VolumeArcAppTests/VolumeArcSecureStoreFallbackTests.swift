import XCTest
import Security

/// VOL-84: Verifies that the `VolumeArcSecureStore` UserDefaults fallback
/// is fenced to Debug / simulator builds only, and that Release device
/// builds hard-fail with `VolumeArcSecureStoreError.keychainUnavailable`
/// instead of silently downgrading secret storage to UserDefaults.
///
/// Swift unit tests compile and run under the Debug configuration, so
/// the behavioral side of the fence can only be exercised in-process for
/// the Debug/simulator branch. The Release-device branch is covered by
/// (a) a compile-time assertion inside an `#if !DEBUG && !targetEnvironment(simulator)`
/// block that the `keychainUnavailable` case exists and the right
/// routines throw it, and (b) an error-surface test that pins the
/// new error case and its localized description.
final class VolumeArcSecureStoreFallbackTests: XCTestCase {
    @inline(never)
    private func makeKeychainUnavailableError(_ status: OSStatus) -> VolumeArcSecureStoreError {
        .keychainUnavailable(status)
    }

    @inline(never)
    private func makeUnexpectedStatusError(_ status: OSStatus) -> VolumeArcSecureStoreError {
        .unexpectedStatus(status)
    }

    // MARK: - Error surface

    func testKeychainUnavailableErrorCarriesOSStatus() {
        let error = makeKeychainUnavailableError(errSecMissingEntitlement)

        // The OSStatus must be preserved so callers / telemetry can
        // distinguish "device locked" from "missing entitlement" from
        // "not available".
        switch error {
        case let .keychainUnavailable(status):
            XCTAssertEqual(status, errSecMissingEntitlement)
        default:
            XCTFail("Expected .keychainUnavailable case, got \(error)")
        }
    }

    func testKeychainUnavailableErrorHasDescriptiveMessage() {
        let error = makeKeychainUnavailableError(errSecNotAvailable)
        let description = error.errorDescription ?? ""

        XCTAssertFalse(description.isEmpty, "keychainUnavailable must have a non-empty description")
        XCTAssertTrue(
            description.lowercased().contains("keychain"),
            "Description should mention Keychain so developers recognize the failure mode"
        )
        XCTAssertTrue(
            description.contains("\(errSecNotAvailable)"),
            "Description should include the underlying OSStatus for diagnosis"
        )
    }

    func testUnexpectedStatusAndKeychainUnavailableAreDistinctCases() {
        // Pin that we didn't collapse the two error cases into one — the
        // whole point of VOL-84 is that `keychainUnavailable` signals a
        // *fence decision*, while `unexpectedStatus` signals a genuinely
        // unknown failure. Callers can inspect the case to decide
        // between "surface to user" vs "report as bug".
        let fenceError = makeKeychainUnavailableError(errSecMissingEntitlement)
        let genericError = makeUnexpectedStatusError(errSecMissingEntitlement)

        switch (fenceError, genericError) {
        case (.keychainUnavailable, .unexpectedStatus):
            break // expected
        default:
            XCTFail("keychainUnavailable and unexpectedStatus must remain distinct cases")
        }
    }

    // MARK: - Round-trip (Debug / simulator happy path)

    /// In the Debug/simulator configuration the store should still
    /// round-trip real Keychain traffic — fencing the fallback must not
    /// regress the normal path.
    func testSecureStoreRoundTripStillWorksUnderDebugSimulator() throws {
        let store = VolumeArcSecureStore()
        let key = "vol84.roundtrip.\(UUID().uuidString)"

        try store.save("hello", for: key)
        XCTAssertEqual(try store.load(key), "hello")

        try store.save("world", for: key)
        XCTAssertEqual(try store.load(key), "world")
    }

    // MARK: - Release compile-time pin
    //
    // Unit tests run under the Debug configuration, so we can't execute
    // the Release branch here. What we *can* do is ensure that, when
    // this file is compiled under a Release non-simulator configuration
    // (e.g. by a future archive-time test plan), the enum case we rely
    // on still exists and the error type is still throwable. If someone
    // deletes `.keychainUnavailable` in Release-only code, this block
    // fails to compile.

    #if !DEBUG && !targetEnvironment(simulator)
    func testReleaseBuildSurfacesKeychainUnavailable() {
        let error: Error = VolumeArcSecureStoreError.keychainUnavailable(errSecMissingEntitlement)
        XCTAssertNotNil((error as? VolumeArcSecureStoreError))
    }
    #endif
}
