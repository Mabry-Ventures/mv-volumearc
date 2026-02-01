// Workout.swift
// BeastMode
// Core model for tracking complete workout sessions

import Foundation
import SwiftData

/// Represents a complete workout session
@Model
final class Workout {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var name: String?
    var startedAt: Date
    var completedAt: Date?
    var notes: String?
    var totalVolume: Double  // Total weight lifted (weight × reps)
    var exerciseCount: Int
    var setCount: Int

    @Relationship(deleteRule: .cascade)
    var exercises: [WorkoutExercise]

    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.startedAt = .now
        self.totalVolume = 0
        self.exerciseCount = 0
        self.setCount = 0
        self.exercises = []
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var duration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    func calculateTotalVolume() -> Double {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { setTotal, set in
                guard let weight = set.weight, let reps = set.reps else { return setTotal }
                return setTotal + (weight * Double(reps))
            }
        }
    }
}

/// Represents an exercise within a workout
@Model
final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var exerciseName: String
    var order: Int
    var notes: String?

    @Relationship(deleteRule: .cascade)
    var sets: [SetLog]

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        exerciseName: String,
        order: Int
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.order = order
        self.sets = []
    }
}
