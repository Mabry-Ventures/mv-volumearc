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

    public static var models: [any PersistentModel.Type] {
        [UserProfileRecord.self, TrainingPlanRecord.self, WorkoutRecord.self, CoachMemoryRecord.self]
    }
}

public enum VolumeArcSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [VolumeArcSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
#endif
