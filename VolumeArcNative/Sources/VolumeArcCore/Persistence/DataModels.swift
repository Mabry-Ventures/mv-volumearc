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

    public init(
        name: String, coachingStyle: String, privacyMode: String,
        advancementLevel: String, availableEquipmentCSV: String,
        preferredRepRangeLower: Int, preferredRepRangeUpper: Int,
        sessionTimeBudgetMinutes: Int, weeklyTrainingDays: Int
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
    }
}

@Model
public final class TrainingPlanRecord {
    public var workoutsJSON: String

    public init(workoutsJSON: String) {
        self.workoutsJSON = workoutsJSON
    }
}

@Model
public final class WorkoutRecord {
    public var title: String
    public var completedAt: Date

    public init(title: String, completedAt: Date) {
        self.title = title
        self.completedAt = completedAt
    }
}

@Model
public final class CoachMemoryRecord {
    public var content: String
    public var createdAt: Date

    public init(content: String, createdAt: Date) {
        self.content = content
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

public struct SwiftDataWorkoutRepository: Sendable {
    public let container: ModelContainer
    public init(container: ModelContainer) { self.container = container }
}

public struct SwiftDataCoachMemoryRepository: Sendable {
    public let container: ModelContainer
    public init(container: ModelContainer) { self.container = container }
}

public struct SwiftDataUserProfileRepository: Sendable {
    public let container: ModelContainer
    public init(container: ModelContainer) { self.container = container }
}

public struct SwiftDataTrainingPlanRepository: Sendable {
    public let container: ModelContainer
    public init(container: ModelContainer) { self.container = container }
}
#endif
