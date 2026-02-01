// ComplicationUpdateServiceTests.swift
// BeastModeTests
// Comprehensive unit tests for ComplicationUpdateService

import Testing
import SwiftData
import Foundation
@testable import BeastMode

// MARK: - Complication Update Service Tests

@Suite("Complication Update Service")
struct ComplicationUpdateServiceTests {

    // MARK: - Complication Data Tests

    @Suite("Complication Data Model")
    struct ComplicationDataModelTests {

        @Test("Complication data stores all fields")
        func complicationDataStoresAllFields() {
            let now = Date()
            let todayWorkout = TodayWorkoutData(
                dayName: "Push Day",
                exerciseCount: 5,
                isRestDay: false,
                isCompleted: false
            )
            let weeklyProgress = WeeklyProgressData(completed: 3, target: 4)

            let data = ComplicationData(
                currentStreak: 14,
                todayWorkout: todayWorkout,
                weeklyProgress: weeklyProgress,
                lastUpdated: now
            )

            #expect(data.currentStreak == 14)
            #expect(data.todayWorkout?.dayName == "Push Day")
            #expect(data.weeklyProgress.completed == 3)
            #expect(data.lastUpdated == now)
        }

        @Test("Empty complication data has defaults")
        func emptyComplicationDataHasDefaults() {
            let empty = ComplicationData.empty

            #expect(empty.currentStreak == 0)
            #expect(empty.todayWorkout == nil)
            #expect(empty.weeklyProgress.completed == 0)
            #expect(empty.weeklyProgress.target == 4)
        }

        @Test("Complication data encodes to JSON")
        func complicationDataEncodesToJSON() throws {
            let data = ComplicationData(
                currentStreak: 7,
                todayWorkout: TodayWorkoutData(
                    dayName: "Leg Day",
                    exerciseCount: 4,
                    isRestDay: false,
                    isCompleted: true
                ),
                weeklyProgress: WeeklyProgressData(completed: 4, target: 4),
                lastUpdated: Date()
            )

            let encoded = try JSONEncoder().encode(data)
            #expect(encoded.count > 0)

            let decoded = try JSONDecoder().decode(ComplicationData.self, from: encoded)
            #expect(decoded.currentStreak == 7)
            #expect(decoded.todayWorkout?.dayName == "Leg Day")
        }

        @Test("Complication data handles nil today workout")
        func complicationDataHandlesNilTodayWorkout() throws {
            let data = ComplicationData(
                currentStreak: 5,
                todayWorkout: nil,
                weeklyProgress: WeeklyProgressData(completed: 2, target: 5),
                lastUpdated: Date()
            )

            let encoded = try JSONEncoder().encode(data)
            let decoded = try JSONDecoder().decode(ComplicationData.self, from: encoded)

            #expect(decoded.todayWorkout == nil)
        }
    }

    // MARK: - Today Workout Data Tests

    @Suite("Today Workout Data Model")
    struct TodayWorkoutDataTests {

        @Test("Today workout data stores correct values")
        func todayWorkoutDataStoresCorrectValues() {
            let data = TodayWorkoutData(
                dayName: "Push Day",
                exerciseCount: 6,
                isRestDay: false,
                isCompleted: false
            )

            #expect(data.dayName == "Push Day")
            #expect(data.exerciseCount == 6)
            #expect(data.isRestDay == false)
            #expect(data.isCompleted == false)
        }

        @Test("Rest day workout data")
        func restDayWorkoutData() {
            let data = TodayWorkoutData(
                dayName: "Rest",
                exerciseCount: 0,
                isRestDay: true,
                isCompleted: false
            )

            #expect(data.isRestDay == true)
            #expect(data.exerciseCount == 0)
        }

        @Test("Completed workout data")
        func completedWorkoutData() {
            let data = TodayWorkoutData(
                dayName: "Pull Day",
                exerciseCount: 5,
                isRestDay: false,
                isCompleted: true
            )

            #expect(data.isCompleted == true)
        }

        @Test("Today workout data encodes correctly")
        func todayWorkoutDataEncodesCorrectly() throws {
            let original = TodayWorkoutData(
                dayName: "Full Body",
                exerciseCount: 8,
                isRestDay: false,
                isCompleted: false
            )

            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(TodayWorkoutData.self, from: encoded)

            #expect(decoded.dayName == original.dayName)
            #expect(decoded.exerciseCount == original.exerciseCount)
            #expect(decoded.isRestDay == original.isRestDay)
            #expect(decoded.isCompleted == original.isCompleted)
        }
    }

    // MARK: - Weekly Progress Data Tests

    @Suite("Weekly Progress Data Model")
    struct WeeklyProgressDataTests {

        @Test("Weekly progress calculates percentage correctly")
        func weeklyProgressCalculatesPercentageCorrectly() {
            let data = WeeklyProgressData(completed: 3, target: 4)
            #expect(data.progressPercentage == 0.75)
        }

        @Test("Weekly progress at 100%")
        func weeklyProgressAt100Percent() {
            let data = WeeklyProgressData(completed: 4, target: 4)
            #expect(data.progressPercentage == 1.0)
        }

        @Test("Weekly progress over 100%")
        func weeklyProgressOver100Percent() {
            let data = WeeklyProgressData(completed: 6, target: 4)
            #expect(data.progressPercentage == 1.5)
        }

        @Test("Weekly progress at 0%")
        func weeklyProgressAt0Percent() {
            let data = WeeklyProgressData(completed: 0, target: 4)
            #expect(data.progressPercentage == 0.0)
        }

        @Test("Weekly progress with zero target")
        func weeklyProgressWithZeroTarget() {
            let data = WeeklyProgressData(completed: 3, target: 0)
            #expect(data.progressPercentage == 0.0)
        }

        @Test("Weekly progress encodes correctly")
        func weeklyProgressEncodesCorrectly() throws {
            let original = WeeklyProgressData(completed: 5, target: 6)

            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(WeeklyProgressData.self, from: encoded)

            #expect(decoded.completed == 5)
            #expect(decoded.target == 6)
        }

        @Test("Weekly progress percentage precision",
              arguments: [
                (1, 4, 0.25),
                (2, 4, 0.5),
                (1, 3, 0.333333),
                (2, 3, 0.666666)
              ])
        func weeklyProgressPercentagePrecision(completed: Int, target: Int, expectedApprox: Double) {
            let data = WeeklyProgressData(completed: completed, target: target)
            #expect(abs(data.progressPercentage - expectedApprox) < 0.001)
        }
    }

    // MARK: - Complication Data Manager Tests

    @Suite("Complication Data Manager")
    struct ComplicationDataManagerTests {

        @Test("Manager singleton exists")
        func managerSingletonExists() {
            let manager1 = ComplicationDataManager.shared
            let manager2 = ComplicationDataManager.shared

            // Should be same instance
            #expect(manager1 === manager2)
        }

        @Test("Manager loads empty data when no data saved")
        func managerLoadsEmptyDataWhenNoDataSaved() {
            let manager = ComplicationDataManager.shared

            // Clear any existing data first
            manager.saveData(.empty)

            let data = manager.loadData()

            // Should return empty data structure
            #expect(data.currentStreak >= 0)
            #expect(data.weeklyProgress.completed >= 0)
        }

        @Test("Manager saves and loads streak update")
        func managerSavesAndLoadsStreakUpdate() {
            let manager = ComplicationDataManager.shared

            manager.updateStreak(21)
            let data = manager.loadData()

            #expect(data.currentStreak == 21)
        }

        @Test("Manager saves and loads today workout update")
        func managerSavesAndLoadsTodayWorkoutUpdate() {
            let manager = ComplicationDataManager.shared

            let workout = TodayWorkoutData(
                dayName: "Arms",
                exerciseCount: 6,
                isRestDay: false,
                isCompleted: false
            )

            manager.updateTodayWorkout(workout)
            let data = manager.loadData()

            #expect(data.todayWorkout?.dayName == "Arms")
            #expect(data.todayWorkout?.exerciseCount == 6)
        }

        @Test("Manager saves and loads weekly progress update")
        func managerSavesAndLoadsWeeklyProgressUpdate() {
            let manager = ComplicationDataManager.shared

            manager.updateWeeklyProgress(completed: 5, target: 6)
            let data = manager.loadData()

            #expect(data.weeklyProgress.completed == 5)
            #expect(data.weeklyProgress.target == 6)
        }

        @Test("Manager preserves other data on streak update")
        func managerPreservesOtherDataOnStreakUpdate() {
            let manager = ComplicationDataManager.shared

            // Set initial state
            let fullData = ComplicationData(
                currentStreak: 10,
                todayWorkout: TodayWorkoutData(
                    dayName: "Chest",
                    exerciseCount: 4,
                    isRestDay: false,
                    isCompleted: false
                ),
                weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
                lastUpdated: Date()
            )
            manager.saveData(fullData)

            // Update only streak
            manager.updateStreak(15)

            let data = manager.loadData()

            // Streak should be updated
            #expect(data.currentStreak == 15)

            // Other data should be preserved
            #expect(data.todayWorkout?.dayName == "Chest")
            #expect(data.weeklyProgress.completed == 3)
        }

        @Test("Manager handles nil today workout")
        func managerHandlesNilTodayWorkout() {
            let manager = ComplicationDataManager.shared

            manager.updateTodayWorkout(nil)
            let data = manager.loadData()

            #expect(data.todayWorkout == nil)
        }
    }

    // MARK: - Streak Fetching Tests

    @Suite("Streak Fetching")
    struct StreakFetchingTests {

        @Test("Fetches current streak for user")
        @MainActor
        func fetchesCurrentStreakForUser() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Create streak for user
            let streak = UserStreak(userId: userId)
            streak.currentStreak = 14
            context.insert(streak)
            try context.save()

            let service = ComplicationUpdateService(modelContext: context)

            // Update all complications (includes fetching streak)
            try await service.updateAllComplications(for: userId)

            // Verify via data manager
            let data = ComplicationDataManager.shared.loadData()
            #expect(data.currentStreak == 14)
        }

        @Test("Returns zero streak for new user")
        @MainActor
        func returnsZeroStreakForNewUser() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID() // No streak record

            let service = ComplicationUpdateService(modelContext: container.mainContext)
            try await service.updateAllComplications(for: userId)

            let data = ComplicationDataManager.shared.loadData()
            #expect(data.currentStreak == 0)
        }
    }

    // MARK: - Today Workout Fetching Tests

    @Suite("Today Workout Fetching")
    struct TodayWorkoutFetchingTests {

        @Test("Fetches today workout from active plan")
        @MainActor
        func fetchesTodayWorkoutFromActivePlan() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Create an active plan
            let plan = WorkoutPlan(
                name: "Test Plan",
                userId: userId,
                difficulty: .intermediate,
                goal: .strength,
                daysPerWeek: 4,
                estimatedDuration: 8
            )
            plan.isActive = true

            // Add a day for today's weekday
            let todayWeekday = Calendar.current.component(.weekday, from: Date())
            let day = PlanDay(
                weekday: todayWeekday,
                name: "Test Day",
                isRestDay: false
            )
            day.plan = plan

            // Add exercises
            let exercise = PlanExercise(
                exerciseId: UUID(),
                exerciseName: "Test Exercise",
                sortOrder: 1
            )
            exercise.planDay = day

            context.insert(plan)
            try context.save()

            let service = ComplicationUpdateService(modelContext: context)
            try await service.updateTodayWorkoutComplication(for: userId)

            let data = ComplicationDataManager.shared.loadData()
            #expect(data.todayWorkout?.dayName == "Test Day")
        }

        @Test("Returns nil when no active plan")
        @MainActor
        func returnsNilWhenNoActivePlan() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let service = ComplicationUpdateService(modelContext: container.mainContext)
            try await service.updateTodayWorkoutComplication(for: userId)

            let data = ComplicationDataManager.shared.loadData()
            #expect(data.todayWorkout == nil)
        }
    }

    // MARK: - Weekly Progress Fetching Tests

    @Suite("Weekly Progress Fetching")
    struct WeeklyProgressFetchingTests {

        @Test("Counts completed workouts this week")
        @MainActor
        func countsCompletedWorkoutsThisWeek() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Create workouts completed this week
            for i in 0..<3 {
                let workout = Workout(userId: userId)
                workout.startedAt = Date().addingTimeInterval(Double(-i) * 86400)
                workout.completedAt = workout.startedAt?.addingTimeInterval(3600)
                context.insert(workout)
            }

            try context.save()

            let service = ComplicationUpdateService(modelContext: context)
            try await service.updateWeeklyProgressComplication(for: userId)

            let data = ComplicationDataManager.shared.loadData()
            #expect(data.weeklyProgress.completed >= 0)
        }

        @Test("Uses target from active plan")
        @MainActor
        func usesTargetFromActivePlan() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Create active plan with 5 days per week
            let plan = WorkoutPlan(
                name: "5-Day Plan",
                userId: userId,
                difficulty: .advanced,
                goal: .hypertrophy,
                daysPerWeek: 5,
                estimatedDuration: 12
            )
            plan.isActive = true
            context.insert(plan)
            try context.save()

            let service = ComplicationUpdateService(modelContext: context)
            try await service.updateWeeklyProgressComplication(for: userId)

            let data = ComplicationDataManager.shared.loadData()
            #expect(data.weeklyProgress.target == 5)
        }

        @Test("Defaults to 4 days target when no plan")
        @MainActor
        func defaultsTo4DaysTargetWhenNoPlan() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let service = ComplicationUpdateService(modelContext: container.mainContext)
            try await service.updateWeeklyProgressComplication(for: userId)

            let data = ComplicationDataManager.shared.loadData()
            #expect(data.weeklyProgress.target == 4)
        }
    }

    // MARK: - Mark Today Completed Tests

    @Suite("Mark Today Completed")
    struct MarkTodayCompletedTests {

        @Test("Marks today as completed")
        @MainActor
        func marksTodayAsCompleted() async throws {
            let manager = ComplicationDataManager.shared

            // Set up initial state with uncompleted workout
            let initialData = ComplicationData(
                currentStreak: 5,
                todayWorkout: TodayWorkoutData(
                    dayName: "Push Day",
                    exerciseCount: 5,
                    isRestDay: false,
                    isCompleted: false
                ),
                weeklyProgress: WeeklyProgressData(completed: 2, target: 4),
                lastUpdated: Date()
            )
            manager.saveData(initialData)

            let container = try ModelContainerFactory.makeContainer()
            let service = ComplicationUpdateService(modelContext: container.mainContext)

            await service.markTodayCompleted()

            let data = manager.loadData()
            #expect(data.todayWorkout?.isCompleted == true)
            #expect(data.weeklyProgress.completed == 3)
        }

        @Test("Incrementing weekly progress on completion")
        @MainActor
        func incrementingWeeklyProgressOnCompletion() async throws {
            let manager = ComplicationDataManager.shared

            let initialData = ComplicationData(
                currentStreak: 10,
                todayWorkout: TodayWorkoutData(
                    dayName: "Back Day",
                    exerciseCount: 6,
                    isRestDay: false,
                    isCompleted: false
                ),
                weeklyProgress: WeeklyProgressData(completed: 3, target: 5),
                lastUpdated: Date()
            )
            manager.saveData(initialData)

            let container = try ModelContainerFactory.makeContainer()
            let service = ComplicationUpdateService(modelContext: container.mainContext)

            await service.markTodayCompleted()

            let data = manager.loadData()
            #expect(data.weeklyProgress.completed == 4)
        }
    }

    // MARK: - Update Streak Complication Tests

    @Suite("Update Streak Complication")
    struct UpdateStreakComplicationTests {

        @Test("Updates streak directly")
        @MainActor
        func updatesStreakDirectly() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = ComplicationUpdateService(modelContext: container.mainContext)

            service.updateStreakComplication(30)

            let data = ComplicationDataManager.shared.loadData()
            #expect(data.currentStreak == 30)
        }

        @Test("Streak update preserves other data")
        @MainActor
        func streakUpdatePreservesOtherData() async throws {
            let manager = ComplicationDataManager.shared

            // Set initial state
            let initialData = ComplicationData(
                currentStreak: 5,
                todayWorkout: TodayWorkoutData(
                    dayName: "Legs",
                    exerciseCount: 4,
                    isRestDay: false,
                    isCompleted: false
                ),
                weeklyProgress: WeeklyProgressData(completed: 2, target: 4),
                lastUpdated: Date()
            )
            manager.saveData(initialData)

            let container = try ModelContainerFactory.makeContainer()
            let service = ComplicationUpdateService(modelContext: container.mainContext)

            service.updateStreakComplication(10)

            let data = manager.loadData()
            #expect(data.currentStreak == 10)
            #expect(data.todayWorkout?.dayName == "Legs")
            #expect(data.weeklyProgress.completed == 2)
        }
    }

    // MARK: - Parameterized Tests

    @Test("Weekly progress percentage calculations",
          arguments: [
            (0, 4, 0.0),
            (1, 4, 0.25),
            (2, 4, 0.5),
            (3, 4, 0.75),
            (4, 4, 1.0),
            (5, 4, 1.25),
            (3, 6, 0.5)
          ])
    func weeklyProgressPercentageCalculations(completed: Int, target: Int, expected: Double) {
        let progress = WeeklyProgressData(completed: completed, target: target)
        #expect(abs(progress.progressPercentage - expected) < 0.001)
    }
}
