// HealthKitService.swift
// BeastMode
// HealthKit integration for body weight and workout data

import Foundation
import HealthKit

/// Service for reading health data from HealthKit
actor HealthKitService {
    private let healthStore = HKHealthStore()

    // MARK: - Types

    private static let bodyWeightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private static let workoutType = HKWorkoutType.workoutType()

    private var readTypes: Set<HKSampleType> {
        [Self.bodyWeightType, Self.workoutType]
    }

    // MARK: - Authorization

    /// Check if HealthKit is available on this device
    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Request authorization to read health data
    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Check authorization status for body weight
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        healthStore.authorizationStatus(for: type)
    }

    var isBodyWeightAuthorized: Bool {
        authorizationStatus(for: Self.bodyWeightType) == .sharingAuthorized
    }

    // MARK: - Body Weight

    /// Fetch body weight history for the specified period
    func fetchBodyWeightHistory(
        from startDate: Date,
        to endDate: Date = .now
    ) async throws -> [BodyWeightEntry] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: Self.bodyWeightType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let entries = (samples as? [HKQuantitySample])?.map { sample in
                    BodyWeightEntry(
                        date: sample.startDate,
                        weight: sample.quantity.doubleValue(for: .pound()),
                        source: sample.sourceRevision.source.name
                    )
                } ?? []

                continuation.resume(returning: entries)
            }

            healthStore.execute(query)
        }
    }

    /// Get the most recent body weight
    func fetchLatestBodyWeight() async throws -> BodyWeightEntry? {
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: Self.bodyWeightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    let entry = BodyWeightEntry(
                        date: sample.startDate,
                        weight: sample.quantity.doubleValue(for: .pound()),
                        source: sample.sourceRevision.source.name
                    )
                    continuation.resume(returning: entry)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }

    /// Get average body weight for a period
    func fetchAverageBodyWeight(
        from startDate: Date,
        to endDate: Date = .now
    ) async throws -> Double? {
        let entries = try await fetchBodyWeightHistory(from: startDate, to: endDate)
        guard !entries.isEmpty else { return nil }
        return entries.map(\.weight).average
    }

    /// Calculate body weight trend
    func calculateBodyWeightTrend(
        from startDate: Date,
        to endDate: Date = .now
    ) async throws -> WeightTrend {
        let entries = try await fetchBodyWeightHistory(from: startDate, to: endDate)
        guard entries.count >= 2 else { return .stable }

        let firstThird = Array(entries.prefix(entries.count / 3))
        let lastThird = Array(entries.suffix(entries.count / 3))

        let firstAvg = firstThird.map(\.weight).average
        let lastAvg = lastThird.map(\.weight).average
        let diff = lastAvg - firstAvg

        if diff > 2 {
            return .gaining(diff)
        } else if diff < -2 {
            return .losing(abs(diff))
        }
        return .stable
    }

    /// Subscribe to body weight changes
    func observeBodyWeightChanges(
        handler: @escaping @Sendable (BodyWeightEntry) -> Void
    ) -> HKObserverQuery {
        let query = HKObserverQuery(
            sampleType: Self.bodyWeightType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }

            Task {
                if let latest = try? await self?.fetchLatestBodyWeight() {
                    await MainActor.run {
                        handler(latest)
                    }
                }
                completionHandler()
            }
        }

        healthStore.execute(query)
        return query
    }

    /// Enable background delivery for body weight updates
    func enableBackgroundDelivery() async throws {
        try await healthStore.enableBackgroundDelivery(
            for: Self.bodyWeightType,
            frequency: .immediate
        )
    }

    /// Disable background delivery
    func disableBackgroundDelivery() async throws {
        try await healthStore.disableBackgroundDelivery(for: Self.bodyWeightType)
    }

    // MARK: - Statistics

    /// Get body weight statistics for a period
    func fetchBodyWeightStatistics(
        from startDate: Date,
        to endDate: Date = .now
    ) async throws -> BodyWeightStatistics {
        let entries = try await fetchBodyWeightHistory(from: startDate, to: endDate)

        guard !entries.isEmpty else {
            return BodyWeightStatistics(
                minimum: nil,
                maximum: nil,
                average: nil,
                latest: nil,
                entryCount: 0,
                trend: .stable
            )
        }

        let weights = entries.map(\.weight)
        let trend = try await calculateBodyWeightTrend(from: startDate, to: endDate)

        return BodyWeightStatistics(
            minimum: weights.min(),
            maximum: weights.max(),
            average: weights.average,
            latest: entries.last?.weight,
            entryCount: entries.count,
            trend: trend
        )
    }
}

// MARK: - Supporting Types

struct BodyWeightStatistics {
    let minimum: Double?
    let maximum: Double?
    let average: Double?
    let latest: Double?
    let entryCount: Int
    let trend: WeightTrend

    var range: Double? {
        guard let min = minimum, let max = maximum else { return nil }
        return max - min
    }
}

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case authorizationDenied
    case dataNotFound
    case queryFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .authorizationDenied:
            return "HealthKit authorization was denied"
        case .dataNotFound:
            return "No data found in HealthKit"
        case .queryFailed(let error):
            return "HealthKit query failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Mock for Previews/Testing

#if DEBUG
/// Mock HealthKit service for previews and testing
class MockHealthKitService {
    static func generateMockBodyWeightEntries(
        count: Int = 30,
        startingWeight: Double = 180,
        trend: WeightTrend = .stable
    ) -> [BodyWeightEntry] {
        var entries: [BodyWeightEntry] = []
        var currentWeight = startingWeight
        let calendar = Calendar.current

        for i in 0..<count {
            let date = calendar.date(byAdding: .day, value: -count + i, to: .now)!

            // Add some random variation
            let variation = Double.random(in: -0.5...0.5)

            // Apply trend
            switch trend {
            case .gaining(let amount):
                currentWeight += amount / Double(count)
            case .losing(let amount):
                currentWeight -= amount / Double(count)
            case .stable:
                break
            }

            entries.append(BodyWeightEntry(
                date: date,
                weight: currentWeight + variation,
                source: "Mock"
            ))
        }

        return entries
    }
}
#endif
