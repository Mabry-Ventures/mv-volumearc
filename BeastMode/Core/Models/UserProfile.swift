// UserProfile.swift
// BeastMode
// User profile model with preferences and rest timer settings

import Foundation
import SwiftData

/// Unit system preference
enum UnitSystem: String, Codable, CaseIterable {
    case imperial = "Imperial"
    case metric = "Metric"

    var weightUnit: String {
        switch self {
        case .imperial: return "lbs"
        case .metric: return "kg"
        }
    }

    var distanceUnit: String {
        switch self {
        case .imperial: return "mi"
        case .metric: return "km"
        }
    }
}

/// Represents a user's profile and preferences
@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var email: String?
    var createdAt: Date
    var unitSystem: String  // Stored as string for SwiftData

    // Rest timer defaults (in seconds)
    var restTimerCompound: TimeInterval   // For big lifts (squat, bench, dead)
    var restTimerIsolation: TimeInterval  // For accessories
    var restTimerDefault: TimeInterval    // Fallback

    // Per-exercise overrides stored as JSON
    var exerciseRestTimersData: Data?

    // Notification preferences
    var notificationsEnabled: Bool
    var restTimerSoundEnabled: Bool
    var restTimerVibrationEnabled: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        email: String? = nil,
        unitSystem: UnitSystem = .imperial
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.createdAt = .now
        self.unitSystem = unitSystem.rawValue

        // Rest timer defaults
        self.restTimerCompound = 180     // 3 minutes
        self.restTimerIsolation = 90     // 1.5 minutes
        self.restTimerDefault = 120      // 2 minutes
        self.exerciseRestTimersData = nil

        // Notification defaults
        self.notificationsEnabled = true
        self.restTimerSoundEnabled = true
        self.restTimerVibrationEnabled = true
    }

    var unitSystemEnum: UnitSystem {
        get { UnitSystem(rawValue: unitSystem) ?? .imperial }
        set { unitSystem = newValue.rawValue }
    }

    /// Per-exercise rest timer overrides
    var exerciseRestTimers: [String: TimeInterval] {
        get {
            guard let data = exerciseRestTimersData else { return [:] }
            return (try? JSONDecoder().decode([String: TimeInterval].self, from: data)) ?? [:]
        }
        set {
            exerciseRestTimersData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Set a custom rest timer for a specific exercise
    func setRestTimer(for exerciseName: String, duration: TimeInterval) {
        var timers = exerciseRestTimers
        timers[exerciseName] = duration
        exerciseRestTimers = timers
    }

    /// Remove custom rest timer for a specific exercise
    func removeRestTimer(for exerciseName: String) {
        var timers = exerciseRestTimers
        timers.removeValue(forKey: exerciseName)
        exerciseRestTimers = timers
    }
}
