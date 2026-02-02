// WorkoutPlanTests.swift
// BeastModeTests
// Unit tests for workout plans and sharing

import XCTest
import SwiftData
@testable import BeastMode

final class WorkoutPlanTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            PersonalRecord.self,
            UserProfile.self,
            UserStreak.self,
            Exercise.self,
            Workout.self,
            WorkoutExercise.self,
            SetLog.self,
            WorkoutPlan.self,
            PlanDay.self,
            PlanExercise.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
    }

    // MARK: - WorkoutPlan Tests

    func testWorkoutPlan_Creation() {
        let userId = UUID()
        let plan = WorkoutPlan(
            userId: userId,
            name: "Push/Pull/Legs",
            description: "Classic 6-day split",
            daysPerWeek: 6,
            difficulty: .intermediate,
            targetGoal: .hypertrophy
        )

        XCTAssertEqual(plan.name, "Push/Pull/Legs")
        XCTAssertEqual(plan.planDescription, "Classic 6-day split")
        XCTAssertEqual(plan.daysPerWeek, 6)
        XCTAssertEqual(plan.difficulty, .intermediate)
        XCTAssertEqual(plan.targetGoal, .hypertrophy)
        XCTAssertFalse(plan.isActive)
        XCTAssertFalse(plan.isPublic)
        XCTAssertNil(plan.shareCode)
    }

    func testWorkoutPlan_ShareCodeGeneration() {
        let plan = WorkoutPlan(userId: UUID(), name: "Test Plan")
        plan.generateShareCode()

        XCTAssertNotNil(plan.shareCode)
        XCTAssertEqual(plan.shareCode?.count, 8)

        // Code should only contain valid characters
        let validChars = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let codeChars = CharacterSet(charactersIn: plan.shareCode!)
        XCTAssertTrue(codeChars.isSubset(of: validChars))
    }

    func testWorkoutPlan_TotalExercises() {
        let plan = WorkoutPlan(userId: UUID(), name: "Test Plan")

        let day1 = PlanDay(weekday: 2, name: "Push", isRestDay: false)
        day1.exercises.append(PlanExercise(exerciseId: UUID(), exerciseName: "Bench", order: 0))
        day1.exercises.append(PlanExercise(exerciseId: UUID(), exerciseName: "OHP", order: 1))

        let day2 = PlanDay(weekday: 3, name: "Pull", isRestDay: false)
        day2.exercises.append(PlanExercise(exerciseId: UUID(), exerciseName: "Rows", order: 0))

        let restDay = PlanDay(weekday: 1, name: "Rest", isRestDay: true)

        plan.days.append(day1)
        plan.days.append(day2)
        plan.days.append(restDay)

        XCTAssertEqual(plan.totalExercises, 3)
        XCTAssertEqual(plan.trainingDays.count, 2)
    }

    func testWorkoutPlan_TotalSets() {
        let plan = WorkoutPlan(userId: UUID(), name: "Test Plan")

        let day = PlanDay(weekday: 2, name: "Push", isRestDay: false)
        day.exercises.append(PlanExercise(exerciseId: UUID(), exerciseName: "Bench", order: 0, targetSets: 4))
        day.exercises.append(PlanExercise(exerciseId: UUID(), exerciseName: "OHP", order: 1, targetSets: 3))

        plan.days.append(day)

        XCTAssertEqual(plan.totalSets, 7)
    }

    // MARK: - PlanDay Tests

    func testPlanDay_SortedExercises() {
        let day = PlanDay(weekday: 2, name: "Push", isRestDay: false)

        let ex3 = PlanExercise(exerciseId: UUID(), exerciseName: "Flyes", order: 2)
        let ex1 = PlanExercise(exerciseId: UUID(), exerciseName: "Bench", order: 0)
        let ex2 = PlanExercise(exerciseId: UUID(), exerciseName: "OHP", order: 1)

        day.exercises.append(ex3)
        day.exercises.append(ex1)
        day.exercises.append(ex2)

        let sorted = day.sortedExercises
        XCTAssertEqual(sorted[0].exerciseName, "Bench")
        XCTAssertEqual(sorted[1].exerciseName, "OHP")
        XCTAssertEqual(sorted[2].exerciseName, "Flyes")
    }

    func testPlanDay_WeekdayName() {
        let monday = PlanDay(weekday: 2, name: "Push", isRestDay: false)
        XCTAssertEqual(monday.weekdayName, "Monday")
        XCTAssertEqual(monday.shortWeekdayName, "Mon")

        let sunday = PlanDay(weekday: 1, name: "Rest", isRestDay: true)
        XCTAssertEqual(sunday.weekdayName, "Sunday")
    }

    // MARK: - PlanExercise Tests

    func testPlanExercise_PrescriptionText() {
        let exercise = PlanExercise(
            exerciseId: UUID(),
            exerciseName: "Bench Press",
            order: 0,
            targetSets: 4,
            targetRepsMin: 6,
            targetRepsMax: 8
        )

        XCTAssertEqual(exercise.prescriptionText, "4 × 6-8")
        XCTAssertEqual(exercise.repRangeText, "6-8")
    }

    func testPlanExercise_PrescriptionText_SameReps() {
        let exercise = PlanExercise(
            exerciseId: UUID(),
            exerciseName: "Plank",
            order: 0,
            targetSets: 3,
            targetRepsMin: 60,
            targetRepsMax: 60
        )

        XCTAssertEqual(exercise.prescriptionText, "3 × 60")
        XCTAssertEqual(exercise.repRangeText, "60")
    }

    // MARK: - PlanDifficulty Tests

    func testPlanDifficulty_Properties() {
        XCTAssertEqual(PlanDifficulty.beginner.rawValue, "Beginner")
        XCTAssertEqual(PlanDifficulty.beginner.icon, "1.circle.fill")

        XCTAssertEqual(PlanDifficulty.intermediate.rawValue, "Intermediate")
        XCTAssertEqual(PlanDifficulty.intermediate.icon, "2.circle.fill")

        XCTAssertEqual(PlanDifficulty.advanced.rawValue, "Advanced")
        XCTAssertEqual(PlanDifficulty.advanced.icon, "3.circle.fill")
    }

    // MARK: - PlanGoal Tests

    func testPlanGoal_Properties() {
        XCTAssertEqual(PlanGoal.strength.rawValue, "Strength")
        XCTAssertEqual(PlanGoal.strength.icon, "bolt.fill")

        XCTAssertEqual(PlanGoal.hypertrophy.rawValue, "Hypertrophy")
        XCTAssertEqual(PlanGoal.hypertrophy.icon, "figure.strengthtraining.traditional")
    }

    // MARK: - PlanTemplate Tests

    func testPlanTemplate_DaysPerWeek() {
        XCTAssertEqual(PlanTemplate.ppl.daysPerWeek, 6)
        XCTAssertEqual(PlanTemplate.upperLower.daysPerWeek, 4)
        XCTAssertEqual(PlanTemplate.fullBody.daysPerWeek, 3)
        XCTAssertEqual(PlanTemplate.bro.daysPerWeek, 5)
        XCTAssertEqual(PlanTemplate.powerbuilding.daysPerWeek, 4)
    }

    // MARK: - ShareablePlan Tests

    func testShareablePlan_Encoding() throws {
        let plan = WorkoutPlan(
            userId: UUID(),
            name: "Test Plan",
            description: "A test plan",
            daysPerWeek: 4,
            difficulty: .intermediate,
            targetGoal: .strength
        )
        plan.authorName = "Test Author"
        plan.tags = ["strength", "4-day"]
        plan.equipmentRequired = ["Barbell"]
        plan.targetMuscleGroups = ["Chest"]

        let day = PlanDay(weekday: 2, name: "Push", isRestDay: false)
        let exercise = PlanExercise(
            exerciseId: UUID(),
            exerciseName: "Bench Press",
            order: 0,
            targetSets: 4,
            targetRepsMin: 6,
            targetRepsMax: 8
        )
        day.exercises.append(exercise)
        plan.days.append(day)

        let shareable = ShareablePlan(from: plan)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(shareable)

        XCTAssertGreaterThan(data.count, 0)

        // Verify it can be decoded
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShareablePlan.self, from: data)

        XCTAssertEqual(decoded.name, "Test Plan")
        XCTAssertEqual(decoded.description, "A test plan")
        XCTAssertEqual(decoded.authorName, "Test Author")
        XCTAssertEqual(decoded.daysPerWeek, 4)
        XCTAssertEqual(decoded.difficulty, "Intermediate")
        XCTAssertEqual(decoded.goal, "Strength")
        XCTAssertEqual(decoded.version, ShareablePlan.currentExportVersion)
        XCTAssertEqual(decoded.tags, ["strength", "4-day"])
        XCTAssertEqual(decoded.equipmentRequired, ["Barbell"])
        XCTAssertEqual(decoded.targetMuscleGroups, ["Chest"])
        XCTAssertEqual(decoded.days.count, 1)
        XCTAssertEqual(decoded.days[0].exercises.count, 1)
    }

    func testShareablePlan_ToPlan() throws {
        let json = """
        {
            "version": 2,
            "name": "Imported Plan",
            "description": "From a friend",
            "authorName": "Friend",
            "difficulty": "Advanced",
            "goal": "Hypertrophy",
            "daysPerWeek": 5,
            "estimatedDuration": 12,
            "days": [
                {
                    "weekday": 2,
                    "name": "Chest Day",
                    "isRestDay": false,
                    "notes": null,
                    "exercises": [
                        {
                            "name": "Bench Press",
                            "sets": 4,
                            "repsMin": 8,
                            "repsMax": 12,
                            "rpe": 8.0,
                            "restSeconds": 120,
                            "notes": null,
                            "superset": false
                        }
                    ]
                }
            ],
            "createdAt": "2024-01-15T10:00:00Z",
            "tags": ["hypertrophy", "5-day"],
            "equipmentRequired": ["Barbell", "Dumbbells"],
            "targetMuscleGroups": ["Chest", "Arms"]
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let shareable = try decoder.decode(ShareablePlan.self, from: data)

        let userId = UUID()
        let plan = shareable.toPlan(userId: userId)

        XCTAssertEqual(plan.name, "Imported Plan")
        XCTAssertEqual(plan.planDescription, "From a friend")
        XCTAssertEqual(plan.authorName, "Friend")
        XCTAssertEqual(plan.difficulty, .advanced)
        XCTAssertEqual(plan.targetGoal, .hypertrophy)
        XCTAssertEqual(plan.daysPerWeek, 5)
        XCTAssertEqual(plan.estimatedDuration, 12)
        XCTAssertEqual(plan.userId, userId)
        XCTAssertEqual(plan.schemaVersion, kWorkoutPlanCurrentVersion)
        XCTAssertEqual(plan.tags, ["hypertrophy", "5-day"])
        XCTAssertEqual(plan.equipmentRequired, ["Barbell", "Dumbbells"])
        XCTAssertEqual(plan.targetMuscleGroups, ["Chest", "Arms"])
        XCTAssertEqual(plan.days.count, 1)

        let day = plan.days[0]
        XCTAssertEqual(day.weekday, 2)
        XCTAssertEqual(day.name, "Chest Day")
        XCTAssertFalse(day.isRestDay)
        XCTAssertEqual(day.exercises.count, 1)

        let exercise = day.exercises[0]
        XCTAssertEqual(exercise.exerciseName, "Bench Press")
        XCTAssertEqual(exercise.targetSets, 4)
        XCTAssertEqual(exercise.targetRepsMin, 8)
        XCTAssertEqual(exercise.targetRepsMax, 12)
        XCTAssertEqual(exercise.targetRPE, 8.0)
        XCTAssertEqual(exercise.restSeconds, 120)
    }

    func testShareablePlan_V1Import_SetsDefaults() throws {
        // Test that V1 plans (without V2 fields) import correctly with defaults
        let v1Json = """
        {
            "version": 1,
            "name": "Legacy Plan",
            "description": null,
            "authorName": null,
            "difficulty": "Intermediate",
            "goal": "Strength",
            "daysPerWeek": 4,
            "estimatedDuration": 8,
            "days": [],
            "createdAt": "2024-01-15T10:00:00Z"
        }
        """

        let data = v1Json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let shareable = try decoder.decode(ShareablePlan.self, from: data)

        let plan = shareable.toPlan(userId: UUID())

        // V2 fields should be empty arrays (not nil)
        XCTAssertTrue(plan.tags.isEmpty)
        XCTAssertTrue(plan.equipmentRequired.isEmpty)
        XCTAssertTrue(plan.targetMuscleGroups.isEmpty)

        // Schema version should reflect original import version
        XCTAssertEqual(plan.schemaVersion, 1)
        XCTAssertTrue(plan.needsMigration)
    }
}

// MARK: - Plan Sharing Service Tests

final class PlanSharingServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            PersonalRecord.self,
            UserProfile.self,
            UserStreak.self,
            Exercise.self,
            Workout.self,
            WorkoutExercise.self,
            SetLog.self,
            WorkoutPlan.self,
            PlanDay.self,
            PlanExercise.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
    }

    func testPlanSharingService_ExportPlan() async throws {
        let plan = WorkoutPlan(userId: UUID(), name: "Test Plan")
        let day = PlanDay(weekday: 2, name: "Push", isRestDay: false)
        day.exercises.append(PlanExercise(exerciseId: UUID(), exerciseName: "Bench", order: 0))
        plan.days.append(day)

        let service = PlanSharingService(modelContext: modelContext)
        let data = try await service.exportPlan(plan)

        XCTAssertGreaterThan(data.count, 0)

        // Verify valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["name"] as? String, "Test Plan")
    }

    func testPlanSharingService_ImportPlan() async throws {
        let json = """
        {
            "version": 2,
            "name": "Imported Plan",
            "description": null,
            "authorName": null,
            "difficulty": "Intermediate",
            "goal": "Strength",
            "daysPerWeek": 4,
            "estimatedDuration": 8,
            "days": [
                {
                    "weekday": 2,
                    "name": "Day 1",
                    "isRestDay": false,
                    "notes": null,
                    "exercises": []
                }
            ],
            "createdAt": "2024-01-15T10:00:00Z",
            "tags": null,
            "equipmentRequired": null,
            "targetMuscleGroups": null
        }
        """

        let data = json.data(using: .utf8)!
        let userId = UUID()

        let service = PlanSharingService(modelContext: modelContext)
        let plan = try await service.importPlan(from: data, userId: userId)

        XCTAssertEqual(plan.name, "Imported Plan")
        XCTAssertEqual(plan.userId, userId)
        XCTAssertEqual(plan.schemaVersion, kWorkoutPlanCurrentVersion)
    }

    func testPlanSharingService_ValidatePlanData_UnsupportedVersion() async throws {
        let json = """
        {
            "version": 99,
            "name": "Future Plan",
            "description": null,
            "authorName": null,
            "difficulty": "Intermediate",
            "goal": "Strength",
            "daysPerWeek": 4,
            "estimatedDuration": 8,
            "days": [],
            "createdAt": "2024-01-15T10:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let service = PlanSharingService(modelContext: modelContext)

        do {
            _ = try await service.validatePlanData(data)
            XCTFail("Should throw unsupported version error")
        } catch PlanSharingError.unsupportedVersion(let version) {
            XCTAssertEqual(version, 99)
        }
    }

    func testPlanSharingService_GenerateShareLink() async throws {
        let plan = WorkoutPlan(userId: UUID(), name: "Test Plan")
        let service = PlanSharingService(modelContext: modelContext)

        let url = try await service.generateShareLink(plan)

        XCTAssertEqual(url.scheme, "beastmode")
        XCTAssertEqual(url.host, "import")
        XCTAssertTrue(url.absoluteString.contains("plan="))
    }
}

// MARK: - Complication Data Tests

final class ComplicationDataTests: XCTestCase {

    func testComplicationData_Encoding() throws {
        let data = ComplicationData(
            currentStreak: 7,
            todayWorkout: TodayWorkoutData(
                dayName: "Push Day",
                exerciseCount: 6,
                isRestDay: false,
                isCompleted: false
            ),
            weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
            lastUpdated: .now
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(ComplicationData.self, from: encoded)

        XCTAssertEqual(decoded.currentStreak, 7)
        XCTAssertEqual(decoded.todayWorkout?.dayName, "Push Day")
        XCTAssertEqual(decoded.todayWorkout?.exerciseCount, 6)
        XCTAssertFalse(decoded.todayWorkout?.isRestDay ?? true)
        XCTAssertFalse(decoded.todayWorkout?.isCompleted ?? true)
        XCTAssertEqual(decoded.weeklyProgress.completed, 3)
        XCTAssertEqual(decoded.weeklyProgress.target, 4)
    }

    func testWeeklyProgressData_ProgressPercentage() {
        let progress1 = WeeklyProgressData(completed: 3, target: 4)
        XCTAssertEqual(progress1.progressPercentage, 0.75)

        let progress2 = WeeklyProgressData(completed: 0, target: 4)
        XCTAssertEqual(progress2.progressPercentage, 0.0)

        let progress3 = WeeklyProgressData(completed: 4, target: 4)
        XCTAssertEqual(progress3.progressPercentage, 1.0)

        let progress4 = WeeklyProgressData(completed: 5, target: 4)
        XCTAssertEqual(progress4.progressPercentage, 1.25)

        let progress5 = WeeklyProgressData(completed: 3, target: 0)
        XCTAssertEqual(progress5.progressPercentage, 0.0)
    }

    func testComplicationData_Empty() {
        let empty = ComplicationData.empty

        XCTAssertEqual(empty.currentStreak, 0)
        XCTAssertNil(empty.todayWorkout)
        XCTAssertEqual(empty.weeklyProgress.completed, 0)
        XCTAssertEqual(empty.weeklyProgress.target, 4)
    }
}
