import Foundation
import SwiftData

/// A workout plan containing a weekly schedule of exercises
@Model
final class WorkoutPlan {
    @Attribute(.unique) var id: UUID
    var name: String
    var isActive: Bool
    var createdAt: Date
    var owner: UserProfile?

    @Relationship(deleteRule: .cascade, inverse: \PlannedDay.plan)
    var days: [PlannedDay] = []

    init(
        id: UUID = UUID(),
        name: String,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.createdAt = createdAt
    }

    /// Get days sorted by weekday
    var sortedDays: [PlannedDay] {
        days.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Get the day for a specific weekday
    func day(for weekday: Weekday) -> PlannedDay? {
        days.first { $0.weekday == weekday }
    }
}

/// A single day in a workout plan
@Model
final class PlannedDay {
    var id: UUID
    var weekday: Weekday
    var focusArea: String
    var sortOrder: Int
    var plan: WorkoutPlan?

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.day)
    var exercises: [PlannedExercise] = []

    init(
        id: UUID = UUID(),
        weekday: Weekday,
        focusArea: String,
        sortOrder: Int
    ) {
        self.id = id
        self.weekday = weekday
        self.focusArea = focusArea
        self.sortOrder = sortOrder
    }

    /// Get exercises sorted by order
    var sortedExercises: [PlannedExercise] {
        exercises.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Check if this is a rest day
    var isRestDay: Bool {
        focusArea.lowercased() == "rest" || exercises.isEmpty
    }

    /// Total number of planned sets for the day
    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.targetSets }
    }
}

/// A planned exercise within a workout day
@Model
final class PlannedExercise {
    var id: UUID
    var name: String
    var targetSets: Int
    var targetRepsMin: Int
    var targetRepsMax: Int
    var exerciseType: ExerciseType
    var notes: String?
    var sortOrder: Int
    var day: PlannedDay?

    init(
        id: UUID = UUID(),
        name: String,
        targetSets: Int,
        targetRepsMin: Int,
        targetRepsMax: Int,
        exerciseType: ExerciseType = .strength,
        notes: String? = nil,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.targetSets = targetSets
        self.targetRepsMin = targetRepsMin
        self.targetRepsMax = targetRepsMax
        self.exerciseType = exerciseType
        self.notes = notes
        self.sortOrder = sortOrder
    }

    /// Formatted rep range string (e.g., "8-12" or "10")
    var repRangeString: String {
        if targetRepsMin == targetRepsMax {
            return "\(targetRepsMin)"
        }
        return "\(targetRepsMin)-\(targetRepsMax)"
    }

    /// Summary string (e.g., "4 x 8-12")
    var summaryString: String {
        "\(targetSets) x \(repRangeString)"
    }
}

// MARK: - Exercise Type

enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case strength
    case cardio
    case core
    case mobility
    case timed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .cardio: return "Cardio"
        case .core: return "Core"
        case .mobility: return "Mobility"
        case .timed: return "Timed"
        }
    }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "heart.fill"
        case .core: return "figure.core.training"
        case .mobility: return "figure.flexibility"
        case .timed: return "timer"
        }
    }
}
