// RestTimerService.swift
// BeastMode
// Service for managing rest timer durations based on exercise type

import Foundation
import Combine

/// Service for determining appropriate rest times based on exercise type and user preferences
class RestTimerService: ObservableObject {
    private let profile: UserProfile

    /// Known compound exercises that benefit from longer rest
    private let compoundExercises: Set<String> = [
        // Chest
        "Barbell Bench Press", "Incline Bench Press", "Dumbbell Bench Press",
        "Decline Bench Press", "Close-Grip Bench Press",
        // Back
        "Barbell Rows", "Bent Over Rows", "T-Bar Rows", "Pull-ups", "Chin-ups",
        "Lat Pulldown", "Seated Cable Rows",
        // Legs
        "Barbell Squats", "Back Squats", "Front Squats", "Leg Press",
        "Hack Squats", "Bulgarian Split Squats", "Lunges",
        // Deadlifts
        "Deadlift", "Conventional Deadlift", "Romanian Deadlift", "Sumo Deadlift",
        "Stiff-Leg Deadlift", "Trap Bar Deadlift",
        // Shoulders
        "Overhead Press", "Military Press", "Push Press", "Arnold Press",
        "Seated Dumbbell Press", "Standing Dumbbell Press"
    ]

    /// Keywords that indicate isolation exercises
    private let isolationKeywords: Set<String> = [
        "curl", "extension", "raise", "fly", "flye", "kickback",
        "pushdown", "pullover", "shrug", "calf", "crunch", "plank",
        "twist", "rotation", "concentration", "preacher", "hammer"
    ]

    init(profile: UserProfile) {
        self.profile = profile
    }

    /// Get the appropriate rest duration for an exercise
    /// - Parameter exerciseName: Name of the exercise
    /// - Returns: Rest duration in seconds
    func getRestDuration(for exerciseName: String) -> TimeInterval {
        // Check for per-exercise override first
        if let override = profile.exerciseRestTimers[exerciseName] {
            return override
        }

        // Check if it's a compound movement
        let normalizedName = exerciseName.lowercased()

        for compound in compoundExercises {
            if normalizedName.contains(compound.lowercased()) ||
               compound.lowercased().contains(normalizedName) {
                return profile.restTimerCompound
            }
        }

        // Check for compound keywords
        let compoundKeywords = ["squat", "deadlift", "bench", "press", "row", "pull-up", "chin-up"]
        for keyword in compoundKeywords {
            if normalizedName.contains(keyword) {
                return profile.restTimerCompound
            }
        }

        // Check for isolation indicators
        for keyword in isolationKeywords {
            if normalizedName.contains(keyword) {
                return profile.restTimerIsolation
            }
        }

        // Default
        return profile.restTimerDefault
    }

    /// Determine if an exercise is compound
    func isCompoundExercise(_ exerciseName: String) -> Bool {
        let normalizedName = exerciseName.lowercased()

        for compound in compoundExercises {
            if normalizedName.contains(compound.lowercased()) {
                return true
            }
        }

        let compoundKeywords = ["squat", "deadlift", "bench", "press", "row"]
        for keyword in compoundKeywords {
            if normalizedName.contains(keyword) {
                return true
            }
        }

        return false
    }

    /// Format a time interval as a user-friendly string
    static func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60

        if secs == 0 {
            return "\(mins)m"
        } else if mins == 0 {
            return "\(secs)s"
        } else {
            return "\(mins):\(String(format: "%02d", secs))"
        }
    }
}

// MARK: - Rest Timer State Manager

/// Observable timer for managing active rest periods
@MainActor
class RestTimerManager: ObservableObject {
    @Published var isRunning = false
    @Published var remainingTime: TimeInterval = 0
    @Published var totalTime: TimeInterval = 0
    @Published var progress: Double = 1.0

    private var timer: Timer?
    private var completionHandler: (() -> Void)?

    deinit {
        timer?.invalidate()
        timer = nil
    }

    var formattedTime: String {
        let mins = Int(remainingTime) / 60
        let secs = Int(remainingTime) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Start a new rest timer
    func start(duration: TimeInterval, onComplete: (() -> Void)? = nil) {
        stop()

        totalTime = duration
        remainingTime = duration
        progress = 1.0
        isRunning = true
        completionHandler = onComplete

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    /// Stop the current timer
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Add time to the current timer
    func addTime(_ seconds: TimeInterval) {
        guard isRunning else { return }
        remainingTime += seconds
        totalTime += seconds
    }

    /// Skip the remaining time
    func skip() {
        stop()
        remainingTime = 0
        progress = 0
    }

    private func tick() {
        guard remainingTime > 0 else {
            complete()
            return
        }

        remainingTime -= 0.1
        progress = remainingTime / totalTime
    }

    private func complete() {
        stop()
        progress = 0

        // Trigger haptic feedback
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif

        completionHandler?()
    }
}
