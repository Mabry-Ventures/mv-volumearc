import Foundation

/// VOL-284: deterministic prescription clamps.
///
/// `CoachWorkoutPlanExtractor` turns free-text coach responses into
/// scheduled numbers. The extractor's static caps (sets <= 8, reps <= 50)
/// bound shape, not safety: nothing stopped a generated response from
/// prescribing a load far beyond anything the athlete has demonstrated.
/// This module is the structural fix — the model proposes, this code
/// disposes. It is pure and provider-agnostic: the same bounds apply no
/// matter which brain produced the text, so swapping the AI brain can
/// never change what reaches a scheduled plan.
///
/// The constants below are coaching policy, not engineering preference.
/// Changing any of them requires Jared's sign-off on VOL-284.
public enum CoachPrescriptionClamp {

    // MARK: - Policy constants (VOL-284 sign-off)

    /// A lift with demonstrated history may progress at most 10% over
    /// the athlete's top working weight for that exercise...
    public static let maxProgressionFraction = 0.10
    /// ...but small implements progress in absolute steps, so always
    /// allow at least one +5 lb jump over the demonstrated top.
    public static let minimumAllowedIncrement = 5
    /// Symptom context in the active conversation freezes loads at 60%
    /// of demonstrated top weight — the ceiling of the "40-60% effort"
    /// language in `CoachSafetyFilter` recovery copy.
    public static let symptomCeilingFraction = 0.60
    /// Planned session volume (sets x reps x weight summed) may exceed
    /// the athlete's biggest recent session by at most 20%.
    public static let maxSessionVolumeJumpFraction = 0.20
    /// At or above this fraction of top weight, rest gets a heavy floor.
    public static let heavyThresholdFraction = 0.85
    public static let heavyRestFloorSeconds = 90
    /// First-exposure ceilings when an exercise has no history at all.
    public static let noHistoryBarbellCap = 135
    public static let noHistoryDumbbellCap = 50
    public static let noHistoryOtherCap = 75
    /// Conservative first-exposure ceilings under symptom context
    /// (mirror `CoachWorkoutPlanExtractor`'s conservative defaults).
    public static let symptomNoHistoryBarbellCap = 45
    public static let symptomNoHistoryDumbbellCap = 20
    public static let symptomNoHistoryOtherCap = 45
    /// Symptom context caps prescribed effort at RPE 6.
    public static let symptomMaxTargetRPE = 6

    // MARK: - Types

    public struct Input: Sendable {
        /// Demonstrated top working weight keyed by
        /// `normalizedExerciseKey` (built from logged exercise IDs).
        public let topWeightByExerciseKey: [String: Double]
        /// Largest recent completed-session volume load, if any.
        public let maxRecentSessionVolume: Double?
        /// True when the active coach conversation carries current
        /// symptom or red-flag context (`CoachSafetyFilter` signal).
        public let hasSymptomContext: Bool

        public init(
            topWeightByExerciseKey: [String: Double] = [:],
            maxRecentSessionVolume: Double? = nil,
            hasSymptomContext: Bool = false
        ) {
            self.topWeightByExerciseKey = topWeightByExerciseKey
            self.maxRecentSessionVolume = maxRecentSessionVolume
            self.hasSymptomContext = hasSymptomContext
        }
    }

    public enum EventKind: String, Sendable {
        case loadCap = "load_cap"
        case noHistoryCap = "no_history_cap"
        case symptomFreeze = "symptom_freeze"
        case symptomRPECap = "symptom_rpe_cap"
        case sessionVolumeCap = "session_volume_cap"
        case heavyRestFloor = "heavy_rest_floor"
    }

    public struct Event: Sendable, Equatable {
        public let kind: EventKind
        public let exerciseName: String
        public let field: String
        public let original: Int
        public let clamped: Int

        public init(kind: EventKind, exerciseName: String, field: String, original: Int, clamped: Int) {
            self.kind = kind
            self.exerciseName = exerciseName
            self.field = field
            self.original = original
            self.clamped = clamped
        }
    }

    // MARK: - API

    /// Normalize an exercise display name or logged exercise ID into a
    /// shared lookup key: lowercased alphanumeric runs joined by `-`.
    /// "Barbell Back Squat" and "barbell-back-squat" both normalize to
    /// `barbell-back-squat`.
    public static func normalizedExerciseKey(_ name: String) -> String {
        String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(separator: " ")
            .joined(separator: "-")
    }

    /// Clamp a coach-proposed plan against the athlete's demonstrated
    /// history. Pure and deterministic; returns the clamped plan plus
    /// one event per bound applied. Clamping an already-clamped plan is
    /// a no-op, so the extraction-time and schedule-time call sites can
    /// both run it safely.
    public static func clamp(
        _ plan: WorkoutSessionPlan,
        input: Input
    ) -> (plan: WorkoutSessionPlan, events: [Event]) {
        var events: [Event] = []
        var exercises = plan.exercises.map { clampExercise($0, input: input, events: &events) }
        applySessionVolumeCap(&exercises, input: input, events: &events)

        var targetRPE = plan.targetRPE
        if input.hasSymptomContext, let rpe = targetRPE, rpe > symptomMaxTargetRPE {
            events.append(Event(
                kind: .symptomRPECap, exerciseName: plan.title,
                field: "planTargetRPE", original: rpe, clamped: symptomMaxTargetRPE
            ))
            targetRPE = symptomMaxTargetRPE
        }

        let clamped = WorkoutSessionPlan(
            title: plan.title,
            durationMinutes: plan.durationMinutes,
            targetRPE: targetRPE,
            exercises: exercises
        )
        return (clamped, events)
    }

    // MARK: - Internals

    public static func topWeight(for name: String, in table: [String: Double]) -> Double? {
        let key = normalizedExerciseKey(name)
        guard !key.isEmpty else { return nil }
        if let exact = table[key] { return exact }
        let matches = table.filter { stored, _ in
            stored.contains(key) || key.contains(stored)
        }
        return matches.max { $0.key.count < $1.key.count }?.value
    }

    private static func clampExercise(
        _ exercise: WeeklyWorkoutExercise,
        input: Input,
        events: inout [Event]
    ) -> WeeklyWorkoutExercise {
        var weight = exercise.weight
        var rpe = exercise.targetRPE
        var rest = exercise.restSeconds

        if let top = topWeight(for: exercise.name, in: input.topWeightByExerciseKey), top > 0 {
            if input.hasSymptomContext {
                let cap = Int(top * symptomCeilingFraction)
                if weight > cap {
                    events.append(Event(
                        kind: .symptomFreeze, exerciseName: exercise.name,
                        field: "weight", original: weight, clamped: cap
                    ))
                    weight = cap
                }
            } else {
                let cap = max(Int(top * (1 + maxProgressionFraction)), Int(top) + minimumAllowedIncrement)
                if weight > cap {
                    events.append(Event(
                        kind: .loadCap, exerciseName: exercise.name,
                        field: "weight", original: weight, clamped: cap
                    ))
                    weight = cap
                }
            }
            if Double(weight) >= top * heavyThresholdFraction, rest < heavyRestFloorSeconds {
                events.append(Event(
                    kind: .heavyRestFloor, exerciseName: exercise.name,
                    field: "restSeconds", original: rest, clamped: heavyRestFloorSeconds
                ))
                rest = heavyRestFloorSeconds
            }
        } else {
            let cap = noHistoryCap(for: exercise.name, symptomContext: input.hasSymptomContext)
            if weight > cap {
                events.append(Event(
                    kind: input.hasSymptomContext ? .symptomFreeze : .noHistoryCap,
                    exerciseName: exercise.name,
                    field: "weight", original: weight, clamped: cap
                ))
                weight = cap
            }
        }

        if input.hasSymptomContext, rpe > symptomMaxTargetRPE {
            events.append(Event(
                kind: .symptomRPECap, exerciseName: exercise.name,
                field: "targetRPE", original: rpe, clamped: symptomMaxTargetRPE
            ))
            rpe = symptomMaxTargetRPE
        }

        return WeeklyWorkoutExercise(
            name: exercise.name,
            sets: exercise.sets,
            reps: exercise.reps,
            weight: weight,
            targetRPE: rpe,
            restSeconds: rest
        )
    }

    /// Mirrors the implement families in
    /// `CoachWorkoutPlanExtractor.defaultWeight(for:response:)`.
    public static func noHistoryCap(for name: String, symptomContext: Bool) -> Int {
        let lowered = name.lowercased()
        if lowered.contains("dumbbell") {
            return symptomContext ? symptomNoHistoryDumbbellCap : noHistoryDumbbellCap
        }
        if lowered.contains("barbell")
            || lowered.contains("squat")
            || lowered.contains("deadlift")
            || lowered.contains("bench") {
            return symptomContext ? symptomNoHistoryBarbellCap : noHistoryBarbellCap
        }
        return symptomContext ? symptomNoHistoryOtherCap : noHistoryOtherCap
    }

    private static func applySessionVolumeCap(
        _ exercises: inout [WeeklyWorkoutExercise],
        input: Input,
        events: inout [Event]
    ) {
        guard let maxRecent = input.maxRecentSessionVolume, maxRecent > 0 else { return }
        let cap = maxRecent * (1 + maxSessionVolumeJumpFraction)
        let originalSets = exercises.map(\.sets)

        while sessionVolume(exercises) > cap {
            guard let index = indexOfLargestReducibleExercise(exercises) else { break }
            let exercise = exercises[index]
            exercises[index] = WeeklyWorkoutExercise(
                name: exercise.name,
                sets: exercise.sets - 1,
                reps: exercise.reps,
                weight: exercise.weight,
                targetRPE: exercise.targetRPE,
                restSeconds: exercise.restSeconds
            )
        }

        for (index, exercise) in exercises.enumerated() where exercise.sets != originalSets[index] {
            events.append(Event(
                kind: .sessionVolumeCap, exerciseName: exercise.name,
                field: "sets", original: originalSets[index], clamped: exercise.sets
            ))
        }
    }

    private static func sessionVolume(_ exercises: [WeeklyWorkoutExercise]) -> Double {
        exercises.reduce(0) { total, exercise in
            total + Double(exercise.sets * exercise.reps * exercise.weight)
        }
    }

    private static func indexOfLargestReducibleExercise(_ exercises: [WeeklyWorkoutExercise]) -> Int? {
        exercises.indices
            .filter { exercises[$0].sets > 1 }
            .max { lhs, rhs in
                let lhsVolume = exercises[lhs].sets * exercises[lhs].reps * exercises[lhs].weight
                let rhsVolume = exercises[rhs].sets * exercises[rhs].reps * exercises[rhs].weight
                return lhsVolume < rhsVolume
            }
    }
}
