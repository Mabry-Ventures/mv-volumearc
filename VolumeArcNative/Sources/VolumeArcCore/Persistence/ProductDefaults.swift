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

public struct WeeklyWorkoutExercise: Codable, Equatable, Sendable {
    public let name: String
    public let sets: Int
    public let reps: Int
    public let weight: Int
    public let targetRPE: Int
    public let restSeconds: Int

    public init(
        name: String,
        sets: Int,
        reps: Int,
        weight: Int,
        targetRPE: Int,
        restSeconds: Int
    ) {
        self.name = name
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.targetRPE = targetRPE
        self.restSeconds = restSeconds
    }
}

public struct WeeklyWorkout: Codable, Sendable {
    public let dayOfWeek: Int
    public let title: String
    public let durationMinutes: Int?
    public let targetRPE: Int?
    public let exercises: [WeeklyWorkoutExercise]

    public init(
        dayOfWeek: Int,
        title: String,
        durationMinutes: Int? = nil,
        targetRPE: Int? = nil,
        exercises: [WeeklyWorkoutExercise] = []
    ) {
        self.dayOfWeek = dayOfWeek
        self.title = title
        self.durationMinutes = durationMinutes
        self.targetRPE = targetRPE
        self.exercises = exercises
    }

    private enum CodingKeys: String, CodingKey {
        case dayOfWeek
        case title
        case durationMinutes
        case targetRPE
        case exercises
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayOfWeek = try container.decode(Int.self, forKey: .dayOfWeek)
        title = try container.decode(String.self, forKey: .title)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        targetRPE = try container.decodeIfPresent(Int.self, forKey: .targetRPE)
        exercises = try container.decodeIfPresent([WeeklyWorkoutExercise].self, forKey: .exercises) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dayOfWeek, forKey: .dayOfWeek)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try container.encodeIfPresent(targetRPE, forKey: .targetRPE)
        if !exercises.isEmpty {
            try container.encode(exercises, forKey: .exercises)
        }
    }

    /// Training plans store weekdays as Monday = 1 ... Sunday = 7.
    public static func trainingWeekday(for date: Date, calendar: Calendar = .current) -> Int {
        let foundationWeekday = calendar.component(.weekday, from: date)
        return foundationWeekday == 1 ? 7 : foundationWeekday - 1
    }
}

public struct WorkoutSessionPlan: Codable, Equatable, Sendable {
    public let title: String
    public let durationMinutes: Int?
    public let targetRPE: Int?
    public let exercises: [WeeklyWorkoutExercise]

    public init(
        title: String,
        durationMinutes: Int? = nil,
        targetRPE: Int? = nil,
        exercises: [WeeklyWorkoutExercise]
    ) {
        self.title = title
        self.durationMinutes = durationMinutes
        self.targetRPE = targetRPE
        self.exercises = exercises
    }

    public init(workout: WeeklyWorkout) {
        self.init(
            title: workout.title,
            durationMinutes: workout.durationMinutes,
            targetRPE: workout.targetRPE,
            exercises: workout.exercises
        )
    }

    public var totalSetCount: Int {
        exercises.reduce(0) { total, exercise in
            total + max(1, exercise.sets)
        }
    }

    public var isEmpty: Bool {
        exercises.isEmpty
    }

    public func exercise(at index: Int) -> WeeklyWorkoutExercise? {
        guard exercises.indices.contains(index) else { return nil }
        return exercises[index]
    }
}

public struct ActiveWorkoutSessionState: Codable, Equatable, Sendable {
    public let workoutID: String
    public let plan: WorkoutSessionPlan
    public let activeExerciseIndex: Int
    public let loggedSetCountForActiveExercise: Int

    public init(
        workoutID: String,
        plan: WorkoutSessionPlan,
        activeExerciseIndex: Int,
        loggedSetCountForActiveExercise: Int
    ) {
        self.workoutID = workoutID
        self.plan = plan
        self.activeExerciseIndex = activeExerciseIndex
        self.loggedSetCountForActiveExercise = loggedSetCountForActiveExercise
    }
}

public protocol ActiveWorkoutSessionStateStore: Sendable {
    func load(workoutID: String) -> ActiveWorkoutSessionState?
    func save(_ state: ActiveWorkoutSessionState)
    func clear(workoutID: String)
}

public final class UserDefaultsActiveSessionStateStore: ActiveWorkoutSessionStateStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "com.mabryventures.VolumeArc.activeWorkoutSession"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func load(workoutID: String) -> ActiveWorkoutSessionState? {
        guard let data = defaults.data(forKey: key(for: workoutID)),
              let decoded = try? JSONDecoder().decode(ActiveWorkoutSessionState.self, from: data),
              decoded.workoutID == workoutID
        else { return nil }
        return decoded
    }

    public func save(_ state: ActiveWorkoutSessionState) {
        guard state.plan.isEmpty == false,
              let data = try? JSONEncoder().encode(state)
        else { return }
        defaults.set(data, forKey: key(for: state.workoutID))
    }

    public func clear(workoutID: String) {
        defaults.removeObject(forKey: key(for: workoutID))
    }

    private func key(for workoutID: String) -> String {
        "\(keyPrefix).\(workoutID)"
    }
}

public final class InMemoryActiveWorkoutSessionStateStore: ActiveWorkoutSessionStateStore, @unchecked Sendable {
    private var states: [String: ActiveWorkoutSessionState] = [:]
    private let lock = NSLock()

    public init() {}

    public func load(workoutID: String) -> ActiveWorkoutSessionState? {
        lock.lock()
        defer { lock.unlock() }
        return states[workoutID]
    }

    public func save(_ state: ActiveWorkoutSessionState) {
        lock.lock()
        defer { lock.unlock() }
        states[state.workoutID] = state
    }

    public func clear(workoutID: String) {
        lock.lock()
        defer { lock.unlock() }
        states.removeValue(forKey: workoutID)
    }
}

public enum WorkoutSessionProfile: String, CaseIterable, Codable, Sendable, Equatable {
    case defaultProfile = "Default"
    case legDay = "Leg Day"
    case upperStrength = "Upper Strength"
    case shortSession = "Short Session"

    public static func parse(_ rawValue: String) -> WorkoutSessionProfile {
        allCases.first { $0.rawValue == rawValue } ?? .defaultProfile
    }
}

public struct WorkoutSessionProfilePreferences: Codable, Equatable, Sendable {
    public let selectedProfile: WorkoutSessionProfile
    public let legDayRuleEnabled: Bool
    public let shortSessionRuleEnabled: Bool

    public init(
        selectedProfile: WorkoutSessionProfile,
        legDayRuleEnabled: Bool,
        shortSessionRuleEnabled: Bool
    ) {
        self.selectedProfile = selectedProfile
        self.legDayRuleEnabled = legDayRuleEnabled
        self.shortSessionRuleEnabled = shortSessionRuleEnabled
    }

    public func resolvedProfile(
        sessionMinutes: Int,
        date: Date = .now,
        calendar: Calendar = .current
    ) -> WorkoutSessionProfile {
        if shortSessionRuleEnabled, sessionMinutes < 45 {
            return .shortSession
        }

        let weekday = calendar.component(.weekday, from: date)
        if legDayRuleEnabled, weekday == 3 || weekday == 5 {
            return .legDay
        }

        return selectedProfile
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
