import Foundation
import HealthKit

/// Service for integrating with HealthKit
actor HealthKitService {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()

    /// Types we read from HealthKit
    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            types.insert(bodyMass)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }()

    /// Types we write to HealthKit
    private let writeTypes: Set<HKSampleType> = {
        var types = Set<HKSampleType>()
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }()

    private init() {}

    // MARK: - Authorization

    /// Check if HealthKit is available on this device
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Request authorization to access HealthKit data
    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    /// Check authorization status for a specific type
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        healthStore.authorizationStatus(for: type)
    }

    // MARK: - Workouts

    /// Save a completed workout to HealthKit
    func saveWorkout(
        startDate: Date,
        endDate: Date,
        totalCalories: Double?,
        exerciseCount: Int,
        totalSets: Int
    ) async throws {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }

        var energyBurned: HKQuantity?
        if let calories = totalCalories {
            energyBurned = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        }

        let workout = HKWorkout(
            activityType: .traditionalStrengthTraining,
            start: startDate,
            end: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalEnergyBurned: energyBurned,
            totalDistance: nil,
            metadata: [
                "BeastMode_ExerciseCount": exerciseCount,
                "BeastMode_TotalSets": totalSets,
                "HKExternalUUID": UUID().uuidString
            ]
        )

        try await healthStore.save(workout)
    }

    /// Fetch recent workouts from HealthKit
    func fetchRecentWorkouts(limit: Int = 10) async throws -> [HKWorkout] {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }

        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Body Measurements

    /// Fetch the most recent body weight
    func fetchRecentBodyWeight() async throws -> Double? {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }

        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return nil
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    let weight = sample.quantity.doubleValue(for: .pound())
                    continuation.resume(returning: weight)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Heart Rate

    /// Fetch average heart rate for a time range
    func fetchAverageHeartRate(from startDate: Date, to endDate: Date) async throws -> Double? {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }

        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let average = statistics?.averageQuantity() {
                    let bpm = average.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    continuation.resume(returning: bpm)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Calories

    /// Fetch active calories burned for a time range
    func fetchActiveCalories(from startDate: Date, to endDate: Date) async throws -> Double? {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }

        guard let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: calorieType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let sum = statistics?.sumQuantity() {
                    let calories = sum.doubleValue(for: .kilocalorie())
                    continuation.resume(returning: calories)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case authorizationDenied
    case dataNotFound

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .authorizationDenied:
            return "Permission to access health data was denied"
        case .dataNotFound:
            return "Requested health data was not found"
        }
    }
}
