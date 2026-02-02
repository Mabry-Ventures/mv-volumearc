// AnalyticsChartSnapshotTests.swift
// BeastModeTests
// Snapshot tests for analytics chart components

import Testing
import SwiftUI
import Charts
@testable import BeastMode

@Suite("Analytics Chart Snapshots")
struct AnalyticsChartSnapshotTests {

    // MARK: - Body Weight Chart Tests

    @Suite("Body Weight Chart")
    struct BodyWeightChartTests {

        @Test("Body weight chart - gaining trend light mode")
        @MainActor
        func bodyWeightChartGainingLight() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                BodyWeightChartSnapshotView(
                    entries: SnapshotAnalyticsTestData.gainingWeightEntries,
                    timeRange: .oneMonth,
                    trend: .gaining(5.2)
                )
            }

            assertSnapshot(matching: view, named: "body_weight_chart_gaining_light")
        }

        @Test("Body weight chart - gaining trend dark mode")
        @MainActor
        func bodyWeightChartGainingDark() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .dark
            ) {
                BodyWeightChartSnapshotView(
                    entries: SnapshotAnalyticsTestData.gainingWeightEntries,
                    timeRange: .oneMonth,
                    trend: .gaining(5.2)
                )
            }

            assertSnapshot(matching: view, named: "body_weight_chart_gaining_dark")
        }

        @Test("Body weight chart - losing trend light mode")
        @MainActor
        func bodyWeightChartLosingLight() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                BodyWeightChartSnapshotView(
                    entries: SnapshotAnalyticsTestData.losingWeightEntries,
                    timeRange: .oneMonth,
                    trend: .losing(8.5)
                )
            }

            assertSnapshot(matching: view, named: "body_weight_chart_losing_light")
        }

        @Test("Body weight chart - stable trend")
        @MainActor
        func bodyWeightChartStable() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                BodyWeightChartSnapshotView(
                    entries: SnapshotAnalyticsTestData.stableWeightEntries,
                    timeRange: .threeMonths,
                    trend: .stable
                )
            }

            assertSnapshot(matching: view, named: "body_weight_chart_stable")
        }

        @Test("Body weight chart - empty state")
        @MainActor
        func bodyWeightChartEmpty() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                BodyWeightChartSnapshotView(
                    entries: [],
                    timeRange: .oneMonth,
                    trend: .stable
                )
            }

            assertSnapshot(matching: view, named: "body_weight_chart_empty")
        }

        @Test("Body weight chart - iPhone SE")
        @MainActor
        func bodyWeightChartiPhoneSE() {
            let view = SnapshotWrapper(
                device: .iPhoneSE,
                colorScheme: .light
            ) {
                BodyWeightChartSnapshotView(
                    entries: SnapshotAnalyticsTestData.gainingWeightEntries,
                    timeRange: .oneMonth,
                    trend: .gaining(5.2)
                )
            }

            assertSnapshot(matching: view, named: "body_weight_chart_iphone_se")
        }

        @Test("Body weight chart - accessibility text size")
        @MainActor
        func bodyWeightChartAccessibility() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light,
                dynamicTypeSize: .accessibility1
            ) {
                BodyWeightChartSnapshotView(
                    entries: SnapshotAnalyticsTestData.gainingWeightEntries,
                    timeRange: .oneMonth,
                    trend: .gaining(5.2)
                )
            }

            assertSnapshot(matching: view, named: "body_weight_chart_accessibility")
        }
    }

    // MARK: - Mini Sparkline Tests

    @Suite("Mini Sparkline")
    struct MiniSparklineTests {

        @Test("Sparkline - increasing trend")
        @MainActor
        func sparklineIncreasing() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                HStack {
                    MiniSparklineSnapshotView(
                        dataPoints: SnapshotAnalyticsTestData.increasingE1RMData
                    )
                    .frame(width: 80, height: 40)
                }
                .padding()
            }

            assertSnapshot(matching: view, named: "sparkline_increasing")
        }

        @Test("Sparkline - decreasing trend")
        @MainActor
        func sparklineDecreasing() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                HStack {
                    MiniSparklineSnapshotView(
                        dataPoints: SnapshotAnalyticsTestData.decreasingE1RMData
                    )
                    .frame(width: 80, height: 40)
                }
                .padding()
            }

            assertSnapshot(matching: view, named: "sparkline_decreasing")
        }

        @Test("Sparkline - plateau trend")
        @MainActor
        func sparklinePlateau() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                HStack {
                    MiniSparklineSnapshotView(
                        dataPoints: SnapshotAnalyticsTestData.plateauE1RMData
                    )
                    .frame(width: 80, height: 40)
                }
                .padding()
            }

            assertSnapshot(matching: view, named: "sparkline_plateau")
        }

        @Test("Sparkline - volatile data")
        @MainActor
        func sparklineVolatile() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                HStack {
                    MiniSparklineSnapshotView(
                        dataPoints: SnapshotAnalyticsTestData.volatileE1RMData
                    )
                    .frame(width: 80, height: 40)
                }
                .padding()
            }

            assertSnapshot(matching: view, named: "sparkline_volatile")
        }

        @Test("Sparkline - dark mode")
        @MainActor
        func sparklineDarkMode() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .dark
            ) {
                HStack {
                    MiniSparklineSnapshotView(
                        dataPoints: SnapshotAnalyticsTestData.increasingE1RMData
                    )
                    .frame(width: 80, height: 40)
                }
                .padding()
            }

            assertSnapshot(matching: view, named: "sparkline_dark")
        }

        @Test("Sparkline - minimal data points")
        @MainActor
        func sparklineMinimalData() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                HStack {
                    MiniSparklineSnapshotView(
                        dataPoints: SnapshotAnalyticsTestData.minimalE1RMData
                    )
                    .frame(width: 80, height: 40)
                }
                .padding()
            }

            assertSnapshot(matching: view, named: "sparkline_minimal_data")
        }
    }

    // MARK: - Summary Cards Tests

    @Suite("Summary Cards")
    struct SummaryCardsTests {

        @Test("Summary cards - active user light mode")
        @MainActor
        func summaryCardsActiveUserLight() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                SummaryCardsSnapshotView(
                    overview: SnapshotAnalyticsTestData.activeUserOverview
                )
            }

            assertSnapshot(matching: view, named: "summary_cards_active_user_light")
        }

        @Test("Summary cards - active user dark mode")
        @MainActor
        func summaryCardsActiveUserDark() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .dark
            ) {
                SummaryCardsSnapshotView(
                    overview: SnapshotAnalyticsTestData.activeUserOverview
                )
            }

            assertSnapshot(matching: view, named: "summary_cards_active_user_dark")
        }

        @Test("Summary cards - new user")
        @MainActor
        func summaryCardsNewUser() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                SummaryCardsSnapshotView(
                    overview: SnapshotAnalyticsTestData.newUserOverview
                )
            }

            assertSnapshot(matching: view, named: "summary_cards_new_user")
        }

        @Test("Summary cards - high volume user")
        @MainActor
        func summaryCardsHighVolume() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                SummaryCardsSnapshotView(
                    overview: SnapshotAnalyticsTestData.highVolumeOverview
                )
            }

            assertSnapshot(matching: view, named: "summary_cards_high_volume")
        }

        @Test("Summary cards - many plateaus")
        @MainActor
        func summaryCardsManyPlateaus() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                SummaryCardsSnapshotView(
                    overview: SnapshotAnalyticsTestData.plateauOverview
                )
            }

            assertSnapshot(matching: view, named: "summary_cards_many_plateaus")
        }

        @Test("Summary cards - iPhone SE")
        @MainActor
        func summaryCardsiPhoneSE() {
            let view = SnapshotWrapper(
                device: .iPhoneSE,
                colorScheme: .light
            ) {
                SummaryCardsSnapshotView(
                    overview: SnapshotAnalyticsTestData.activeUserOverview
                )
            }

            assertSnapshot(matching: view, named: "summary_cards_iphone_se")
        }

        @Test("Summary cards - accessibility text size")
        @MainActor
        func summaryCardsAccessibility() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light,
                dynamicTypeSize: .accessibility1
            ) {
                SummaryCardsSnapshotView(
                    overview: SnapshotAnalyticsTestData.activeUserOverview
                )
            }

            assertSnapshot(matching: view, named: "summary_cards_accessibility")
        }
    }

    // MARK: - Progress Breakdown Tests

    @Suite("Progress Breakdown")
    struct ProgressBreakdownTests {

        @Test("Progress breakdown - balanced distribution light mode")
        @MainActor
        func progressBreakdownBalancedLight() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ProgressBreakdownSnapshotView(
                    overview: SnapshotAnalyticsTestData.balancedProgressOverview
                )
            }

            assertSnapshot(matching: view, named: "progress_breakdown_balanced_light")
        }

        @Test("Progress breakdown - balanced distribution dark mode")
        @MainActor
        func progressBreakdownBalancedDark() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .dark
            ) {
                ProgressBreakdownSnapshotView(
                    overview: SnapshotAnalyticsTestData.balancedProgressOverview
                )
            }

            assertSnapshot(matching: view, named: "progress_breakdown_balanced_dark")
        }

        @Test("Progress breakdown - mostly progressing")
        @MainActor
        func progressBreakdownMostlyProgressing() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ProgressBreakdownSnapshotView(
                    overview: SnapshotAnalyticsTestData.mostlyProgressingOverview
                )
            }

            assertSnapshot(matching: view, named: "progress_breakdown_mostly_progressing")
        }

        @Test("Progress breakdown - mostly plateau")
        @MainActor
        func progressBreakdownMostlyPlateau() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ProgressBreakdownSnapshotView(
                    overview: SnapshotAnalyticsTestData.mostlyPlateauOverview
                )
            }

            assertSnapshot(matching: view, named: "progress_breakdown_mostly_plateau")
        }

        @Test("Progress breakdown - some declining")
        @MainActor
        func progressBreakdownSomeDeclining() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ProgressBreakdownSnapshotView(
                    overview: SnapshotAnalyticsTestData.someDecliningOverview
                )
            }

            assertSnapshot(matching: view, named: "progress_breakdown_some_declining")
        }

        @Test("Progress breakdown - all progressing")
        @MainActor
        func progressBreakdownAllProgressing() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ProgressBreakdownSnapshotView(
                    overview: SnapshotAnalyticsTestData.allProgressingOverview
                )
            }

            assertSnapshot(matching: view, named: "progress_breakdown_all_progressing")
        }

        @Test("Progress breakdown - insufficient data")
        @MainActor
        func progressBreakdownInsufficientData() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ProgressBreakdownSnapshotView(
                    overview: SnapshotAnalyticsTestData.insufficientDataOverview
                )
            }

            assertSnapshot(matching: view, named: "progress_breakdown_insufficient_data")
        }

        @Test("Progress breakdown - accessibility text size")
        @MainActor
        func progressBreakdownAccessibility() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light,
                dynamicTypeSize: .accessibility1
            ) {
                ProgressBreakdownSnapshotView(
                    overview: SnapshotAnalyticsTestData.balancedProgressOverview
                )
            }

            assertSnapshot(matching: view, named: "progress_breakdown_accessibility")
        }
    }

    // MARK: - Exercise Trend Row Tests

    @Suite("Exercise Trend Row")
    struct ExerciseTrendRowTests {

        @Test("Exercise trend row - increasing light mode")
        @MainActor
        func exerciseTrendRowIncreasingLight() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ExerciseTrendRowSnapshotView(
                    exerciseName: "Barbell Bench Press",
                    estimatedOneRepMax: 225,
                    trend: .increasing(percentage: 8.5),
                    dataPoints: SnapshotAnalyticsTestData.increasingE1RMData
                )
            }

            assertSnapshot(matching: view, named: "exercise_trend_row_increasing_light")
        }

        @Test("Exercise trend row - increasing dark mode")
        @MainActor
        func exerciseTrendRowIncreasingDark() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .dark
            ) {
                ExerciseTrendRowSnapshotView(
                    exerciseName: "Barbell Bench Press",
                    estimatedOneRepMax: 225,
                    trend: .increasing(percentage: 8.5),
                    dataPoints: SnapshotAnalyticsTestData.increasingE1RMData
                )
            }

            assertSnapshot(matching: view, named: "exercise_trend_row_increasing_dark")
        }

        @Test("Exercise trend row - decreasing")
        @MainActor
        func exerciseTrendRowDecreasing() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ExerciseTrendRowSnapshotView(
                    exerciseName: "Overhead Press",
                    estimatedOneRepMax: 135,
                    trend: .decreasing(percentage: 5.2),
                    dataPoints: SnapshotAnalyticsTestData.decreasingE1RMData
                )
            }

            assertSnapshot(matching: view, named: "exercise_trend_row_decreasing")
        }

        @Test("Exercise trend row - plateau")
        @MainActor
        func exerciseTrendRowPlateau() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ExerciseTrendRowSnapshotView(
                    exerciseName: "Barbell Squat",
                    estimatedOneRepMax: 315,
                    trend: .plateau(weeks: 3),
                    dataPoints: SnapshotAnalyticsTestData.plateauE1RMData
                )
            }

            assertSnapshot(matching: view, named: "exercise_trend_row_plateau")
        }

        @Test("Exercise trend row - insufficient data")
        @MainActor
        func exerciseTrendRowInsufficient() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ExerciseTrendRowSnapshotView(
                    exerciseName: "Romanian Deadlift",
                    estimatedOneRepMax: nil,
                    trend: .insufficient,
                    dataPoints: SnapshotAnalyticsTestData.minimalE1RMData
                )
            }

            assertSnapshot(matching: view, named: "exercise_trend_row_insufficient")
        }

        @Test("Exercise trend row - long exercise name")
        @MainActor
        func exerciseTrendRowLongName() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ExerciseTrendRowSnapshotView(
                    exerciseName: "Single Arm Dumbbell Incline Bench Press",
                    estimatedOneRepMax: 95,
                    trend: .increasing(percentage: 12.3),
                    dataPoints: SnapshotAnalyticsTestData.increasingE1RMData
                )
            }

            assertSnapshot(matching: view, named: "exercise_trend_row_long_name")
        }

        @Test("Exercise trend row - iPhone SE")
        @MainActor
        func exerciseTrendRowiPhoneSE() {
            let view = SnapshotWrapper(
                device: .iPhoneSE,
                colorScheme: .light
            ) {
                ExerciseTrendRowSnapshotView(
                    exerciseName: "Barbell Bench Press",
                    estimatedOneRepMax: 225,
                    trend: .increasing(percentage: 8.5),
                    dataPoints: SnapshotAnalyticsTestData.increasingE1RMData
                )
            }

            assertSnapshot(matching: view, named: "exercise_trend_row_iphone_se")
        }

        @Test("Exercise trend row - accessibility text size")
        @MainActor
        func exerciseTrendRowAccessibility() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light,
                dynamicTypeSize: .accessibility1
            ) {
                ExerciseTrendRowSnapshotView(
                    exerciseName: "Barbell Bench Press",
                    estimatedOneRepMax: 225,
                    trend: .increasing(percentage: 8.5),
                    dataPoints: SnapshotAnalyticsTestData.increasingE1RMData
                )
            }

            assertSnapshot(matching: view, named: "exercise_trend_row_accessibility")
        }

        @Test("Exercise trend row - high E1RM value")
        @MainActor
        func exerciseTrendRowHighE1RM() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                ExerciseTrendRowSnapshotView(
                    exerciseName: "Deadlift",
                    estimatedOneRepMax: 585,
                    trend: .increasing(percentage: 3.2),
                    dataPoints: SnapshotAnalyticsTestData.increasingE1RMData
                )
            }

            assertSnapshot(matching: view, named: "exercise_trend_row_high_e1rm")
        }
    }

    // MARK: - Trend Badge Tests

    @Suite("Trend Badge")
    struct TrendBadgeTests {

        @Test("Trend badge - gaining")
        @MainActor
        func trendBadgeGaining() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                HStack(spacing: 20) {
                    TrendBadgeSnapshotView(trend: .gaining(5.5))
                    TrendBadgeSnapshotView(trend: .gaining(12.3))
                }
                .padding()
            }

            assertSnapshot(matching: view, named: "trend_badge_gaining")
        }

        @Test("Trend badge - losing")
        @MainActor
        func trendBadgeLosing() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                HStack(spacing: 20) {
                    TrendBadgeSnapshotView(trend: .losing(3.2))
                    TrendBadgeSnapshotView(trend: .losing(8.7))
                }
                .padding()
            }

            assertSnapshot(matching: view, named: "trend_badge_losing")
        }

        @Test("Trend badge - stable")
        @MainActor
        func trendBadgeStable() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .light
            ) {
                TrendBadgeSnapshotView(trend: .stable)
                    .padding()
            }

            assertSnapshot(matching: view, named: "trend_badge_stable")
        }

        @Test("Trend badge - all variants dark mode")
        @MainActor
        func trendBadgeAllVariantsDark() {
            let view = SnapshotWrapper(
                device: .iPhone15Pro,
                colorScheme: .dark
            ) {
                VStack(spacing: 12) {
                    TrendBadgeSnapshotView(trend: .gaining(5.5))
                    TrendBadgeSnapshotView(trend: .losing(3.2))
                    TrendBadgeSnapshotView(trend: .stable)
                }
                .padding()
            }

            assertSnapshot(matching: view, named: "trend_badge_all_variants_dark")
        }
    }
}

// MARK: - Snapshot Test Data

/// Test data fixtures for analytics snapshot tests
enum SnapshotAnalyticsTestData {

    // MARK: - Body Weight Entries

    static var gainingWeightEntries: [SnapshotBodyWeightEntry] {
        generateBodyWeightEntries(count: 30, startWeight: 175, endWeight: 182)
    }

    static var losingWeightEntries: [SnapshotBodyWeightEntry] {
        generateBodyWeightEntries(count: 30, startWeight: 195, endWeight: 185)
    }

    static var stableWeightEntries: [SnapshotBodyWeightEntry] {
        generateBodyWeightEntries(count: 60, startWeight: 180, endWeight: 181)
    }

    private static func generateBodyWeightEntries(
        count: Int,
        startWeight: Double,
        endWeight: Double
    ) -> [SnapshotBodyWeightEntry] {
        let calendar = Calendar.current
        return (0..<count).map { i in
            let date = calendar.date(byAdding: .day, value: -count + i, to: .now)!
            let progress = Double(i) / Double(max(1, count - 1))
            let weight = startWeight + (endWeight - startWeight) * progress
            let variance = Double.random(in: -0.3...0.3)
            return SnapshotBodyWeightEntry(
                date: date,
                weight: weight + variance,
                source: "Apple Watch"
            )
        }
    }

    // MARK: - E1RM Data Points

    static var increasingE1RMData: [SnapshotDataPoint] {
        generateE1RMDataPoints(count: 12, startE1RM: 200, endE1RM: 225)
    }

    static var decreasingE1RMData: [SnapshotDataPoint] {
        generateE1RMDataPoints(count: 12, startE1RM: 150, endE1RM: 135)
    }

    static var plateauE1RMData: [SnapshotDataPoint] {
        generateE1RMDataPoints(count: 12, startE1RM: 315, endE1RM: 318)
    }

    static var volatileE1RMData: [SnapshotDataPoint] {
        let calendar = Calendar.current
        let values: [Double] = [200, 210, 195, 220, 205, 225, 200, 230, 210, 235]
        return values.enumerated().map { (i, e1rm) in
            SnapshotDataPoint(
                date: calendar.date(byAdding: .day, value: -values.count + i, to: .now)!,
                estimatedOneRepMax: e1rm
            )
        }
    }

    static var minimalE1RMData: [SnapshotDataPoint] {
        generateE1RMDataPoints(count: 2, startE1RM: 135, endE1RM: 140)
    }

    private static func generateE1RMDataPoints(
        count: Int,
        startE1RM: Double,
        endE1RM: Double
    ) -> [SnapshotDataPoint] {
        let calendar = Calendar.current
        return (0..<count).map { i in
            let date = calendar.date(byAdding: .day, value: -count * 3 + i * 3, to: .now)!
            let progress = Double(i) / Double(max(1, count - 1))
            let e1rm = startE1RM + (endE1RM - startE1RM) * progress
            return SnapshotDataPoint(date: date, estimatedOneRepMax: e1rm)
        }
    }

    // MARK: - Analytics Overviews

    static var activeUserOverview: SnapshotAnalyticsOverview {
        SnapshotAnalyticsOverview(
            totalWorkouts: 48,
            totalVolume: 245000,
            progressingCount: 5,
            plateauCount: 2,
            decliningCount: 1,
            insufficientDataCount: 0
        )
    }

    static var newUserOverview: SnapshotAnalyticsOverview {
        SnapshotAnalyticsOverview(
            totalWorkouts: 3,
            totalVolume: 8500,
            progressingCount: 0,
            plateauCount: 0,
            decliningCount: 0,
            insufficientDataCount: 4
        )
    }

    static var highVolumeOverview: SnapshotAnalyticsOverview {
        SnapshotAnalyticsOverview(
            totalWorkouts: 156,
            totalVolume: 1250000,
            progressingCount: 8,
            plateauCount: 3,
            decliningCount: 0,
            insufficientDataCount: 1
        )
    }

    static var plateauOverview: SnapshotAnalyticsOverview {
        SnapshotAnalyticsOverview(
            totalWorkouts: 72,
            totalVolume: 385000,
            progressingCount: 2,
            plateauCount: 6,
            decliningCount: 0,
            insufficientDataCount: 0
        )
    }

    static var balancedProgressOverview: SnapshotAnalyticsOverview {
        SnapshotAnalyticsOverview(
            totalWorkouts: 36,
            totalVolume: 180000,
            progressingCount: 4,
            plateauCount: 3,
            decliningCount: 1,
            insufficientDataCount: 2
        )
    }

    static var mostlyProgressingOverview: SnapshotAnalyticsOverview {
        SnapshotAnalyticsOverview(
            totalWorkouts: 60,
            totalVolume: 320000,
            progressingCount: 7,
            plateauCount: 1,
            decliningCount: 0,
            insufficientDataCount: 0
        )
    }

    static var mostlyPlateauOverview: SnapshotAnalyticsOverview {
        SnapshotAnalyticsOverview(
            totalWorkouts: 84,
            totalVolume: 450000,
            progressingCount: 1,
            plateauCount: 6,
            decliningCount: 1,
            insufficientDataCount: 0
        )
    }

    static var someDecliningOverview: SnapshotAnalyticsOverview {
        SnapshotAnalyticsOverview(
            totalWorkouts: 45,
            totalVolume: 220000,
            progressingCount: 2,
            plateauCount: 2,
            decliningCount: 3,
            insufficientDataCount: 1
        )
    }

    static var allProgressingOverview: SnapshotAnalyticsOverview {
        SnapshotAnalyticsOverview(
            totalWorkouts: 52,
            totalVolume: 275000,
            progressingCount: 6,
            plateauCount: 0,
            decliningCount: 0,
            insufficientDataCount: 0
        )
    }

    static var insufficientDataOverview: SnapshotAnalyticsOverview {
        SnapshotAnalyticsOverview(
            totalWorkouts: 5,
            totalVolume: 15000,
            progressingCount: 0,
            plateauCount: 0,
            decliningCount: 0,
            insufficientDataCount: 6
        )
    }
}

// MARK: - Snapshot Data Types

struct SnapshotBodyWeightEntry: Identifiable {
    var id: Date { date }
    let date: Date
    let weight: Double
    let source: String
}

struct SnapshotDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let estimatedOneRepMax: Double
}

struct SnapshotAnalyticsOverview {
    let totalWorkouts: Int
    let totalVolume: Double
    let progressingCount: Int
    let plateauCount: Int
    let decliningCount: Int
    let insufficientDataCount: Int

    var totalExercises: Int {
        progressingCount + plateauCount + decliningCount + insufficientDataCount
    }
}

/// Weight trend for snapshot testing
enum SnapshotWeightTrend: Equatable {
    case gaining(Double)
    case losing(Double)
    case stable

    var icon: String {
        switch self {
        case .gaining: return "arrow.up.right"
        case .losing: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var text: String {
        switch self {
        case .gaining(let amount): return "+\(String(format: "%.1f", amount)) lbs"
        case .losing(let amount): return "-\(String(format: "%.1f", amount)) lbs"
        case .stable: return "Stable"
        }
    }

    var color: Color {
        switch self {
        case .gaining: return .green
        case .losing: return .orange
        case .stable: return .blue
        }
    }
}

/// Progress trend for snapshot testing
enum SnapshotProgressTrend: Equatable {
    case increasing(percentage: Double)
    case plateau(weeks: Int)
    case decreasing(percentage: Double)
    case insufficient

    var color: Color {
        switch self {
        case .increasing: return .green
        case .plateau: return .orange
        case .decreasing: return .red
        case .insufficient: return .gray
        }
    }

    var icon: String {
        switch self {
        case .increasing: return "arrow.up.right.circle.fill"
        case .plateau: return "arrow.right.circle.fill"
        case .decreasing: return "arrow.down.right.circle.fill"
        case .insufficient: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Stub Views for Snapshot Testing

/// Stub Body Weight Chart View
struct BodyWeightChartSnapshotView: View {
    let entries: [SnapshotBodyWeightEntry]
    let timeRange: ChartTimeRange
    let trend: SnapshotWeightTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Body Weight")
                        .font(.headline)

                    if let latest = entries.last {
                        Text("\(String(format: "%.1f", latest.weight)) lbs")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                }

                Spacer()

                TrendBadgeSnapshotView(trend: trend)
            }

            // Chart or empty state
            if entries.isEmpty {
                emptyStateView
            } else {
                chartView
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "scalemass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No Weight Data")
                .font(.headline)

            Text("Connect to Apple Health to see your body weight trends")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    private var chartView: some View {
        Chart {
            ForEach(entries) { entry in
                AreaMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", entry.weight)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .blue.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", entry.weight)
                )
                .foregroundStyle(Color.blue.gradient)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 200)
    }
}

/// Stub Trend Badge View
struct TrendBadgeSnapshotView: View {
    let trend: SnapshotWeightTrend

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trend.icon)
            Text(trend.text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(trend.color.opacity(0.2), in: Capsule())
        .foregroundStyle(trend.color)
    }
}

/// Stub Mini Sparkline View
struct MiniSparklineSnapshotView: View {
    let dataPoints: [SnapshotDataPoint]

    var body: some View {
        Chart {
            ForEach(dataPoints.suffix(10)) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("E1RM", point.estimatedOneRepMax)
                )
                .foregroundStyle(Color.orange.gradient)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

/// Stub Summary Cards View
struct SummaryCardsSnapshotView: View {
    let overview: SnapshotAnalyticsOverview

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                SummaryCardSnapshotView(
                    title: "Workouts",
                    value: "\(overview.totalWorkouts)",
                    subtitle: "Week Avg",
                    icon: "figure.strengthtraining.traditional",
                    color: .blue
                )

                SummaryCardSnapshotView(
                    title: "Total Volume",
                    value: formatVolume(overview.totalVolume),
                    subtitle: "Weight × Reps",
                    icon: "scalemass.fill",
                    color: .purple
                )

                SummaryCardSnapshotView(
                    title: "Progressing",
                    value: "\(overview.progressingCount)",
                    subtitle: "Exercises Improving",
                    icon: "arrow.up.right",
                    color: .green
                )

                SummaryCardSnapshotView(
                    title: "Plateaus",
                    value: "\(overview.plateauCount)",
                    subtitle: "Need Attention",
                    icon: "arrow.right",
                    color: .orange
                )
            }
            .padding(.horizontal)
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.0fK", volume / 1_000)
        }
        return "\(Int(volume))"
    }
}

/// Stub Summary Card
struct SummaryCardSnapshotView: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

/// Stub Progress Breakdown View
struct ProgressBreakdownSnapshotView: View {
    let overview: SnapshotAnalyticsOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress Breakdown")
                .font(.headline)

            // Progress bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if overview.progressingCount > 0 {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: barWidth(for: overview.progressingCount, in: geo.size.width))
                    }

                    if overview.plateauCount > 0 {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: barWidth(for: overview.plateauCount, in: geo.size.width))
                    }

                    if overview.decliningCount > 0 {
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: barWidth(for: overview.decliningCount, in: geo.size.width))
                    }

                    if overview.insufficientDataCount > 0 {
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: barWidth(for: overview.insufficientDataCount, in: geo.size.width))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)

            // Legend
            HStack(spacing: 16) {
                LegendItemSnapshotView(color: .green, label: "Progressing", count: overview.progressingCount)
                LegendItemSnapshotView(color: .orange, label: "Plateau", count: overview.plateauCount)
                LegendItemSnapshotView(color: .red, label: "Declining", count: overview.decliningCount)
            }
            .font(.caption)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func barWidth(for count: Int, in totalWidth: CGFloat) -> CGFloat {
        let total = overview.totalExercises
        guard total > 0 else { return 0 }
        return (CGFloat(count) / CGFloat(total)) * totalWidth
    }
}

/// Stub Legend Item
struct LegendItemSnapshotView: View {
    let color: Color
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label) (\(count))")
                .foregroundStyle(.secondary)
        }
    }
}

/// Stub Exercise Trend Row View
struct ExerciseTrendRowSnapshotView: View {
    let exerciseName: String
    let estimatedOneRepMax: Double?
    let trend: SnapshotProgressTrend
    let dataPoints: [SnapshotDataPoint]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(exerciseName)
                    .font(.headline)
                    .lineLimit(1)

                if let e1rm = estimatedOneRepMax {
                    Text("E1RM: \(Int(e1rm)) lbs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Mini sparkline
            if dataPoints.count >= 2 {
                MiniSparklineSnapshotView(dataPoints: dataPoints)
                    .frame(width: 60, height: 30)
            }

            // Trend badge
            Image(systemName: trend.icon)
                .foregroundStyle(trend.color)
                .font(.title3)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}
