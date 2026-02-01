// AnalyticsService.swift
// BeastMode
// Service for generating progressive overload analytics

import Foundation
import SwiftData

/// Service for computing and aggregating workout analytics
actor AnalyticsService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Overview Generation

    /// Generate comprehensive analytics for all exercises
    func generateOverview(
        for userId: UUID,
        timeRange: ChartTimeRange = .threeMonths
    ) async throws -> AnalyticsOverview {
        let cutoffDate = timeRange.startDate

        // Fetch all completed workouts in range
        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.userId == userId &&
                workout.completedAt != nil &&
                workout.startedAt >= cutoffDate
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        let workouts = try modelContext.fetch(workoutDescriptor)

        // Extract all sets grouped by exercise
        var exerciseData: [String: [SetWithDate]] = [:]

        for workout in workouts {
            for exercise in workout.exercises {
                let setsWithDates = exercise.sets
                    .filter { $0.isCompleted && $0.weight != nil && $0.reps != nil }
                    .map { SetWithDate(set: $0, date: workout.startedAt, weekId: weekId(for: workout.startedAt)) }

                if exerciseData[exercise.exerciseName] != nil {
                    exerciseData[exercise.exerciseName]?.append(contentsOf: setsWithDates)
                } else {
                    exerciseData[exercise.exerciseName] = setsWithDates
                }
            }
        }

        // Generate analytics for each exercise
        var exerciseAnalytics: [ExerciseAnalytics] = []

        for (name, sets) in exerciseData {
            if let analytics = buildExerciseAnalytics(name: name, sets: sets) {
                exerciseAnalytics.append(analytics)
            }
        }

        // Sort by most recent activity
        exerciseAnalytics.sort { ($0.lastPerformed ?? .distantPast) > ($1.lastPerformed ?? .distantPast) }

        // Calculate overall stats
        let totalVolume = exerciseAnalytics.reduce(0) { $0 + $1.totalVolume }
        let weeks = max(1, Calendar.current.dateComponents([.weekOfYear], from: cutoffDate, to: .now).weekOfYear ?? 1)
        let avgWorkoutsPerWeek = Double(workouts.count) / Double(weeks)

        return AnalyticsOverview(
            exercises: exerciseAnalytics,
            totalWorkouts: workouts.count,
            totalVolume: totalVolume,
            averageWorkoutsPerWeek: avgWorkoutsPerWeek,
            timeRange: timeRange
        )
    }

    // MARK: - Single Exercise Analytics

    /// Generate analytics for a single exercise
    func generateExerciseAnalytics(
        exerciseName: String,
        userId: UUID,
        timeRange: ChartTimeRange = .threeMonths
    ) async throws -> ExerciseAnalytics? {
        let cutoffDate = timeRange.startDate

        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.userId == userId &&
                workout.completedAt != nil &&
                workout.startedAt >= cutoffDate
            },
            sortBy: [SortDescriptor(\.startedAt)]
        )

        let workouts = try modelContext.fetch(workoutDescriptor)

        var sets: [SetWithDate] = []

        for workout in workouts {
            for exercise in workout.exercises where exercise.exerciseName == exerciseName {
                let setsWithDates = exercise.sets
                    .filter { $0.isCompleted && $0.weight != nil && $0.reps != nil }
                    .map { SetWithDate(set: $0, date: workout.startedAt, weekId: weekId(for: workout.startedAt)) }
                sets.append(contentsOf: setsWithDates)
            }
        }

        return buildExerciseAnalytics(name: exerciseName, sets: sets)
    }

    // MARK: - PR History

    /// Get PR history for an exercise
    func getPRHistory(
        exerciseName: String,
        userId: UUID
    ) async throws -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate<PersonalRecord> { pr in
                pr.exerciseName == exerciseName && pr.userId == userId
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        return try modelContext.fetch(descriptor)
    }

    // MARK: - Private Helpers

    private func buildExerciseAnalytics(name: String, sets: [SetWithDate]) -> ExerciseAnalytics? {
        guard !sets.isEmpty else { return nil }

        // Build data points
        var dataPoints: [AnalyticsDataPoint] = []

        for setWithDate in sets {
            guard let weight = setWithDate.set.weight,
                  let reps = setWithDate.set.reps else { continue }

            let e1rm = calculateE1RM(weight: weight, reps: reps)
            let volume = weight * Double(reps)

            dataPoints.append(AnalyticsDataPoint(
                date: setWithDate.date,
                weight: weight,
                reps: reps,
                estimatedOneRepMax: e1rm,
                volume: volume,
                weekId: setWithDate.weekId
            ))
        }

        guard !dataPoints.isEmpty else { return nil }

        // Sort by date
        dataPoints.sort { $0.date < $1.date }

        // Calculate metrics
        let trend = calculateTrend(dataPoints: dataPoints)
        let volumeTrend = calculateVolumeTrend(dataPoints: dataPoints)
        let bestE1RM = dataPoints.map(\.estimatedOneRepMax).max()

        // Frequency calculation
        let uniqueWeeks = Set(dataPoints.map(\.weekId))
        let workoutCount = Set(dataPoints.map { Calendar.current.startOfDay(for: $0.date) }).count
        let frequency = uniqueWeeks.isEmpty ? 0 : Double(workoutCount) / Double(uniqueWeeks.count)

        // Totals
        let totalSets = dataPoints.count
        let totalReps = dataPoints.reduce(0) { $0 + $1.reps }
        let totalVolume = dataPoints.reduce(0) { $0 + $1.volume }

        return ExerciseAnalytics(
            exerciseName: name,
            dataPoints: dataPoints,
            trend: trend,
            estimatedOneRepMax: bestE1RM,
            volumeTrend: volumeTrend,
            frequencyPerWeek: frequency,
            lastPerformed: dataPoints.last?.date,
            totalSets: totalSets,
            totalReps: totalReps,
            totalVolume: totalVolume
        )
    }

    private func calculateTrend(dataPoints: [AnalyticsDataPoint]) -> ProgressTrend {
        guard dataPoints.count >= 4 else { return .insufficient }

        // Compare first third to last third of E1RM values
        let thirdCount = max(1, dataPoints.count / 3)
        let firstThird = Array(dataPoints.prefix(thirdCount))
        let lastThird = Array(dataPoints.suffix(thirdCount))

        let firstAvgE1RM = firstThird.map(\.estimatedOneRepMax).average
        let lastAvgE1RM = lastThird.map(\.estimatedOneRepMax).average

        guard firstAvgE1RM > 0 else { return .insufficient }

        let percentChange = ((lastAvgE1RM - firstAvgE1RM) / firstAvgE1RM) * 100

        if percentChange > 2.5 {
            return .increasing(percentage: percentChange)
        } else if percentChange < -2.5 {
            return .decreasing(percentage: abs(percentChange))
        } else {
            // Calculate plateau duration
            let weeks = Set(dataPoints.map(\.weekId)).count
            return .plateau(weeks: weeks)
        }
    }

    private func calculateVolumeTrend(dataPoints: [AnalyticsDataPoint]) -> VolumeTrend {
        let calendar = Calendar.current
        let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now))!
        let previousWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)!

        let currentWeekPoints = dataPoints.filter { $0.date >= currentWeekStart }
        let previousWeekPoints = dataPoints.filter { $0.date >= previousWeekStart && $0.date < currentWeekStart }

        let currentVolume = currentWeekPoints.reduce(0) { $0 + $1.volume }
        let previousVolume = previousWeekPoints.reduce(0) { $0 + $1.volume }

        let uniqueWeeks = Set(dataPoints.map(\.weekId)).count
        let avgVolume = uniqueWeeks > 0 ? dataPoints.reduce(0) { $0 + $1.volume } / Double(uniqueWeeks) : 0

        return VolumeTrend(
            currentWeekVolume: currentVolume,
            previousWeekVolume: previousVolume,
            averageVolume: avgVolume
        )
    }

    private func calculateE1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        if reps == 1 { return weight }
        let effectiveReps = min(reps, 12)
        return weight * (36.0 / (37.0 - Double(effectiveReps)))
    }

    private func weekId(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }
}

// MARK: - Helper Types

private struct SetWithDate {
    let set: SetLog
    let date: Date
    let weekId: String
}
