// WorkoutFixtures.swift
// BeastModeTests
// Pre-built workout test data

import Foundation
@testable import BeastMode

/// Fixtures for Workout and related model testing
enum WorkoutFixtures {

    // MARK: - Workout Plans

    /// Standard Push/Pull/Legs split
    static func pplSplit(userId: UUID) -> WorkoutPlan {
        let plan = WorkoutPlan(
            userId: userId,
            name: "Push/Pull/Legs",
            description: "Classic 6-day PPL split",
            daysPerWeek: 6,
            difficulty: .intermediate,
            targetGoal: .hypertrophy
        )

        // Monday - Push
        let pushDay = PlanDay(weekday: 2, name: "Push", isRestDay: false)
        pushDay.exercises = [
            makePlanExercise("Barbell Bench Press", sets: 4, repsMin: 6, repsMax: 8, order: 0),
            makePlanExercise("Incline Dumbbell Press", sets: 3, repsMin: 8, repsMax: 12, order: 1),
            makePlanExercise("Overhead Press", sets: 3, repsMin: 8, repsMax: 10, order: 2),
            makePlanExercise("Tricep Pushdowns", sets: 3, repsMin: 10, repsMax: 15, order: 3)
        ]
        plan.days.append(pushDay)

        // Tuesday - Pull
        let pullDay = PlanDay(weekday: 3, name: "Pull", isRestDay: false)
        pullDay.exercises = [
            makePlanExercise("Deadlift", sets: 4, repsMin: 5, repsMax: 6, order: 0),
            makePlanExercise("Barbell Rows", sets: 4, repsMin: 6, repsMax: 8, order: 1),
            makePlanExercise("Pull-ups", sets: 3, repsMin: 6, repsMax: 10, order: 2),
            makePlanExercise("Dumbbell Curls", sets: 3, repsMin: 10, repsMax: 12, order: 3)
        ]
        plan.days.append(pullDay)

        // Wednesday - Legs
        let legsDay = PlanDay(weekday: 4, name: "Legs", isRestDay: false)
        legsDay.exercises = [
            makePlanExercise("Barbell Squats", sets: 4, repsMin: 6, repsMax: 8, order: 0),
            makePlanExercise("Leg Press", sets: 3, repsMin: 10, repsMax: 12, order: 1)
        ]
        plan.days.append(legsDay)

        // Sunday - Rest
        let restDay = PlanDay(weekday: 1, name: "Rest", isRestDay: true)
        plan.days.append(restDay)

        return plan
    }

    /// Empty plan for testing
    static func emptyPlan(userId: UUID) -> WorkoutPlan {
        WorkoutPlan(
            userId: userId,
            name: "Empty Plan",
            description: nil,
            daysPerWeek: 0,
            difficulty: .beginner,
            targetGoal: .general
        )
    }

    // MARK: - Workouts

    /// Creates a workout with specified exercises
    static func makeWorkout(
        userId: UUID,
        exercises: [(name: String, sets: [(weight: Double, reps: Int)])],
        date: Date = .now
    ) -> Workout {
        let workout = Workout(userId: userId)
        workout.startedAt = date
        workout.completedAt = date.addingTimeInterval(3600)

        for (exerciseName, sets) in exercises {
            let exercise = WorkoutExercise(
                exerciseId: UUID(),
                exerciseName: exerciseName
            )
            exercise.workout = workout

            for (index, setData) in sets.enumerated() {
                let setLog = SetLog(
                    setNumber: index + 1,
                    weight: setData.weight,
                    reps: setData.reps,
                    completedAt: date
                )
                setLog.workoutExercise = exercise
            }
        }

        return workout
    }

    /// Simple bench press workout
    static func benchWorkout(userId: UUID, weight: Double = 185, reps: Int = 8) -> Workout {
        makeWorkout(
            userId: userId,
            exercises: [
                ("Barbell Bench Press", [
                    (weight: weight, reps: reps),
                    (weight: weight, reps: reps - 1),
                    (weight: weight, reps: reps - 2),
                    (weight: weight, reps: reps - 3)
                ])
            ]
        )
    }

    /// Full body workout with multiple exercises
    static func fullBodyWorkout(userId: UUID) -> Workout {
        makeWorkout(
            userId: userId,
            exercises: [
                ("Barbell Squats", [
                    (weight: 225, reps: 8),
                    (weight: 225, reps: 7),
                    (weight: 225, reps: 6)
                ]),
                ("Barbell Bench Press", [
                    (weight: 185, reps: 8),
                    (weight: 185, reps: 7),
                    (weight: 185, reps: 6)
                ]),
                ("Barbell Rows", [
                    (weight: 155, reps: 10),
                    (weight: 155, reps: 9),
                    (weight: 155, reps: 8)
                ])
            ]
        )
    }

    // MARK: - Set Logs

    /// Creates a single set log
    static func makeSetLog(
        number: Int,
        weight: Double,
        reps: Int,
        isWarmup: Bool = false,
        isPR: Bool = false
    ) -> SetLog {
        let set = SetLog(
            setNumber: number,
            weight: weight,
            reps: reps,
            completedAt: .now
        )
        set.isWarmup = isWarmup
        set.isPR = isPR
        return set
    }

    /// Generates progressive sets (decreasing reps)
    static func progressiveSets(
        baseWeight: Double,
        baseReps: Int,
        count: Int
    ) -> [SetLog] {
        (1...count).map { num in
            makeSetLog(
                number: num,
                weight: baseWeight,
                reps: max(1, baseReps - (num - 1))
            )
        }
    }

    /// Generates warmup + working sets
    static func warmupAndWorkingSets(workingWeight: Double, workingReps: Int) -> [SetLog] {
        var sets: [SetLog] = []

        // Warmup sets
        sets.append(makeSetLog(number: 1, weight: workingWeight * 0.5, reps: 10, isWarmup: true))
        sets.append(makeSetLog(number: 2, weight: workingWeight * 0.7, reps: 5, isWarmup: true))

        // Working sets
        for i in 3...6 {
            sets.append(makeSetLog(number: i, weight: workingWeight, reps: workingReps - (i - 3)))
        }

        return sets
    }

    // MARK: - Helpers

    private static func makePlanExercise(
        _ name: String,
        sets: Int,
        repsMin: Int,
        repsMax: Int,
        order: Int
    ) -> PlanExercise {
        PlanExercise(
            exerciseId: UUID(),
            exerciseName: name,
            order: order,
            targetSets: sets,
            targetRepsMin: repsMin,
            targetRepsMax: repsMax
        )
    }
}

// MARK: - Week Generation

extension WorkoutFixtures {

    /// Generates a week of workouts with progressive overload
    static func generateWeekOfWorkouts(
        userId: UUID,
        weeksAgo: Int,
        baseWeight: Double = 185
    ) -> [Workout] {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(
            byAdding: .weekOfYear,
            value: -weeksAgo,
            to: calendar.startOfDay(for: .now)
        )!

        var workouts: [Workout] = []

        // Generate 5 workouts (Mon-Fri)
        for dayOffset in 0..<5 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek) else {
                continue
            }

            // Progressive overload: weight increases over time
            let progressedWeight = baseWeight + Double(12 - weeksAgo) * 2.5

            let workout = makeWorkout(
                userId: userId,
                exercises: [
                    ("Barbell Bench Press", [
                        (weight: progressedWeight, reps: 8),
                        (weight: progressedWeight, reps: 7),
                        (weight: progressedWeight, reps: 6),
                        (weight: progressedWeight, reps: 5)
                    ])
                ],
                date: date
            )

            workouts.append(workout)
        }

        return workouts
    }
}
