import XCTest
import VolumeArcCore

/// Tests for `VolumeArcPersistenceController.BootstrapStatus` and telemetry
/// event generation. Uses the real production type — no surrogate.
final class VolumeArcPersistenceTests: XCTestCase {

    // MARK: - BootstrapStatus.isDegraded

    func testCloudSyncedIsNotDegraded() {
        let status = makeStatus(mode: .cloudSynced, severity: .info)
        XCTAssertFalse(status.isDegraded)
    }

    func testLocalFallbackIsDegraded() {
        let status = makeStatus(mode: .localFallback, severity: .warning)
        XCTAssertTrue(status.isDegraded)
    }

    func testInMemoryFallbackIsDegraded() {
        let status = makeStatus(mode: .inMemoryFallback, severity: .warning)
        XCTAssertTrue(status.isDegraded)
    }

    func testUnavailableIsDegraded() {
        let status = makeStatus(mode: .unavailable, severity: .error)
        XCTAssertTrue(status.isDegraded)
    }

    // MARK: - Real shared controller produces a valid status

    @MainActor
    func testSharedControllerProducesValidBootstrapStatus() {
        let controller = VolumeArcPersistenceController.shared
        let status = controller.bootstrapStatus

        // Whatever mode the controller ended up in, the status must be
        // internally consistent: severity must match degraded-ness, message
        // must be non-empty, and metadata must contain the storageMode key.
        XCTAssertFalse(status.message.isEmpty)
        XCTAssertNotNil(status.metadata["storageMode"])

        if status.isDegraded {
            XCTAssertNotEqual(status.severity, .info)
        } else {
            XCTAssertEqual(status.severity, .info)
        }
    }

    @MainActor
    func testBootstrapTelemetryEventsEmitDegradedMessageForFallback() {
        // The shared controller may be healthy or degraded depending on the
        // test environment. If degraded, exactly one event should be emitted.
        let controller = VolumeArcPersistenceController.shared
        let events = controller.bootstrapTelemetryEvents

        if controller.bootstrapStatus.isDegraded {
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.category, "persistence")
            XCTAssertEqual(events.first?.name, "bootstrap_degraded")
            XCTAssertEqual(events.first?.message, controller.bootstrapStatus.message)
        } else {
            XCTAssertTrue(events.isEmpty)
        }
    }

    // MARK: - Severity ordering

    func testSeverityEscalatesAcrossModes() {
        XCTAssertTrue(TelemetrySeverity.info < .warning)
        XCTAssertTrue(TelemetrySeverity.warning < .error)
    }

    // MARK: - Helpers

    private func makeStatus(
        mode: VolumeArcPersistenceController.StorageMode,
        severity: TelemetrySeverity
    ) -> VolumeArcPersistenceController.BootstrapStatus {
        VolumeArcPersistenceController.BootstrapStatus(
            storageMode: mode,
            severity: severity,
            message: "Test \(mode.rawValue)",
            metadata: ["storageMode": mode.rawValue]
        )
    }
}
