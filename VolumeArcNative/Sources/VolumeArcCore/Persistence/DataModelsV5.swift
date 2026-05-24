#if canImport(SwiftData)
import Foundation
import SwiftData

public enum VolumeArcSchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)

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

    @Model
    public final class TrainingProgramRecord {
        public var identifier: String = ""
        public var catalogIdentifier: String = ""
        public var name: String = ""
        public var author: String = ""
        public var weeks: Int = 0
        public var sessionsPerWeek: Int = 0
        public var advancementCriteria: String = ""
        public var difficultyTier: String = "novice"
        public var equipmentRequirement: String = "barbell"
        public var sessionsJSON: String = "[]"
        public var isActive: Bool = false
        public var assignedAt: Date?
        public var currentWeek: Int = 1
        public var currentDay: Int = 1
        public var updatedAt: Date = Date()

        public init(
            identifier: String = UUID().uuidString,
            catalogIdentifier: String = "",
            name: String = "",
            author: String = "",
            weeks: Int = 0,
            sessionsPerWeek: Int = 0,
            advancementCriteria: String = "",
            difficultyTier: String = "novice",
            equipmentRequirement: String = "barbell",
            sessionsJSON: String = "[]",
            isActive: Bool = false,
            assignedAt: Date? = nil,
            currentWeek: Int = 1,
            currentDay: Int = 1,
            updatedAt: Date = .now
        ) {
            self.identifier = identifier
            self.catalogIdentifier = catalogIdentifier
            self.name = name
            self.author = author
            self.weeks = weeks
            self.sessionsPerWeek = sessionsPerWeek
            self.advancementCriteria = advancementCriteria
            self.difficultyTier = difficultyTier
            self.equipmentRequirement = equipmentRequirement
            self.sessionsJSON = sessionsJSON
            self.isActive = isActive
            self.assignedAt = assignedAt
            self.currentWeek = currentWeek
            self.currentDay = currentDay
            self.updatedAt = updatedAt
        }
    }

    public static var models: [any PersistentModel.Type] {
        [
            UserProfileRecord.self,
            TrainingPlanRecord.self,
            WorkoutRecord.self,
            CoachMemoryRecord.self,
            TrainingProgramRecord.self,
            OutboundSyncQueueRecord.self,
        ]
    }
}
#endif
