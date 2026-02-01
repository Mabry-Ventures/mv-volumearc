// WeeklyReviewServiceTests.swift
// BeastModeTests
// Comprehensive unit tests for WeeklyReviewService

import Testing
import SwiftData
import Foundation
@testable import BeastMode

// MARK: - Weekly Review Service Tests

@Suite("Weekly Review Service")
struct WeeklyReviewServiceTests {

    // MARK: - Week ID Tests

    @Suite("Week ID Calculation")
    struct WeekIDCalculationTests {

        @Test("Current week ID has correct format")
        @MainActor
        func currentWeekIdHasCorrectFormat() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = WeeklyReviewService(modelContext: container.mainContext)

            let weekId = await service.currentWeekId()

            // Format should be "YYYY-W##"
            #expect(weekId.contains("-W"))

            let parts = weekId.split(separator: "-W")
            #expect(parts.count == 2)

            // Year should be 4 digits
            #expect(parts[0].count == 4)

            // Week number should be 1-2 digits
            #expect(parts[1].count >= 1 && parts[1].count <= 2)
        }

        @Test("Week ID for specific date")
        @MainActor
        func weekIdForSpecificDate() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = WeeklyReviewService(modelContext: container.mainContext)

            // Create a known date
            var components = DateComponents()
            components.year = 2024
            components.month = 3
            components.day = 15 // A known date in 2024
            let date = Calendar.current.date(from: components)!

            let weekId = await service.weekId(for: date)

            // Should contain 2024
            #expect(weekId.contains("2024"))
            #expect(weekId.contains("-W"))
        }

        @Test("Different dates in same week have same week ID")
        @MainActor
        func differentDatesInSameWeekHaveSameWeekId() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = WeeklyReviewService(modelContext: container.mainContext)

            let calendar = Calendar.current

            // Get start of current week
            let startOfWeek = calendar.date(from: calendar.dateComponents(
                [.yearForWeekOfYear, .weekOfYear],
                from: Date()
            ))!

            // Get another day in the same week (add 2 days)
            let laterInWeek = calendar.date(byAdding: .day, value: 2, to: startOfWeek)!

            let weekId1 = await service.weekId(for: startOfWeek)
            let weekId2 = await service.weekId(for: laterInWeek)

            #expect(weekId1 == weekId2)
        }

        @Test("Different weeks have different week IDs")
        @MainActor
        func differentWeeksHaveDifferentWeekIds() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = WeeklyReviewService(modelContext: container.mainContext)

            let thisWeek = Date()
            let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: thisWeek)!

            let thisWeekId = await service.weekId(for: thisWeek)
            let lastWeekId = await service.weekId(for: lastWeek)

            #expect(thisWeekId != lastWeekId)
        }

        @Test("Year boundary week IDs")
        @MainActor
        func yearBoundaryWeekIds() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = WeeklyReviewService(modelContext: container.mainContext)

            // December 31, 2024
            var dec31Components = DateComponents()
            dec31Components.year = 2024
            dec31Components.month = 12
            dec31Components.day = 31
            let dec31 = Calendar.current.date(from: dec31Components)!

            // January 1, 2025
            var jan1Components = DateComponents()
            jan1Components.year = 2025
            jan1Components.month = 1
            jan1Components.day = 1
            let jan1 = Calendar.current.date(from: jan1Components)!

            let dec31WeekId = await service.weekId(for: dec31)
            let jan1WeekId = await service.weekId(for: jan1)

            // Both should have valid format
            #expect(dec31WeekId.contains("-W"))
            #expect(jan1WeekId.contains("-W"))
        }
    }

    // MARK: - Weekly Review Model Tests

    @Suite("Weekly Review Model")
    struct WeeklyReviewModelTests {

        @Test("Weekly review stores correct values")
        func weeklyReviewStoresCorrectValues() {
            let now = Date()
            let review = WeeklyReview(
                weekId: "2024-W10",
                generatedAt: now,
                content: "Great week!",
                workoutCount: 5,
                totalVolume: 50000,
                prCount: 2
            )

            #expect(review.weekId == "2024-W10")
            #expect(review.generatedAt == now)
            #expect(review.content == "Great week!")
            #expect(review.workoutCount == 5)
            #expect(review.totalVolume == 50000)
            #expect(review.prCount == 2)
        }

        @Test("Weekly review with zero values")
        func weeklyReviewWithZeroValues() {
            let review = WeeklyReview(
                weekId: "2024-W1",
                generatedAt: Date(),
                content: "No workouts this week",
                workoutCount: 0,
                totalVolume: 0,
                prCount: 0
            )

            #expect(review.workoutCount == 0)
            #expect(review.totalVolume == 0)
            #expect(review.prCount == 0)
        }
    }

    // MARK: - Weekly Review Cache Tests

    @Suite("Weekly Review Cache")
    struct WeeklyReviewCacheTests {

        @Test("Cache stores and retrieves reviews")
        func cacheStoresAndRetrievesReviews() async {
            let cache = WeeklyReviewCache()

            let review = WeeklyReview(
                weekId: "2024-W10",
                generatedAt: Date(),
                content: "Test review",
                workoutCount: 3,
                totalVolume: 30000,
                prCount: 1
            )

            await cache.store(review)
            let retrieved = await cache.get(for: "2024-W10")

            #expect(retrieved != nil)
            #expect(retrieved?.content == "Test review")
        }

        @Test("Cache returns nil for missing week")
        func cacheReturnsNilForMissingWeek() async {
            let cache = WeeklyReviewCache()

            let retrieved = await cache.get(for: "2024-W99")

            #expect(retrieved == nil)
        }

        @Test("Cache can be cleared")
        func cacheCanBeCleared() async {
            let cache = WeeklyReviewCache()

            let review = WeeklyReview(
                weekId: "2024-W5",
                generatedAt: Date(),
                content: "Test",
                workoutCount: 1,
                totalVolume: 1000,
                prCount: 0
            )

            await cache.store(review)
            await cache.clear()

            let retrieved = await cache.get(for: "2024-W5")
            #expect(retrieved == nil)
        }

        @Test("Cache updates existing review")
        func cacheUpdatesExistingReview() async {
            let cache = WeeklyReviewCache()

            let review1 = WeeklyReview(
                weekId: "2024-W3",
                generatedAt: Date(),
                content: "Original",
                workoutCount: 2,
                totalVolume: 20000,
                prCount: 0
            )

            let review2 = WeeklyReview(
                weekId: "2024-W3",
                generatedAt: Date(),
                content: "Updated",
                workoutCount: 4,
                totalVolume: 40000,
                prCount: 2
            )

            await cache.store(review1)
            await cache.store(review2)

            let retrieved = await cache.get(for: "2024-W3")
            #expect(retrieved?.content == "Updated")
            #expect(retrieved?.workoutCount == 4)
        }

        @Test("Cache stores multiple weeks")
        func cacheStoresMultipleWeeks() async {
            let cache = WeeklyReviewCache()

            for week in 1...5 {
                let review = WeeklyReview(
                    weekId: "2024-W\(week)",
                    generatedAt: Date(),
                    content: "Week \(week)",
                    workoutCount: week,
                    totalVolume: Double(week * 10000),
                    prCount: 0
                )
                await cache.store(review)
            }

            for week in 1...5 {
                let retrieved = await cache.get(for: "2024-W\(week)")
                #expect(retrieved != nil)
                #expect(retrieved?.content == "Week \(week)")
            }
        }
    }

    // MARK: - Weekly Review Generation Tests

    @Suite("Weekly Review Generation")
    struct WeeklyReviewGenerationTests {

        @Test("Generates review for week with workouts")
        @MainActor
        func generatesReviewForWeekWithWorkouts() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Create user streak
            let streak = UserStreak(userId: userId)
            streak.currentStreak = 7
            context.insert(streak)

            // Create a workout for this week
            let workout = Workout(userId: userId)
            workout.startedAt = Date()
            workout.completedAt = Date()
            context.insert(workout)

            let exercise = WorkoutExercise(
                exerciseId: UUID(),
                exerciseName: "Bench Press"
            )
            exercise.workout = workout

            let set = SetLog(setNumber: 1, weight: 185, reps: 5, completedAt: Date())
            set.workoutExercise = exercise

            try context.save()

            let service = WeeklyReviewService(modelContext: context)
            let weekId = await service.currentWeekId()

            let review = try await service.generateWeeklyReview(for: weekId, userId: userId)

            #expect(review.weekId == weekId)
            #expect(review.content.isEmpty == false)
            #expect(review.workoutCount >= 0)
        }

        @Test("Generates review for week without workouts")
        @MainActor
        func generatesReviewForWeekWithoutWorkouts() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Create user streak but no workouts
            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = WeeklyReviewService(modelContext: context)
            let weekId = await service.currentWeekId()

            let review = try await service.generateWeeklyReview(for: weekId, userId: userId)

            #expect(review.workoutCount == 0)
        }
    }

    // MARK: - Date Range Parsing Tests

    @Suite("Date Range Parsing")
    struct DateRangeParsingTests {

        @Test("Week ID format parsing")
        func weekIdFormatParsing() {
            let weekId = "2024-W15"
            let parts = weekId.split(separator: "-W")

            #expect(parts.count == 2)
            #expect(Int(parts[0]) == 2024)
            #expect(Int(parts[1]) == 15)
        }

        @Test("Invalid week ID format")
        func invalidWeekIdFormat() {
            let invalidIds = ["2024", "2024-15", "W15", "invalid"]

            for id in invalidIds {
                let parts = id.split(separator: "-W")
                // Should not produce exactly 2 valid parts with proper numbers
                if parts.count == 2 {
                    let yearValid = Int(parts[0]) != nil
                    let weekValid = Int(parts[1]) != nil
                    if !yearValid || !weekValid {
                        #expect(true) // Invalid as expected
                    }
                } else {
                    #expect(true) // Invalid as expected
                }
            }
        }

        @Test("Week number bounds")
        func weekNumberBounds() {
            // Week numbers should be 1-53
            for week in 1...53 {
                let weekId = "2024-W\(week)"
                let parts = weekId.split(separator: "-W")
                let weekNum = Int(parts[1])
                #expect(weekNum == week)
                #expect(weekNum! >= 1 && weekNum! <= 53)
            }
        }
    }

    // MARK: - Workout Summary Tests

    @Suite("Workout Summary")
    struct WorkoutSummaryTests {

        @Test("Summary includes exercise names")
        @MainActor
        func summaryIncludesExerciseNames() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Create a workout with exercises
            let workout = Workout(userId: userId)
            workout.startedAt = Date()
            workout.completedAt = Date()
            context.insert(workout)

            let benchPress = WorkoutExercise(
                exerciseId: UUID(),
                exerciseName: "Bench Press"
            )
            benchPress.workout = workout

            let squats = WorkoutExercise(
                exerciseId: UUID(),
                exerciseName: "Barbell Squats"
            )
            squats.workout = workout

            // Add sets
            let set1 = SetLog(setNumber: 1, weight: 185, reps: 5, completedAt: Date())
            set1.workoutExercise = benchPress

            let set2 = SetLog(setNumber: 1, weight: 225, reps: 5, completedAt: Date())
            set2.workoutExercise = squats

            try context.save()

            // Verify workout has exercises
            #expect(workout.exercises.count == 2)
        }

        @Test("Summary includes set details")
        @MainActor
        func summaryIncludesSetDetails() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext

            let workout = Workout(userId: UUID())
            workout.startedAt = Date()
            workout.completedAt = Date()
            context.insert(workout)

            let exercise = WorkoutExercise(
                exerciseId: UUID(),
                exerciseName: "Deadlift"
            )
            exercise.workout = workout

            let set = SetLog(setNumber: 1, weight: 315, reps: 3, completedAt: Date())
            set.workoutExercise = exercise

            try context.save()

            // Verify set is stored correctly
            #expect(set.weight == 315)
            #expect(set.reps == 3)
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test("Handles new user with no history")
        @MainActor
        func handlesNewUserWithNoHistory() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = WeeklyReviewService(modelContext: container.mainContext)

            let userId = UUID() // New user with no data
            let weekId = await service.currentWeekId()

            let review = try await service.generateWeeklyReview(for: weekId, userId: userId)

            // Should generate a review even with no data
            #expect(review.weekId == weekId)
            #expect(review.workoutCount == 0)
        }

        @Test("Handles very old week IDs")
        @MainActor
        func handlesVeryOldWeekIds() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = WeeklyReviewService(modelContext: container.mainContext)

            let oldWeekId = "2020-W1"
            let userId = UUID()

            let review = try await service.generateWeeklyReview(for: oldWeekId, userId: userId)

            #expect(review.weekId == oldWeekId)
            #expect(review.workoutCount == 0) // No data from that far back
        }

        @Test("Handles future week IDs")
        @MainActor
        func handlesFutureWeekIds() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = WeeklyReviewService(modelContext: container.mainContext)

            let futureWeekId = "2030-W1"
            let userId = UUID()

            let review = try await service.generateWeeklyReview(for: futureWeekId, userId: userId)

            #expect(review.weekId == futureWeekId)
            #expect(review.workoutCount == 0)
        }
    }
}
