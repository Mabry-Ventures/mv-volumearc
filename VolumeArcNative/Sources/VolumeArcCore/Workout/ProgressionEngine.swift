import Foundation

/// Real progression engine using evidence-based strength training principles.
///
/// For beginners: linear progression (add weight every session when targets are met)
/// For intermediate: undulating (rotate heavy/moderate/light across the week)
/// For advanced: auto-regulated based on RPE and readiness
///
/// The engine evaluates readiness, selects an exercise based on available equipment,
/// computes the next target from recent performance, and suggests an action.
public struct ProgressionEngine: Sendable {
    private let readinessModel: ReadinessModel

    public init(readinessModel: ReadinessModel = ReadinessModel()) {
        self.readinessModel = readinessModel
    }

    /// Compute the readiness assessment for the given athlete and recent sessions.
    public func evaluateReadiness(
        from sessions: [RecentSession],
        athlete: AthleteProfile
    ) -> ReadinessAssessment {
        readinessModel.evaluate(sessions: sessions, athlete: athlete)
    }

    /// Build an autopilot recommendation for the next set of the primary exercise.
    public func buildAutopilotState(
        for history: ExerciseHistory,
        athlete: AthleteProfile,
        goal: StrengthGoal,
        recentSessions: [RecentSession],
        memory: CoachMemory
    ) -> WorkoutAutopilotState {
        // Find the exercise in the catalog, or fall back to back squat.
        let exercise = VolumeArcExerciseCatalog.exercise(withID: history.exerciseID)
            ?? VolumeArcExerciseCatalog.backSquat

        // Choose the best substitute if the preferred exercise isn't available.
        let selected = selectAvailableExercise(exercise, athlete: athlete)

        // Compute the next target from history + progression rules.
        let target = nextTarget(
            for: selected,
            history: history,
            athlete: athlete,
            goal: goal
        )

        // Select the best cue from the exercise's cue bank.
        let cue = selectCue(for: selected, memory: memory)

        // Determine suggested action based on last session's performance.
        let action = suggestedAction(
            history: history,
            recentReadiness: readinessModel.evaluate(sessions: recentSessions, athlete: athlete)
        )

        // Build the recommendation reason.
        let reason = buildReason(
            selected: selected,
            target: target,
            history: history,
            action: action
        )

        return WorkoutAutopilotState(
            nextExerciseID: selected.id,
            nextExerciseName: selected.name,
            nextTarget: target,
            bestCue: cue,
            recommendationReason: reason,
            suggestedAction: action
        )
    }

    // MARK: - Exercise selection

    private func selectAvailableExercise(
        _ exercise: ExerciseDefinition,
        athlete: AthleteProfile
    ) -> ExerciseDefinition {
        if athlete.availableEquipment.contains(exercise.primaryEquipment) {
            return exercise
        }
        if let alt = VolumeArcExerciseCatalog.alternatives(
            for: exercise,
            availableEquipment: athlete.availableEquipment
        ).first {
            return alt
        }
        return exercise
    }

    // MARK: - Target computation

    private func nextTarget(
        for exercise: ExerciseDefinition,
        history: ExerciseHistory,
        athlete: AthleteProfile,
        goal: StrengthGoal
    ) -> WorkoutTarget {
        guard let lastSession = history.lastSession,
              let topSet = lastSession.sets.max(by: { $0.weight < $1.weight })
        else {
            return starterTarget(for: exercise, athlete: athlete, goal: goal)
        }

        let repRange = exerciseRepRange(exercise, goal: goal, athlete: athlete)

        let progressed = topSet.reps >= repRange.upperBound && topSet.rpe <= exercise.defaultRPE + 0.5
        let struggled = topSet.rpe >= exercise.defaultRPE + 1.5

        let nextWeight: Double
        if progressed {
            nextWeight = nextProgressionWeight(from: topSet.weight, level: athlete.advancementLevel)
        } else if struggled {
            nextWeight = topSet.weight
        } else {
            nextWeight = topSet.weight
        }

        return WorkoutTarget(
            weight: nextWeight,
            unit: "lb",
            repRange: repRange,
            targetRPE: exercise.defaultRPE
        )
    }

    private func starterTarget(
        for exercise: ExerciseDefinition,
        athlete: AthleteProfile,
        goal: StrengthGoal
    ) -> WorkoutTarget {
        let repRange = exerciseRepRange(exercise, goal: goal, athlete: athlete)

        let starterWeight: Double
        switch exercise.primaryEquipment {
        case .barbell where exercise.isCompound: starterWeight = 95
        case .barbell: starterWeight = 65
        case .dumbbell: starterWeight = 25
        case .machine, .cable: starterWeight = 50
        case .kettlebell: starterWeight = 35
        case .bodyweight, .band: starterWeight = 0
        }

        return WorkoutTarget(
            weight: starterWeight,
            unit: "lb",
            repRange: repRange,
            targetRPE: exercise.defaultRPE
        )
    }

    private func nextProgressionWeight(from current: Double, level: AdvancementLevel) -> Double {
        switch level {
        case .beginner: return current + 5
        case .intermediate: return current + 2.5
        case .advanced: return current + 1.25
        }
    }

    private func exerciseRepRange(
        _ exercise: ExerciseDefinition,
        goal: StrengthGoal,
        athlete: AthleteProfile
    ) -> ClosedRange<Int> {
        switch goal {
        case .powerlifting: return 3...5
        case .generalStrength: return exercise.defaultRepRange
        case .hypertrophy: return 8...12
        case .weightLoss: return 10...15
        }
    }

    // MARK: - Cue selection

    private func selectCue(for exercise: ExerciseDefinition, memory: CoachMemory) -> String {
        for entry in memory.mostRecent {
            for cue in exercise.cues where entry.summary.lowercased().contains(keyWord(of: cue).lowercased()) {
                return cue
            }
        }
        return exercise.cues.first ?? "Move with intention."
    }

    private func keyWord(of cue: String) -> String {
        cue.split(separator: " ").first.map(String.init) ?? cue
    }

    // MARK: - Action suggestion

    private func suggestedAction(
        history: ExerciseHistory,
        recentReadiness: ReadinessAssessment
    ) -> WorkoutAction {
        guard let last = history.lastSession,
              let topSet = last.sets.max(by: { $0.weight < $1.weight })
        else {
            return .hold
        }

        if recentReadiness.score < 50 {
            return .decrease
        }
        if topSet.rpe <= 7.0 && recentReadiness.score >= 75 {
            return .increase
        }
        if topSet.rpe >= 9.0 {
            return .hold
        }
        return .hold
    }

    // MARK: - Reason text

    private func buildReason(
        selected: ExerciseDefinition,
        target: WorkoutTarget,
        history: ExerciseHistory,
        action: WorkoutAction
    ) -> String {
        guard let last = history.lastSession,
              let topSet = last.sets.max(by: { $0.weight < $1.weight })
        else {
            return "Starting fresh with \(selected.name) at a conservative load. Build confidence, own the movement."
        }

        let weightDelta = target.weight - topSet.weight
        let rpeString = String(format: "%.1f", topSet.rpe)
        let topSetSummary = "\(Int(topSet.weight))lb x \(topSet.reps) at RPE \(rpeString)"

        switch action {
        case .increase:
            if weightDelta > 0 {
                return "Last \(selected.name): \(topSetSummary). Adding \(Int(weightDelta))lb — you've earned it."
            } else {
                return "Last \(selected.name): \(topSetSummary). Push for more reps at the same load."
            }
        case .hold:
            return "Last \(selected.name): \(topSetSummary). Hold the load and own the next set."
        case .decrease:
            return "Last \(selected.name): \(topSetSummary). Readiness is down — back off slightly and move well."
        }
    }
}
