import Foundation
import HealthKit
import WatchKit
import Combine

/// Manages workout sessions on Apple Watch
@MainActor
class WatchWorkoutManager: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var isWorkoutActive = false
    @Published var currentExercise: PlannedExercise?
    @Published var currentSetNumber = 1
    @Published var elapsedTime: TimeInterval = 0
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var completedSets = 0

    @Published var todayExercises: [PlannedExercise]?

    // MARK: - Private Properties

    private var healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?
    private var timer: Timer?

    // MARK: - Computed Properties

    var formattedElapsedTime: String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Initialization

    override init() {
        super.init()
        requestAuthorization()
    }

    // MARK: - Authorization

    private func requestAuthorization() {
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { _, _ in }
    }

    // MARK: - Workout Control

    func startWorkout(for day: PlannedDay) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        builder = session?.associatedWorkoutBuilder()

        builder?.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )

        session?.delegate = self
        builder?.delegate = self

        startDate = Date()
        session?.startActivity(with: startDate!)
        try await builder?.beginCollection(at: startDate!)

        todayExercises = day.sortedExercises
        isWorkoutActive = true
        currentSetNumber = 1
        completedSets = 0

        // Start timer
        startTimer()
    }

    func endWorkout() async throws {
        stopTimer()
        session?.end()
        try await builder?.endCollection(at: Date())

        if let workout = try await builder?.finishWorkout() {
            // Workout saved to HealthKit
            sendWorkoutToPhone(workout)
        }

        // Reset state
        isWorkoutActive = false
        currentExercise = nil
        currentSetNumber = 1
        elapsedTime = 0
        heartRate = 0
        activeCalories = 0
        completedSets = 0
    }

    // MARK: - Exercise Selection

    func selectExercise(_ exercise: PlannedExercise) {
        currentExercise = exercise
        currentSetNumber = 1
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Set Logging

    func logSet(weight: Double, reps: Int) {
        guard let exercise = currentExercise else { return }

        // Create set log and sync to phone
        let setLog = SetLogTransfer(
            exerciseId: exercise.id.uuidString,
            exerciseName: exercise.name,
            setNumber: currentSetNumber,
            weight: weight,
            reps: reps,
            duration: nil,
            timestamp: Date()
        )

        PhoneConnectivityService.shared.sendSetLog(setLog)

        currentSetNumber += 1
        completedSets += 1

        WKInterfaceDevice.current().play(.success)
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startDate = self.startDate else { return }
                self.elapsedTime = Date().timeIntervalSince(startDate)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Phone Communication

    private func sendWorkoutToPhone(_ workout: HKWorkout) {
        let transfer = WorkoutTransfer(
            startTime: workout.startDate,
            endTime: workout.endDate,
            focusArea: todayExercises?.first?.day?.focusArea ?? "Workout",
            exerciseLogs: []
        )
        PhoneConnectivityService.shared.sendWorkoutComplete(transfer)
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // Handle state changes
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        // Handle errors
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            let statistics = workoutBuilder.statistics(for: quantityType)

            Task { @MainActor in
                switch quantityType {
                case HKQuantityType.quantityType(forIdentifier: .heartRate):
                    if let value = statistics?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
                        self.heartRate = value
                    }

                case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                    if let value = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                        self.activeCalories = value
                    }

                default:
                    break
                }
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle events
    }
}
