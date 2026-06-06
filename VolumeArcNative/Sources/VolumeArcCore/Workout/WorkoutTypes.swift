import Foundation

public enum WorkoutAction: String, Sendable, CaseIterable, Codable {
    case increase
    case hold
    case decrease
}

public enum AdvancementLevel: String, Sendable, CaseIterable {
    case beginner
    case intermediate
    case advanced
}

public enum CoachingStyle: String, Sendable, CaseIterable {
    case motivational
    case analytical
    case minimal
}

public enum PrivacyMode: String, Sendable, CaseIterable {
    case standard
    case strict
}

public struct WorkoutTarget: Sendable, Equatable {
    public let weight: Double
    public let unit: String
    public let repRange: ClosedRange<Int>
    public let targetRPE: Double

    public init(weight: Double, unit: String, repRange: ClosedRange<Int>, targetRPE: Double) {
        self.weight = weight
        self.unit = unit
        self.repRange = repRange
        self.targetRPE = targetRPE
    }
}

public struct WorkoutAutopilotState: Sendable {
    public let nextExerciseID: String
    public let nextExerciseName: String
    public let nextTarget: WorkoutTarget
    public let bestCue: String
    public let recommendationReason: String
    public let suggestedAction: WorkoutAction

    public init(
        nextExerciseID: String,
        nextExerciseName: String,
        nextTarget: WorkoutTarget,
        bestCue: String,
        recommendationReason: String,
        suggestedAction: WorkoutAction = .hold
    ) {
        self.nextExerciseID = nextExerciseID
        self.nextExerciseName = nextExerciseName
        self.nextTarget = nextTarget
        self.bestCue = bestCue
        self.recommendationReason = recommendationReason
        self.suggestedAction = suggestedAction
    }
}

public enum CoachWorkoutPlanExtractor {
    public static func plan(from response: String, title: String) -> WorkoutSessionPlan? {
        let exercises = response
            .split(whereSeparator: \.isNewline)
            .compactMap { exercise(from: String($0), response: response) }
            .prefix(8)
        guard !exercises.isEmpty else { return nil }

        let exerciseList = Array(exercises)
        let targetRPE = conservativeResponse(response) ? 6 : 7
        return WorkoutSessionPlan(
            title: title,
            durationMinutes: min(75, max(20, exerciseList.count * 10)),
            targetRPE: targetRPE,
            exercises: exerciseList
        )
    }

    private static func exercise(from line: String, response: String) -> WeeklyWorkoutExercise? {
        let trimmed = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-* "))
        guard trimmed.range(of: "set", options: .caseInsensitive) != nil,
              trimmed.range(of: "rep", options: .caseInsensitive) != nil
                || trimmed.range(of: "second", options: .caseInsensitive) != nil
        else { return nil }

        guard let name = exerciseName(from: trimmed),
              !name.isEmpty,
              let sets = firstInt(matching: #"(\d+)\s*sets?"#, in: trimmed)
        else { return nil }

        let reps = firstInt(matching: #"(\d+)\s*reps?"#, in: trimmed)
            ?? firstInt(matching: #"(\d+)\s*seconds?"#, in: trimmed)
            ?? 1
        let targetRPE = conservativeResponse(response) ? 6 : 7
        let weight = firstInt(matching: #"(\d+)\s*(?:lb|lbs|pounds?)"#, in: trimmed)
            ?? defaultWeight(for: name, response: response)
        return WeeklyWorkoutExercise(
            name: name,
            sets: max(1, min(sets, 8)),
            reps: max(1, min(reps, 50)),
            weight: max(0, weight),
            targetRPE: targetRPE,
            restSeconds: targetRPE <= 6 ? 75 : 120
        )
    }

    private static func exerciseName(from line: String) -> String? {
        let delimiterRanges = [
            line.range(of: ":"),
            line.range(of: " - "),
            line.range(of: " -- "),
        ].compactMap { $0 }
        guard let delimiter = delimiterRanges.min(by: { $0.lowerBound < $1.lowerBound }) else {
            return nil
        }
        let name = line[..<delimiter.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.localizedCaseInsensitiveContains("sample workout") else { return nil }
        guard !name.localizedCaseInsensitiveContains("workout plan") else { return nil }
        return name
    }

    private static func firstInt(matching pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[matchRange])
    }

    private static func conservativeResponse(_ response: String) -> Bool {
        let lowered = response.lowercased()
        return lowered.contains("light")
            || lowered.contains("take it easy")
            || lowered.contains("sick")
            || lowered.contains("sore")
            || lowered.contains("pain")
            || lowered.contains("tight")
            || lowered.contains("run down")
            || lowered.contains("rpe 6")
    }

    private static func defaultWeight(for name: String, response: String) -> Int {
        let loweredName = name.lowercased()
        let isConservative = conservativeResponse(response)
        if loweredName.contains("dumbbell") {
            return isConservative ? 20 : 35
        }
        if loweredName.contains("barbell")
            || loweredName.contains("squat")
            || loweredName.contains("deadlift")
            || loweredName.contains("bench") {
            return isConservative ? 45 : 95
        }
        return 0
    }
}

public struct ReadinessAssessment: Sendable {
    public let score: Int
    public let brief: String
    public let factors: [Factor]

    public struct Factor: Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let impact: Int  // -100 to +100
        public let detail: String

        public init(name: String, impact: Int, detail: String) {
            self.name = name
            self.impact = impact
            self.detail = detail
        }
    }

    public init(score: Int, brief: String, factors: [Factor] = []) {
        self.score = score
        self.brief = brief
        self.factors = factors
    }
}

public struct WorkoutSetPerformance: Codable, Sendable, Equatable {
    public let weight: Double
    public let reps: Int
    public let rpe: Double
    public let completedAt: Date

    public init(weight: Double, reps: Int, rpe: Double, completedAt: Date) {
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.completedAt = completedAt
    }
}

public struct WatchWorkoutSyncPayload: Codable, Sendable {
    public let workoutID: String
    public let receivedAt: Date
    public let title: String
    public let exerciseID: String
    public let exerciseName: String
    public let set: WorkoutSetPerformance
    public let recommendedAction: String
    public let durationMinutes: Int
    public let completionRate: Double
    public let summary: String

    public init(
        workoutID: String, receivedAt: Date, title: String,
        exerciseID: String, exerciseName: String,
        set: WorkoutSetPerformance, recommendedAction: WorkoutAction,
        durationMinutes: Int, completionRate: Double, summary: String
    ) {
        self.workoutID = workoutID
        self.receivedAt = receivedAt
        self.title = title
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.set = set
        self.recommendedAction = recommendedAction.rawValue
        self.durationMinutes = durationMinutes
        self.completionRate = completionRate
        self.summary = summary
    }
}

public struct AthleteProfile: Sendable {
    public let name: String
    public let coachingStyle: CoachingStyle
    public let privacyMode: PrivacyMode
    public let advancementLevel: AdvancementLevel
    public let availableEquipment: Set<Equipment>
    public let sessionTimeBudgetMinutes: Int
    public let weeklyTrainingDays: Int
    public let preferredRepRange: ClosedRange<Int>

    public init(
        name: String,
        coachingStyle: CoachingStyle = .motivational,
        privacyMode: PrivacyMode = .standard,
        advancementLevel: AdvancementLevel = .intermediate,
        availableEquipment: Set<Equipment> = [.barbell, .dumbbell, .machine, .bodyweight],
        sessionTimeBudgetMinutes: Int = 60,
        weeklyTrainingDays: Int = 4,
        preferredRepRange: ClosedRange<Int> = 5...8
    ) {
        self.name = name
        self.coachingStyle = coachingStyle
        self.privacyMode = privacyMode
        self.advancementLevel = advancementLevel
        self.availableEquipment = availableEquipment
        self.sessionTimeBudgetMinutes = sessionTimeBudgetMinutes
        self.weeklyTrainingDays = weeklyTrainingDays
        self.preferredRepRange = preferredRepRange
    }
}

public extension AthleteProfile {
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        if parts.isEmpty { return "VA" }
        return parts.compactMap(\.first).map(String.init).joined()
    }
}

/// A completed training session.
public struct RecentSession: Sendable {
    public let identifier: String?
    public let title: String?
    public let sourceName: String?
    public let date: Date
    public let durationMinutes: Int
    public let exerciseIDs: [String]
    public let totalVolumeLoad: Double  // Sum of weight × reps × sets
    public let averageRPE: Double
    public let completedSetCount: Int

    public init(
        identifier: String? = nil,
        title: String? = nil,
        sourceName: String? = nil,
        date: Date,
        durationMinutes: Int = 60,
        exerciseIDs: [String] = [],
        totalVolumeLoad: Double = 0,
        averageRPE: Double = 7.0,
        completedSetCount: Int = 0
    ) {
        self.identifier = identifier
        self.title = title
        self.sourceName = sourceName
        self.date = date
        self.durationMinutes = durationMinutes
        self.exerciseIDs = exerciseIDs
        self.totalVolumeLoad = totalVolumeLoad
        self.averageRPE = averageRPE
        self.completedSetCount = completedSetCount
    }

    public var isExternalHealthSession: Bool {
        completedSetCount == 0 && exerciseIDs.contains { $0.hasPrefix("healthkit-") }
    }

    public var isUserDeletable: Bool {
        identifier != nil && !isExternalHealthSession
    }
}

/// Historical performance for a single exercise.
public struct ExerciseHistory: Sendable {
    public let exerciseID: String
    public let sessions: [ExerciseSession]

    public init(exerciseID: String, sessions: [ExerciseSession] = []) {
        self.exerciseID = exerciseID
        self.sessions = sessions
    }

    /// The most recent session, if any.
    public var lastSession: ExerciseSession? {
        sessions.max(by: { $0.date < $1.date })
    }

    /// The top working weight across all recorded sessions.
    public var topWeight: Double {
        sessions.flatMap(\.sets).map(\.weight).max() ?? 0
    }

    public var isEmpty: Bool { sessions.isEmpty }
}

public struct ExerciseSession: Sendable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let sets: [WorkoutSetPerformance]

    public init(date: Date, sets: [WorkoutSetPerformance]) {
        self.date = date
        self.sets = sets
    }

    public var totalVolumeLoad: Double {
        sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    public var topSetWeight: Double {
        sets.map(\.weight).max() ?? 0
    }

    public var averageRPE: Double {
        guard !sets.isEmpty else { return 0 }
        return sets.map(\.rpe).reduce(0, +) / Double(sets.count)
    }
}

public enum StrengthGoal: String, Sendable, CaseIterable {
    case generalStrength = "general-strength"
    case hypertrophy
    case powerlifting
    case weightLoss = "weight-loss"
}

public struct CoachMemory: Sendable {
    public struct Entry: Sendable, Identifiable {
        public var id: Date { createdAt }
        public let createdAt: Date
        public let summary: String
        public let theme: String?

        public init(createdAt: Date, summary: String, theme: String? = nil) {
            self.createdAt = createdAt
            self.summary = summary
            self.theme = theme
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }

    public var mostRecent: [Entry] {
        entries.sorted { $0.createdAt > $1.createdAt }.prefix(5).map { $0 }
    }
}
