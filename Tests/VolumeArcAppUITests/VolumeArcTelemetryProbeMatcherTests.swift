import XCTest

/// VOL-149: unit coverage for `VolumeArcAppUITestSupport.telemetryLabel`.
///
/// The probe writes a JSON array of `{c, n, s}` records to the
/// `debug.telemetry.events` overlay; the assertion helper parses it
/// to decide whether a target (category, name) pair has fired. These
/// tests exercise the parser in isolation so a regression that breaks
/// the matcher surfaces here instead of as a confusing XCUITest
/// timeout downstream.
///
/// Note: lives in the UITests target (not VolumeArcAppTests) because
/// the matcher belongs to `VolumeArcAppUITestSupport`, which is only
/// linked into the UITests product.
final class VolumeArcTelemetryProbeMatcherTests: XCTestCase {
    func testMatchesEventInSingleEntryArray() {
        let label = #"[{"c":"dashboard","n":"refresh","s":"info"}]"#
        XCTAssertTrue(
            VolumeArcAppUITestSupport.telemetryLabel(label, contains: "dashboard", name: "refresh")
        )
    }

    func testMatchesEventInMiddleOfArray() {
        let label = """
        [
          {"c":"workout","n":"started","s":"info"},
          {"c":"workout","n":"set_logged","s":"info"},
          {"c":"workout","n":"completed","s":"info"}
        ]
        """
        XCTAssertTrue(
            VolumeArcAppUITestSupport.telemetryLabel(label, contains: "workout", name: "set_logged")
        )
    }

    func testDoesNotMatchWhenCategoryMissing() {
        let label = #"[{"c":"workout","n":"started","s":"info"}]"#
        XCTAssertFalse(
            VolumeArcAppUITestSupport.telemetryLabel(label, contains: "coach", name: "started")
        )
    }

    func testDoesNotMatchWhenNameMissing() {
        let label = #"[{"c":"workout","n":"started","s":"info"}]"#
        XCTAssertFalse(
            VolumeArcAppUITestSupport.telemetryLabel(label, contains: "workout", name: "completed")
        )
    }

    func testEmptyLabelReturnsFalse() {
        XCTAssertFalse(
            VolumeArcAppUITestSupport.telemetryLabel("", contains: "workout", name: "started")
        )
    }

    func testEmptyArrayReturnsFalse() {
        XCTAssertFalse(
            VolumeArcAppUITestSupport.telemetryLabel("[]", contains: "workout", name: "started")
        )
    }

    func testNonJSONLabelReturnsFalse() {
        XCTAssertFalse(
            VolumeArcAppUITestSupport.telemetryLabel("not-json", contains: "workout", name: "started")
        )
    }

    func testWrongShapeReturnsFalse() {
        // Probe schema requires top-level array of dicts. A bare dict
        // means somebody changed the encoder and forgot to update the
        // matcher; the test pins the contract.
        let label = #"{"c":"workout","n":"started","s":"info"}"#
        XCTAssertFalse(
            VolumeArcAppUITestSupport.telemetryLabel(label, contains: "workout", name: "started")
        )
    }

    func testCaseSensitive() {
        // Category / name matching is exact — uppercase variants
        // shouldn't match. Pinned because telemetry event names are
        // canonically lowercase + dot-separated.
        let label = #"[{"c":"Workout","n":"Started","s":"info"}]"#
        XCTAssertFalse(
            VolumeArcAppUITestSupport.telemetryLabel(label, contains: "workout", name: "started")
        )
    }
}
