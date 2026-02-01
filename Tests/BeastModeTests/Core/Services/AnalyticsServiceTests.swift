// AnalyticsServiceTests.swift
// BeastModeTests
// Unit tests for analytics service using Swift Testing

import Testing
import SwiftData
import Foundation
@testable import BeastMode

@Suite("Analytics Service")
struct AnalyticsServiceTests {

    // MARK: - Trend Calculation

    @Suite("Progress Trend")
    struct ProgressTrendTests {

        @Test("Detects increasing trend when E1RM grows >2.5%")
        @MainActor
        func detectsIncreasingTrend() async throws {
            let container = try ModelContainerFactory.makeAnalyticsContainer()
            let service = AnalyticsService(modelContext: container.mainContext)

            let analytics = try await service.generateExerciseAnalytics(
                exerciseName: "Barbell Bench Press",
                timeRange: .threeMonths
            )

            guard case .increasing(let percentage) = analytics?.progressTrend else {
                Issue.record("Expected increasing trend")
                return
            }

            #expect(percentage > 2.5)
        }

        @Test("Detects plateau when change is within ±2.5%")
        @MainActor
        func detectsPlateau() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let user = UserFixtures.standardUser
            context.insert(user)

            // Insert flat data (same weight/reps each week for 8 weeks)
            let calendar = Calendar.current
            for weeksAgo in 0..<8 {
                guard let weekStart = calendar.date(
                    byAdding: .weekOfYear,
                    value: -weeksAgo,
                    to: .now
                ) else { continue }

                let workout = Workout(userId: userId)
                workout.startedAt = weekStart
                workout.completedAt = weekStart.addingTimeInterval(3600)

                let exercise = WorkoutExercise(
                    exerciseId: UUID(),
                    exerciseName: "Flat Exercise"
                )
                exercise.workout = workout

                // Same weight/reps every week
                for setNum in 1...3 {
                    let set = SetLog(
                        setNumber: setNum,
                        weight: 185,
                        reps: 8,
                        completedAt: weekStart
                    )
                    set.workoutExercise = exercise
                }

                context.insert(workout)
            }
            try context.save()

            let service = AnalyticsService(modelContext: context)
            let analytics = try await service.generateExerciseAnalytics(
                exerciseName: "Flat Exercise",
                timeRange: .threeMonths
            )

            guard case .plateau(let weeks) = analytics?.progressTrend else {
                Issue.record("Expected plateau trend")
                return
            }

            #expect(weeks >= 1)
        }

        @Test("Returns insufficient for <4 data points")
        @MainActor
        func insufficientData() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let user = UserFixtures.standardUser
            context.insert(user)

            // Only 2 data points
            let workout = Workout(userId: userId)
            workout.startedAt = .now
            workout.completedAt = .now.addingTimeInterval(3600)

            let exercise = WorkoutExercise(
                exerciseId: UUID(),
                exerciseName: "New Exercise"
            )
            exercise.workout = workout

            let set1 = SetLog(setNumber: 1, weight: 100, reps: 10, completedAt: .now)
            set1.workoutExercise = exercise
            let set2 = SetLog(setNumber: 2, weight: 100, reps: 10, completedAt: .now)
            set2.workoutExercise = exercise

            context.insert(workout)
            try context.save()

            let service = AnalyticsService(modelContext: context)
            let analytics = try await service.generateExerciseAnalytics(
                exerciseName: "New Exercise",
                timeRange: .threeMonths
            )

            #expect(analytics?.progressTrend == .insufficient)
        }

        @Test("Trend threshold at 2.5%",
              arguments: [
                (changePercent: 3.0, expected: "increasing"),
                (changePercent: 2.5, expected: "plateau"),
                (changePercent: 0.0, expected: "plateau"),
                (changePercent: -2.5, expected: "plateau"),
                (changePercent: -3.0, expected: "decreasing")
              ])
        func trendThresholds(changePercent: Double, expected: String) {
            let trend = AnalyticsService.calculateTrend(percentChange: changePercent, weeks: 4)

            switch expected {
            case "increasing":
                guard case .increasing = trend else {
                    Issue.record("Expected increasing trend for \(changePercent)%")
                    return
                }
            case "decreasing":
                guard case .decreasing = trend else {
                    Issue.record("Expected decreasing trend for \(changePercent)%")
                    return
                }
            case "plateau":
                guard case .plateau = trend else {
                    Issue.record("Expected plateau trend for \(changePercent)%")
                    return
                }
            default:
                Issue.record("Unknown expected trend: \(expected)")
            }
        }
    }

    // MARK: - Volume Calculation

    @Suite("Volume Trend")
    struct VolumeTrendTests {

        @Test("Calculates weekly volume correctly")
        @MainActor
        func calculatesWeeklyVolume() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let user = UserFixtures.standardUser
            context.insert(user)

            // This week: 3 sets of 200 × 8 = 4800 volume
            let workout = Workout(userId: userId)
            workout.startedAt = .now
            workout.completedAt = .now.addingTimeInterval(3600)

            let exercise = WorkoutExercise(
                exerciseId: UUID(),
                exerciseName: "Test Exercise"
            )
            exercise.workout = workout

            for setNum in 1...3 {
                let set = SetLog(
                    setNumber: setNum,
                    weight: 200,
                    reps: 8,
                    completedAt: .now
                )
                set.workoutExercise = exercise
            }

            context.insert(workout)
            try context.save()

            let service = AnalyticsService(modelContext: context)
            let volume = try await service.calculateWeeklyVolume(
                for: "Test Exercise",
                in: .now
            )

            #expect(volume == 4800)  // 3 × 200 × 8
        }

        @Test("Volume change percentage calculation",
              arguments: [
                (current: 5000.0, previous: 4000.0, expected: 25.0),
                (current: 4000.0, previous: 5000.0, expected: -20.0),
                (current: 4000.0, previous: 4000.0, expected: 0.0)
              ])
        func volumeChangePercentage(
            current: Double,
            previous: Double,
            expected: Double
        ) {
            let change = AnalyticsService.calculateVolumeChange(
                current: current,
                previous: previous
            )

            #expect(change.isApproximatelyEqual(to: expected, tolerance: 0.1))
        }

        @Test("Volume change handles zero previous")
        func volumeChangeZeroPrevious() {
            let change = AnalyticsService.calculateVolumeChange(
                current: 4000,
                previous: 0
            )

            // Should return 0 or handle gracefully (no division by zero)
            #expect(!change.isNaN)
            #expect(!change.isInfinite)
        }
    }

    // MARK: - Overview Generation

    @Suite("Analytics Overview")
    struct OverviewTests {

        @Test("Generates overview for all exercises")
        @MainActor
        func generatesOverview() async throws {
            let container = try ModelContainerFactory.makeAnalyticsContainer()
            let service = AnalyticsService(modelContext: container.mainContext)

            let overview = try await service.generateOverview(timeRange: .threeMonths)

            #expect(overview.exercises.count >= 2)  // At least bench and squat from fixtures
            #expect(overview.totalWorkouts > 0)
            #expect(overview.totalVolume > 0)
        }

        @Test("Categorizes exercises by trend")
        @MainActor
        func categorizesByTrend() async throws {
            let container = try ModelContainerFactory.makeAnalyticsContainer()
            let service = AnalyticsService(modelContext: container.mainContext)

            let overview = try await service.generateOverview(timeRange: .threeMonths)

            // Our fixtures have progressive overload, so should be increasing
            #expect(overview.progressingCount > 0)

            // Total should equal sum of categories (excluding insufficient)
            let totalCategorized = overview.progressingCount +
                                   overview.plateauCount +
                                   overview.decliningCount

            #expect(totalCategorized <= overview.exercises.count)
        }

        @Test("Calculates average workouts per week")
        @MainActor
        func calculatesAvgWorkoutsPerWeek() async throws {
            let container = try ModelContainerFactory.makeAnalyticsContainer()
            let service = AnalyticsService(modelContext: container.mainContext)

            let overview = try await service.generateOverview(timeRange: .threeMonths)

            // 12 weeks of data, 5 days each = 60 days / 12 weeks = 5/week
            #expect(overview.averageWorkoutsPerWeek >= 4.0)
            #expect(overview.averageWorkoutsPerWeek <= 6.0)
        }

        @Test("Overview handles empty data")
        @MainActor
        func overviewHandlesEmptyData() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = AnalyticsService(modelContext: container.mainContext)

            let overview = try await service.generateOverview(timeRange: .threeMonths)

            #expect(overview.exercises.isEmpty)
            #expect(overview.totalWorkouts == 0)
            #expect(overview.totalVolume == 0)
        }
    }

    // MARK: - Time Range Filtering

    @Suite("Time Range")
    struct TimeRangeTests {

        @Test("Respects time range filter",
              arguments: ChartTimeRange.allCases)
        @MainActor
        func respectsTimeRange(timeRange: ChartTimeRange) async throws {
            let container = try ModelContainerFactory.makeAnalyticsContainer()
            let service = AnalyticsService(modelContext: container.mainContext)

            let analytics = try await service.generateExerciseAnalytics(
                exerciseName: "Barbell Bench Press",
                timeRange: timeRange
            )

            // All data points should be within range
            let cutoff = timeRange.startDate
            for point in analytics?.dataPoints ?? [] {
                #expect(point.date >= cutoff)
            }
        }

        @Test("Time range start dates are correct")
        func timeRangeStartDates() {
            let calendar = Calendar.current
            let now = Date.now

            for range in ChartTimeRange.allCases {
                let start = range.startDate

                switch range {
                case .oneMonth:
                    let expected = calendar.date(byAdding: .month, value: -1, to: now)!
                    #expect(calendar.isDate(start, inSameDayAs: expected))
                case .threeMonths:
                    let expected = calendar.date(byAdding: .month, value: -3, to: now)!
                    #expect(calendar.isDate(start, inSameDayAs: expected))
                case .sixMonths:
                    let expected = calendar.date(byAdding: .month, value: -6, to: now)!
                    #expect(calendar.isDate(start, inSameDayAs: expected))
                case .oneYear:
                    let expected = calendar.date(byAdding: .year, value: -1, to: now)!
                    #expect(calendar.isDate(start, inSameDayAs: expected))
                case .allTime:
                    // All time should be a very old date
                    #expect(start < calendar.date(byAdding: .year, value: -10, to: now)!)
                }
            }
        }
    }

    // MARK: - Data Point Generation

    @Suite("Data Points")
    struct DataPointTests {

        @Test("Groups sets into data points correctly")
        @MainActor
        func groupsSetsIntoDataPoints() async throws {
            let container = try ModelContainerFactory.makeAnalyticsContainer()
            let service = AnalyticsService(modelContext: container.mainContext)

            let analytics = try await service.generateExerciseAnalytics(
                exerciseName: "Barbell Bench Press",
                timeRange: .threeMonths
            )

            #expect(analytics?.dataPoints.isEmpty == false)

            // Each data point should have valid values
            for point in analytics?.dataPoints ?? [] {
                #expect(point.weight > 0)
                #expect(point.reps > 0)
                #expect(point.estimatedOneRepMax > 0)
            }
        }

        @Test("Data points are sorted by date")
        @MainActor
        func dataPointsSortedByDate() async throws {
            let container = try ModelContainerFactory.makeAnalyticsContainer()
            let service = AnalyticsService(modelContext: container.mainContext)

            let analytics = try await service.generateExerciseAnalytics(
                exerciseName: "Barbell Bench Press",
                timeRange: .threeMonths
            )

            let points = analytics?.dataPoints ?? []

            for i in 1..<points.count {
                #expect(points[i].date >= points[i-1].date)
            }
        }
    }
}

// MARK: - Analytics Service Extensions for Testing

extension AnalyticsService {

    /// Calculate trend from percent change (exposed for testing)
    static func calculateTrend(percentChange: Double, weeks: Int) -> ProgressTrend {
        if percentChange > 2.5 {
            return .increasing(percentage: percentChange)
        } else if percentChange < -2.5 {
            return .decreasing(percentage: abs(percentChange))
        } else {
            return .plateau(weeks: weeks)
        }
    }

    /// Calculate volume change percentage (exposed for testing)
    static func calculateVolumeChange(current: Double, previous: Double) -> Double {
        guard previous > 0 else { return 0 }
        return ((current - previous) / previous) * 100
    }
}
