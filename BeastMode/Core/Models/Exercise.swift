// Exercise.swift
// BeastMode
// Core model for exercise definitions

import Foundation
import SwiftData

/// Categories for exercise classification
enum ExerciseCategory: String, Codable, CaseIterable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case legs = "Legs"
    case core = "Core"
    case cardio = "Cardio"
    case fullBody = "Full Body"
    case other = "Other"
}

/// Types of exercises based on how they're tracked
enum ExerciseType: String, Codable, CaseIterable {
    case weightAndReps = "Weight & Reps"
    case bodyweight = "Bodyweight"
    case timed = "Timed"
    case distance = "Distance"
    case cardio = "Cardio"
}

/// Represents an exercise definition
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: ExerciseCategory
    var exerciseType: ExerciseType
    var muscleGroups: [String]
    var isCompound: Bool
    var instructions: String?
    var createdAt: Date
    var isCustom: Bool

    init(
        id: UUID = UUID(),
        name: String,
        category: ExerciseCategory,
        exerciseType: ExerciseType = .weightAndReps,
        muscleGroups: [String] = [],
        isCompound: Bool = false,
        instructions: String? = nil,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.exerciseType = exerciseType
        self.muscleGroups = muscleGroups
        self.isCompound = isCompound
        self.instructions = instructions
        self.createdAt = .now
        self.isCustom = isCustom
    }
}
