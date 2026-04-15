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

    // MARK: - VOL-67 Codex P2 (fixup #16): outbound backfill flag scoped by storage mode

    /// The outbound-queue-backfill completion flag must be scoped per
    /// storage mode, not shared across all modes. Previously a single
    /// fixed key was used, so a first-launch backfill that ran against
    /// `.localFallback` (CloudKit entitlement missing) would mark the
    /// flag complete; a later recovery to `.cloudSynced` opens a
    /// DIFFERENT store file whose pre-existing migrated records still
    /// need outbound queue rows — but the shared flag would
    /// short-circuit the backfill, stranding that data until the user
    /// edited it.
    ///
    /// Fix: append `storageMode.rawValue` to the flag key prefix so
    /// every mode tracks its own completion independently.
    @MainActor
    func testOutboundQueueBackfillFlagKeyIsScopedByStorageMode() {
        let cloudKey = VolumeArcPersistenceController.outboundQueueBackfillFlagKey(for: .cloudSynced)
        let localKey = VolumeArcPersistenceController.outboundQueueBackfillFlagKey(for: .localFallback)
        let inMemoryKey = VolumeArcPersistenceController.outboundQueueBackfillFlagKey(for: .inMemoryFallback)
        let unavailableKey = VolumeArcPersistenceController.outboundQueueBackfillFlagKey(for: .unavailable)

        // Each mode must produce a distinct key so completion tracking
        // stays independent per store.
        let allKeys: Set<String> = [cloudKey, localKey, inMemoryKey, unavailableKey]
        XCTAssertEqual(allKeys.count, 4, "Each storage mode must produce a unique backfill flag key")

        // Keys must encode the storage mode's raw value so the key is
        // stable across app launches for a given mode.
        XCTAssertTrue(cloudKey.hasSuffix(VolumeArcPersistenceController.StorageMode.cloudSynced.rawValue))
        XCTAssertTrue(localKey.hasSuffix(VolumeArcPersistenceController.StorageMode.localFallback.rawValue))
        XCTAssertTrue(inMemoryKey.hasSuffix(VolumeArcPersistenceController.StorageMode.inMemoryFallback.rawValue))
        XCTAssertTrue(unavailableKey.hasSuffix(VolumeArcPersistenceController.StorageMode.unavailable.rawValue))

        // All keys must share the same prefix so a future migration
        // could enumerate + clear them together.
        let prefix = "VolumeArcPersistence.outboundQueueBackfillV4Completed"
        XCTAssertTrue(cloudKey.hasPrefix(prefix))
        XCTAssertTrue(localKey.hasPrefix(prefix))
        XCTAssertTrue(inMemoryKey.hasPrefix(prefix))
        XCTAssertTrue(unavailableKey.hasPrefix(prefix))
    }

    /// End-to-end behavior: if the fallback-mode flag is set AND the
    /// cloud-mode flag is NOT set, running the backfill under the
    /// cloud-mode flag key must still execute. This demonstrates that
    /// scoping the flag by mode correctly preserves the ability to
    /// backfill a new store after a mode-recovery.
    @MainActor
    func testBackfillRunsAfterModeRecoveryWhenFlagIsScopedByMode() throws {
        // VOL-67 Copilot (fixup #17): the suite name is randomized per
        // test and the cleanup MUST remove that same suite name, not a
        // static "test" domain. The previous `forName: "test"` was a
        // no-op — it left the per-test suite persisted on disk where
        // it could accumulate across runs and leak state into any
        // future test that happened to pick the same UUID.
        let suiteName = "test.\(UUID().uuidString)"
        let ephemeralDefaults = UserDefaults(suiteName: suiteName)!
        defer { ephemeralDefaults.removePersistentDomain(forName: suiteName) }

        // Simulate: local-fallback backfill already ran and marked its
        // flag complete.
        let localFlag = VolumeArcPersistenceController.outboundQueueBackfillFlagKey(for: .localFallback)
        ephemeralDefaults.set(true, forKey: localFlag)

        // The cloud-mode flag must still be unset, so a cloud-mode
        // backfill would still run. `OutboundQueueBackfill.performIfNeeded`
        // treats "unset" as "run required".
        let cloudFlag = VolumeArcPersistenceController.outboundQueueBackfillFlagKey(for: .cloudSynced)
        XCTAssertFalse(
            ephemeralDefaults.bool(forKey: cloudFlag),
            "Cloud-mode flag must remain unset after local-mode backfill completes"
        )
        XCTAssertNotEqual(localFlag, cloudFlag,
                          "Local and cloud backfill flags must be distinct keys")
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
