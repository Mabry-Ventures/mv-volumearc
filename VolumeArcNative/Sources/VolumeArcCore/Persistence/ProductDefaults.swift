import Foundation

public enum CoachingStyle: String, Sendable { case motivational, analytical, minimal }
public enum PrivacyMode: String, Sendable { case standard, strict }
public enum AdvancementLevel: String, Sendable { case beginner, intermediate, advanced }
public enum EquipmentType: String, Sendable { case barbell, dumbbell, machine, bodyweight, cable, kettlebell }

public struct UserProfileDefaults: Sendable {
    public let name: String
    public let coachingStyle: CoachingStyle
    public let privacyMode: PrivacyMode
    public let advancementLevel: AdvancementLevel
    public let availableEquipment: [EquipmentType]
    public let preferredRepRangeLower: Int
    public let preferredRepRangeUpper: Int
    public let sessionTimeBudgetMinutes: Int
    public let weeklyTrainingDays: Int
}

public struct WeeklyWorkout: Codable, Sendable {
    public let dayOfWeek: Int
    public let title: String
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
    public static let strengthGoal = StrengthGoal(rawValue: "general-strength")
    public static let coachMemory = CoachMemory()

    public static func emptyHistory(for exercise: Exercise) -> ExerciseHistory {
        ExerciseHistory(exerciseID: exercise.id)
    }
}
