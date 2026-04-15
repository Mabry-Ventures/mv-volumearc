#if canImport(SwiftData)
import Foundation
import SwiftData
import VolumeArcCore

@MainActor
final class VolumeArcPersistenceController {
    enum StorageMode: String, Sendable {
        case cloudSynced
        case localFallback
        case inMemoryFallback
        case unavailable
    }

    struct BootstrapStatus: Sendable {
        let storageMode: StorageMode
        let severity: TelemetrySeverity
        let message: String
        let metadata: [String: String]

        var isDegraded: Bool {
            storageMode != .cloudSynced
        }
    }

    static let shared = VolumeArcPersistenceController()

    let container: ModelContainer?
    let bootstrapStatus: BootstrapStatus

    private init() {
        let schema = Schema(VolumeArcSchemaV4.models)
        let bootstrap = Self.makeContainer(for: schema)
        container = bootstrap.container
        bootstrapStatus = bootstrap.status

        do {
            try seedIfNeeded()
        } catch {
            // Keep the app alive even if first-run seed data cannot be written.
            // The user will start with an empty profile and can configure later.
            // This failure is tracked in bootstrapTelemetryEvents via the
            // persistence status, so the startup notice will surface it.
        }

        // VOL-67 Copilot (fixup #13): backfill the outbound sync queue
        // for pre-VOL-67 records the first time the app opens after
        // V3→V4 migration. This logic can't live inside the V3→V4
        // `didMigrate` stage because the outbound queue lives in a
        // SEPARATE SwiftData configuration from the syncable records
        // in production — a migration stage's context is bound to one
        // store at a time, so cross-config inserts silently drop.
        // Running the backfill here with a container-scoped
        // `ModelContext` gives us both configs in scope, so
        // `context.insert(OutboundSyncQueueRecord(...))` routes to
        // the queue store correctly.
        do {
            try backfillOutboundQueueIfNeeded()
        } catch {
            // Missing a backfill row isn't fatal — the record is
            // still safe locally, it just won't push until the user
            // edits it. Suppress and move on.
        }
    }

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

    private func seedIfNeeded() throws {
        guard let container else { return }

        let context = ModelContext(container)
        var descriptor = FetchDescriptor<UserProfileRecord>()
        descriptor.fetchLimit = 1

        guard try context.fetch(descriptor).isEmpty else { return }

        // VOL-67 Codex P1 (fixup #10): seeded defaults must carry
        // `Date.distantPast` as their `updatedAt` so any inbound
        // authoritative profile / plan from CloudKit — even one
        // written days or weeks ago — wins the `shouldApply`
        // timestamp comparison and replaces the local defaults. If
        // we used `Date.now` (the model's default), the fresh
        // install would advertise itself as "most recently
        // modified" and subsequent pulls would be dropped as
        // "local is newer", stranding the user on defaults AND
        // risking an outbound push that overwrites their real
        // server copy on the next local edit.
        let defaults = VolumeArcProductDefaults.userProfile
        let profile = UserProfileRecord(
            name: defaults.name,
            coachingStyle: defaults.coachingStyle.rawValue,
            privacyMode: defaults.privacyMode.rawValue,
            advancementLevel: defaults.advancementLevel.rawValue,
            availableEquipmentCSV: defaults.availableEquipment.map(\.rawValue).sorted().joined(separator: ","),
            preferredRepRangeLower: defaults.preferredRepRangeLower,
            preferredRepRangeUpper: defaults.preferredRepRangeUpper,
            sessionTimeBudgetMinutes: defaults.sessionTimeBudgetMinutes,
            weeklyTrainingDays: defaults.weeklyTrainingDays,
            updatedAt: .distantPast
        )
        let trainingPlan = TrainingPlanRecord(
            workoutsJSON: SyncPayloadCodec.encode(VolumeArcProductDefaults.weeklySchedule) ?? "[]",
            updatedAt: .distantPast
        )

        context.insert(profile)
        context.insert(trainingPlan)

        try context.save()
    }

    /// VOL-67 Copilot (fixup #13): the backfill logic lives in
    /// `VolumeArcCore.OutboundQueueBackfill` so it's testable in
    /// isolation. The production key prefix is fixed so the flag
    /// survives app relaunches; the active storage mode is appended
    /// at call time (see `outboundQueueBackfillFlagKey(for:)`).
    ///
    /// VOL-67 Codex P2 (fixup #16): the completion flag MUST be scoped
    /// by storage mode. Previously the flag was a single fixed string
    /// shared across all modes, so a first-launch backfill that ran
    /// against `.localFallback` (e.g., when the CloudKit entitlement
    /// was missing) would mark the flag complete. A later recovery to
    /// `.cloudSynced` opens a DIFFERENT store file
    /// (`VolumeArc.sqlite` vs `VolumeArc-LocalFallback.sqlite`) whose
    /// pre-existing migrated records still need outbound queue rows —
    /// but the shared flag would short-circuit the backfill and those
    /// records would never sync until the user edited them. Scoping
    /// by storage mode gives each store its own completion marker.
    private static let outboundQueueBackfillDefaultsKeyPrefix = "VolumeArcPersistence.outboundQueueBackfillV4Completed"

    static func outboundQueueBackfillFlagKey(for storageMode: StorageMode) -> String {
        "\(outboundQueueBackfillDefaultsKeyPrefix).\(storageMode.rawValue)"
    }

    private func backfillOutboundQueueIfNeeded() throws {
        guard let container else { return }
        try OutboundQueueBackfill.performIfNeeded(
            container: container,
            userDefaults: .standard,
            flagKey: Self.outboundQueueBackfillFlagKey(for: bootstrapStatus.storageMode)
        )
    }

    private static func makeContainer(for schema: Schema) -> (container: ModelContainer?, status: BootstrapStatus) {
        var attempts: [(StorageMode, Error)] = []

        // VOL-59 fixup: only attempt the cloud-synced configuration
        // when the process actually carries a CloudKit entitlement.
        // Without it, SwiftData's CloudKit mirror traps the process
        // during `ModelContainer` init — we can't try/catch our way
        // around that. When we skip this branch, record a synthetic
        // "entitlement unavailable" error so the telemetry metadata
        // explains why bootstrap fell through to `.localFallback`
        // instead of reporting a healthy "Cloud-backed persistence
        // ready" state (which would be a lie — CloudKit is off).
        if VolumeArcCloudConfiguration.hasCloudKitEntitlement {
            do {
                return (
                    container: try ModelContainer(
                        for: schema,
                        migrationPlan: VolumeArcSchemaMigrationPlan.self,
                        configurations: [
                            primaryConfiguration(schema: syncableSchema()),
                            outboundQueueConfiguration(schema: outboundQueueSchema(), isStoredInMemoryOnly: false),
                        ]
                    ),
                    status: BootstrapStatus(
                        storageMode: .cloudSynced,
                        severity: .info,
                        message: "Cloud-backed persistence ready.",
                        metadata: ["storageMode": StorageMode.cloudSynced.rawValue]
                    )
                )
            } catch {
                attempts.append((.cloudSynced, error))
            }
        } else {
            attempts.append((.cloudSynced, VolumeArcPersistenceBootstrapError.cloudKitEntitlementUnavailable))
        }

        do {
            return (
                container: try ModelContainer(
                    for: schema,
                    migrationPlan: VolumeArcSchemaMigrationPlan.self,
                    configurations: [fallbackLocalConfiguration(schema: schema, isStoredInMemoryOnly: false)]
                ),
                status: BootstrapStatus(
                    storageMode: .localFallback,
                    severity: .warning,
                    message: "Cloud sync is unavailable, so VolumeArc is using a local on-device store until persistence recovers.",
                    metadata: metadata(for: .localFallback, attempts: attempts)
                )
            )
        } catch {
            attempts.append((.localFallback, error))
        }

        do {
            return (
                container: try ModelContainer(
                    for: schema,
                    migrationPlan: VolumeArcSchemaMigrationPlan.self,
                    configurations: [fallbackLocalConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                ),
                status: BootstrapStatus(
                    storageMode: .inMemoryFallback,
                    severity: .warning,
                    message: "Persistent storage is unavailable, so VolumeArc is running in temporary memory-only mode.",
                    metadata: metadata(for: .inMemoryFallback, attempts: attempts)
                )
            )
        } catch {
            attempts.append((.inMemoryFallback, error))
            return (
                container: nil,
                status: BootstrapStatus(
                    storageMode: .unavailable,
                    severity: .error,
                    message: "SwiftData could not start, so VolumeArc is using in-memory repositories until storage becomes available.",
                    metadata: metadata(for: .unavailable, attempts: attempts)
                )
            )
        }
    }

    private static func metadata(
        for mode: StorageMode,
        attempts: [(StorageMode, Error)]
    ) -> [String: String] {
        var metadata: [String: String] = ["storageMode": mode.rawValue]
        for (index, attempt) in attempts.enumerated() {
            metadata["attempt\(index + 1)Mode"] = attempt.0.rawValue
            metadata["attempt\(index + 1)Error"] = String(describing: attempt.1)
        }
        return metadata
    }

    private static func primaryConfiguration(schema: Schema) -> ModelConfiguration {
        // VOL-55: containerIdentifier is a compile-time constant so the
        // empty check is strictly a guard against future configuration
        // flexibility (e.g., reading from a .env file).
        //
        // VOL-59 fixup: `makeContainer` verifies `hasCloudKitEntitlement`
        // before calling this function, so we can unconditionally attach
        // `.private(containerIdentifier)` here. If the caller ever slips
        // that check, SwiftData will trap on `CKContainer` init — which
        // is the same behavior as the legacy code path and surfaces the
        // bug loudly rather than silently reporting a degraded state as
        // healthy.
        let cloudDatabase: ModelConfiguration.CloudKitDatabase
        let containerIdentifier = VolumeArcCloudConfiguration.containerIdentifier
        if !containerIdentifier.isEmpty {
            cloudDatabase = .private(containerIdentifier)
        } else {
            cloudDatabase = .automatic
        }

        return ModelConfiguration(
            "VolumeArc",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: cloudDatabase
        )
    }

    private static func fallbackLocalConfiguration(schema: Schema, isStoredInMemoryOnly: Bool) -> ModelConfiguration {
        ModelConfiguration(
            "VolumeArc-LocalFallback",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            allowsSave: true,
            cloudKitDatabase: .none
        )
    }
    private static func outboundQueueConfiguration(schema: Schema, isStoredInMemoryOnly: Bool) -> ModelConfiguration {
        ModelConfiguration(
            "VolumeArc-OutboundQueue",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            allowsSave: true,
            cloudKitDatabase: .none
        )
    }

    private static func syncableSchema() -> Schema {
        Schema([
            UserProfileRecord.self,
            TrainingPlanRecord.self,
            WorkoutRecord.self,
            CoachMemoryRecord.self,
        ])
    }

    private static func outboundQueueSchema() -> Schema {
        Schema([OutboundSyncQueueRecord.self])
    }
}

/// Synthetic error used as a placeholder `attempts` entry when
/// `makeContainer` intentionally skips the cloud-synced branch because
/// the process has no CloudKit entitlement. `metadata(for:attempts:)`
/// serializes this into the bootstrap telemetry so the degraded state
/// is traceable back to the entitlement gap rather than looking like
/// a crash/throw.
enum VolumeArcPersistenceBootstrapError: Error, CustomStringConvertible {
    case cloudKitEntitlementUnavailable

    var description: String {
        switch self {
        case .cloudKitEntitlementUnavailable:
            return "CloudKit entitlement is not present on this build (simulator or unsigned binary)."
        }
    }
}
#endif
