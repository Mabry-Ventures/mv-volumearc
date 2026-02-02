// WorkoutPlan.swift
// BeastMode
// Models for custom workout plans and weekly splits

import Foundation
import SwiftData

// MARK: - Workout Plan Model

/// Current schema version for WorkoutPlan
/// Increment this when making breaking changes to the plan structure
let kWorkoutPlanCurrentVersion: Int = 2

/// A custom workout plan/split that can be shared
@Model
final class WorkoutPlan {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var name: String
    var planDescription: String?
    var createdAt: Date
    var updatedAt: Date
    var isActive: Bool

    // Schema version for migration support
    var schemaVersion: Int

    // Sharing properties
    var isPublic: Bool
    var shareCode: String?
    var authorName: String?
    var downloadCount: Int

    // Plan metadata
    var daysPerWeek: Int
    var difficulty: PlanDifficulty
    var targetGoal: PlanGoal
    var estimatedDuration: Int  // weeks

    // V2: Additional metadata for enhanced plan features
    var tags: [String]
    var equipmentRequired: [String]
    var targetMuscleGroups: [String]

    @Relationship(deleteRule: .cascade)
    var days: [PlanDay]

    init(
        userId: UUID,
        name: String,
        description: String? = nil,
        daysPerWeek: Int = 4,
        difficulty: PlanDifficulty = .intermediate,
        targetGoal: PlanGoal = .strength
    ) {
        self.id = UUID()
        self.userId = userId
        self.name = name
        self.planDescription = description
        self.createdAt = .now
        self.updatedAt = .now
        self.isActive = false
        self.schemaVersion = kWorkoutPlanCurrentVersion
        self.isPublic = false
        self.shareCode = nil
        self.authorName = nil
        self.downloadCount = 0
        self.daysPerWeek = daysPerWeek
        self.difficulty = difficulty
        self.targetGoal = targetGoal
        self.estimatedDuration = 8
        self.tags = []
        self.equipmentRequired = []
        self.targetMuscleGroups = []
        self.days = []
    }

    /// Check if plan needs migration to current version
    var needsMigration: Bool {
        schemaVersion < kWorkoutPlanCurrentVersion
    }

    /// Generate a unique share code
    func generateShareCode() {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        shareCode = String((0..<8).map { _ in chars.randomElement()! })
    }

    /// Get the day for a specific weekday (1 = Sunday, 7 = Saturday)
    func day(for weekday: Int) -> PlanDay? {
        days.first { $0.weekday == weekday }
    }

    /// Get sorted days
    var sortedDays: [PlanDay] {
        days.sorted { $0.weekday < $1.weekday }
    }

    /// Get training days only (non-rest days)
    var trainingDays: [PlanDay] {
        days.filter { !$0.isRestDay }.sorted { $0.weekday < $1.weekday }
    }

    /// Total exercises across all days
    var totalExercises: Int {
        days.reduce(0) { $0 + $1.exercises.count }
    }

    /// Total sets across all days
    var totalSets: Int {
        days.reduce(0) { total, day in
            total + day.exercises.reduce(0) { $0 + $1.targetSets }
        }
    }
}

// MARK: - Plan Day Model

/// A single day within a workout plan
@Model
final class PlanDay {
    @Attribute(.unique) var id: UUID
    var weekday: Int  // 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    var name: String  // e.g., "Push Day", "Legs", "Rest"
    var isRestDay: Bool
    var notes: String?

    @Relationship(deleteRule: .cascade)
    var exercises: [PlanExercise]

    var plan: WorkoutPlan?

    init(weekday: Int, name: String, isRestDay: Bool = false) {
        self.id = UUID()
        self.weekday = weekday
        self.name = name
        self.isRestDay = isRestDay
        self.notes = nil
        self.exercises = []
    }

    /// Get sorted exercises by order
    var sortedExercises: [PlanExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    /// Weekday name
    var weekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(weekday: weekday)) ?? .now
        return formatter.string(from: date)
    }

    /// Short weekday name
    var shortWeekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(weekday: weekday)) ?? .now
        return formatter.string(from: date)
    }
}

// MARK: - Plan Exercise Model

/// An exercise template within a plan day
@Model
final class PlanExercise {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var exerciseName: String
    var order: Int

    // Target prescription
    var targetSets: Int
    var targetRepsMin: Int
    var targetRepsMax: Int
    var targetRPE: Double?  // Rate of Perceived Exertion (1-10)
    var restSeconds: Int

    // Notes/instructions
    var notes: String?
    var superset: Bool  // If true, minimal rest before next exercise

    var day: PlanDay?

    init(
        exerciseId: UUID,
        exerciseName: String,
        order: Int,
        targetSets: Int = 3,
        targetRepsMin: Int = 8,
        targetRepsMax: Int = 12,
        targetRPE: Double? = nil,
        restSeconds: Int = 90
    ) {
        self.id = UUID()
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.order = order
        self.targetSets = targetSets
        self.targetRepsMin = targetRepsMin
        self.targetRepsMax = targetRepsMax
        self.targetRPE = targetRPE
        self.restSeconds = restSeconds
        self.notes = nil
        self.superset = false
    }

    /// Formatted rep range
    var repRangeText: String {
        if targetRepsMin == targetRepsMax {
            return "\(targetRepsMin)"
        }
        return "\(targetRepsMin)-\(targetRepsMax)"
    }

    /// Formatted sets x reps
    var prescriptionText: String {
        "\(targetSets) × \(repRangeText)"
    }
}

// MARK: - Enums

/// Plan difficulty level
enum PlanDifficulty: String, Codable, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"

    var icon: String {
        switch self {
        case .beginner: return "1.circle.fill"
        case .intermediate: return "2.circle.fill"
        case .advanced: return "3.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .beginner: return "22C55E"  // Green
        case .intermediate: return "F59E0B"  // Amber
        case .advanced: return "EF4444"  // Red
        }
    }
}

/// Target training goal
enum PlanGoal: String, Codable, CaseIterable {
    case strength = "Strength"
    case hypertrophy = "Hypertrophy"
    case endurance = "Endurance"
    case powerlifting = "Powerlifting"
    case general = "General Fitness"

    var icon: String {
        switch self {
        case .strength: return "bolt.fill"
        case .hypertrophy: return "figure.strengthtraining.traditional"
        case .endurance: return "heart.fill"
        case .powerlifting: return "scalemass.fill"
        case .general: return "figure.mixed.cardio"
        }
    }

    var description: String {
        switch self {
        case .strength: return "Focus on heavy weights, low reps"
        case .hypertrophy: return "Focus on muscle growth, moderate reps"
        case .endurance: return "Focus on stamina, high reps"
        case .powerlifting: return "Squat, bench, deadlift focused"
        case .general: return "Balanced overall fitness"
        }
    }
}

// MARK: - Plan Templates

/// Pre-built plan templates
enum PlanTemplate: String, CaseIterable, Identifiable {
    case ppl = "Push/Pull/Legs"
    case upperLower = "Upper/Lower"
    case fullBody = "Full Body"
    case bro = "Bro Split"
    case powerbuilding = "Powerbuilding"

    var id: String { rawValue }

    var daysPerWeek: Int {
        switch self {
        case .ppl: return 6
        case .upperLower: return 4
        case .fullBody: return 3
        case .bro: return 5
        case .powerbuilding: return 4
        }
    }

    var description: String {
        switch self {
        case .ppl: return "Push, Pull, Legs repeated twice"
        case .upperLower: return "Upper body and lower body alternating"
        case .fullBody: return "3 full body workouts per week"
        case .bro: return "One muscle group per day"
        case .powerbuilding: return "Strength + hypertrophy hybrid"
        }
    }

    var icon: String {
        switch self {
        case .ppl: return "arrow.left.arrow.right"
        case .upperLower: return "arrow.up.arrow.down"
        case .fullBody: return "figure.stand"
        case .bro: return "figure.arms.open"
        case .powerbuilding: return "bolt.fill"
        }
    }
}

// MARK: - Shareable Plan DTO

/// Data transfer object for sharing plans
/// Supports multiple versions for backwards compatibility
struct ShareablePlan: Codable {
    let version: Int
    let name: String
    let description: String?
    let authorName: String?
    let difficulty: String
    let goal: String
    let daysPerWeek: Int
    let estimatedDuration: Int
    let days: [ShareablePlanDay]
    let createdAt: Date

    // V2 fields (optional for backwards compatibility)
    let tags: [String]?
    let equipmentRequired: [String]?
    let targetMuscleGroups: [String]?

    /// Export format version (distinct from schema version)
    static let currentExportVersion = 2

    /// Minimum supported import version
    static let minimumSupportedVersion = 1

    init(from plan: WorkoutPlan) {
        self.version = Self.currentExportVersion
        self.name = plan.name
        self.description = plan.planDescription
        self.authorName = plan.authorName
        self.difficulty = plan.difficulty.rawValue
        self.goal = plan.targetGoal.rawValue
        self.daysPerWeek = plan.daysPerWeek
        self.estimatedDuration = plan.estimatedDuration
        self.days = plan.sortedDays.map { ShareablePlanDay(from: $0) }
        self.createdAt = plan.createdAt

        // V2 fields
        self.tags = plan.tags.isEmpty ? nil : plan.tags
        self.equipmentRequired = plan.equipmentRequired.isEmpty ? nil : plan.equipmentRequired
        self.targetMuscleGroups = plan.targetMuscleGroups.isEmpty ? nil : plan.targetMuscleGroups
    }

    /// Check if this version is supported for import
    var isVersionSupported: Bool {
        version >= Self.minimumSupportedVersion && version <= Self.currentExportVersion
    }

    /// Check if this is an older version that needs migration
    var needsMigration: Bool {
        version < Self.currentExportVersion
    }

    /// Convert back to WorkoutPlan (handles all supported versions)
    func toPlan(userId: UUID) -> WorkoutPlan {
        let plan = WorkoutPlan(
            userId: userId,
            name: name,
            description: description,
            daysPerWeek: daysPerWeek,
            difficulty: PlanDifficulty(rawValue: difficulty) ?? .intermediate,
            targetGoal: PlanGoal(rawValue: goal) ?? .strength
        )
        plan.estimatedDuration = estimatedDuration
        plan.authorName = authorName

        // Apply V2 fields if present, otherwise use defaults
        plan.tags = tags ?? []
        plan.equipmentRequired = equipmentRequired ?? []
        plan.targetMuscleGroups = targetMuscleGroups ?? []

        // Set schema version based on import version
        // If importing V1, mark as needing potential upgrade
        plan.schemaVersion = version == 1 ? 1 : kWorkoutPlanCurrentVersion

        for dayDTO in days {
            let day = PlanDay(
                weekday: dayDTO.weekday,
                name: dayDTO.name,
                isRestDay: dayDTO.isRestDay
            )
            day.notes = dayDTO.notes

            for (index, exerciseDTO) in dayDTO.exercises.enumerated() {
                let exercise = PlanExercise(
                    exerciseId: UUID(),  // Generate new ID
                    exerciseName: exerciseDTO.name,
                    order: index,
                    targetSets: exerciseDTO.sets,
                    targetRepsMin: exerciseDTO.repsMin,
                    targetRepsMax: exerciseDTO.repsMax,
                    targetRPE: exerciseDTO.rpe,
                    restSeconds: exerciseDTO.restSeconds
                )
                exercise.notes = exerciseDTO.notes
                exercise.superset = exerciseDTO.superset
                day.exercises.append(exercise)
            }

            plan.days.append(day)
        }

        return plan
    }

    /// Create a migrated copy at the current version
    func migratedToCurrentVersion() -> ShareablePlan {
        guard needsMigration else { return self }

        return ShareablePlan(
            version: Self.currentExportVersion,
            name: name,
            description: description,
            authorName: authorName,
            difficulty: difficulty,
            goal: goal,
            daysPerWeek: daysPerWeek,
            estimatedDuration: estimatedDuration,
            days: days,
            createdAt: createdAt,
            tags: tags,
            equipmentRequired: equipmentRequired,
            targetMuscleGroups: targetMuscleGroups
        )
    }

    /// Full initializer for migration
    private init(
        version: Int,
        name: String,
        description: String?,
        authorName: String?,
        difficulty: String,
        goal: String,
        daysPerWeek: Int,
        estimatedDuration: Int,
        days: [ShareablePlanDay],
        createdAt: Date,
        tags: [String]?,
        equipmentRequired: [String]?,
        targetMuscleGroups: [String]?
    ) {
        self.version = version
        self.name = name
        self.description = description
        self.authorName = authorName
        self.difficulty = difficulty
        self.goal = goal
        self.daysPerWeek = daysPerWeek
        self.estimatedDuration = estimatedDuration
        self.days = days
        self.createdAt = createdAt
        self.tags = tags
        self.equipmentRequired = equipmentRequired
        self.targetMuscleGroups = targetMuscleGroups
    }
}

struct ShareablePlanDay: Codable {
    let weekday: Int
    let name: String
    let isRestDay: Bool
    let notes: String?
    let exercises: [ShareablePlanExercise]

    init(from day: PlanDay) {
        self.weekday = day.weekday
        self.name = day.name
        self.isRestDay = day.isRestDay
        self.notes = day.notes
        self.exercises = day.sortedExercises.map { ShareablePlanExercise(from: $0) }
    }
}

struct ShareablePlanExercise: Codable {
    let name: String
    let sets: Int
    let repsMin: Int
    let repsMax: Int
    let rpe: Double?
    let restSeconds: Int
    let notes: String?
    let superset: Bool

    init(from exercise: PlanExercise) {
        self.name = exercise.exerciseName
        self.sets = exercise.targetSets
        self.repsMin = exercise.targetRepsMin
        self.repsMax = exercise.targetRepsMax
        self.rpe = exercise.targetRPE
        self.restSeconds = exercise.restSeconds
        self.notes = exercise.notes
        self.superset = exercise.superset
    }
}
