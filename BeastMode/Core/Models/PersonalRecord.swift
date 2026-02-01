// PersonalRecord.swift
// BeastMode
// Model for tracking personal records

import Foundation
import SwiftData

/// Represents a personal record achievement
@Model
final class PersonalRecord {
    @Attribute(.unique) var id: UUID
    var exerciseName: String
    var weight: Double
    var reps: Int
    var estimatedOneRepMax: Double
    var date: Date
    var sourceSetId: UUID?
    var prType: String  // Stored as string for SwiftData compatibility
    var userId: UUID

    init(
        id: UUID = UUID(),
        exerciseName: String,
        weight: Double,
        reps: Int,
        estimatedOneRepMax: Double,
        date: Date = .now,
        sourceSetId: UUID? = nil,
        prType: PRType = .estimatedMax(improvement: 0),
        userId: UUID
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.estimatedOneRepMax = estimatedOneRepMax
        self.date = date
        self.sourceSetId = sourceSetId
        self.prType = prType.rawValue
        self.userId = userId
    }

    var prTypeEnum: PRType {
        PRType(rawValue: prType) ?? .firstTime
    }
}

/// Types of personal records
enum PRType: Equatable, Hashable {
    case firstTime
    case estimatedMax(improvement: Double)
    case heaviestWeight(weight: Double)
    case repRecord(atWeight: Double, reps: Int)

    var title: String {
        switch self {
        case .firstTime: return "FIRST PR!"
        case .estimatedMax: return "NEW MAX!"
        case .heaviestWeight: return "HEAVIEST EVER!"
        case .repRecord: return "REP RECORD!"
        }
    }

    var subtitle: String {
        switch self {
        case .firstTime:
            return "You're on the board!"
        case .estimatedMax(let improvement):
            return "+\(Int(improvement)) lbs estimated 1RM"
        case .heaviestWeight(let weight):
            return "\(Int(weight)) lbs is your new best"
        case .repRecord(let weight, let reps):
            return "\(reps) reps @ \(Int(weight)) lbs"
        }
    }

    var rawValue: String {
        switch self {
        case .firstTime:
            return "firstTime"
        case .estimatedMax(let improvement):
            return "estimatedMax:\(improvement)"
        case .heaviestWeight(let weight):
            return "heaviestWeight:\(weight)"
        case .repRecord(let weight, let reps):
            return "repRecord:\(weight):\(reps)"
        }
    }

    init?(rawValue: String) {
        if rawValue == "firstTime" {
            self = .firstTime
            return
        }

        let parts = rawValue.split(separator: ":")
        guard parts.count >= 2 else { return nil }

        switch parts[0] {
        case "estimatedMax":
            if let improvement = Double(parts[1]) {
                self = .estimatedMax(improvement: improvement)
            } else {
                return nil
            }
        case "heaviestWeight":
            if let weight = Double(parts[1]) {
                self = .heaviestWeight(weight: weight)
            } else {
                return nil
            }
        case "repRecord":
            if parts.count >= 3,
               let weight = Double(parts[1]),
               let reps = Int(parts[2]) {
                self = .repRecord(atWeight: weight, reps: reps)
            } else {
                return nil
            }
        default:
            return nil
        }
    }
}
