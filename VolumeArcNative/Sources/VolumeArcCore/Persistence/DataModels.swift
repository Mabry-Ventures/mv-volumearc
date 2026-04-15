#if canImport(SwiftData)
import CryptoKit
import Foundation
import SwiftData

// VOL-55 follow-up: every `@Model` property needs a default value when
// SwiftData's CloudKit integration is enabled. Without defaults, the
// store fails to load at launch with:
//
//   "CloudKit integration requires that all attributes be optional, or
//    have a default value set."
//
// Previously this constraint was silently bypassed because the CloudKit
// container wasn't configured in the bundle (Info.plist was missing
// `VolumeArcCloudKitContainer`), so SwiftData fell back to
// `.automatic` cloud database and the defaults check never ran. Now that
// VOL-55 hardcodes the container ID as a Swift constant, CloudKit is
// actually active, and every non-optional property must have a default.

@Model
public final class UserProfileRecord {
    public var name: String = ""
    public var coachingStyle: String = "motivational"
    public var privacyMode: String = "standard"
    public var advancementLevel: String = "intermediate"
    public var availableEquipmentCSV: String = ""
    public var preferredRepRangeLower: Int = 5
    public var preferredRepRangeUpper: Int = 8
    public var sessionTimeBudgetMinutes: Int = 60
    public var weeklyTrainingDays: Int = 4
    public var onboardingCompleted: Bool = false
    // @Model macro rejects `.now` shorthand; must fully qualify.
    public var updatedAt: Date = Date()

    public init(
        name: String = "",
        coachingStyle: String = "motivational",
        privacyMode: String = "standard",
        advancementLevel: String = "intermediate",
        availableEquipmentCSV: String = "",
        preferredRepRangeLower: Int = 5,
        preferredRepRangeUpper: Int = 8,
        sessionTimeBudgetMinutes: Int = 60,
        weeklyTrainingDays: Int = 4,
        onboardingCompleted: Bool = false,
        updatedAt: Date = .now
    ) {
        self.name = name
        self.coachingStyle = coachingStyle
        self.privacyMode = privacyMode
        self.advancementLevel = advancementLevel
        self.availableEquipmentCSV = availableEquipmentCSV
        self.preferredRepRangeLower = preferredRepRangeLower
        self.preferredRepRangeUpper = preferredRepRangeUpper
        self.sessionTimeBudgetMinutes = sessionTimeBudgetMinutes
        self.weeklyTrainingDays = weeklyTrainingDays
        self.onboardingCompleted = onboardingCompleted
        self.updatedAt = updatedAt
    }
}

@Model
public final class TrainingPlanRecord {
    public var workoutsJSON: String = "[]"
    public var updatedAt: Date = Date()

    public init(workoutsJSON: String = "[]", updatedAt: Date = .now) {
        self.workoutsJSON = workoutsJSON
        self.updatedAt = updatedAt
    }
}

@Model
public final class WorkoutRecord {
    public var identifier: String = ""
    public var title: String = ""
    public var startedAt: Date = Date()
    public var completedAt: Date?
    public var durationMinutes: Int = 0
    public var exerciseIDsCSV: String = ""
    public var setsJSON: String = "[]"
    public var totalVolumeLoad: Double = 0
    public var averageRPE: Double = 0
    public var completedSetCount: Int = 0
    public var summary: String = ""
    public var updatedAt: Date = Date()

    public init(
        identifier: String = UUID().uuidString,
        title: String = "",
        startedAt: Date = .now,
        completedAt: Date? = nil,
        durationMinutes: Int = 0,
        exerciseIDsCSV: String = "",
        setsJSON: String = "[]",
        totalVolumeLoad: Double = 0,
        averageRPE: Double = 0,
        completedSetCount: Int = 0,
        summary: String = "",
        updatedAt: Date = .now
    ) {
        self.identifier = identifier
        self.title = title
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMinutes = durationMinutes
        self.exerciseIDsCSV = exerciseIDsCSV
        self.setsJSON = setsJSON
        self.totalVolumeLoad = totalVolumeLoad
        self.averageRPE = averageRPE
        self.completedSetCount = completedSetCount
        self.summary = summary
        self.updatedAt = updatedAt
    }
}

@Model
public final class CoachMemoryRecord {
    public var identifier: String = ""
    public var content: String = ""
    public var theme: String = ""
    public var createdAt: Date = Date()

    public init(
        identifier: String = UUID().uuidString,
        content: String = "",
        theme: String = "",
        createdAt: Date = .now
    ) {
        self.identifier = identifier
        self.content = content
        self.theme = theme
        self.createdAt = createdAt
    }
}

public enum VolumeArcSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    @Model
    public final class UserProfileRecord {
        public var name: String
        public var coachingStyle: String
        public var privacyMode: String
        public var advancementLevel: String
        public var availableEquipmentCSV: String
        public var preferredRepRangeLower: Int
        public var preferredRepRangeUpper: Int
        public var sessionTimeBudgetMinutes: Int
        public var weeklyTrainingDays: Int
        public var onboardingCompleted: Bool
        public var updatedAt: Date

        public init(
            name: String, coachingStyle: String, privacyMode: String,
            advancementLevel: String, availableEquipmentCSV: String,
            preferredRepRangeLower: Int, preferredRepRangeUpper: Int,
            sessionTimeBudgetMinutes: Int, weeklyTrainingDays: Int,
            onboardingCompleted: Bool = false,
            updatedAt: Date = .now
        ) {
            self.name = name
            self.coachingStyle = coachingStyle
            self.privacyMode = privacyMode
            self.advancementLevel = advancementLevel
            self.availableEquipmentCSV = availableEquipmentCSV
            self.preferredRepRangeLower = preferredRepRangeLower
            self.preferredRepRangeUpper = preferredRepRangeUpper
            self.sessionTimeBudgetMinutes = sessionTimeBudgetMinutes
            self.weeklyTrainingDays = weeklyTrainingDays
            self.onboardingCompleted = onboardingCompleted
            self.updatedAt = updatedAt
        }
    }

    /// Frozen V1 shape for the last supported pre-migration store.
    /// The launch-blocking persisted shape delta is that V1 training plans did not
    /// have `updatedAt`, while V2 backfills it with the model default.
    @Model
    public final class TrainingPlanRecord {
        public var workoutsJSON: String

        public init(workoutsJSON: String) {
            self.workoutsJSON = workoutsJSON
        }
    }

    @Model
    public final class WorkoutRecord {
        public var identifier: String
        public var title: String
        public var startedAt: Date
        public var completedAt: Date?
        public var durationMinutes: Int
        public var exerciseIDsCSV: String
        public var setsJSON: String
        public var totalVolumeLoad: Double
        public var averageRPE: Double
        public var completedSetCount: Int
        public var summary: String

        public init(
            identifier: String = UUID().uuidString,
            title: String,
            startedAt: Date = .now,
            completedAt: Date? = nil,
            durationMinutes: Int = 0,
            exerciseIDsCSV: String = "",
            setsJSON: String = "[]",
            totalVolumeLoad: Double = 0,
            averageRPE: Double = 0,
            completedSetCount: Int = 0,
            summary: String = ""
        ) {
            self.identifier = identifier
            self.title = title
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.durationMinutes = durationMinutes
            self.exerciseIDsCSV = exerciseIDsCSV
            self.setsJSON = setsJSON
            self.totalVolumeLoad = totalVolumeLoad
            self.averageRPE = averageRPE
            self.completedSetCount = completedSetCount
            self.summary = summary
        }
    }

    @Model
    public final class CoachMemoryRecord {
        public var content: String
        public var theme: String
        public var createdAt: Date

        public init(content: String, theme: String = "", createdAt: Date = .now) {
            self.content = content
            self.theme = theme
            self.createdAt = createdAt
        }
    }

    public static var models: [any PersistentModel.Type] {
        [UserProfileRecord.self, TrainingPlanRecord.self, WorkoutRecord.self, CoachMemoryRecord.self]
    }
}

public enum VolumeArcSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    @Model
    public final class UserProfileRecord {
        public var name: String
        public var coachingStyle: String
        public var privacyMode: String
        public var advancementLevel: String
        public var availableEquipmentCSV: String
        public var preferredRepRangeLower: Int
        public var preferredRepRangeUpper: Int
        public var sessionTimeBudgetMinutes: Int
        public var weeklyTrainingDays: Int
        public var onboardingCompleted: Bool
        public var updatedAt: Date

        public init(
            name: String, coachingStyle: String, privacyMode: String,
            advancementLevel: String, availableEquipmentCSV: String,
            preferredRepRangeLower: Int, preferredRepRangeUpper: Int,
            sessionTimeBudgetMinutes: Int, weeklyTrainingDays: Int,
            onboardingCompleted: Bool = false,
            updatedAt: Date = .now
        ) {
            self.name = name
            self.coachingStyle = coachingStyle
            self.privacyMode = privacyMode
            self.advancementLevel = advancementLevel
            self.availableEquipmentCSV = availableEquipmentCSV
            self.preferredRepRangeLower = preferredRepRangeLower
            self.preferredRepRangeUpper = preferredRepRangeUpper
            self.sessionTimeBudgetMinutes = sessionTimeBudgetMinutes
            self.weeklyTrainingDays = weeklyTrainingDays
            self.onboardingCompleted = onboardingCompleted
            self.updatedAt = updatedAt
        }
    }

    @Model
    public final class TrainingPlanRecord {
        public var workoutsJSON: String
        public var updatedAt: Date?

        public init(workoutsJSON: String, updatedAt: Date? = nil) {
            self.workoutsJSON = workoutsJSON
            self.updatedAt = updatedAt
        }
    }

    @Model
    public final class WorkoutRecord {
        public var identifier: String
        public var title: String
        public var startedAt: Date
        public var completedAt: Date?
        public var durationMinutes: Int
        public var exerciseIDsCSV: String
        public var setsJSON: String
        public var totalVolumeLoad: Double
        public var averageRPE: Double
        public var completedSetCount: Int
        public var summary: String

        public init(
            identifier: String = UUID().uuidString,
            title: String,
            startedAt: Date = .now,
            completedAt: Date? = nil,
            durationMinutes: Int = 0,
            exerciseIDsCSV: String = "",
            setsJSON: String = "[]",
            totalVolumeLoad: Double = 0,
            averageRPE: Double = 0,
            completedSetCount: Int = 0,
            summary: String = ""
        ) {
            self.identifier = identifier
            self.title = title
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.durationMinutes = durationMinutes
            self.exerciseIDsCSV = exerciseIDsCSV
            self.setsJSON = setsJSON
            self.totalVolumeLoad = totalVolumeLoad
            self.averageRPE = averageRPE
            self.completedSetCount = completedSetCount
            self.summary = summary
        }
    }

    @Model
    public final class CoachMemoryRecord {
        public var content: String
        public var theme: String
        public var createdAt: Date

        public init(content: String, theme: String = "", createdAt: Date = .now) {
            self.content = content
            self.theme = theme
            self.createdAt = createdAt
        }
    }

    public static var models: [any PersistentModel.Type] {
        [UserProfileRecord.self, TrainingPlanRecord.self, WorkoutRecord.self, CoachMemoryRecord.self]
    }
}

public enum VolumeArcSchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    @Model
    public final class UserProfileRecord {
        public var name: String = ""
        public var coachingStyle: String = "motivational"
        public var privacyMode: String = "standard"
        public var advancementLevel: String = "intermediate"
        public var availableEquipmentCSV: String = ""
        public var preferredRepRangeLower: Int = 5
        public var preferredRepRangeUpper: Int = 8
        public var sessionTimeBudgetMinutes: Int = 60
        public var weeklyTrainingDays: Int = 4
        public var onboardingCompleted: Bool = false
        public var updatedAt: Date = Date()

        public init(
            name: String = "",
            coachingStyle: String = "motivational",
            privacyMode: String = "standard",
            advancementLevel: String = "intermediate",
            availableEquipmentCSV: String = "",
            preferredRepRangeLower: Int = 5,
            preferredRepRangeUpper: Int = 8,
            sessionTimeBudgetMinutes: Int = 60,
            weeklyTrainingDays: Int = 4,
            onboardingCompleted: Bool = false,
            updatedAt: Date = .now
        ) {
            self.name = name
            self.coachingStyle = coachingStyle
            self.privacyMode = privacyMode
            self.advancementLevel = advancementLevel
            self.availableEquipmentCSV = availableEquipmentCSV
            self.preferredRepRangeLower = preferredRepRangeLower
            self.preferredRepRangeUpper = preferredRepRangeUpper
            self.sessionTimeBudgetMinutes = sessionTimeBudgetMinutes
            self.weeklyTrainingDays = weeklyTrainingDays
            self.onboardingCompleted = onboardingCompleted
            self.updatedAt = updatedAt
        }
    }

    @Model
    public final class TrainingPlanRecord {
        public var workoutsJSON: String = "[]"
        public var updatedAt: Date = Date()

        public init(workoutsJSON: String = "[]", updatedAt: Date = .now) {
            self.workoutsJSON = workoutsJSON
            self.updatedAt = updatedAt
        }
    }

    @Model
    public final class WorkoutRecord {
        public var identifier: String = ""
        public var title: String = ""
        public var startedAt: Date = Date()
        public var completedAt: Date?
        public var durationMinutes: Int = 0
        public var exerciseIDsCSV: String = ""
        public var setsJSON: String = "[]"
        public var totalVolumeLoad: Double = 0
        public var averageRPE: Double = 0
        public var completedSetCount: Int = 0
        public var summary: String = ""

        public init(
            identifier: String = UUID().uuidString,
            title: String = "",
            startedAt: Date = .now,
            completedAt: Date? = nil,
            durationMinutes: Int = 0,
            exerciseIDsCSV: String = "",
            setsJSON: String = "[]",
            totalVolumeLoad: Double = 0,
            averageRPE: Double = 0,
            completedSetCount: Int = 0,
            summary: String = ""
        ) {
            self.identifier = identifier
            self.title = title
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.durationMinutes = durationMinutes
            self.exerciseIDsCSV = exerciseIDsCSV
            self.setsJSON = setsJSON
            self.totalVolumeLoad = totalVolumeLoad
            self.averageRPE = averageRPE
            self.completedSetCount = completedSetCount
            self.summary = summary
        }
    }

    @Model
    public final class CoachMemoryRecord {
        public var content: String = ""
        public var theme: String = ""
        public var createdAt: Date = Date()

        public init(content: String = "", theme: String = "", createdAt: Date = .now) {
            self.content = content
            self.theme = theme
            self.createdAt = createdAt
        }
    }

    public static var models: [any PersistentModel.Type] {
        [UserProfileRecord.self, TrainingPlanRecord.self, WorkoutRecord.self, CoachMemoryRecord.self]
    }
}

public enum VolumeArcSchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            UserProfileRecord.self,
            TrainingPlanRecord.self,
            WorkoutRecord.self,
            CoachMemoryRecord.self,
            OutboundSyncQueueRecord.self,
        ]
    }
}

public enum VolumeArcSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [VolumeArcSchemaV1.self, VolumeArcSchemaV2.self, VolumeArcSchemaV3.self, VolumeArcSchemaV4.self]
    }

    public static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4]
    }

    private static let v1ToV2 = MigrationStage.custom(
        fromVersion: VolumeArcSchemaV1.self,
        toVersion: VolumeArcSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            let migratedPlans = try context.fetch(FetchDescriptor<VolumeArcSchemaV2.TrainingPlanRecord>())
            let backfillDate = Date()
            for plan in migratedPlans where plan.updatedAt == nil {
                plan.updatedAt = backfillDate
            }
            try context.save()
        }
    )

    private static let v2ToV3 = MigrationStage.lightweight(
        fromVersion: VolumeArcSchemaV2.self,
        toVersion: VolumeArcSchemaV3.self
    )

    private static let v3ToV4 = MigrationStage.custom(
        fromVersion: VolumeArcSchemaV3.self,
        toVersion: VolumeArcSchemaV4.self,
        willMigrate: nil,
        didMigrate: { context in
            // VOL-67 Codex P2 fixup #8: assign deterministic IDs to
            // pre-existing memories. `UUID().uuidString` would make
            // every device pick a different ID for the same logical
            // memory on upgrade, breaking cross-device delete
            // reconciliation. SHA256 over a stable `(createdAt,
            // content, theme)` triple gives the same ID on every
            // device for the same row.
            let migratedWorkouts = try context.fetch(FetchDescriptor<WorkoutRecord>())
            for workout in migratedWorkouts {
                workout.updatedAt = workout.completedAt ?? workout.startedAt
            }

            let migratedMemories = try context.fetch(FetchDescriptor<CoachMemoryRecord>())
            for memory in migratedMemories where memory.identifier.isEmpty {
                memory.identifier = deterministicLegacyMemoryIdentifier(
                    createdAt: memory.createdAt,
                    content: memory.content,
                    theme: memory.theme
                )
            }

            // VOL-67 Codex P1 fixup #17: clamp migrated singleton
            // `updatedAt` to `Date.distantPast`. Pre-fixup-#10 `seedIfNeeded`
            // set profile/plan defaults with a launch-time `Date()` value,
            // which then looks newer than older-but-authoritative cloud
            // data. `DefaultSyncPayloadApplier.shouldApply` uses strict
            // `localTimestamp > inboundTimestamp` for its "local newer"
            // branch, so the seeded defaults would win conflict
            // resolution against real cloud singletons that happened to
            // be written before the local install. Clamping to
            // `distantPast` makes the migrated local record lose every
            // shouldApply comparison against a real cloud record, so
            // any pull with real data overwrites the stale defaults.
            // Per-record kinds (workouts, memories) keep their real
            // timestamps because they reflect concrete user actions
            // and carry stable identifiers that don't collide across
            // devices. This mirrors the distantPast clamp already
            // applied to the outbound-queue backfill payload in
            // `OutboundQueueBackfill.performIfNeeded` (fixup #13) —
            // both layers must agree that migrated singletons are
            // lowest-priority state.
            let migratedProfiles = try context.fetch(FetchDescriptor<UserProfileRecord>())
            for profile in migratedProfiles {
                profile.updatedAt = .distantPast
            }

            let migratedPlans = try context.fetch(FetchDescriptor<TrainingPlanRecord>())
            for plan in migratedPlans {
                plan.updatedAt = .distantPast
            }

            try context.save()

            // VOL-67 Copilot (fixup #13): the outbound queue lives in
            // a SEPARATE SwiftData configuration from the syncable
            // models in production (see
            // `VolumeArcPersistenceController.makeContainer` — primary
            // store holds UserProfileRecord/etc, a distinct store
            // holds OutboundSyncQueueRecord). A custom migration stage's
            // `context` is bound to the store being migrated, so
            // `context.insert(OutboundSyncQueueRecord(...))` here would
            // silently drop the row — it can't route across config
            // boundaries. The queue backfill therefore lives in
            // `VolumeArcPersistenceController.backfillOutboundQueueIfNeeded`,
            // which runs post-bootstrap with a container-scoped
            // context that has both configs visible.
        }
    )

    /// Produce a stable identifier for a legacy coach memory based on
    /// its `(createdAt, content, theme)` triple. SHA256 gives the same
    /// 64-character hex string on every device that's migrating the
    /// same logical memory, so delete tombstones and queue
    /// invalidation can target the same record across devices after
    /// upgrade. VOL-67 Codex P2 (fixup #8).
    ///
    /// VOL-67 Codex P2 fixup #17: the hash input is length-prefixed
    /// so that different field values always produce different
    /// canonical strings. The original newline-delimited format was
    /// ambiguous when content/theme contained newlines — e.g.,
    /// `(content: "", theme: "foo\nbar")` and
    /// `(content: "\nfoo", theme: "bar")` both serialized to
    /// `"<millis>\n\nfoo\nbar"`, producing the same identifier for
    /// different memories. Length-prefixed encoding (`<bytes>:<data>`)
    /// eliminates every such collision because the parser always
    /// knows how many bytes belong to each field, so different
    /// inputs always produce different canonical strings.
    ///
    /// Also uses microsecond precision (`%.6f` format) instead of
    /// integer milliseconds to reduce the chance that two memories
    /// created within the same ms hash to the same identifier. The
    /// fixed-format string avoids `Int64(Double * N)` rounding drift
    /// that can produce different integers on different devices for
    /// the same `Date`.
    ///
    /// This hash scheme is a BREAKING change from fixup #8's format,
    /// but fixup #8 has never shipped to production — the migration
    /// lives on `sprint/phase3b-cloudkit-fresh` which hasn't merged.
    /// Both hashes land together in this PR, so no user ever sees
    /// the old-format identifier.
    fileprivate static func deterministicLegacyMemoryIdentifier(
        createdAt: Date,
        content: String,
        theme: String
    ) -> String {
        let timestamp = String(format: "%.6f", createdAt.timeIntervalSince1970)
        let contentBytes = content.utf8.count
        let themeBytes = theme.utf8.count
        let canonical = "ts=\(timestamp)|c=\(contentBytes):\(content)|t=\(themeBytes):\(theme)"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return "legacy-" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
