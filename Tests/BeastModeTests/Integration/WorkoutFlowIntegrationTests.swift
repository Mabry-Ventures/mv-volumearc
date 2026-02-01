// WorkoutFlowIntegrationTests.swift
// BeastModeTests
// Integration tests for complete workout flows

import Testing
import SwiftData
import Foundation
@testable import BeastMode

@Suite("Workout Flow Integration", .serialized)
struct WorkoutFlowIntegrationTests {

    @Test("Complete workout flow from plan to log to PR")
    @MainActor
    func completeWorkoutFlow() async throws {
        // Setup
        let container = try ModelContainerFactory.makePopulatedContainer()
        let context = container.mainContext

        let user = UserFixtures.standardUser
        context.insert(user)

        let streak = UserStreak(userId: user.id)
        context.insert(streak)

        // Create a workout plan
        let plan = WorkoutFixtures.pplSplit(userId: user.id)
        plan.isActive = true
        context.insert(plan)
        try context.save()

        // 1. Fetch today's planned workout
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: .now)
        let todaysPlan = plan.day(for: weekday)

        // 2. Create and start workout
        let workout = Workout(userId: user.id)
        workout.startedAt = .now
        context.insert(workout)

        // 3. Log sets for each planned exercise
        let prService = PRDetectionService(modelContext: context)
        var detectedPRs: [PRType] = []

        if let plannedDay = todaysPlan, !plannedDay.isRestDay {
            for plannedExercise in plannedDay.sortedExercises {
                let exerciseLog = WorkoutExercise(
                    exerciseId: plannedExercise.exerciseId,
                    exerciseName: plannedExercise.exerciseName
                )
                exerciseLog.workout = workout

                // Log sets with progressive weights
                for setNumber in 1...plannedExercise.targetSets {
                    let weight = 185 + Double(setNumber * 5)
                    let reps = 8

                    let setLog = SetLog(
                        setNumber: setNumber,
                        weight: weight,
                        reps: reps,
                        completedAt: .now
                    )
                    setLog.workoutExercise = exerciseLog

                    // Check for PR
                    if let prType = await prService.checkForPR(
                        exerciseName: plannedExercise.exerciseName,
                        weight: weight,
                        reps: reps,
                        userId: user.id
                    ) {
                        detectedPRs.append(prType)
                        setLog.isPR = true
                    }
                }
            }
        }

        // 4. Complete workout
        workout.completedAt = .now
        try context.save()

        // Verify workout is complete
        #expect(workout.completedAt != nil)
        #expect(workout.exercises.count > 0 || todaysPlan?.isRestDay == true)

        // First workout should have PRs (first time for all exercises)
        if todaysPlan?.isRestDay != true {
            #expect(detectedPRs.count > 0, "First workout should have PRs")
        }

        // 5. Update streak
        let streakService = StreakService(modelContext: context)
        let badges = try await streakService.recordWorkout(
            for: user.id,
            completedAt: .now
        )

        #expect(badges.contains(.firstWorkout))

        // Verify streak was updated
        let updatedStreak = try await streakService.getStreak(for: user.id)
        #expect(updatedStreak?.currentStreak == 1)
    }

    @Test("Multiple weeks build analytics correctly")
    @MainActor
    func multiWeekAnalytics() async throws {
        let container = try ModelContainerFactory.makeAnalyticsContainer()
        let analyticsService = AnalyticsService(modelContext: container.mainContext)

        let overview = try await analyticsService.generateOverview(timeRange: .threeMonths)

        // Should have meaningful data from 12 weeks of workouts
        #expect(overview.totalWorkouts >= 50)  // 12 weeks × 5 days
        #expect(overview.exercises.count >= 2)
        #expect(overview.progressingCount > 0)
    }

    @Test("PR detection across workout sessions")
    @MainActor
    func prDetectionAcrossSessions() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let context = container.mainContext
        let userId = UUID()

        let user = UserProfile(displayName: "Test")
        context.insert(user)

        let prService = PRDetectionService(modelContext: context)

        // Session 1: Initial workout
        let pr1 = await prService.checkForPR(
            exerciseName: "Barbell Bench Press",
            weight: 185,
            reps: 8,
            userId: userId
        )
        #expect(pr1 == .firstTime)

        // Save PR
        try await prService.savePR(
            exerciseName: "Barbell Bench Press",
            weight: 185,
            reps: 8,
            estimatedOneRepMax: PRFixtures.calculateE1RM(weight: 185, reps: 8),
            userId: userId
        )

        // Session 2: Same weight, more reps
        let pr2 = await prService.checkForPR(
            exerciseName: "Barbell Bench Press",
            weight: 185,
            reps: 10,
            userId: userId
        )

        // Should be rep record or E1RM improvement
        #expect(pr2 != nil)
        #expect(pr2 != .firstTime)

        // Session 3: Heavier weight
        try await prService.savePR(
            exerciseName: "Barbell Bench Press",
            weight: 185,
            reps: 10,
            estimatedOneRepMax: PRFixtures.calculateE1RM(weight: 185, reps: 10),
            userId: userId
        )

        let pr3 = await prService.checkForPR(
            exerciseName: "Barbell Bench Press",
            weight: 205,
            reps: 5,
            userId: userId
        )

        #expect(pr3 != nil)
    }

    @Test("Streak continues across days")
    @MainActor
    func streakContinuesAcrossDays() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let context = container.mainContext
        let userId = UUID()

        let streak = UserStreak(userId: userId)
        context.insert(streak)
        try context.save()

        let service = StreakService(modelContext: context)
        let calendar = Calendar.current

        // Day 1
        let day1 = calendar.date(byAdding: .day, value: -4, to: .now)!
        _ = try await service.recordWorkout(for: userId, completedAt: day1)

        // Day 2
        let day2 = calendar.date(byAdding: .day, value: -3, to: .now)!
        _ = try await service.recordWorkout(for: userId, completedAt: day2)

        // Day 3
        let day3 = calendar.date(byAdding: .day, value: -2, to: .now)!
        _ = try await service.recordWorkout(for: userId, completedAt: day3)

        // Day 4
        let day4 = calendar.date(byAdding: .day, value: -1, to: .now)!
        _ = try await service.recordWorkout(for: userId, completedAt: day4)

        // Day 5
        _ = try await service.recordWorkout(for: userId, completedAt: .now)

        let finalStreak = try await service.getStreak(for: userId)
        #expect(finalStreak?.currentStreak == 5)
    }
}

// MARK: - Plan Sharing Integration

@Suite("Plan Sharing Integration")
struct PlanSharingIntegrationTests {

    @Test("Export, share, import flow")
    @MainActor
    func exportShareImportFlow() async throws {
        // Setup: User A creates a plan
        let containerA = try ModelContainerFactory.makeContainer()
        let userIdA = UUID()

        let originalPlan = WorkoutFixtures.pplSplit(userId: userIdA)
        containerA.mainContext.insert(originalPlan)
        try containerA.mainContext.save()

        let serviceA = PlanSharingService(modelContext: containerA.mainContext)

        // Step 1: Export
        let exportedData = try await serviceA.exportPlan(originalPlan)
        _ = try await serviceA.generateShareCode(for: originalPlan)

        // Step 2: Simulate sharing (data transfer)
        let sharedData = exportedData

        // Step 3: User B imports
        let containerB = try ModelContainerFactory.makeContainer()
        let userIdB = UUID()
        let serviceB = PlanSharingService(modelContext: containerB.mainContext)

        let importedPlan = try await serviceB.importPlan(from: sharedData, userId: userIdB)

        // Verify
        #expect(importedPlan.name == originalPlan.name)
        #expect(importedPlan.userId == userIdB)
        #expect(importedPlan.isActive == false)  // Not active by default
        #expect(importedPlan.days.count == originalPlan.days.count)

        // Verify exercises match
        let originalExerciseNames = Set(originalPlan.days.flatMap(\.exercises).map(\.exerciseName))
        let importedExerciseNames = Set(importedPlan.days.flatMap(\.exercises).map(\.exerciseName))
        #expect(originalExerciseNames == importedExerciseNames)
    }

    @Test("Deep link import flow")
    @MainActor
    func deepLinkImportFlow() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let userId = UUID()

        let original = WorkoutFixtures.pplSplit(userId: userId)
        container.mainContext.insert(original)
        try container.mainContext.save()

        let service = PlanSharingService(modelContext: container.mainContext)

        // Generate share link
        let shareURL = try await service.generateShareLink(original)

        // Import from URL
        let newUserId = UUID()
        let imported = try await service.importPlanFromURL(shareURL, userId: newUserId)

        #expect(imported.name == original.name)
        #expect(imported.userId == newUserId)
    }

    @Test("Imported plan can be activated and used")
    @MainActor
    func importedPlanCanBeUsed() async throws {
        let container = try ModelContainerFactory.makeContainer()
        let context = container.mainContext
        let service = PlanSharingService(modelContext: context)

        // Import a plan
        let json = """
        {
            "version": 1,
            "name": "Imported PPL",
            "description": "Push Pull Legs",
            "difficulty": "Intermediate",
            "goal": "Hypertrophy",
            "daysPerWeek": 6,
            "estimatedDuration": 8,
            "authorName": "Gym Bro",
            "days": [
                {"weekday": 2, "name": "Push", "isRestDay": false, "exercises": [
                    {"name": "Bench Press", "sets": 4, "repsMin": 6, "repsMax": 8, "restSeconds": 120, "superset": false}
                ]},
                {"weekday": 3, "name": "Pull", "isRestDay": false, "exercises": [
                    {"name": "Rows", "sets": 4, "repsMin": 6, "repsMax": 8, "restSeconds": 120, "superset": false}
                ]}
            ],
            "createdAt": "2024-01-15T10:00:00Z"
        }
        """

        let importedPlan = try await service.importPlan(
            from: json.data(using: .utf8)!,
            userId: UUID()
        )

        // Activate it
        importedPlan.isActive = true
        try context.save()

        // Verify it can be used
        let monday = importedPlan.day(for: 2)  // Monday
        #expect(monday?.name == "Push")
        #expect(monday?.exercises.first?.exerciseName == "Bench Press")
    }
}
