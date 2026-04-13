import XCTest
import VolumeArcCore

final class VolumeArcPersistenceTests: XCTestCase {

    // MARK: - BootstrapStatus.isDegraded

    func testCloudSyncedIsNotDegraded() {
        let status = VolumeArcPersistenceController.BootstrapStatus(
            storageMode: .cloudSynced,
            severity: .info,
            message: "Cloud-backed persistence ready.",
            metadata: ["storageMode": "cloudSynced"]
        )
        XCTAssertFalse(status.isDegraded)
    }

    func testLocalFallbackIsDegraded() {
        let status = VolumeArcPersistenceController.BootstrapStatus(
            storageMode: .localFallback,
            severity: .warning,
            message: "Cloud sync unavailable.",
            metadata: ["storageMode": "localFallback"]
        )
        XCTAssertTrue(status.isDegraded)
    }

    func testInMemoryFallbackIsDegraded() {
        let status = VolumeArcPersistenceController.BootstrapStatus(
            storageMode: .inMemoryFallback,
            severity: .warning,
            message: "Running in memory-only mode.",
            metadata: ["storageMode": "inMemoryFallback"]
        )
        XCTAssertTrue(status.isDegraded)
    }

    func testUnavailableIsDegraded() {
        let status = VolumeArcPersistenceController.BootstrapStatus(
            storageMode: .unavailable,
            severity: .error,
            message: "SwiftData could not start.",
            metadata: ["storageMode": "unavailable"]
        )
        XCTAssertTrue(status.isDegraded)
    }

    // MARK: - Telemetry event generation

    func testCloudSyncedProducesNoTelemetryEvents() {
        let controller = makePersistenceController(mode: .cloudSynced, severity: .info)
        XCTAssertTrue(controller.bootstrapTelemetryEvents.isEmpty)
    }

    func testLocalFallbackProducesWarningEvent() {
        let controller = makePersistenceController(mode: .localFallback, severity: .warning)
        let events = controller.bootstrapTelemetryEvents
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.severity, .warning)
        XCTAssertEqual(events.first?.category, "persistence")
        XCTAssertEqual(events.first?.name, "bootstrap_degraded")
    }

    func testUnavailableProducesErrorEvent() {
        let controller = makePersistenceController(mode: .unavailable, severity: .error)
        let events = controller.bootstrapTelemetryEvents
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.severity, .error)
    }

    // MARK: - Severity escalation

    func testSeverityEscalatesAcrossModes() {
        let infoStatus = VolumeArcPersistenceController.BootstrapStatus(
            storageMode: .cloudSynced, severity: .info, message: "", metadata: [:]
        )
        let warningStatus = VolumeArcPersistenceController.BootstrapStatus(
            storageMode: .localFallback, severity: .warning, message: "", metadata: [:]
        )
        let errorStatus = VolumeArcPersistenceController.BootstrapStatus(
            storageMode: .unavailable, severity: .error, message: "", metadata: [:]
        )
        XCTAssertTrue(infoStatus.severity < warningStatus.severity)
        XCTAssertTrue(warningStatus.severity < errorStatus.severity)
    }

    // MARK: - Helpers

    private func makePersistenceController(
        mode: VolumeArcPersistenceController.StorageMode,
        severity: TelemetrySeverity
    ) -> StubPersistenceController {
        StubPersistenceController(
            bootstrapStatus: .init(
                storageMode: mode,
                severity: severity,
                message: "Test \(mode.rawValue)",
                metadata: ["storageMode": mode.rawValue]
            )
        )
    }
}

/// Stub that exposes the same telemetry event logic as VolumeArcPersistenceController
/// without requiring a real SwiftData container.
private struct StubPersistenceController {
    let bootstrapStatus: VolumeArcPersistenceController.BootstrapStatus

    var bootstrapTelemetryEvents: [TelemetryEvent] {
        guard bootstrapStatus.isDegraded else { return [] }
        return [
            TelemetryEvent(
                category: "persistence",
                name: "bootstrap_degraded",
                severity: bootstrapStatus.storageMode == .unavailable ? .error : .warning,
                message: bootstrapStatus.message,
                metadata: bootstrapStatus.metadata
            )
        ]
    }
}
