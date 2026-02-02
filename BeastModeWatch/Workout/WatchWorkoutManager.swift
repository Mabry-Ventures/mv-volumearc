// WatchWorkoutManager.swift
// BeastModeWatch
// Manages independent workout sessions on Apple Watch

import Foundation
import Combine
import HealthKit
import WatchKit

/// Manages workout sessions independently on the Apple Watch
@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = WatchWorkoutManager()

    // MARK: - Published Properties

    @Published var activeWorkout: WatchWorkoutSession?
    @Published var currentExercise: WatchExerciseLog?
    @Published var pendingWorkouts: [WatchWorkoutSession] = []
    @Published var exerciseTemplates: [QuickExerciseTemplate] = QuickExerciseTemplate.defaults
    @Published var isWorkoutActive: Bool = false
    @Published var elapsedTime: TimeInterval = 0

    // MARK: - Input State (for Digital Crown)

    @Published var inputWeight: Double = 0
    @Published var inputReps: Int = 10
    @Published var weightIncrement: Double = 5.0

    // MARK: - Private Properties

    private var healthStore: HKHealthStore?
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var timerCancellable: AnyCancellable?

    private let storageKey = "pendingWatchWorkouts"
    private let templatesKey = "exerciseTemplates"
    private let lastWeightKey = "lastUsedWeights"

    // MARK: - Initialization

    private override init() {
        super.init()
        loadPendingWorkouts()
        loadExerciseTemplates()

        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        }
    }

    // MARK: - Workout Session Control

    /// Start a new workout session
    func startWorkout(name: String = "Quick Workout") {
        guard activeWorkout == nil else {
            print("Workout already in progress")
            return
        }

        activeWorkout = WatchWorkoutSession(name: name)
        isWorkoutActive = true
        elapsedTime = 0

        startTimer()
        startHealthKitWorkout()

        // Haptic feedback
        WKInterfaceDevice.current().play(.start)
    }

    /// End the current workout session
    func endWorkout() {
        guard var workout = activeWorkout else { return }

        workout.completedAt = Date()
        workout.syncStatus = .pending

        // Save to pending workouts for sync
        pendingWorkouts.append(workout)
        savePendingWorkouts()

        // End HealthKit workout
        endHealthKitWorkout()

        // Reset state
        activeWorkout = nil
        currentExercise = nil
        isWorkoutActive = false
        stopTimer()

        // Haptic feedback
        WKInterfaceDevice.current().play(.success)

        // Notify connectivity manager to sync
        Task {
            await WatchConnectivityManager.shared.syncPendingWorkouts()
        }
    }

    /// Cancel the current workout without saving
    func cancelWorkout() {
        activeWorkout = nil
        currentExercise = nil
        isWorkoutActive = false
        stopTimer()
        endHealthKitWorkout()

        WKInterfaceDevice.current().play(.failure)
    }

    // MARK: - Exercise Management

    /// Add a new exercise to the current workout
    func addExercise(from template: QuickExerciseTemplate) {
        guard var workout = activeWorkout else { return }

        let exercise = WatchExerciseLog(
            name: template.name,
            category: template.category,
            order: workout.exercises.count
        )

        workout.exercises.append(exercise)
        activeWorkout = workout
        currentExercise = exercise

        // Set default weight from last used or template
        inputWeight = getLastUsedWeight(for: template.name) ?? template.defaultWeight
        inputReps = template.defaultReps

        WKInterfaceDevice.current().play(.click)
    }

    /// Add a custom exercise by name
    func addCustomExercise(name: String, category: String = "Other") {
        guard var workout = activeWorkout else { return }

        let exercise = WatchExerciseLog(
            name: name,
            category: category,
            order: workout.exercises.count
        )

        workout.exercises.append(exercise)
        activeWorkout = workout
        currentExercise = exercise

        inputWeight = getLastUsedWeight(for: name) ?? 0
        inputReps = 10

        WKInterfaceDevice.current().play(.click)
    }

    /// Select an existing exercise in the workout
    func selectExercise(_ exercise: WatchExerciseLog) {
        currentExercise = exercise
        inputWeight = getLastUsedWeight(for: exercise.name) ?? (exercise.sets.last?.weight ?? 0)
        inputReps = exercise.sets.last?.reps ?? 10
    }

    // MARK: - Set Logging

    /// Log a set for the current exercise
    func logSet() {
        guard var workout = activeWorkout,
              var exercise = currentExercise,
              let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exercise.id }) else {
            return
        }

        let setNumber = exercise.sets.count + 1
        let newSet = WatchSetLog(
            setNumber: setNumber,
            weight: inputWeight,
            reps: inputReps
        )

        exercise.sets.append(newSet)
        workout.exercises[exerciseIndex] = exercise

        activeWorkout = workout
        currentExercise = exercise

        // Save last used weight
        saveLastUsedWeight(inputWeight, for: exercise.name)

        // Haptic feedback
        WKInterfaceDevice.current().play(.click)
    }

    /// Remove the last set from current exercise
    func undoLastSet() {
        guard var workout = activeWorkout,
              var exercise = currentExercise,
              let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exercise.id }),
              !exercise.sets.isEmpty else {
            return
        }

        exercise.sets.removeLast()
        workout.exercises[exerciseIndex] = exercise

        activeWorkout = workout
        currentExercise = exercise

        WKInterfaceDevice.current().play(.retry)
    }

    // MARK: - Weight/Rep Adjustment (Digital Crown)

    /// Adjust weight using Digital Crown rotation
    func adjustWeight(by delta: Double) {
        let newWeight = max(0, inputWeight + (delta * weightIncrement))
        inputWeight = newWeight.rounded(toPlaces: 1)
    }

    /// Adjust reps
    func adjustReps(by delta: Int) {
        inputReps = max(1, min(100, inputReps + delta))
    }

    /// Set specific weight
    func setWeight(_ weight: Double) {
        inputWeight = max(0, weight).rounded(toPlaces: 1)
    }

    /// Set specific reps
    func setReps(_ reps: Int) {
        inputReps = max(1, min(100, reps))
    }

    // MARK: - Storage

    /// Load pending workouts from local storage
    private func loadPendingWorkouts() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }

        do {
            pendingWorkouts = try JSONDecoder().decode([WatchWorkoutSession].self, from: data)
        } catch {
            print("Failed to load pending workouts: \(error)")
        }
    }

    /// Save pending workouts to local storage
    func savePendingWorkouts() {
        do {
            let data = try JSONEncoder().encode(pendingWorkouts)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save pending workouts: \(error)")
        }
    }

    /// Load exercise templates
    private func loadExerciseTemplates() {
        guard let data = UserDefaults.standard.data(forKey: templatesKey) else { return }

        do {
            exerciseTemplates = try JSONDecoder().decode([QuickExerciseTemplate].self, from: data)
        } catch {
            print("Failed to load exercise templates: \(error)")
        }
    }

    /// Update exercise templates (from iPhone sync)
    func updateExerciseTemplates(_ templates: [QuickExerciseTemplate]) {
        exerciseTemplates = templates
        do {
            let data = try JSONEncoder().encode(templates)
            UserDefaults.standard.set(data, forKey: templatesKey)
        } catch {
            print("Failed to save exercise templates: \(error)")
        }
    }

    /// Get last used weight for an exercise
    private func getLastUsedWeight(for exerciseName: String) -> Double? {
        guard let data = UserDefaults.standard.data(forKey: lastWeightKey),
              let weights = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return nil
        }
        return weights[exerciseName]
    }

    /// Save last used weight for an exercise
    private func saveLastUsedWeight(_ weight: Double, for exerciseName: String) {
        var weights: [String: Double] = [:]

        if let data = UserDefaults.standard.data(forKey: lastWeightKey),
           let existing = try? JSONDecoder().decode([String: Double].self, from: data) {
            weights = existing
        }

        weights[exerciseName] = weight

        if let data = try? JSONEncoder().encode(weights) {
            UserDefaults.standard.set(data, forKey: lastWeightKey)
        }
    }

    /// Remove synced workouts from pending list
    func markWorkoutsAsSynced(_ workoutIds: [UUID]) {
        pendingWorkouts.removeAll { workoutIds.contains($0.id) }
        savePendingWorkouts()
    }

    /// Get workouts ready for sync
    func getWorkoutsForSync() -> [WatchWorkoutSession] {
        pendingWorkouts.filter { $0.syncStatus == .pending && $0.isCompleted }
    }

    // MARK: - Timer

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let workout = self.activeWorkout else { return }
                self.elapsedTime = Date().timeIntervalSince(workout.startedAt)
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        elapsedTime = 0
    }

    // MARK: - HealthKit Integration

    private func startHealthKitWorkout() {
        guard let healthStore else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()
            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            workoutSession?.startActivity(with: Date())
            workoutBuilder?.beginCollection(withStart: Date()) { success, error in
                if let error {
                    print("Failed to begin workout collection: \(error)")
                }
            }
        } catch {
            print("Failed to start HealthKit workout: \(error)")
        }
    }

    private func endHealthKitWorkout() {
        guard let workoutSession, let workoutBuilder else { return }

        workoutSession.end()

        workoutBuilder.endCollection(withEnd: Date()) { [weak self] success, error in
            if let error {
                print("Failed to end workout collection: \(error)")
                return
            }

            self?.workoutBuilder?.finishWorkout { workout, error in
                if let error {
                    print("Failed to finish workout: \(error)")
                } else if let workout {
                    print("Workout saved to HealthKit: \(workout)")
                }
            }
        }

        self.workoutSession = nil
        self.workoutBuilder = nil
    }
}

// MARK: - Helper Extensions

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
