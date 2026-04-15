import Foundation

public struct UserProfileDefaults: Sendable {
    public let name: String
    public let coachingStyle: CoachingStyle
    public let privacyMode: PrivacyMode
    public let advancementLevel: AdvancementLevel
    public let availableEquipment: [Equipment]
    public let preferredRepRangeLower: Int
    public let preferredRepRangeUpper: Int
    public let sessionTimeBudgetMinutes: Int
    public let weeklyTrainingDays: Int

    public init(
        name: String,
        coachingStyle: CoachingStyle,
        privacyMode: PrivacyMode,
        advancementLevel: AdvancementLevel,
        availableEquipment: [Equipment],
        preferredRepRangeLower: Int,
        preferredRepRangeUpper: Int,
        sessionTimeBudgetMinutes: Int,
        weeklyTrainingDays: Int
    ) {
        self.name = name
        self.coachingStyle = coachingStyle
        self.privacyMode = privacyMode
        self.advancementLevel = advancementLevel
        self.availableEquipment = availableEquipment
        self.preferredRepRangeLower = preferredRepRangeLower
        self.preferredRepRangeUpper = preferredRepRangeUpper
        self.sessionTimeBudgetMinutes = sessionTimeBudgetMinutes
        self.weeklyTrainingDays = weeklyTrainingDays
    }
}

public struct WeeklyWorkout: Codable, Sendable {
    public let dayOfWeek: Int
    public let title: String

    public init(dayOfWeek: Int, title: String) {
        self.dayOfWeek = dayOfWeek
        self.title = title
    }
}

public enum VolumeArcProductDefaults {
    public static let userProfile = UserProfileDefaults(
        name: "",
        coachingStyle: .motivational,
        privacyMode: .standard,
        advancementLevel: .intermediate,
        availableEquipment: [.barbell, .dumbbell, .machine],
        preferredRepRangeLower: 5,
        preferredRepRangeUpper: 8,
        sessionTimeBudgetMinutes: 60,
        weeklyTrainingDays: 4
    )

    public static let weeklySchedule: [WeeklyWorkout] = [
        WeeklyWorkout(dayOfWeek: 1, title: "Upper Strength"),
        WeeklyWorkout(dayOfWeek: 2, title: "Lower Strength"),
        WeeklyWorkout(dayOfWeek: 4, title: "Upper Volume"),
        WeeklyWorkout(dayOfWeek: 5, title: "Lower Volume"),
    ]

    public static let starterRecentSessions: [RecentSession] = []
    public static let athleteProfile = AthleteProfile(name: "")
    public static let strengthGoal = StrengthGoal.generalStrength
    public static let coachMemory = CoachMemory()

    public static func emptyHistory(for exercise: ExerciseDefinition) -> ExerciseHistory {
        ExerciseHistory(exerciseID: exercise.id)
    }
}
