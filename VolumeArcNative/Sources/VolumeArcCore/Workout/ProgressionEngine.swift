import Foundation

public struct ProgressionEngine: Sendable {
    public init() {}

    public func evaluateReadiness(from sessions: [RecentSession], athlete: AthleteProfile) -> ReadinessAssessment {
        let score = max(50, 100 - sessions.count * 5)
        return ReadinessAssessment(
            score: score,
            brief: score >= 80
                ? "Well-recovered. Ready for full volume."
                : "Moderate fatigue. Consider a lighter session."
        )
    }

    public func buildAutopilotState(
        for history: ExerciseHistory,
        athlete: AthleteProfile,
        goal: StrengthGoal,
        recentSessions: [RecentSession],
        memory: CoachMemory
    ) -> WorkoutAutopilotState {
        WorkoutAutopilotState(
            nextExerciseName: "Back Squat",
            nextTarget: WorkoutTarget(weight: 225, unit: "lb", repRange: 5..<8, targetRPE: 7.5),
            bestCue: "Brace hard, break at the hips first.",
            recommendationReason: "Volume is tracking well. Hold the load and own the reps."
        )
    }
}

public enum VolumeArcExerciseCatalog {
    public static let backSquat = Exercise(id: "back-squat", name: "Back Squat")
    public static let frontSquat = Exercise(id: "front-squat", name: "Front Squat")
}
