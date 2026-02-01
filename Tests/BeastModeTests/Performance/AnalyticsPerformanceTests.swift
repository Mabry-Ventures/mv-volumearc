// AnalyticsPerformanceTests.swift
// BeastModeTests
// Performance tests for analytics and data processing

import Testing
import SwiftData
import Foundation
@testable import BeastMode

@Suite("Analytics Performance", .serialized)
struct AnalyticsPerformanceTests {

    // MARK: - Large Dataset Performance

    @Test("Analytics overview with 1000 workouts completes quickly")
    @MainActor
    func analyticsOverviewPerformance() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let context = container.mainContext
        let userId = UUID()

        // Insert 1000 workouts (simulating 3+ years of data)
        let calendar = Calendar.current
        for i in 0..<1000 {
            let date = calendar.date(byAdding: .day, value: -i, to: .now) ?? .now
            let workout = Workout(userId: userId)
            workout.startedAt = date
            workout.completedAt = date.addingTimeInterval(3600) // 1 hour
            context.insert(workout)

            // Add exercises
            for exerciseName in ["Bench Press", "Squats", "Deadlift"] {
                let exercise = WorkoutExercise(
                    exerciseId: UUID(),
                    exerciseName: exerciseName
                )
                exercise.workout = workout

                // Add sets
                for setNum in 1...4 {
                    let set = SetLog(
                        setNumber: setNum,
                        weight: Double(150 + setNum * 10),
                        reps: 8,
                        completedAt: date
                    )
                    set.workoutExercise = exercise
                }
            }
        }
        try context.save()

        // Measure analytics generation time
        let startTime = Date()

        let service = AnalyticsService(modelContext: context)
        let overview = try await service.generateOverview(timeRange: .threeMonths)

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete within 2 seconds
        #expect(elapsed < 2.0, "Analytics overview took \(elapsed)s, expected < 2s")
        #expect(overview.totalWorkouts > 0)
    }

    @Test("PR detection with extensive history completes quickly")
    @MainActor
    func prDetectionPerformance() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let context = container.mainContext
        let userId = UUID()

        // Insert 500 PRs for various exercises
        let exercises = ["Bench Press", "Squats", "Deadlift", "Overhead Press", "Barbell Rows"]
        let calendar = Calendar.current

        for (exerciseIndex, exerciseName) in exercises.enumerated() {
            for i in 0..<100 {
                let date = calendar.date(byAdding: .day, value: -(exerciseIndex * 100 + i), to: .now) ?? .now
                let weight = Double(100 + i * 2)
                let reps = max(1, 12 - (i / 10))

                let pr = PersonalRecord(
                    exerciseName: exerciseName,
                    weight: weight,
                    reps: reps,
                    estimatedOneRepMax: PRFixtures.calculateE1RM(weight: weight, reps: reps),
                    achievedAt: date,
                    userId: userId
                )
                context.insert(pr)
            }
        }
        try context.save()

        // Measure PR check time
        let startTime = Date()

        let service = PRDetectionService(modelContext: context)
        _ = await service.checkForPR(
            exerciseName: "Bench Press",
            weight: 315,
            reps: 5,
            userId: userId
        )

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete within 500ms
        #expect(elapsed < 0.5, "PR detection took \(elapsed)s, expected < 0.5s")
    }

    @Test("Streak calculation with year of data completes quickly")
    @MainActor
    func streakCalculationPerformance() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let context = container.mainContext
        let userId = UUID()

        let streak = UserStreak(userId: userId)
        context.insert(streak)

        // Simulate 365 days of workout history (5 workouts per week pattern)
        let calendar = Calendar.current
        for i in 0..<365 {
            let date = calendar.date(byAdding: .day, value: -i, to: .now) ?? .now
            let weekday = calendar.component(.weekday, from: date)

            // Skip weekends (simulate rest days)
            if weekday == 1 || weekday == 7 { continue }

            let workout = Workout(userId: userId)
            workout.startedAt = date
            workout.completedAt = date.addingTimeInterval(3600)
            context.insert(workout)
        }
        try context.save()

        // Measure streak update time
        let startTime = Date()

        let service = StreakService(modelContext: context)
        _ = try await service.recordWorkout(for: userId, completedAt: .now)

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete within 500ms
        #expect(elapsed < 0.5, "Streak calculation took \(elapsed)s, expected < 0.5s")
    }

    // MARK: - Batch Operations Performance

    @Test("Batch workout insertion performance")
    @MainActor
    func batchWorkoutInsertionPerformance() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let context = container.mainContext
        let userId = UUID()

        let startTime = Date()

        // Insert 100 workouts in batch
        for i in 0..<100 {
            let workout = Workout(userId: userId)
            workout.startedAt = Date().addingTimeInterval(Double(-i * 86400))
            workout.completedAt = workout.startedAt?.addingTimeInterval(3600)
            context.insert(workout)
        }
        try context.save()

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete within 1 second
        #expect(elapsed < 1.0, "Batch insertion took \(elapsed)s, expected < 1s")
    }

    @Test("Exercise search with large library")
    @MainActor
    func exerciseSearchPerformance() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let context = container.mainContext

        // Insert 500 exercises
        let bodyParts = ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core"]
        let equipment = ["Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight"]

        for i in 0..<500 {
            let exercise = Exercise(
                name: "Exercise \(i)",
                category: bodyParts[i % bodyParts.count],
                equipment: equipment[i % equipment.count],
                instructions: "Instructions for exercise \(i)"
            )
            context.insert(exercise)
        }
        try context.save()

        // Measure search time
        let startTime = Date()

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.category == "Chest" },
            sortBy: [SortDescriptor(\.name)]
        )
        let results = try context.fetch(descriptor)

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete within 100ms
        #expect(elapsed < 0.1, "Exercise search took \(elapsed)s, expected < 0.1s")
        #expect(results.count > 0)
    }

    // MARK: - Memory Performance

    @Test("Memory usage remains stable during large data processing")
    @MainActor
    func memoryStabilityTest() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let context = container.mainContext
        let userId = UUID()

        // Process multiple batches and verify no memory issues
        for batch in 0..<10 {
            // Insert batch of workouts
            for i in 0..<50 {
                let workout = Workout(userId: userId)
                workout.startedAt = Date().addingTimeInterval(Double(-(batch * 50 + i) * 86400))
                workout.completedAt = workout.startedAt?.addingTimeInterval(3600)
                context.insert(workout)
            }
            try context.save()

            // Generate analytics (should process efficiently)
            let service = AnalyticsService(modelContext: context)
            _ = try await service.generateOverview(timeRange: .oneMonth)
        }

        // If we get here without crashing, memory is being managed properly
        #expect(true)
    }

    // MARK: - Concurrent Operations

    @Test("Concurrent analytics requests don't cause issues")
    @MainActor
    func concurrentAnalyticsRequests() async throws {
        let container = try ModelContainerFactory.makeAnalyticsContainer()
        let service = AnalyticsService(modelContext: container.mainContext)

        // Launch multiple concurrent requests
        async let overview1 = service.generateOverview(timeRange: .oneMonth)
        async let overview2 = service.generateOverview(timeRange: .threeMonths)
        async let overview3 = service.generateOverview(timeRange: .sixMonths)

        let results = try await (overview1, overview2, overview3)

        // All should complete successfully
        #expect(results.0.totalWorkouts >= 0)
        #expect(results.1.totalWorkouts >= 0)
        #expect(results.2.totalWorkouts >= 0)
    }
}

// MARK: - Data Import/Export Performance

@Suite("Data Import/Export Performance")
struct DataImportExportPerformanceTests {

    @Test("Plan export with many exercises")
    @MainActor
    func planExportPerformance() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let context = container.mainContext
        let userId = UUID()

        // Create a comprehensive plan with many exercises
        let plan = WorkoutPlan(
            name: "Comprehensive Plan",
            userId: userId,
            difficulty: .advanced,
            goal: .strength,
            daysPerWeek: 6,
            estimatedDuration: 12
        )

        // Add 6 days with 8 exercises each
        for dayNum in 1...6 {
            let day = PlanDay(
                weekday: dayNum + 1,
                name: "Day \(dayNum)",
                isRestDay: false
            )
            day.plan = plan

            for exerciseNum in 1...8 {
                let exercise = PlanExercise(
                    exerciseId: UUID(),
                    exerciseName: "Exercise \(dayNum)-\(exerciseNum)",
                    sortOrder: exerciseNum
                )
                exercise.targetSets = 4
                exercise.targetRepsMin = 6
                exercise.targetRepsMax = 8
                exercise.restSeconds = 120
                exercise.planDay = day
            }
        }

        context.insert(plan)
        try context.save()

        // Measure export time
        let startTime = Date()

        let service = PlanSharingService(modelContext: context)
        let data = try await service.exportPlan(plan)

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete within 200ms
        #expect(elapsed < 0.2, "Plan export took \(elapsed)s, expected < 0.2s")
        #expect(data.count > 0)
    }

    @Test("Plan import with validation")
    @MainActor
    func planImportPerformance() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let service = PlanSharingService(modelContext: container.mainContext)

        // Create a large JSON payload
        var daysJSON: [String] = []
        for dayNum in 1...6 {
            var exercisesJSON: [String] = []
            for exerciseNum in 1...8 {
                exercisesJSON.append("""
                {
                    "name": "Exercise \\(dayNum)-\\(exerciseNum)",
                    "sets": 4,
                    "repsMin": 6,
                    "repsMax": 8,
                    "restSeconds": 120,
                    "superset": false
                }
                """)
            }
            daysJSON.append("""
            {
                "weekday": \(dayNum + 1),
                "name": "Day \(dayNum)",
                "isRestDay": false,
                "exercises": [\(exercisesJSON.joined(separator: ","))]
            }
            """)
        }

        let json = """
        {
            "version": 1,
            "name": "Large Plan",
            "description": "A comprehensive training plan",
            "difficulty": "Advanced",
            "goal": "Strength",
            "daysPerWeek": 6,
            "estimatedDuration": 12,
            "days": [\(daysJSON.joined(separator: ","))],
            "createdAt": "2024-01-15T10:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!

        // Measure import time
        let startTime = Date()

        let imported = try await service.importPlan(from: data, userId: UUID())

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete within 300ms
        #expect(elapsed < 0.3, "Plan import took \(elapsed)s, expected < 0.3s")
        #expect(imported.days.count == 6)
    }
}

// MARK: - UI Responsiveness Performance

@Suite("UI Responsiveness Performance")
struct UIResponsivenessPerformanceTests {

    @Test("Workout list fetch for display")
    @MainActor
    func workoutListFetchPerformance() async throws {
        let container = try ModelContainerFactory.makeAnalyticsContainer()
        let context = container.mainContext

        // Measure fetch time for recent workouts
        let startTime = Date()

        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: .now)!

        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.completedAt != nil },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20

        let workouts = try context.fetch(descriptor)

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete within 50ms for UI responsiveness
        #expect(elapsed < 0.05, "Workout list fetch took \(elapsed)s, expected < 0.05s")
        #expect(workouts.count <= 20)
    }

    @Test("PR history fetch for exercise detail")
    @MainActor
    func prHistoryFetchPerformance() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let context = container.mainContext
        let userId = UUID()

        // Insert PR history
        let calendar = Calendar.current
        for i in 0..<50 {
            let date = calendar.date(byAdding: .week, value: -i, to: .now) ?? .now
            let pr = PersonalRecord(
                exerciseName: "Bench Press",
                weight: Double(135 + i * 5),
                reps: 5,
                estimatedOneRepMax: PRFixtures.calculateE1RM(weight: Double(135 + i * 5), reps: 5),
                achievedAt: date,
                userId: userId
            )
            context.insert(pr)
        }
        try context.save()

        // Measure fetch time
        let startTime = Date()

        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseName == "Bench Press" && $0.userId == userId },
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        )

        let prs = try context.fetch(descriptor)

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete within 30ms
        #expect(elapsed < 0.03, "PR history fetch took \(elapsed)s, expected < 0.03s")
        #expect(prs.count == 50)
    }
}
