import Foundation
import VolumeArcCore

enum TestFixtures {
    static func liveActivityState(
        workoutTitle: String = "Strength Day",
        exercise: String = "Back Squat",
        target: String = "225 x 5",
        rest: Int? = 90
    ) -> LiveActivityState {
        LiveActivityState(
            workoutTitle: workoutTitle,
            activeExerciseName: exercise,
            targetSummary: target,
            restSecondsRemaining: rest
        )
    }

    static func watchPayload(
        kind: WatchPayloadKind = .liveState,
        workoutID: String = "test-session",
        body: String = "action=hold"
    ) -> WatchPayload {
        WatchPayload(kind: kind, workoutID: workoutID, body: body)
    }

    static func operationalSignal(
        id: String = "test-signal",
        title: String = "Test",
        message: String = "Test signal message",
        severity: TelemetrySeverity = .warning
    ) -> OperationalSignalSummary {
        OperationalSignalSummary(id: id, title: title, message: message, severity: severity)
    }

    static func telemetryEvent(
        category: String = "test",
        name: String = "test_event",
        severity: TelemetrySeverity = .info,
        message: String = "Test event"
    ) -> TelemetryEvent {
        TelemetryEvent(category: category, name: name, severity: severity, message: message)
    }

    // MARK: - Readiness

    /// The inputs the `ReadinessModel` consumes: a recent-session history
    /// plus the athlete profile. Bundled as a tuple so tests can drive
    /// `ReadinessModel.evaluate(sessions:athlete:)` with one call.
    static func readinessInput(
        sessions: [RecentSession]? = nil,
        athlete: AthleteProfile = athleteProfile()
    ) -> (sessions: [RecentSession], athlete: AthleteProfile) {
        (sessions ?? workoutSequence(), athlete)
    }

    static func athleteProfile(
        name: String = "Test Athlete",
        weeklyTrainingDays: Int = 4
    ) -> AthleteProfile {
        AthleteProfile(
            name: name,
            weeklyTrainingDays: weeklyTrainingDays
        )
    }

    /// A five-session workout sequence spanning the last seven days with
    /// ascending volume and a mid-range RPE profile — representative of
    /// an intermediate lifter's week. Useful for readiness and
    /// progression tests that need more than one data point.
    static func workoutSequence(reference: Date = .now) -> [RecentSession] {
        [
            RecentSession(
                date: reference.addingTimeInterval(-86_400 * 6),
                durationMinutes: 55,
                exerciseIDs: ["back-squat", "bench-press"],
                totalVolumeLoad: 6_400,
                averageRPE: 7.0,
                completedSetCount: 12
            ),
            RecentSession(
                date: reference.addingTimeInterval(-86_400 * 4),
                durationMinutes: 62,
                exerciseIDs: ["deadlift", "overhead-press"],
                totalVolumeLoad: 7_200,
                averageRPE: 7.5,
                completedSetCount: 11
            ),
            RecentSession(
                date: reference.addingTimeInterval(-86_400 * 2),
                durationMinutes: 58,
                exerciseIDs: ["back-squat", "pull-up"],
                totalVolumeLoad: 7_800,
                averageRPE: 8.0,
                completedSetCount: 13
            ),
            RecentSession(
                date: reference.addingTimeInterval(-86_400 * 1),
                durationMinutes: 64,
                exerciseIDs: ["bench-press", "bent-row"],
                totalVolumeLoad: 8_100,
                averageRPE: 8.0,
                completedSetCount: 12
            ),
            RecentSession(
                date: reference.addingTimeInterval(-3_600 * 6),
                durationMinutes: 48,
                exerciseIDs: ["deadlift"],
                totalVolumeLoad: 5_400,
                averageRPE: 7.0,
                completedSetCount: 8
            ),
        ]
    }

    /// A three-day training plan snapshot (heavy / accessory / light) with
    /// representative sets. Returned as a list of `ExerciseSession`
    /// values — one per plan day — so tests can feed it into repositories,
    /// progression helpers, or the `SyncPayloadCodec` without needing
    /// extra adapter code.
    static func trainingPlanThreeDays(reference: Date = .now) -> [ExerciseSession] {
        [
            // Day 1 — heavy barbell day.
            ExerciseSession(
                date: reference.addingTimeInterval(-86_400 * 5),
                sets: [
                    WorkoutSetPerformance(weight: 225, reps: 5, rpe: 8.0, completedAt: reference.addingTimeInterval(-86_400 * 5)),
                    WorkoutSetPerformance(weight: 225, reps: 5, rpe: 8.5, completedAt: reference.addingTimeInterval(-86_400 * 5 + 180)),
                    WorkoutSetPerformance(weight: 235, reps: 3, rpe: 9.0, completedAt: reference.addingTimeInterval(-86_400 * 5 + 360)),
                ]
            ),
            // Day 2 — accessory volume day.
            ExerciseSession(
                date: reference.addingTimeInterval(-86_400 * 3),
                sets: [
                    WorkoutSetPerformance(weight: 135, reps: 10, rpe: 7.0, completedAt: reference.addingTimeInterval(-86_400 * 3)),
                    WorkoutSetPerformance(weight: 135, reps: 10, rpe: 7.5, completedAt: reference.addingTimeInterval(-86_400 * 3 + 180)),
                    WorkoutSetPerformance(weight: 145, reps: 8, rpe: 8.0, completedAt: reference.addingTimeInterval(-86_400 * 3 + 360)),
                ]
            ),
            // Day 3 — light / technique day.
            ExerciseSession(
                date: reference.addingTimeInterval(-86_400 * 1),
                sets: [
                    WorkoutSetPerformance(weight: 95, reps: 12, rpe: 6.0, completedAt: reference.addingTimeInterval(-86_400 * 1)),
                    WorkoutSetPerformance(weight: 95, reps: 12, rpe: 6.5, completedAt: reference.addingTimeInterval(-86_400 * 1 + 180)),
                ]
            ),
        ]
    }
}
