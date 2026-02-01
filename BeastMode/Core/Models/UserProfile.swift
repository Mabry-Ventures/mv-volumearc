import Foundation
import SwiftData

/// User profile containing preferences and relationships to workout data
@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var createdAt: Date
    var preferredUnits: WeightUnit
    var restTimerDefault: TimeInterval
    var weekStartsOn: Weekday

    @Relationship(deleteRule: .cascade, inverse: \WorkoutPlan.owner)
    var plans: [WorkoutPlan] = []

    @Relationship(deleteRule: .cascade, inverse: \PersonalRecord.owner)
    var personalRecords: [PersonalRecord] = []

    init(
        id: UUID = UUID(),
        displayName: String = "Athlete",
        createdAt: Date = Date(),
        preferredUnits: WeightUnit = .pounds,
        restTimerDefault: TimeInterval = 90,
        weekStartsOn: Weekday = .monday
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.preferredUnits = preferredUnits
        self.restTimerDefault = restTimerDefault
        self.weekStartsOn = weekStartsOn
    }
}

// MARK: - Weight Unit

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case pounds = "lbs"
    case kilograms = "kg"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pounds: return "Pounds (lbs)"
        case .kilograms: return "Kilograms (kg)"
        }
    }

    var abbreviation: String { rawValue }

    /// Convert from this unit to pounds
    func toPounds(_ value: Double) -> Double {
        switch self {
        case .pounds: return value
        case .kilograms: return value * 2.20462
        }
    }

    /// Convert from this unit to kilograms
    func toKilograms(_ value: Double) -> Double {
        switch self {
        case .pounds: return value / 2.20462
        case .kilograms: return value
        }
    }
}

// MARK: - Weekday

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var fullName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }

    var singleLetter: String {
        switch self {
        case .sunday: return "S"
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "T"
        case .friday: return "F"
        case .saturday: return "S"
        }
    }

    /// Get the current weekday
    static var today: Weekday {
        let calendar = Calendar.current
        let weekdayNumber = calendar.component(.weekday, from: Date())
        return Weekday(rawValue: weekdayNumber) ?? .monday
    }
}
