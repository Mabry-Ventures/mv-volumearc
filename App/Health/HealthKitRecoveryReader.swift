#if canImport(HealthKit)
import Foundation
import HealthKit
import VolumeArcCore

/// VOL-181 Phase 1B: HealthKit-backed `RecoveryReader` that produces a
/// real `RecoveryContext` from `HKHealthStore` samples. Reads:
///
/// - **HRV (SDNN)** — 7-day mean and 28-day rolling baseline. Delta is
///   computed in Swift from the two means; HK has no native "delta vs
///   baseline" type.
/// - **Sleep** — 7-day total of `.asleepCore + .asleepDeep + .asleepREM`
///   per Apple's sleep-analysis recommendation. Compared against a
///   default 8h/night target to compute sleep debt.
/// - **Strength load** — 7-day sum of `traditionalStrengthTraining`
///   workouts: total active energy (converted kcal → kJ) and total
///   duration (seconds → minutes).
/// - **Apple Watch Vitals score** — not exposed as a public HK type as
///   of 2026-05; returns `nil`. A future Apple SDK release may
///   surface this; tracked separately.
///
/// All reads are non-throwing-on-no-data: if HK has no samples in the
/// window, the corresponding `RecoveryContext` field is `nil` (so
/// `RecoveryContext.asPromptBullets()` simply omits that line). Errors
/// are only thrown for HK availability or authorization failures.
///
/// The struct accepts a `HKHealthStore` dependency at init so the
/// production path can share the app's existing store instance and
/// tests (which can't easily mock `HKHealthStore` directly) can
/// substitute a different reader implementation via the
/// `RecoveryReader` protocol seam.
public struct HealthKitRecoveryReader: RecoveryReader {

    private let healthStore: HKHealthStore
    private let sleepTargetHours: Double
    private let strengthActivityType: HKWorkoutActivityType

    public init(
        healthStore: HKHealthStore = HKHealthStore(),
        sleepTargetHours: Double = 8.0,
        strengthActivityType: HKWorkoutActivityType = .traditionalStrengthTraining
    ) {
        self.healthStore = healthStore
        self.sleepTargetHours = sleepTargetHours
        self.strengthActivityType = strengthActivityType
    }

    public func currentRecovery(now: Date = .now) async throws -> RecoveryContext {
        guard HKHealthStore.isHealthDataAvailable() else {
            return RecoveryContext()
        }

        async let hrv7 = meanHRV(overDays: 7, now: now)
        async let hrv28 = meanHRV(overDays: 28, now: now)
        async let sleep7 = totalSleepHours(overDays: 7, now: now)
        async let load = strengthLoad(overDays: 7, now: now)

        let (mean7Day, baseline, sleepTotal, strengthSummary) = try await (
            hrv7, hrv28, sleep7, load
        )

        let deltaPercent: Double? = {
            guard let mean7Day, let baseline, baseline > 0 else { return nil }
            return ((mean7Day - baseline) / baseline) * 100.0
        }()

        let debt: Double? = sleepTotal.map { total in
            total - (sleepTargetHours * 7.0)
        }

        return RecoveryContext(
            hrvMean7Day: mean7Day,
            hrvBaseline28Day: baseline,
            hrvDeltaPercent: deltaPercent,
            sleep7DayTotalHours: sleepTotal,
            sleepDailyTargetHours: sleepTargetHours,
            sleepDebtHours: debt,
            strengthLoad7DayKJ: strengthSummary?.kj,
            strengthLoad7DayMinutes: strengthSummary?.minutes,
            appleWatchVitalsScore: nil
        )
    }

    // MARK: - HRV

    private func meanHRV(overDays days: Int, now: Date) async throws -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return nil
        }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrvType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let ms = result?.averageQuantity()?.doubleValue(for: HKUnit.secondUnit(with: .milli))
                continuation.resume(returning: ms)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Sleep

    private func totalSleepHours(overDays days: Int, now: Date) async throws -> Double? {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                // Filter to actual asleep states (Core/Deep/REM). Apple
                // recommends this over `.asleepUnspecified` for
                // duration-sensitive computations like sleep debt.
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let totalSeconds = categorySamples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { running, sample in
                        running + sample.endDate.timeIntervalSince(sample.startDate)
                    }
                if totalSeconds == 0 {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: totalSeconds / 3600.0)
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Strength load

    private struct StrengthLoadSummary {
        let kj: Double
        let minutes: Double
    }

    private func strengthLoad(overDays days: Int, now: Date) async throws -> StrengthLoadSummary? {
        let workoutType = HKObjectType.workoutType()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let activityPredicate = HKQuery.predicateForWorkouts(with: strengthActivityType)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, activityPredicate])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                // Modern API: HKWorkout.statistics(for:) — works on
                // iOS 16+ and replaces the deprecated
                // `totalEnergyBurned` accessor. Sum across workouts.
                let energyType = HKQuantityType(.activeEnergyBurned)
                let totalKcal: Double = workouts.reduce(0.0) { acc, workout in
                    let kcal = workout.statistics(for: energyType)?
                        .sumQuantity()?
                        .doubleValue(for: .kilocalorie()) ?? 0
                    return acc + kcal
                }
                let totalMinutes = workouts.reduce(0.0) { acc, workout in
                    acc + (workout.duration / 60.0)
                }
                // 1 kcal = 4.184 kJ (Apple Health convention).
                let totalKJ = totalKcal * 4.184
                continuation.resume(returning: StrengthLoadSummary(kj: totalKJ, minutes: totalMinutes))
            }
            healthStore.execute(query)
        }
    }
}

#endif
