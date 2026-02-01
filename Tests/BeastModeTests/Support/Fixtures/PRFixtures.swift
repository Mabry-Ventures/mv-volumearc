// PRFixtures.swift
// BeastModeTests
// Pre-built personal record test data

import Foundation
@testable import BeastMode

/// Fixtures for PersonalRecord testing
enum PRFixtures {

    // MARK: - Individual PRs

    /// Creates a PR with specified parameters
    static func makePR(
        exercise: String,
        weight: Double,
        reps: Int,
        date: Date = .now,
        userId: UUID = UUID()
    ) -> PersonalRecord {
        PersonalRecord(
            exerciseName: exercise,
            weight: weight,
            reps: reps,
            estimatedOneRepMax: calculateE1RM(weight: weight, reps: reps),
            achievedAt: date,
            userId: userId
        )
    }

    /// First-time PR (no history)
    static func firstTimePR(
        exercise: String = "New Exercise",
        weight: Double = 100,
        reps: Int = 10
    ) -> PersonalRecord {
        makePR(exercise: exercise, weight: weight, reps: reps)
    }

    // MARK: - PR Histories

    /// Bench press PR progression over 3 months
    static func benchPressPRHistory(userId: UUID = UUID()) -> [PersonalRecord] {
        let calendar = Calendar.current
        return [
            makePR(
                exercise: "Barbell Bench Press",
                weight: 185,
                reps: 8,
                date: calendar.date(byAdding: .month, value: -3, to: .now)!,
                userId: userId
            ),
            makePR(
                exercise: "Barbell Bench Press",
                weight: 195,
                reps: 6,
                date: calendar.date(byAdding: .month, value: -2, to: .now)!,
                userId: userId
            ),
            makePR(
                exercise: "Barbell Bench Press",
                weight: 205,
                reps: 5,
                date: calendar.date(byAdding: .month, value: -1, to: .now)!,
                userId: userId
            ),
            makePR(
                exercise: "Barbell Bench Press",
                weight: 215,
                reps: 4,
                date: .now,
                userId: userId
            )
        ]
    }

    /// Squat PR progression
    static func squatPRHistory(userId: UUID = UUID()) -> [PersonalRecord] {
        let calendar = Calendar.current
        return [
            makePR(
                exercise: "Barbell Squats",
                weight: 225,
                reps: 8,
                date: calendar.date(byAdding: .month, value: -2, to: .now)!,
                userId: userId
            ),
            makePR(
                exercise: "Barbell Squats",
                weight: 245,
                reps: 6,
                date: calendar.date(byAdding: .month, value: -1, to: .now)!,
                userId: userId
            ),
            makePR(
                exercise: "Barbell Squats",
                weight: 265,
                reps: 5,
                date: .now,
                userId: userId
            )
        ]
    }

    /// Deadlift PR progression
    static func deadliftPRHistory(userId: UUID = UUID()) -> [PersonalRecord] {
        let calendar = Calendar.current
        return [
            makePR(
                exercise: "Deadlift",
                weight: 275,
                reps: 5,
                date: calendar.date(byAdding: .month, value: -2, to: .now)!,
                userId: userId
            ),
            makePR(
                exercise: "Deadlift",
                weight: 295,
                reps: 5,
                date: calendar.date(byAdding: .month, value: -1, to: .now)!,
                userId: userId
            ),
            makePR(
                exercise: "Deadlift",
                weight: 315,
                reps: 5,
                date: .now,
                userId: userId
            )
        ]
    }

    /// Mixed exercise PRs for overview testing
    static func mixedExercisePRs(userId: UUID = UUID()) -> [PersonalRecord] {
        benchPressPRHistory(userId: userId) +
        squatPRHistory(userId: userId) +
        deadliftPRHistory(userId: userId) +
        [
            makePR(exercise: "Overhead Press", weight: 135, reps: 6, userId: userId),
            makePR(exercise: "Barbell Rows", weight: 175, reps: 8, userId: userId)
        ]
    }

    // MARK: - Edge Cases

    /// PR at body weight (0 weight)
    static func bodyweightPR() -> PersonalRecord {
        makePR(exercise: "Pull-ups", weight: 0, reps: 15)
    }

    /// Single rep max
    static func singleRepMax() -> PersonalRecord {
        makePR(exercise: "Barbell Bench Press", weight: 315, reps: 1)
    }

    /// High rep PR
    static func highRepPR() -> PersonalRecord {
        makePR(exercise: "Push-ups", weight: 0, reps: 50)
    }

    // MARK: - Helpers

    /// Calculates estimated 1RM using Brzycki formula
    static func calculateE1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        guard reps <= 12 else { return weight }
        if reps == 1 { return weight }
        return weight * (36.0 / (37.0 - Double(reps)))
    }
}

// MARK: - Test Scenarios

extension PRFixtures {

    /// Creates a scenario where a new lift would beat the current E1RM
    struct PRTestScenario {
        let existingPRs: [PersonalRecord]
        let newWeight: Double
        let newReps: Int
        let expectedPRType: PRType?
    }

    /// Scenarios for E1RM improvement
    static var e1rmImprovementScenarios: [PRTestScenario] {
        let userId = UUID()
        let existingPR = makePR(
            exercise: "Barbell Bench Press",
            weight: 205,
            reps: 6,
            userId: userId
        )
        // Existing E1RM: 205 × (36/31) ≈ 238

        return [
            // Higher E1RM: 225 × 5 = 253 (improvement)
            PRTestScenario(
                existingPRs: [existingPR],
                newWeight: 225,
                newReps: 5,
                expectedPRType: .estimatedMax(improvement: 6.3)
            ),
            // Same E1RM range: 215 × 6 ≈ 250 (slight improvement)
            PRTestScenario(
                existingPRs: [existingPR],
                newWeight: 215,
                newReps: 6,
                expectedPRType: .estimatedMax(improvement: 5.0)
            ),
            // Lower E1RM: 200 × 6 ≈ 232 (no PR)
            PRTestScenario(
                existingPRs: [existingPR],
                newWeight: 200,
                newReps: 6,
                expectedPRType: nil
            )
        ]
    }

    /// Scenarios for rep records at same weight
    static var repRecordScenarios: [PRTestScenario] {
        let userId = UUID()
        let existingPR = makePR(
            exercise: "Barbell Bench Press",
            weight: 185,
            reps: 8,
            userId: userId
        )

        return [
            // More reps at same weight
            PRTestScenario(
                existingPRs: [existingPR],
                newWeight: 185,
                newReps: 10,
                expectedPRType: .repRecord(atWeight: 185, reps: 10)
            ),
            // Same reps (no PR)
            PRTestScenario(
                existingPRs: [existingPR],
                newWeight: 185,
                newReps: 8,
                expectedPRType: nil
            ),
            // Fewer reps (no PR)
            PRTestScenario(
                existingPRs: [existingPR],
                newWeight: 185,
                newReps: 6,
                expectedPRType: nil
            )
        ]
    }
}
