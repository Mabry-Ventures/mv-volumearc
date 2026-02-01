// Analytics.swift
// BeastMode
// Models for progressive overload analytics

import Foundation
import SwiftUI

// MARK: - Exercise Analytics

/// Comprehensive analytics for a single exercise
struct ExerciseAnalytics: Identifiable {
    let id = UUID()
    let exerciseName: String
    let dataPoints: [AnalyticsDataPoint]
    let trend: ProgressTrend
    let estimatedOneRepMax: Double?
    let volumeTrend: VolumeTrend
    let frequencyPerWeek: Double
    let lastPerformed: Date?
    let totalSets: Int
    let totalReps: Int
    let totalVolume: Double  // Weight × Reps
}

/// Single data point for analytics charts
struct AnalyticsDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double
    let reps: Int
    let estimatedOneRepMax: Double
    let volume: Double  // Weight × Reps for that set
    let weekId: String
}

// MARK: - Progress Trend

/// Represents the direction of progress for an exercise
enum ProgressTrend: Equatable {
    case increasing(percentage: Double)
    case plateau(weeks: Int)
    case decreasing(percentage: Double)
    case insufficient  // Not enough data

    var description: String {
        switch self {
        case .increasing(let pct): return "+\(String(format: "%.1f", pct))% over period"
        case .plateau(let weeks): return "Plateau for \(weeks) weeks"
        case .decreasing(let pct): return "-\(String(format: "%.1f", pct))% over period"
        case .insufficient: return "Need more data"
        }
    }

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

// MARK: - Volume Trend

/// Tracks volume changes week over week
struct VolumeTrend {
    let currentWeekVolume: Double
    let previousWeekVolume: Double
    let averageVolume: Double

    var changePercentage: Double {
        guard previousWeekVolume > 0 else { return 0 }
        return ((currentWeekVolume - previousWeekVolume) / previousWeekVolume) * 100
    }

    var isProgressing: Bool {
        changePercentage > 0
    }

    var changeDescription: String {
        let pct = abs(changePercentage)
        if pct < 1 {
            return "No change"
        } else if isProgressing {
            return "+\(String(format: "%.1f", pct))%"
        } else {
            return "-\(String(format: "%.1f", pct))%"
        }
    }
}

// MARK: - Analytics Overview

/// High-level overview of all exercise analytics
struct AnalyticsOverview {
    let exercises: [ExerciseAnalytics]
    let totalWorkouts: Int
    let totalVolume: Double
    let averageWorkoutsPerWeek: Double
    let timeRange: ChartTimeRange

    var progressingExercises: [ExerciseAnalytics] {
        exercises.filter {
            if case .increasing = $0.trend { return true }
            return false
        }
    }

    var plateauExercises: [ExerciseAnalytics] {
        exercises.filter {
            if case .plateau = $0.trend { return true }
            return false
        }
    }

    var decliningExercises: [ExerciseAnalytics] {
        exercises.filter {
            if case .decreasing = $0.trend { return true }
            return false
        }
    }

    var insufficientDataExercises: [ExerciseAnalytics] {
        exercises.filter {
            if case .insufficient = $0.trend { return true }
            return false
        }
    }
}

// MARK: - Chart Time Range

/// Time ranges for analytics charts
enum ChartTimeRange: String, CaseIterable, Identifiable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case allTime = "All"

    var id: String { rawValue }

    var startDate: Date {
        let calendar = Calendar.current
        switch self {
        case .oneMonth: return calendar.date(byAdding: .month, value: -1, to: .now)!
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: .now)!
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: .now)!
        case .oneYear: return calendar.date(byAdding: .year, value: -1, to: .now)!
        case .allTime: return .distantPast
        }
    }

    var strideComponent: Calendar.Component {
        switch self {
        case .oneMonth: return .day
        case .threeMonths: return .weekOfYear
        case .sixMonths: return .month
        case .oneYear: return .month
        case .allTime: return .month
        }
    }

    var strideCount: Int {
        switch self {
        case .oneMonth: return 7
        case .threeMonths: return 2
        case .sixMonths: return 1
        case .oneYear: return 2
        case .allTime: return 3
        }
    }

    var dateFormat: Date.FormatStyle {
        switch self {
        case .oneMonth: return .dateTime.day()
        case .threeMonths: return .dateTime.month(.abbreviated).day()
        case .sixMonths, .oneYear, .allTime: return .dateTime.month(.abbreviated)
        }
    }

    var displayName: String {
        switch self {
        case .oneMonth: return "1 Month"
        case .threeMonths: return "3 Months"
        case .sixMonths: return "6 Months"
        case .oneYear: return "1 Year"
        case .allTime: return "All Time"
        }
    }
}

// MARK: - Body Weight

/// Entry for body weight tracking
struct BodyWeightEntry: Identifiable, Codable, Equatable {
    var id: Date { date }
    let date: Date
    let weight: Double  // In user's preferred unit
    let source: String

    var formattedWeight: String {
        "\(String(format: "%.1f", weight)) lbs"
    }
}

/// Body weight trend analysis
enum WeightTrend: Equatable {
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

// MARK: - Weekly Review

/// AI-generated weekly review
struct WeeklyReview: Identifiable {
    let id = UUID()
    let weekId: String
    let generatedAt: Date
    let content: String
    let workoutCount: Int
    let totalVolume: Double
    let prCount: Int
}

// MARK: - Weight Suggestion

/// AI-generated weight progression suggestion
struct WeightSuggestion: Codable, Identifiable {
    var id: String { exerciseName }
    var exerciseName: String
    let suggestedWeight: Double
    let suggestedReps: Int
    let confidence: Confidence
    let reasoning: String
    let alternativeApproach: String?

    enum Confidence: String, Codable {
        case high, medium, low

        var color: Color {
            switch self {
            case .high: return .green
            case .medium: return .orange
            case .low: return .gray
            }
        }
    }

    init(
        exerciseName: String = "",
        suggestedWeight: Double,
        suggestedReps: Int,
        confidence: Confidence,
        reasoning: String,
        alternativeApproach: String? = nil
    ) {
        self.exerciseName = exerciseName
        self.suggestedWeight = suggestedWeight
        self.suggestedReps = suggestedReps
        self.confidence = confidence
        self.reasoning = reasoning
        self.alternativeApproach = alternativeApproach
    }
}

// MARK: - Array Extensions

extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let avg = average
        let variance = reduce(0) { $0 + pow($1 - avg, 2) } / Double(count - 1)
        return sqrt(variance)
    }
}
