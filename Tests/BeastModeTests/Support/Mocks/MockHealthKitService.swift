// MockHealthKitService.swift
// BeastModeTests
// Controllable mock for HealthKit service testing

import Foundation
@testable import BeastMode

/// Controllable mock for HealthKit service testing
actor MockHealthKitService: HealthKitServiceProtocol {

    // MARK: - Configuration

    var isAuthorized = true
    var bodyWeightHistory: [BodyWeightEntry] = []
    var latestBodyWeight: BodyWeightEntry?
    var shouldThrowError: Error?

    // MARK: - Call Tracking

    private(set) var authorizationRequestCount = 0
    private(set) var bodyWeightFetchCount = 0
    private(set) var latestWeightFetchCount = 0
    private(set) var observerSetupCount = 0

    // MARK: - Protocol Implementation

    func requestAuthorization() async throws {
        authorizationRequestCount += 1

        if let error = shouldThrowError {
            throw error
        }

        if !isAuthorized {
            throw HealthKitError.notAuthorized
        }
    }

    func fetchBodyWeightHistory(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [BodyWeightEntry] {
        bodyWeightFetchCount += 1

        if let error = shouldThrowError {
            throw error
        }

        return bodyWeightHistory.filter { entry in
            entry.date >= startDate && entry.date <= endDate
        }
    }

    func fetchLatestBodyWeight() async throws -> BodyWeightEntry? {
        latestWeightFetchCount += 1

        if let error = shouldThrowError {
            throw error
        }

        return latestBodyWeight ?? bodyWeightHistory.max(by: { $0.date < $1.date })
    }

    func observeBodyWeightChanges(handler: @escaping (BodyWeightEntry) -> Void) async throws {
        observerSetupCount += 1

        if let error = shouldThrowError {
            throw error
        }

        // In tests, we can manually trigger the handler
    }

    // MARK: - Test Helpers

    func reset() {
        isAuthorized = true
        bodyWeightHistory = []
        latestBodyWeight = nil
        shouldThrowError = nil
        authorizationRequestCount = 0
        bodyWeightFetchCount = 0
        latestWeightFetchCount = 0
        observerSetupCount = 0
    }

    func setAuthorized(_ authorized: Bool) {
        isAuthorized = authorized
    }

    func setError(_ error: Error) {
        shouldThrowError = error
    }

    /// Sets up a weight trend over time
    func setBodyWeightTrend(
        startWeight: Double,
        endWeight: Double,
        days: Int
    ) {
        let calendar = Calendar.current
        bodyWeightHistory = (0..<days).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: .now)!
            let progress = Double(days - dayOffset) / Double(days)
            let weight = startWeight + (endWeight - startWeight) * progress
            return BodyWeightEntry(date: date, weight: weight, source: "MockScale")
        }.reversed()

        latestBodyWeight = bodyWeightHistory.last
    }

    /// Sets a stable weight
    func setStableWeight(_ weight: Double, days: Int = 30) {
        let calendar = Calendar.current
        bodyWeightHistory = (0..<days).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: .now)!
            // Add small variance for realism
            let variance = Double.random(in: -0.5...0.5)
            return BodyWeightEntry(date: date, weight: weight + variance, source: "MockScale")
        }.reversed()

        latestBodyWeight = BodyWeightEntry(date: .now, weight: weight, source: "MockScale")
    }

    /// Sets up weight loss scenario
    func setWeightLossScenario() {
        setBodyWeightTrend(startWeight: 200, endWeight: 185, days: 90)
    }

    /// Sets up weight gain scenario
    func setWeightGainScenario() {
        setBodyWeightTrend(startWeight: 170, endWeight: 180, days: 60)
    }

    /// Sets up plateau scenario
    func setPlateauScenario() {
        setStableWeight(175, days: 45)
    }
}

// MARK: - Mock HealthKit Errors

enum HealthKitError: LocalizedError {
    case notAuthorized
    case notAvailable
    case dataNotFound
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "HealthKit access not authorized"
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .dataNotFound:
            return "No data found for the requested type"
        case .writeFailed:
            return "Failed to write data to HealthKit"
        }
    }
}

// MARK: - Test Scenarios

extension MockHealthKitService {

    /// Pre-built scenarios for testing
    enum Scenarios {

        /// User who is losing weight steadily
        static func losingWeight() -> MockHealthKitService {
            let service = MockHealthKitService()
            Task {
                await service.setWeightLossScenario()
            }
            return service
        }

        /// User who is gaining weight (bulking)
        static func bulking() -> MockHealthKitService {
            let service = MockHealthKitService()
            Task {
                await service.setWeightGainScenario()
            }
            return service
        }

        /// User whose weight is stable
        static func maintaining() -> MockHealthKitService {
            let service = MockHealthKitService()
            Task {
                await service.setPlateauScenario()
            }
            return service
        }

        /// User who denied HealthKit access
        static func denied() -> MockHealthKitService {
            let service = MockHealthKitService()
            Task {
                await service.setAuthorized(false)
            }
            return service
        }

        /// User with no weight data
        static func noData() -> MockHealthKitService {
            MockHealthKitService()
        }
    }
}
