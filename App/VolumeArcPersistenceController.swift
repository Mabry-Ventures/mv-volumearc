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
        let schema = Schema(VolumeArcSchemaV3.models)
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
            weeklyTrainingDays: defaults.weeklyTrainingDays
        )
        let trainingPlan = TrainingPlanRecord(
            workoutsJSON: SyncPayloadCodec.encode(VolumeArcProductDefaults.weeklySchedule) ?? "[]"
        )

        context.insert(profile)
        context.insert(trainingPlan)

        try context.save()
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
                        configurations: [primaryConfiguration(schema: schema)]
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
                    configurations: [fallbackLocalConfiguration(schema: schema)]
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
                    configurations: [inMemoryConfiguration(schema: schema)]
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

    private static func fallbackLocalConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            "VolumeArc-LocalFallback",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )
    }

    private static func inMemoryConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            "VolumeArc-InMemoryFallback",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
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
