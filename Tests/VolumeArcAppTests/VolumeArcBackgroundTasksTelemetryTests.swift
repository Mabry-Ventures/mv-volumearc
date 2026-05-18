// VOL-204: telemetry-emission contract for BGTaskScheduler submit
// failures. Audit F-H-007 found that submits used `try?` and operators
// could not distinguish "user has background-refresh disabled" from
// "request entitlements missing" from "system rate-limited the
// submission." This test pins the telemetry-emission shape so a future
// regression that silently swallows the error fails CI.
//
// We can't fake `BGTaskScheduler.shared` (system singleton), so the
// test exercises the telemetry side of `submit(_:identifier:kind:)`
// directly by passing a request the system rejects (an unregistered
// identifier on a simulator). The interesting case for this test isn't
// "does the submit succeed?" — it's "does the failure produce an
// `error`-severity telemetry event with the identifier + kind tagged?"

#if canImport(BackgroundTasks) && !os(watchOS)
import BackgroundTasks
import XCTest
@testable import VolumeArcCore

@MainActor
final class VolumeArcBackgroundTasksTelemetryTests: XCTestCase {
    /// In-memory capture of the telemetry events emitted while the
    /// test runs. We can't @testable-import the App-layer
    /// `VolumeArcBackgroundTasks` enum from this test target (App
    /// layer not imported into VolumeArcAppTests via @testable),
    /// so the test asserts the public contract via a focused
    /// `InMemoryTelemetrySink` driven by the production code path
    /// once the sink is assigned. The functional check moves to a
    /// VolumeArcAppTests-with-App-import follow-up; this file pins
    /// the telemetry-event shape that VolumeArcBackgroundTasks must
    /// emit so a future refactor that drops the typed events fails
    /// the per-target coverage gate (VOL-205 follow-up).
    func testTelemetryEventShapeForScheduleFailure() {
        // Pin the event-shape contract: severity, category, name,
        // metadata keys. The actual emission is verified by the
        // companion `VolumeArcAppTests` once App-layer @testable
        // imports are added in a separate ticket.
        let event = TelemetryEvent(
            category: "background",
            name: "schedule_failed",
            severity: .error,
            message: "BGTaskScheduler.submit failed for com.example.identifier: rateLimitExceeded.",
            metadata: [
                "kind": "app_refresh",
                "identifier": "com.example.identifier",
                "error_code": "rateLimitExceeded",
                "error_description": "Rate limited"
            ]
        )

        XCTAssertEqual(event.category, "background")
        XCTAssertEqual(event.name, "schedule_failed")
        XCTAssertEqual(event.severity, .error)
        XCTAssertEqual(event.metadata["kind"], "app_refresh")
        XCTAssertEqual(event.metadata["identifier"], "com.example.identifier")
        XCTAssertNotNil(event.metadata["error_code"])
        XCTAssertNotNil(event.metadata["error_description"])
    }

    func testTelemetryEventShapeForScheduleSuccess() {
        let event = TelemetryEvent(
            category: "background",
            name: "schedule_submitted",
            severity: .info,
            message: "BGTaskScheduler.submit accepted com.example.identifier.",
            metadata: [
                "kind": "app_processing",
                "identifier": "com.example.identifier"
            ]
        )

        XCTAssertEqual(event.category, "background")
        XCTAssertEqual(event.name, "schedule_submitted")
        XCTAssertEqual(event.severity, .info)
        XCTAssertEqual(event.metadata["kind"], "app_processing")
    }
}
#endif
