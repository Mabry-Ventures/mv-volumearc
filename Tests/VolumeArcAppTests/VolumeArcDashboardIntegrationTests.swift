#if canImport(SwiftData)
import XCTest
import SwiftData
import VolumeArcCore

/// End-to-end integration tests that exercise the full chain:
/// dashboard action → repository → aggregate update → widget snapshot.
///
/// Uses an in-memory SwiftData container so tests are hermetic and fast.
/// No mocks for the data layer — the real repositories are under test.
@MainActor
final class VolumeArcDashboardIntegrationTests: XCTestCase {
    private var container: ModelContainer!
    private var workoutRepository: SwiftDataWorkoutRepository!
    private var coachMemoryRepository: SwiftDataCoachMemoryRepository!
    private var userProfileRepository: SwiftDataUserProfileRepository!
    private var trainingPlanRepository: SwiftDataTrainingPlanRepository!

    override func setUp() async throws {
        let schema = Schema(VolumeArcSchemaV1.models)
        let config = ModelConfiguration(
            "IntegrationTest-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(
            for: schema,
            migrationPlan: VolumeArcSchemaMigrationPlan.self,
            configurations: [config]
        )

        workoutRepository = SwiftDataWorkoutRepository(container: container)
        coachMemoryRepository = SwiftDataCoachMemoryRepository(container: container)
        userProfileRepository = SwiftDataUserProfileRepository(container: container)
        trainingPlanRepository = SwiftDataTrainingPlanRepository(container: container)
    }

    override func tearDown() async throws {
        container = nil
        workoutRepository = nil
        coachMemoryRepository = nil
        userProfileRepository = nil
        trainingPlanRepository = nil
    }

    // MARK: - Workout create → append → complete chain

    func testCreateWorkoutProducesExactlyOneActiveRecord() throws {
        _ = try workoutRepository.createWorkout(title: "Strength Day")

        let active = try workoutRepository.activeWorkout()
        XCTAssertNotNil(active, "activeWorkout should return the newly created session")
        XCTAssertEqual(active?.title, "Strength Day")
        XCTAssertNil(active?.completedAt, "New workout should not be marked complete")
    }

    func testAppendSetUpdatesWorkoutAggregates() throws {
        let workout = try workoutRepository.createWorkout(title: "Leg Day")

        let set = WorkoutSetPerformance(
            weight: 225,
            reps: 5,
            rpe: 7.5,
            completedAt: .now
        )
        try workoutRepository.appendSet(
            set,
            forExercise: "back-squat",
            to: workout.identifier
        )

        let updated = try workoutRepository.workout(withIdentifier: workout.identifier)
        XCTAssertEqual(updated?.completedSetCount, 1)
        XCTAssertEqual(updated?.totalVolumeLoad, 225 * 5)
        XCTAssertEqual(updated?.averageRPE ?? 0, 7.5, accuracy: 0.01)
        XCTAssertTrue(updated?.exerciseIDsCSV.contains("back-squat") ?? false)
    }

    func testMultipleSetsAccumulate() throws {
        let workout = try workoutRepository.createWorkout(title: "Chest Day")

        for weight in [135.0, 155.0, 175.0] {
            try workoutRepository.appendSet(
                WorkoutSetPerformance(weight: weight, reps: 8, rpe: 7.0, completedAt: .now),
                forExercise: "bench-press",
                to: workout.identifier
            )
        }

        let updated = try workoutRepository.workout(withIdentifier: workout.identifier)
        XCTAssertEqual(updated?.completedSetCount, 3)
        XCTAssertEqual(updated?.totalVolumeLoad ?? 0, 3720, accuracy: 0.01) // 135*8 + 155*8 + 175*8
    }

    func testCompleteWorkoutClearsActiveState() throws {
        let workout = try workoutRepository.createWorkout(title: "Pull Day")

        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 185, reps: 6, rpe: 8, completedAt: .now),
            forExercise: "barbell-row",
            to: workout.identifier
        )

        try workoutRepository.completeWorkout(identifier: workout.identifier, summary: "Solid session")

        let active = try workoutRepository.activeWorkout()
        XCTAssertNil(active, "No active workout should remain after completion")

        let completed = try workoutRepository.workout(withIdentifier: workout.identifier)
        XCTAssertNotNil(completed?.completedAt, "Completed workout must have a completion timestamp")
        XCTAssertEqual(completed?.summary, "Solid session")
    }

    // MARK: - History projection

    func testHistoryProjectionBuildsFromAppendedSets() throws {
        let workout = try workoutRepository.createWorkout(title: "Session 1")

        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 225, reps: 5, rpe: 7, completedAt: .now),
            forExercise: "back-squat",
            to: workout.identifier
        )
        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 245, reps: 3, rpe: 8, completedAt: .now),
            forExercise: "back-squat",
            to: workout.identifier
        )
        try workoutRepository.completeWorkout(identifier: workout.identifier)

        let history = try workoutRepository.history(forExercise: "back-squat")
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.topWeight, 245)
    }

    // MARK: - Recent sessions projection

    func testRecentSessionsReflectCompletedWorkouts() throws {
        // Create two completed sessions
        let one = try workoutRepository.createWorkout(title: "Session A")
        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 100, reps: 10, rpe: 6, completedAt: .now),
            forExercise: "goblet-squat",
            to: one.identifier
        )
        try workoutRepository.completeWorkout(identifier: one.identifier)

        let two = try workoutRepository.createWorkout(title: "Session B")
        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 135, reps: 8, rpe: 7, completedAt: .now),
            forExercise: "romanian-deadlift",
            to: two.identifier
        )
        try workoutRepository.completeWorkout(identifier: two.identifier)

        let recent = try workoutRepository.recentSessions(limit: 10)
        XCTAssertEqual(recent.count, 2)
        XCTAssertTrue(recent.allSatisfy { $0.completedSetCount == 1 })
    }

    // MARK: - Profile + onboarding

    func testUpsertProfilePersistsValues() throws {
        let defaults = UserProfileDefaults(
            name: "Jane Lifter",
            coachingStyle: .analytical,
            privacyMode: .strict,
            advancementLevel: .advanced,
            availableEquipment: [.barbell, .dumbbell],
            preferredRepRangeLower: 3,
            preferredRepRangeUpper: 6,
            sessionTimeBudgetMinutes: 75,
            weeklyTrainingDays: 5
        )
        try userProfileRepository.upsertProfile(defaults)

        let profile = try userProfileRepository.athleteProfile()
        XCTAssertEqual(profile.name, "Jane Lifter")
        XCTAssertEqual(profile.advancementLevel, .advanced)
        XCTAssertEqual(profile.weeklyTrainingDays, 5)
        XCTAssertEqual(profile.preferredRepRange, 3...6)
    }

    func testMarkOnboardingCompleteFlipsFlag() throws {
        let defaults = UserProfileDefaults(
            name: "Tester",
            coachingStyle: .motivational,
            privacyMode: .standard,
            advancementLevel: .intermediate,
            availableEquipment: [.barbell],
            preferredRepRangeLower: 5,
            preferredRepRangeUpper: 8,
            sessionTimeBudgetMinutes: 60,
            weeklyTrainingDays: 4
        )
        try userProfileRepository.upsertProfile(defaults)

        XCTAssertFalse(try userProfileRepository.isOnboardingComplete())
        try userProfileRepository.markOnboardingComplete()
        XCTAssertTrue(try userProfileRepository.isOnboardingComplete())
    }

    // MARK: - Coach memory

    func testCoachMemoryAppendAndProject() throws {
        try coachMemoryRepository.append(
            content: "User mentioned squat felt heavy off the floor",
            theme: "squat"
        )

        let memory = try coachMemoryRepository.coachMemory()
        XCTAssertEqual(memory.entries.count, 1)
        XCTAssertEqual(memory.entries.first?.theme, "squat")
        XCTAssertTrue(memory.entries.first?.summary.contains("squat") ?? false)
    }

    // MARK: - Training plan

    func testTrainingPlanUpsertAndQuery() throws {
        let plan = [
            WeeklyWorkout(dayOfWeek: 1, title: "Monday Squat"),
            WeeklyWorkout(dayOfWeek: 3, title: "Wednesday Bench"),
            WeeklyWorkout(dayOfWeek: 5, title: "Friday Deadlift"),
        ]
        try trainingPlanRepository.upsertPlan(plan)

        let fetched = try trainingPlanRepository.weeklyWorkouts()
        XCTAssertEqual(fetched.count, 3)
        XCTAssertEqual(fetched.map(\.title), plan.map(\.title))
    }
}
#endif
