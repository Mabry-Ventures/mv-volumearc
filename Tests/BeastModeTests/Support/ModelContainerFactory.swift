// ModelContainerFactory.swift
// BeastModeTests
// Factory for creating isolated, in-memory model containers for testing

import SwiftData
import Foundation
@testable import BeastMode

/// Factory for creating isolated, in-memory model containers for testing
@MainActor
enum ModelContainerFactory {

    /// Creates a fresh in-memory container with all Beast Mode models
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            UserStreak.self,
            Exercise.self,
            Workout.self,
            WorkoutExercise.self,
            SetLog.self,
            PersonalRecord.self,
            WorkoutPlan.self,
            PlanDay.self,
            PlanExercise.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    /// Creates a container pre-populated with fixture data
    static func makePopulatedContainer() throws -> ModelContainer {
        let container = try makeContainer()
        let context = container.mainContext

        // Insert standard fixtures
        let user = UserFixtures.standardUser
        context.insert(user)

        let streak = UserStreak(userId: user.id)
        context.insert(streak)

        // Seed default exercises
        seedDefaultExercises(context: context)

        try context.save()
        return container
    }

    /// Creates a container with extensive historical data for analytics testing
    static func makeAnalyticsContainer() throws -> ModelContainer {
        let container = try makeContainer()
        let context = container.mainContext

        let user = UserFixtures.standardUser
        context.insert(user)

        let streak = UserStreak(userId: user.id)
        streak.currentStreak = 30
        streak.longestStreak = 45
        context.insert(streak)

        // Seed exercises first
        seedDefaultExercises(context: context)

        // Generate 12 weeks of workout history
        let calendar = Calendar.current
        for weeksAgo in 0..<12 {
            let weekStart = calendar.date(
                byAdding: .weekOfYear,
                value: -weeksAgo,
                to: calendar.startOfDay(for: .now)
            )!

            // Generate 5 workouts per week
            for dayOffset in 0..<5 {
                guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else {
                    continue
                }

                let workout = Workout(userId: user.id)
                workout.startedAt = date
                workout.completedAt = date.addingTimeInterval(3600)

                // Add exercise logs with progressive overload
                let benchExercise = WorkoutExercise(exerciseId: UUID(), exerciseName: "Barbell Bench Press")
                benchExercise.workout = workout

                // Progressive weight: increases over time
                let baseWeight = 185.0 + Double(12 - weeksAgo) * 2.5

                for setNum in 1...4 {
                    let set = SetLog(
                        setNumber: setNum,
                        weight: baseWeight,
                        reps: 8 - (setNum - 1),
                        completedAt: date
                    )
                    set.workoutExercise = benchExercise
                }

                let squatExercise = WorkoutExercise(exerciseId: UUID(), exerciseName: "Barbell Squats")
                squatExercise.workout = workout

                let squatBaseWeight = 225.0 + Double(12 - weeksAgo) * 5.0

                for setNum in 1...4 {
                    let set = SetLog(
                        setNumber: setNum,
                        weight: squatBaseWeight,
                        reps: 8 - (setNum - 1),
                        completedAt: date
                    )
                    set.workoutExercise = squatExercise
                }

                context.insert(workout)
            }
        }

        try context.save()
        return container
    }

    /// Creates a container with a specific streak configuration
    static func makeStreakContainer(
        currentStreak: Int,
        longestStreak: Int,
        weeklyCount: Int
    ) throws -> ModelContainer {
        let container = try makeContainer()
        let context = container.mainContext

        let user = UserFixtures.standardUser
        context.insert(user)

        let streak = UserStreak(userId: user.id)
        streak.currentStreak = currentStreak
        streak.longestStreak = longestStreak
        streak.currentWeekWorkouts = weeklyCount
        context.insert(streak)

        try context.save()
        return container
    }

    // MARK: - Private Helpers

    private static func seedDefaultExercises(context: ModelContext) {
        let exercises: [(String, ExerciseCategory, Bool)] = [
            ("Barbell Bench Press", .chest, true),
            ("Incline Dumbbell Press", .chest, true),
            ("Barbell Squats", .legs, true),
            ("Deadlift", .back, true),
            ("Overhead Press", .shoulders, true),
            ("Barbell Rows", .back, true),
            ("Pull-ups", .back, true),
            ("Dumbbell Curls", .biceps, false),
            ("Tricep Pushdowns", .triceps, false),
            ("Leg Press", .legs, true)
        ]

        for (name, category, isCompound) in exercises {
            let exercise = Exercise(
                name: name,
                category: category,
                exerciseType: .weightAndReps,
                muscleGroups: [category.rawValue],
                isCompound: isCompound,
                isCustom: false
            )
            context.insert(exercise)
        }
    }
}
