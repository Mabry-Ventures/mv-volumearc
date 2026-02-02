// WatchWorkoutModels.swift
// BeastModeWatch
// Codable models for watch-independent workout logging

import Foundation

// MARK: - Watch Workout Session

/// Represents a workout session logged independently on the Apple Watch
struct WatchWorkoutSession: Codable, Identifiable {
    let id: UUID
    var name: String
    var startedAt: Date
    var completedAt: Date?
    var exercises: [WatchExerciseLog]
    var syncStatus: SyncStatus

    init(
        id: UUID = UUID(),
        name: String = "Quick Workout",
        startedAt: Date = .now,
        completedAt: Date? = nil,
        exercises: [WatchExerciseLog] = [],
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.exercises = exercises
        self.syncStatus = syncStatus
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var duration: TimeInterval {
        let endTime = completedAt ?? Date()
        return endTime.timeIntervalSince(startedAt)
    }

    var totalVolume: Double {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { setTotal, set in
                setTotal + (set.weight * Double(set.reps))
            }
        }
    }

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    /// Format duration as string (e.g., "45:30")
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Watch Exercise Log

/// Represents an exercise within a watch workout session
struct WatchExerciseLog: Codable, Identifiable {
    let id: UUID
    var name: String
    var category: String
    var sets: [WatchSetLog]
    var order: Int

    init(
        id: UUID = UUID(),
        name: String,
        category: String = "Other",
        sets: [WatchSetLog] = [],
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.sets = sets
        self.order = order
    }

    var totalVolume: Double {
        sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }
}

// MARK: - Watch Set Log

/// Represents a single set logged on the watch
struct WatchSetLog: Codable, Identifiable {
    let id: UUID
    var setNumber: Int
    var weight: Double
    var reps: Int
    var completedAt: Date

    init(
        id: UUID = UUID(),
        setNumber: Int,
        weight: Double,
        reps: Int,
        completedAt: Date = .now
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.completedAt = completedAt
    }

    var volume: Double {
        weight * Double(reps)
    }
}

// MARK: - Sync Status

/// Status of workout synchronization with iPhone
enum SyncStatus: String, Codable {
    case pending = "pending"
    case syncing = "syncing"
    case synced = "synced"
    case failed = "failed"
}

// MARK: - Quick Exercise Templates

/// Pre-defined exercise templates for quick selection on watch
struct QuickExerciseTemplate: Codable, Identifiable {
    let id: UUID
    let name: String
    let category: String
    let defaultWeight: Double
    let defaultReps: Int

    init(
        id: UUID = UUID(),
        name: String,
        category: String,
        defaultWeight: Double = 0,
        defaultReps: Int = 10
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.defaultWeight = defaultWeight
        self.defaultReps = defaultReps
    }

    /// Default exercise templates for common exercises
    static let defaults: [QuickExerciseTemplate] = [
        QuickExerciseTemplate(name: "Bench Press", category: "Chest", defaultWeight: 135, defaultReps: 10),
        QuickExerciseTemplate(name: "Squat", category: "Legs", defaultWeight: 185, defaultReps: 8),
        QuickExerciseTemplate(name: "Deadlift", category: "Back", defaultWeight: 225, defaultReps: 5),
        QuickExerciseTemplate(name: "Overhead Press", category: "Shoulders", defaultWeight: 95, defaultReps: 8),
        QuickExerciseTemplate(name: "Barbell Row", category: "Back", defaultWeight: 135, defaultReps: 10),
        QuickExerciseTemplate(name: "Pull-ups", category: "Back", defaultWeight: 0, defaultReps: 10),
        QuickExerciseTemplate(name: "Dumbbell Curl", category: "Biceps", defaultWeight: 30, defaultReps: 12),
        QuickExerciseTemplate(name: "Tricep Pushdown", category: "Triceps", defaultWeight: 50, defaultReps: 12),
        QuickExerciseTemplate(name: "Leg Press", category: "Legs", defaultWeight: 270, defaultReps: 12),
        QuickExerciseTemplate(name: "Lat Pulldown", category: "Back", defaultWeight: 120, defaultReps: 10)
    ]
}

// MARK: - Watch Connectivity Message Types

/// Message types for WatchConnectivity communication
enum WatchMessageType: String, Codable {
    case workoutCompleted = "workout_completed"
    case requestSync = "request_sync"
    case syncAcknowledged = "sync_acknowledged"
    case exerciseTemplatesUpdate = "exercise_templates_update"
    case userDataSync = "user_data_sync"
}

/// Wrapper for WatchConnectivity messages
struct WatchMessage: Codable {
    let type: WatchMessageType
    let payload: Data
    let timestamp: Date

    init(type: WatchMessageType, payload: Data, timestamp: Date = .now) {
        self.type = type
        self.payload = payload
        self.timestamp = timestamp
    }
}

// MARK: - Workout Transfer Data

/// Data structure for transferring completed workouts to iPhone
struct WorkoutTransferData: Codable {
    let workouts: [WatchWorkoutSession]
    let transferredAt: Date

    init(workouts: [WatchWorkoutSession], transferredAt: Date = .now) {
        self.workouts = workouts
        self.transferredAt = transferredAt
    }
}
