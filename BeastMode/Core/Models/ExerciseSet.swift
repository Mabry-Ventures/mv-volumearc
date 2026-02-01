import Foundation
import SwiftData

/// A log of an exercise performed during a workout
@Model
final class ExerciseLog {
    var id: UUID
    var exerciseName: String
    var exerciseType: ExerciseType
    var notes: String?
    var sortOrder: Int
    var dailyLog: DailyLog?

    /// For cardio/timed exercises (e.g., "30 min, 3.5 mi, 145 bpm avg")
    var details: String?

    @Relationship(deleteRule: .cascade, inverse: \SetLog.exerciseLog)
    var sets: [SetLog] = []

    init(
        id: UUID = UUID(),
        exerciseName: String,
        exerciseType: ExerciseType = .strength,
        notes: String? = nil,
        sortOrder: Int,
        details: String? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.exerciseType = exerciseType
        self.notes = notes
        self.sortOrder = sortOrder
        self.details = details
    }

    /// Get sorted sets
    var sortedSets: [SetLog] {
        sets.sorted { $0.setNumber < $1.setNumber }
    }

    /// Number of completed sets
    var completedSetsCount: Int {
        sets.filter { $0.completedAt != nil }.count
    }

    /// Total volume for this exercise
    var totalVolume: Double {
        sets.reduce(0) { total, set in
            guard let weight = set.weight, let reps = set.reps else { return total }
            return total + (weight * Double(reps))
        }
    }

    /// Best set (highest weight with most reps)
    var bestSet: SetLog? {
        sets
            .filter { $0.completedAt != nil && $0.weight != nil && $0.reps != nil }
            .max { lhs, rhs in
                let lhsScore = (lhs.weight ?? 0) * Double(lhs.reps ?? 0)
                let rhsScore = (rhs.weight ?? 0) * Double(rhs.reps ?? 0)
                return lhsScore < rhsScore
            }
    }

    /// Check if any set was a PR
    var hasPR: Bool {
        sets.contains { $0.isPR }
    }

    /// Summary for AI context
    var summaryForAI: String {
        let setsInfo = sortedSets
            .filter { $0.completedAt != nil }
            .map { set in
                if let weight = set.weight, let reps = set.reps {
                    return "\(Int(weight))lbs x \(reps)"
                } else if let duration = set.duration {
                    return "\(Int(duration))s"
                }
                return "incomplete"
            }
            .joined(separator: ", ")
        return "\(exerciseName): \(setsInfo)"
    }
}

/// A single set within an exercise
@Model
final class SetLog {
    var id: UUID
    var setNumber: Int
    var weight: Double?
    var reps: Int?
    var duration: TimeInterval?
    var isWarmup: Bool
    var isPR: Bool
    var rpe: Int?
    var completedAt: Date?
    var exerciseLog: ExerciseLog?

    init(
        id: UUID = UUID(),
        setNumber: Int,
        weight: Double? = nil,
        reps: Int? = nil,
        duration: TimeInterval? = nil,
        isWarmup: Bool = false,
        isPR: Bool = false,
        rpe: Int? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.duration = duration
        self.isWarmup = isWarmup
        self.isPR = isPR
        self.rpe = rpe
        self.completedAt = completedAt
    }

    /// Check if this set is complete
    var isComplete: Bool {
        completedAt != nil
    }

    /// Volume for this set
    var volume: Double {
        guard let weight = weight, let reps = reps else { return 0 }
        return weight * Double(reps)
    }

    /// Estimated one rep max using Epley formula
    var estimatedOneRepMax: Double? {
        guard let weight = weight, let reps = reps, reps > 0 else { return nil }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// Display string for the set
    var displayString: String {
        if let weight = weight, let reps = reps {
            return "\(Int(weight)) x \(reps)"
        } else if let duration = duration {
            let seconds = Int(duration)
            if seconds >= 60 {
                return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
            }
            return "\(seconds)s"
        }
        return "—"
    }
}
