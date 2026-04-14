import Foundation

public enum WorkoutAction: String, Sendable, CaseIterable {
    case increase
    case hold
    case decrease
}

public struct Exercise: Sendable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct WorkoutTarget: Sendable {
    public let weight: Double
    public let unit: String
    public let repRange: Range<Int>
    public let targetRPE: Double

    public init(weight: Double, unit: String, repRange: Range<Int>, targetRPE: Double) {
        self.weight = weight
        self.unit = unit
        self.repRange = repRange
        self.targetRPE = targetRPE
    }
}

public struct WorkoutAutopilotState: Sendable {
    public let nextExerciseName: String
    public let nextTarget: WorkoutTarget
    public let bestCue: String
    public let recommendationReason: String

    public init(nextExerciseName: String, nextTarget: WorkoutTarget, bestCue: String, recommendationReason: String) {
        self.nextExerciseName = nextExerciseName
        self.nextTarget = nextTarget
        self.bestCue = bestCue
        self.recommendationReason = recommendationReason
    }
}

public struct ReadinessAssessment: Sendable {
    public let score: Int
    public let brief: String

    public init(score: Int, brief: String) {
        self.score = score
        self.brief = brief
    }
}

public struct WorkoutSetPerformance: Codable, Sendable {
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
    public init(name: String) { self.name = name }
}

public struct RecentSession: Sendable {
    public let date: Date
    public init(date: Date) { self.date = date }
}

public struct ExerciseHistory: Sendable {
    public let exerciseID: String
    public init(exerciseID: String) { self.exerciseID = exerciseID }
}

public struct StrengthGoal: Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct CoachMemory: Sendable {
    public let entries: [String]
    public init(entries: [String] = []) { self.entries = entries }
}
