import XCTest
import VolumeArcCore

/// Tests for ProgressionEngine — periodization, exercise selection, action suggestions.
/// Exercises real production logic.
final class VolumeArcProgressionTests: XCTestCase {
    private let engine = ProgressionEngine()
    private let athlete = AthleteProfile(
        name: "Test",
        advancementLevel: .intermediate,
        availableEquipment: [.barbell, .dumbbell, .machine, .bodyweight]
    )

    // MARK: - Empty history → starter target

    func testEmptyHistoryReturnsStarterTarget() {
        let history = ExerciseHistory(exerciseID: "back-squat")
        let state = engine.buildAutopilotState(
            for: history,
            athlete: athlete,
            goal: .generalStrength,
            recentSessions: [],
            memory: CoachMemory()
        )

        XCTAssertEqual(state.nextExerciseID, "back-squat")
        XCTAssertEqual(state.nextExerciseName, "Back Squat")
        XCTAssertGreaterThan(state.nextTarget.weight, 0)
        XCTAssertFalse(state.recommendationReason.isEmpty)
    }

    // MARK: - Progression after hitting target

    func testProgressionIncrementsAfterHittingUpperRepBound() {
        let lastSession = ExerciseSession(
            date: .now.addingTimeInterval(-86_400),
            sets: [
                WorkoutSetPerformance(weight: 225, reps: 8, rpe: 7.0, completedAt: .now.addingTimeInterval(-86_400)),
                WorkoutSetPerformance(weight: 225, reps: 8, rpe: 7.5, completedAt: .now.addingTimeInterval(-86_400 + 300)),
            ]
        )
        let history = ExerciseHistory(exerciseID: "back-squat", sessions: [lastSession])

        let state = engine.buildAutopilotState(
            for: history,
            athlete: athlete,
            goal: .generalStrength,
            recentSessions: [],
            memory: CoachMemory()
        )

        // Intermediate progresses by 2.5 lbs
        XCTAssertGreaterThan(state.nextTarget.weight, 225,
            "Hitting top of rep range at target RPE should trigger progression")
        XCTAssertEqual(state.nextTarget.weight, 227.5,
            "Intermediate progression should add 2.5 lb")
    }

    func testProgressionIncrementIsLevelDependent() {
        let lastSession = ExerciseSession(
            date: .now,
            sets: [WorkoutSetPerformance(weight: 100, reps: 8, rpe: 7.0, completedAt: .now)]
        )
        let history = ExerciseHistory(exerciseID: "back-squat", sessions: [lastSession])

        let beginner = AthleteProfile(name: "A", advancementLevel: .beginner)
        let beginnerState = engine.buildAutopilotState(
            for: history, athlete: beginner, goal: .generalStrength,
            recentSessions: [], memory: CoachMemory()
        )

        let advanced = AthleteProfile(name: "A", advancementLevel: .advanced)
        let advancedState = engine.buildAutopilotState(
            for: history, athlete: advanced, goal: .generalStrength,
            recentSessions: [], memory: CoachMemory()
        )

        // Beginner: +5, Advanced: +1.25
        XCTAssertEqual(beginnerState.nextTarget.weight, 105)
        XCTAssertEqual(advancedState.nextTarget.weight, 101.25)
    }

    // MARK: - Holds when grinding

    func testHoldsWeightAfterGrindingSession() {
        let lastSession = ExerciseSession(
            date: .now.addingTimeInterval(-86_400),
            sets: [WorkoutSetPerformance(weight: 225, reps: 5, rpe: 9.5, completedAt: .now.addingTimeInterval(-86_400))]
        )
        let history = ExerciseHistory(exerciseID: "back-squat", sessions: [lastSession])

        let state = engine.buildAutopilotState(
            for: history,
            athlete: athlete,
            goal: .generalStrength,
            recentSessions: [],
            memory: CoachMemory()
        )

        XCTAssertEqual(state.nextTarget.weight, 225,
            "A grinding session at RPE 9.5 should result in holding the weight")
    }

    // MARK: - Exercise substitution

    func testExerciseSubstitutionRespectsAvailableEquipment() {
        let barbellOnlyAthlete = AthleteProfile(
            name: "A",
            availableEquipment: [.dumbbell, .bodyweight]
        )
        let history = ExerciseHistory(exerciseID: "back-squat")

        let state = engine.buildAutopilotState(
            for: history,
            athlete: barbellOnlyAthlete,
            goal: .generalStrength,
            recentSessions: [],
            memory: CoachMemory()
        )

        XCTAssertNotEqual(state.nextExerciseID, "back-squat",
            "Back squat requires barbell; should substitute when only dumbbells/bodyweight available")
    }

    // MARK: - Goal-based rep ranges

    func testHypertrophyGoalProducesHigherRepRange() {
        let lastSession = ExerciseSession(
            date: .now,
            sets: [WorkoutSetPerformance(weight: 135, reps: 8, rpe: 7.0, completedAt: .now)]
        )
        let history = ExerciseHistory(exerciseID: "bench-press", sessions: [lastSession])

        let strength = engine.buildAutopilotState(
            for: history, athlete: athlete, goal: .generalStrength,
            recentSessions: [], memory: CoachMemory()
        )
        let hypertrophy = engine.buildAutopilotState(
            for: history, athlete: athlete, goal: .hypertrophy,
            recentSessions: [], memory: CoachMemory()
        )
        let powerlifting = engine.buildAutopilotState(
            for: history, athlete: athlete, goal: .powerlifting,
            recentSessions: [], memory: CoachMemory()
        )

        XCTAssertEqual(hypertrophy.nextTarget.repRange, 8...12)
        XCTAssertEqual(powerlifting.nextTarget.repRange, 3...5)
        XCTAssertNotEqual(strength.nextTarget.repRange, hypertrophy.nextTarget.repRange)
    }

    // MARK: - Recommendation reason quality

    func testRecommendationReasonCitesLastSession() {
        let lastSession = ExerciseSession(
            date: .now.addingTimeInterval(-86_400),
            sets: [WorkoutSetPerformance(weight: 185, reps: 5, rpe: 7.5, completedAt: .now.addingTimeInterval(-86_400))]
        )
        let history = ExerciseHistory(exerciseID: "back-squat", sessions: [lastSession])

        let state = engine.buildAutopilotState(
            for: history,
            athlete: athlete,
            goal: .generalStrength,
            recentSessions: [],
            memory: CoachMemory()
        )

        XCTAssertTrue(state.recommendationReason.contains("185"),
            "Reason should cite the actual weight from last session")
    }

    // MARK: - Two different users get different recommendations

    func testDifferentHistoriesProduceDifferentStates() {
        let weakHistory = ExerciseHistory(exerciseID: "back-squat", sessions: [
            ExerciseSession(date: .now, sets: [
                WorkoutSetPerformance(weight: 135, reps: 8, rpe: 7.0, completedAt: .now)
            ])
        ])
        let strongHistory = ExerciseHistory(exerciseID: "back-squat", sessions: [
            ExerciseSession(date: .now, sets: [
                WorkoutSetPerformance(weight: 405, reps: 8, rpe: 7.0, completedAt: .now)
            ])
        ])

        let weakState = engine.buildAutopilotState(
            for: weakHistory, athlete: athlete, goal: .generalStrength,
            recentSessions: [], memory: CoachMemory()
        )
        let strongState = engine.buildAutopilotState(
            for: strongHistory, athlete: athlete, goal: .generalStrength,
            recentSessions: [], memory: CoachMemory()
        )

        XCTAssertNotEqual(weakState.nextTarget.weight, strongState.nextTarget.weight,
            "Two athletes with different histories must get different recommendations")
    }
}
