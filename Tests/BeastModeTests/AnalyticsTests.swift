// AnalyticsTests.swift
// BeastModeTests
// Unit tests for analytics and trend calculations

import XCTest
import SwiftData
@testable import BeastMode

final class AnalyticsTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            PersonalRecord.self,
            UserProfile.self,
            UserStreak.self,
            Exercise.self,
            Workout.self,
            WorkoutExercise.self,
            SetLog.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
    }

    // MARK: - Progress Trend Tests

    func testProgressTrend_Increasing() {
        // Trend should be increasing when E1RM improves by >2.5%
        let trend = ProgressTrend.increasing(percentage: 5.0)
        XCTAssertEqual(trend.description, "+5.0% over period")
        XCTAssertEqual(trend.icon, "arrow.up.right.circle.fill")
    }

    func testProgressTrend_Plateau() {
        let trend = ProgressTrend.plateau(weeks: 3)
        XCTAssertEqual(trend.description, "Plateau for 3 weeks")
        XCTAssertEqual(trend.icon, "arrow.right.circle.fill")
    }

    func testProgressTrend_Decreasing() {
        let trend = ProgressTrend.decreasing(percentage: 4.5)
        XCTAssertEqual(trend.description, "-4.5% over period")
        XCTAssertEqual(trend.icon, "arrow.down.right.circle.fill")
    }

    func testProgressTrend_Insufficient() {
        let trend = ProgressTrend.insufficient
        XCTAssertEqual(trend.description, "Need more data")
        XCTAssertEqual(trend.icon, "questionmark.circle.fill")
    }

    // MARK: - Volume Trend Tests

    func testVolumeTrend_ChangePercentage_Positive() {
        let trend = VolumeTrend(
            currentWeekVolume: 5500,
            previousWeekVolume: 5000,
            averageVolume: 5250
        )

        XCTAssertEqual(trend.changePercentage, 10.0, accuracy: 0.01)
        XCTAssertTrue(trend.isProgressing)
    }

    func testVolumeTrend_ChangePercentage_Negative() {
        let trend = VolumeTrend(
            currentWeekVolume: 4500,
            previousWeekVolume: 5000,
            averageVolume: 4750
        )

        XCTAssertEqual(trend.changePercentage, -10.0, accuracy: 0.01)
        XCTAssertFalse(trend.isProgressing)
    }

    func testVolumeTrend_ChangePercentage_ZeroPrevious() {
        let trend = VolumeTrend(
            currentWeekVolume: 5000,
            previousWeekVolume: 0,
            averageVolume: 2500
        )

        XCTAssertEqual(trend.changePercentage, 0)
    }

    // MARK: - Chart Time Range Tests

    func testChartTimeRange_StartDates() {
        let now = Date.now
        let calendar = Calendar.current

        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!

        // One month should be approximately 30 days ago
        let oneMonthRange = ChartTimeRange.oneMonth.startDate
        let daysDiff = calendar.dateComponents([.day], from: oneMonthRange, to: now).day ?? 0
        XCTAssertTrue(daysDiff >= 28 && daysDiff <= 31)

        // Three months should be approximately 90 days ago
        let threeMonthRange = ChartTimeRange.threeMonths.startDate
        let threeMonthDiff = calendar.dateComponents([.day], from: threeMonthRange, to: now).day ?? 0
        XCTAssertTrue(threeMonthDiff >= 88 && threeMonthDiff <= 92)
    }

    func testChartTimeRange_AllTimeStartsAtDistantPast() {
        let startDate = ChartTimeRange.allTime.startDate
        XCTAssertEqual(startDate, .distantPast)
    }

    // MARK: - Body Weight Trend Tests

    func testWeightTrend_Gaining() {
        let trend = WeightTrend.gaining(3.5)
        XCTAssertEqual(trend.text, "+3.5 lbs")
        XCTAssertEqual(trend.icon, "arrow.up.right")
    }

    func testWeightTrend_Losing() {
        let trend = WeightTrend.losing(2.0)
        XCTAssertEqual(trend.text, "-2.0 lbs")
        XCTAssertEqual(trend.icon, "arrow.down.right")
    }

    func testWeightTrend_Stable() {
        let trend = WeightTrend.stable
        XCTAssertEqual(trend.text, "Stable")
        XCTAssertEqual(trend.icon, "arrow.right")
    }

    // MARK: - Weight Suggestion Tests

    func testWeightSuggestion_Decoding() throws {
        let json = """
        {
            "suggestedWeight": 195,
            "suggestedReps": 6,
            "confidence": "high",
            "reasoning": "You've been hitting 8+ reps consistently.",
            "alternativeApproach": "Try pause reps"
        }
        """

        let data = json.data(using: .utf8)!
        let suggestion = try JSONDecoder().decode(WeightSuggestion.self, from: data)

        XCTAssertEqual(suggestion.suggestedWeight, 195)
        XCTAssertEqual(suggestion.suggestedReps, 6)
        XCTAssertEqual(suggestion.confidence, .high)
        XCTAssertEqual(suggestion.reasoning, "You've been hitting 8+ reps consistently.")
        XCTAssertEqual(suggestion.alternativeApproach, "Try pause reps")
    }

    func testWeightSuggestion_DecodingWithoutAlternative() throws {
        let json = """
        {
            "suggestedWeight": 185,
            "suggestedReps": 8,
            "confidence": "medium",
            "reasoning": "Maintain current weight and build volume."
        }
        """

        let data = json.data(using: .utf8)!
        let suggestion = try JSONDecoder().decode(WeightSuggestion.self, from: data)

        XCTAssertEqual(suggestion.suggestedWeight, 185)
        XCTAssertNil(suggestion.alternativeApproach)
    }

    func testWeightSuggestion_ConfidenceColors() {
        XCTAssertEqual(WeightSuggestion.Confidence.high.color, .green)
        XCTAssertEqual(WeightSuggestion.Confidence.medium.color, .orange)
        XCTAssertEqual(WeightSuggestion.Confidence.low.color, .gray)
    }

    // MARK: - Array Extension Tests

    func testArrayAverage() {
        let values = [10.0, 20.0, 30.0, 40.0]
        XCTAssertEqual(values.average, 25.0)
    }

    func testArrayAverage_Empty() {
        let values: [Double] = []
        XCTAssertEqual(values.average, 0)
    }

    func testArrayAverage_SingleValue() {
        let values = [42.0]
        XCTAssertEqual(values.average, 42.0)
    }

    func testArrayStandardDeviation() {
        let values = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
        // Population std dev is 2, sample std dev is ~2.138
        XCTAssertEqual(values.standardDeviation, 2.138, accuracy: 0.01)
    }

    // MARK: - Body Weight Entry Tests

    func testBodyWeightEntry_FormattedWeight() {
        let entry = BodyWeightEntry(date: .now, weight: 182.5, source: "Apple Watch")
        XCTAssertEqual(entry.formattedWeight, "182.5 lbs")
    }

    func testBodyWeightEntry_Equality() {
        let date = Date.now
        let entry1 = BodyWeightEntry(date: date, weight: 180.0, source: "Scale")
        let entry2 = BodyWeightEntry(date: date, weight: 180.0, source: "Scale")

        XCTAssertEqual(entry1, entry2)
    }

    // MARK: - Analytics Overview Tests

    func testAnalyticsOverview_ProgressCategories() {
        let exerciseAnalytics = [
            createMockExerciseAnalytics(name: "Bench Press", trend: .increasing(percentage: 5)),
            createMockExerciseAnalytics(name: "Squat", trend: .plateau(weeks: 3)),
            createMockExerciseAnalytics(name: "Deadlift", trend: .increasing(percentage: 8)),
            createMockExerciseAnalytics(name: "OHP", trend: .decreasing(percentage: 3)),
            createMockExerciseAnalytics(name: "Rows", trend: .insufficient)
        ]

        let overview = AnalyticsOverview(
            exercises: exerciseAnalytics,
            totalWorkouts: 20,
            totalVolume: 100000,
            averageWorkoutsPerWeek: 4.0,
            timeRange: .threeMonths
        )

        XCTAssertEqual(overview.progressingExercises.count, 2)
        XCTAssertEqual(overview.plateauExercises.count, 1)
        XCTAssertEqual(overview.decliningExercises.count, 1)
        XCTAssertEqual(overview.insufficientDataExercises.count, 1)
    }

    // MARK: - Helpers

    private func createMockExerciseAnalytics(name: String, trend: ProgressTrend) -> ExerciseAnalytics {
        ExerciseAnalytics(
            exerciseName: name,
            dataPoints: [],
            trend: trend,
            estimatedOneRepMax: 225,
            volumeTrend: VolumeTrend(currentWeekVolume: 5000, previousWeekVolume: 4800, averageVolume: 4900),
            frequencyPerWeek: 2.0,
            lastPerformed: .now,
            totalSets: 30,
            totalReps: 200,
            totalVolume: 45000
        )
    }
}

// MARK: - Analytics Service Tests

final class AnalyticsServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            PersonalRecord.self,
            UserProfile.self,
            UserStreak.self,
            Exercise.self,
            Workout.self,
            WorkoutExercise.self,
            SetLog.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
    }

    func testAnalyticsService_EmptyOverview() async throws {
        let service = AnalyticsService(modelContext: modelContext)
        let userId = UUID()

        let overview = try await service.generateOverview(for: userId, timeRange: .threeMonths)

        XCTAssertEqual(overview.exercises.count, 0)
        XCTAssertEqual(overview.totalWorkouts, 0)
        XCTAssertEqual(overview.totalVolume, 0)
    }

    func testAnalyticsService_WithWorkouts() async throws {
        let service = AnalyticsService(modelContext: modelContext)
        let userId = UUID()

        // Create a workout with exercises and sets
        let workout = Workout(userId: userId)
        workout.completedAt = .now

        let exercise = WorkoutExercise(
            exerciseId: UUID(),
            exerciseName: "Bench Press",
            order: 0
        )

        let set = SetLog(exerciseId: exercise.exerciseId, setNumber: 1)
        set.weight = 185
        set.reps = 8
        set.completedAt = .now

        exercise.sets.append(set)
        workout.exercises.append(exercise)

        modelContext.insert(workout)
        try modelContext.save()

        let overview = try await service.generateOverview(for: userId, timeRange: .threeMonths)

        XCTAssertEqual(overview.totalWorkouts, 1)
        XCTAssertEqual(overview.exercises.count, 1)
        XCTAssertEqual(overview.exercises.first?.exerciseName, "Bench Press")
    }
}
