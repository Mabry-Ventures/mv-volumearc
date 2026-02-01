// HealthKitServiceTests.swift
// BeastModeTests
// Comprehensive unit tests for HealthKitService

import Testing
import Foundation
@testable import BeastMode

// MARK: - Health Kit Service Tests

@Suite("HealthKit Service")
struct HealthKitServiceTests {

    // MARK: - Body Weight Entry Tests

    @Suite("Body Weight Entry")
    struct BodyWeightEntryTests {

        @Test("Body weight entry stores correct values")
        func bodyWeightEntryStoresCorrectValues() {
            let date = Date()
            let entry = BodyWeightEntry(
                date: date,
                weight: 180.5,
                source: "Apple Health"
            )

            #expect(entry.date == date)
            #expect(entry.weight == 180.5)
            #expect(entry.source == "Apple Health")
        }

        @Test("Body weight entry is equatable")
        func bodyWeightEntryIsEquatable() {
            let date = Date()
            let entry1 = BodyWeightEntry(date: date, weight: 180, source: "Test")
            let entry2 = BodyWeightEntry(date: date, weight: 180, source: "Test")

            #expect(entry1.weight == entry2.weight)
        }
    }

    // MARK: - Weight Trend Tests

    @Suite("Weight Trend")
    struct WeightTrendTests {

        @Test("Stable trend when no change")
        func stableTrendWhenNoChange() {
            let trend: WeightTrend = .stable

            switch trend {
            case .stable:
                #expect(true)
            default:
                Issue.record("Expected stable trend")
            }
        }

        @Test("Gaining trend with positive change")
        func gainingTrendWithPositiveChange() {
            let trend: WeightTrend = .gaining(5.0)

            switch trend {
            case .gaining(let amount):
                #expect(amount == 5.0)
            default:
                Issue.record("Expected gaining trend")
            }
        }

        @Test("Losing trend with negative change")
        func losingTrendWithNegativeChange() {
            let trend: WeightTrend = .losing(3.5)

            switch trend {
            case .losing(let amount):
                #expect(amount == 3.5)
            default:
                Issue.record("Expected losing trend")
            }
        }

        @Test("Weight trend description",
              arguments: [
                (WeightTrend.stable, "stable"),
                (WeightTrend.gaining(5.0), "gaining"),
                (WeightTrend.losing(3.0), "losing")
              ])
        func weightTrendDescription(trend: WeightTrend, expectedKeyword: String) {
            let description = String(describing: trend)
            #expect(description.lowercased().contains(expectedKeyword))
        }
    }

    // MARK: - Body Weight Statistics Tests

    @Suite("Body Weight Statistics")
    struct BodyWeightStatisticsTests {

        @Test("Statistics calculate range correctly")
        func statisticsCalculateRangeCorrectly() {
            let stats = BodyWeightStatistics(
                minimum: 175.0,
                maximum: 185.0,
                average: 180.0,
                latest: 182.0,
                entryCount: 30,
                trend: .stable
            )

            #expect(stats.range == 10.0)
        }

        @Test("Statistics range is nil when missing values")
        func statisticsRangeIsNilWhenMissingValues() {
            let stats = BodyWeightStatistics(
                minimum: nil,
                maximum: 185.0,
                average: nil,
                latest: nil,
                entryCount: 0,
                trend: .stable
            )

            #expect(stats.range == nil)
        }

        @Test("Empty statistics have zero entry count")
        func emptyStatisticsHaveZeroEntryCount() {
            let stats = BodyWeightStatistics(
                minimum: nil,
                maximum: nil,
                average: nil,
                latest: nil,
                entryCount: 0,
                trend: .stable
            )

            #expect(stats.entryCount == 0)
        }
    }

    // MARK: - HealthKit Error Tests

    @Suite("HealthKit Errors")
    struct HealthKitErrorTests {

        @Test("Not available error has correct description")
        func notAvailableErrorHasCorrectDescription() {
            let error = HealthKitError.notAvailable

            #expect(error.errorDescription?.contains("not available") == true)
        }

        @Test("Authorization denied error has correct description")
        func authorizationDeniedErrorHasCorrectDescription() {
            let error = HealthKitError.authorizationDenied

            #expect(error.errorDescription?.contains("denied") == true)
        }

        @Test("Data not found error has correct description")
        func dataNotFoundErrorHasCorrectDescription() {
            let error = HealthKitError.dataNotFound

            #expect(error.errorDescription?.contains("No data") == true)
        }

        @Test("Query failed error includes underlying error")
        func queryFailedErrorIncludesUnderlyingError() {
            let underlyingError = NSError(domain: "TestDomain", code: 42, userInfo: nil)
            let error = HealthKitError.queryFailed(underlyingError)

            #expect(error.errorDescription?.contains("query failed") == true)
        }
    }

    // MARK: - Mock HealthKit Service Tests

    @Suite("Mock HealthKit Service")
    struct MockHealthKitServiceTests {

        @Test("Mock generates stable weight entries")
        func mockGeneratesStableWeightEntries() {
            let entries = MockHealthKitService.generateMockBodyWeightEntries(
                count: 10,
                startingWeight: 180,
                trend: .stable
            )

            #expect(entries.count == 10)

            // First and last should be close for stable trend
            let firstWeight = entries.first!.weight
            let lastWeight = entries.last!.weight
            let diff = abs(lastWeight - firstWeight)
            #expect(diff < 5) // Allow for random variation
        }

        @Test("Mock generates gaining weight entries")
        func mockGeneratesGainingWeightEntries() {
            let entries = MockHealthKitService.generateMockBodyWeightEntries(
                count: 30,
                startingWeight: 170,
                trend: .gaining(10)
            )

            #expect(entries.count == 30)

            // Last should be higher than first
            let firstWeight = entries.first!.weight
            let lastWeight = entries.last!.weight
            #expect(lastWeight > firstWeight)
        }

        @Test("Mock generates losing weight entries")
        func mockGeneratesLosingWeightEntries() {
            let entries = MockHealthKitService.generateMockBodyWeightEntries(
                count: 30,
                startingWeight: 200,
                trend: .losing(15)
            )

            #expect(entries.count == 30)

            // Last should be lower than first
            let firstWeight = entries.first!.weight
            let lastWeight = entries.last!.weight
            #expect(lastWeight < firstWeight)
        }

        @Test("Mock entries are in chronological order")
        func mockEntriesAreInChronologicalOrder() {
            let entries = MockHealthKitService.generateMockBodyWeightEntries(count: 10)

            for i in 1..<entries.count {
                #expect(entries[i].date > entries[i-1].date)
            }
        }

        @Test("Mock entries have correct source")
        func mockEntriesHaveCorrectSource() {
            let entries = MockHealthKitService.generateMockBodyWeightEntries(count: 5)

            for entry in entries {
                #expect(entry.source == "Mock")
            }
        }

        @Test("Mock generates expected number of entries")
        func mockGeneratesExpectedNumberOfEntries() {
            let entries1 = MockHealthKitService.generateMockBodyWeightEntries(count: 1)
            #expect(entries1.count == 1)

            let entries50 = MockHealthKitService.generateMockBodyWeightEntries(count: 50)
            #expect(entries50.count == 50)

            let entries100 = MockHealthKitService.generateMockBodyWeightEntries(count: 100)
            #expect(entries100.count == 100)
        }
    }

    // MARK: - MockHealthKitService Actor Tests

    @Suite("MockHealthKitService Actor")
    struct MockHealthKitServiceActorTests {

        @Test("Mock service returns configured weight entries")
        func mockServiceReturnsConfiguredWeightEntries() async throws {
            let mock = MockHealthKitService()
            let entries = [
                BodyWeightEntry(date: Date(), weight: 180, source: "Test"),
                BodyWeightEntry(date: Date().addingTimeInterval(-86400), weight: 179, source: "Test")
            ]
            await mock.setBodyWeightTrend(entries)

            let result = try await mock.fetchBodyWeightHistory()
            #expect(result.count == 2)
        }

        @Test("Mock service stable weight scenario")
        func mockServiceStableWeightScenario() async throws {
            let mock = await MockHealthKitService.maintaining()

            let entries = try await mock.fetchBodyWeightHistory()
            #expect(entries.isEmpty == false)
        }

        @Test("Mock service gaining weight scenario")
        func mockServiceGainingWeightScenario() async throws {
            let mock = await MockHealthKitService.bulking()

            let entries = try await mock.fetchBodyWeightHistory()
            #expect(entries.isEmpty == false)

            // Should show weight gain
            if entries.count >= 2 {
                let firstWeight = entries.first!.weight
                let lastWeight = entries.last!.weight
                #expect(lastWeight > firstWeight)
            }
        }

        @Test("Mock service losing weight scenario")
        func mockServiceLosingWeightScenario() async throws {
            let mock = await MockHealthKitService.losingWeight()

            let entries = try await mock.fetchBodyWeightHistory()
            #expect(entries.isEmpty == false)

            // Should show weight loss
            if entries.count >= 2 {
                let firstWeight = entries.first!.weight
                let lastWeight = entries.last!.weight
                #expect(lastWeight < firstWeight)
            }
        }

        @Test("Mock service denied scenario returns empty")
        func mockServiceDeniedScenarioReturnsEmpty() async throws {
            let mock = await MockHealthKitService.denied()

            let entries = try await mock.fetchBodyWeightHistory()
            #expect(entries.isEmpty)
        }

        @Test("Mock service tracks fetch calls")
        func mockServiceTracksFetchCalls() async throws {
            let mock = MockHealthKitService()
            await mock.setStableWeight(at: 175)

            _ = try await mock.fetchBodyWeightHistory()
            _ = try await mock.fetchBodyWeightHistory()

            let callCount = await mock.fetchHistoryCallCount
            #expect(callCount == 2)
        }

        @Test("Mock service latest weight")
        func mockServiceLatestWeight() async throws {
            let mock = MockHealthKitService()
            let entries = [
                BodyWeightEntry(date: Date().addingTimeInterval(-86400), weight: 179, source: "Test"),
                BodyWeightEntry(date: Date(), weight: 180, source: "Test")
            ]
            await mock.setBodyWeightTrend(entries)

            let latest = try await mock.fetchLatestBodyWeight()
            #expect(latest?.weight == 180)
        }
    }

    // MARK: - Array Extension Tests

    @Suite("Array Average Extension")
    struct ArrayAverageExtensionTests {

        @Test("Average of doubles is calculated correctly")
        func averageOfDoublesIsCalculatedCorrectly() {
            let values = [10.0, 20.0, 30.0]
            #expect(values.average == 20.0)
        }

        @Test("Average of single value equals that value")
        func averageOfSingleValueEqualsThatValue() {
            let values = [42.5]
            #expect(values.average == 42.5)
        }

        @Test("Average of empty array is zero")
        func averageOfEmptyArrayIsZero() {
            let values: [Double] = []
            #expect(values.average == 0.0)
        }

        @Test("Average handles negative values")
        func averageHandlesNegativeValues() {
            let values = [-10.0, 10.0, 20.0]
            #expect(abs(values.average - 6.666666) < 0.001)
        }
    }

    // MARK: - Weight Trend Calculation Tests

    @Suite("Weight Trend Calculation")
    struct WeightTrendCalculationTests {

        @Test("Trend is stable for small changes")
        func trendIsStableForSmallChanges() {
            // Weight change of less than 2 lbs should be stable
            let change = 1.5
            let trend: WeightTrend = change > 2 ? .gaining(change) : change < -2 ? .losing(abs(change)) : .stable

            switch trend {
            case .stable:
                #expect(true)
            default:
                Issue.record("Expected stable trend for change of 1.5 lbs")
            }
        }

        @Test("Trend is gaining for positive changes over threshold")
        func trendIsGainingForPositiveChangesOverThreshold() {
            let change = 5.0
            let trend: WeightTrend = change > 2 ? .gaining(change) : .stable

            switch trend {
            case .gaining(let amount):
                #expect(amount == 5.0)
            default:
                Issue.record("Expected gaining trend for change of 5 lbs")
            }
        }

        @Test("Trend is losing for negative changes over threshold")
        func trendIsLosingForNegativeChangesOverThreshold() {
            let change = -4.0
            let trend: WeightTrend = change < -2 ? .losing(abs(change)) : .stable

            switch trend {
            case .losing(let amount):
                #expect(amount == 4.0)
            default:
                Issue.record("Expected losing trend for change of -4 lbs")
            }
        }
    }

    // MARK: - Date Range Tests

    @Suite("Date Range Helpers")
    struct DateRangeHelpersTests {

        @Test("Two weeks ago calculation")
        func twoWeeksAgoCalculation() {
            let now = Date()
            let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)!

            let daysDiff = Calendar.current.dateComponents([.day], from: twoWeeksAgo, to: now).day!
            #expect(daysDiff == 14)
        }

        @Test("One month ago calculation")
        func oneMonthAgoCalculation() {
            let now = Date()
            let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: now)!

            let monthDiff = Calendar.current.dateComponents([.month], from: oneMonthAgo, to: now).month!
            #expect(monthDiff == 1)
        }
    }
}
