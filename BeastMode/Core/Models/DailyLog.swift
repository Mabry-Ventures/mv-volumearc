import Foundation
import SwiftData

/// A log of a single day's workout
@Model
final class DailyLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    var weekId: String
    var weekday: Weekday
    var startedAt: Date?
    var completedAt: Date?
    var totalDuration: TimeInterval?
    var overallNotes: String?
    var mood: WorkoutMood?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.dailyLog)
    var exerciseLogs: [ExerciseLog] = []

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        weekday: Weekday? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        totalDuration: TimeInterval? = nil,
        overallNotes: String? = nil,
        mood: WorkoutMood? = nil
    ) {
        self.id = id
        self.date = date
        self.weekId = Self.calculateWeekId(from: date)
        self.weekday = weekday ?? Weekday.today
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.totalDuration = totalDuration
        self.overallNotes = overallNotes
        self.mood = mood
    }

    /// Check if the workout is complete
    var isComplete: Bool {
        completedAt != nil
    }

    /// Check if the workout is in progress
    var isInProgress: Bool {
        startedAt != nil && completedAt == nil
    }

    /// Get sorted exercise logs
    var sortedExerciseLogs: [ExerciseLog] {
        exerciseLogs.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Total number of completed sets
    var completedSetsCount: Int {
        exerciseLogs.reduce(0) { total, log in
            total + log.sets.filter { $0.completedAt != nil }.count
        }
    }

    /// Total volume (weight x reps) for the workout
    var totalVolume: Double {
        exerciseLogs.reduce(0) { total, log in
            total + log.totalVolume
        }
    }

    /// Calculate the ISO week ID from a date (e.g., "2025-W28")
    static func calculateWeekId(from date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    /// Get a formatted date string
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    /// Get duration formatted as string
    var formattedDuration: String? {
        guard let duration = totalDuration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Workout Mood

enum WorkoutMood: String, Codable, CaseIterable, Identifiable {
    case crushing = "crushing"
    case solid = "solid"
    case okay = "okay"
    case struggled = "struggled"
    case rest = "rest"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .crushing: return "💪"
        case .solid: return "👍"
        case .okay: return "😐"
        case .struggled: return "😤"
        case .rest: return "😴"
        }
    }

    var displayName: String {
        switch self {
        case .crushing: return "Crushing It"
        case .solid: return "Solid"
        case .okay: return "Okay"
        case .struggled: return "Struggled"
        case .rest: return "Rest Day"
        }
    }
}
