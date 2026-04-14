#if canImport(SwiftData)
import Foundation
import SwiftData

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
    public var updatedAt: Date

    public init(workoutsJSON: String, updatedAt: Date = .now) {
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

    public static var models: [any PersistentModel.Type] {
        [UserProfileRecord.self, TrainingPlanRecord.self, WorkoutRecord.self, CoachMemoryRecord.self]
    }
}

public enum VolumeArcSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [VolumeArcSchemaV1.self, VolumeArcSchemaV2.self, VolumeArcSchemaV3.self]
    }

    public static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3]
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
}
#endif
