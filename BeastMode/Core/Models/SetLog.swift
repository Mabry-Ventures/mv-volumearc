// SetLog.swift
// BeastMode
// Core model for tracking individual sets within a workout

import Foundation
import SwiftData

/// Represents a single set performed during an exercise
@Model
final class SetLog {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var setNumber: Int
    var weight: Double?
    var reps: Int?
    var duration: TimeInterval?  // For timed exercises
    var distance: Double?        // For cardio exercises
    var rpe: Int?               // Rate of Perceived Exertion (1-10)
    var notes: String?
    var completedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        setNumber: Int,
        weight: Double? = nil,
        reps: Int? = nil,
        duration: TimeInterval? = nil,
        distance: Double? = nil,
        rpe: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.duration = duration
        self.distance = distance
        self.rpe = rpe
        self.notes = notes
        self.createdAt = .now
    }

    var isCompleted: Bool {
        completedAt != nil
    }
}
