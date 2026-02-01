import Foundation
import SwiftData

/// A personal record for an exercise
@Model
final class PersonalRecord {
    @Attribute(.unique) var id: UUID
    var exerciseName: String
    var weight: Double
    var reps: Int
    var estimatedOneRepMax: Double
    var date: Date
    var notes: String?
    var videoURL: URL?
    var owner: UserProfile?

    /// Link to the actual set that achieved this PR
    var sourceSetId: UUID?

    init(
        id: UUID = UUID(),
        exerciseName: String,
        weight: Double,
        reps: Int,
        date: Date = Date(),
        notes: String? = nil,
        videoURL: URL? = nil,
        sourceSetId: UUID? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.estimatedOneRepMax = Self.calculateE1RM(weight: weight, reps: reps)
        self.date = date
        self.notes = notes
        self.videoURL = videoURL
        self.sourceSetId = sourceSetId
    }

    /// Calculate estimated one rep max using Epley formula
    static func calculateE1RM(weight: Double, reps: Int) -> Double {
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// Display string for the PR
    var displayString: String {
        "\(Int(weight)) lbs x \(reps) reps"
    }

    /// Formatted date string
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    /// E1RM formatted string
    var e1rmString: String {
        "E1RM: \(Int(estimatedOneRepMax)) lbs"
    }

    /// Summary for AI context
    var summaryForAI: String {
        "\(exerciseName): \(Int(weight))lbs x \(reps) (E1RM: \(Int(estimatedOneRepMax))) on \(formattedDate)"
    }
}

// MARK: - PR Detection Helper

extension PersonalRecord {
    /// Check if a set beats this PR
    func isBeatenBy(weight: Double, reps: Int) -> Bool {
        let newE1RM = Self.calculateE1RM(weight: weight, reps: reps)
        return newE1RM > self.estimatedOneRepMax
    }

    /// Create a PR from a SetLog
    static func from(setLog: SetLog, exerciseName: String) -> PersonalRecord? {
        guard let weight = setLog.weight, let reps = setLog.reps else { return nil }
        return PersonalRecord(
            exerciseName: exerciseName,
            weight: weight,
            reps: reps,
            date: setLog.completedAt ?? Date(),
            sourceSetId: setLog.id
        )
    }
}
