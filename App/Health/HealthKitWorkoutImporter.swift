#if canImport(HealthKit)
import Foundation
import HealthKit
import VolumeArcCore

/// Imports completed Apple Health workouts from any source except VolumeArc
/// itself so outside sessions can influence local readiness/history.
struct HealthKitWorkoutImporter: HealthWorkoutImporting {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func completedWorkouts(since startDate: Date, now: Date) async throws -> [ImportedHealthWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: now,
            options: .strictStartDate
        )
        let workouts = try await queryWorkouts(predicate: predicate)
        return workouts
            .filter { $0.endDate <= now }
            .filter { !Self.isVolumeArcWorkout($0) }
            .map(Self.importedWorkout(from:))
    }

    private func queryWorkouts(predicate: NSPredicate) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 200,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            healthStore.execute(query)
        }
    }

    private static func importedWorkout(from workout: HKWorkout) -> ImportedHealthWorkout {
        let source = workout.sourceRevision.source
        let energy = activeEnergyKilocalories(from: workout)
        let activityName = activityDisplayName(for: workout.workoutActivityType)
        let title = source.name.isEmpty ? activityName : "\(activityName) from \(source.name)"
        return ImportedHealthWorkout(
            externalIdentifier: workout.uuid.uuidString,
            sourceName: source.name,
            sourceBundleIdentifier: source.bundleIdentifier,
            title: title,
            activityIdentifier: String(workout.workoutActivityType.rawValue),
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            durationMinutes: max(1, Int((workout.duration / 60.0).rounded(.up))),
            activeEnergyKilocalories: energy
        )
    }

    private static func isVolumeArcWorkout(_ workout: HKWorkout) -> Bool {
        if workout.metadata?[HealthWorkoutMetadata.volumeArcWorkoutIDKey] != nil {
            return true
        }
        return workout.sourceRevision.source.bundleIdentifier.hasPrefix("com.mabryventures.VolumeArc")
    }

    private static func activeEnergyKilocalories(from workout: HKWorkout) -> Double? {
        let energyType = HKQuantityType(.activeEnergyBurned)
        return workout.statistics(for: energyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
    }

    private static func activityDisplayName(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining:
            return "Strength training"
        case .functionalStrengthTraining:
            return "Functional strength"
        case .coreTraining:
            return "Core training"
        case .running:
            return "Run"
        case .walking:
            return "Walk"
        case .cycling:
            return "Ride"
        case .highIntensityIntervalTraining:
            return "HIIT"
        case .yoga:
            return "Yoga"
        case .pilates:
            return "Pilates"
        case .rowing:
            return "Row"
        case .elliptical:
            return "Elliptical"
        case .swimming:
            return "Swim"
        default:
            return "Workout"
        }
    }
}
#endif
