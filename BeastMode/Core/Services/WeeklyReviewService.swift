// WeeklyReviewService.swift
// BeastMode
// Service for generating AI-powered weekly workout reviews

import Foundation
import SwiftData

/// Service for generating comprehensive weekly workout reviews
actor WeeklyReviewService {
    private let modelContext: ModelContext
    private let aiCoachService: AICoachService
    private let healthKitService: HealthKitService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.aiCoachService = AICoachService()
        self.healthKitService = HealthKitService()
    }

    // MARK: - Weekly Review Generation

    /// Generate a weekly review for a specific week
    func generateWeeklyReview(for weekId: String, userId: UUID) async throws -> WeeklyReview {
        // Fetch workout data for the week
        let workoutSummary = try await fetchWorkoutSummary(for: weekId, userId: userId)

        // Get analytics overview
        let analyticsService = AnalyticsService(modelContext: modelContext)
        let overview = try await analyticsService.generateOverview(for: userId, timeRange: .oneMonth)

        // Get body weight trend
        let weightTrend = try? await getBodyWeightTrend()

        // Get streak info
        let streak = try await getStreak(for: userId)

        // Get PR count for the week
        let prCount = try await getPRCount(for: weekId, userId: userId)

        // Get workout count
        let workoutCount = try await getWorkoutCount(for: weekId, userId: userId)

        // Build AI prompt
        let prompt = Prompts.weeklyReview(
            workoutData: workoutSummary,
            bodyWeightTrend: weightTrend,
            progressingExercises: overview.progressingExercises.map(\.exerciseName),
            plateauExercises: overview.plateauExercises.map(\.exerciseName),
            streakDays: streak?.currentStreak ?? 0
        )

        // Get AI response
        let content = try await aiCoachService.generateWeeklyReview(prompt: prompt)

        return WeeklyReview(
            weekId: weekId,
            generatedAt: .now,
            content: content,
            workoutCount: workoutCount,
            totalVolume: overview.totalVolume,
            prCount: prCount
        )
    }

    /// Get the current week ID
    func currentWeekId() -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }

    /// Get week ID for a given date
    func weekId(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }

    // MARK: - Private Helpers

    private func fetchWorkoutSummary(for weekId: String, userId: UUID) async throws -> String {
        // Calculate date range for the week
        let (startDate, endDate) = dateRange(for: weekId)

        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.userId == userId &&
                workout.completedAt != nil &&
                workout.startedAt >= startDate &&
                workout.startedAt <= endDate
            },
            sortBy: [SortDescriptor(\.startedAt)]
        )

        let workouts = try modelContext.fetch(descriptor)

        guard !workouts.isEmpty else {
            return "No workouts logged this week."
        }

        var summary = ""
        let calendar = Calendar.current

        for workout in workouts {
            let dayName = calendar.weekdaySymbols[calendar.component(.weekday, from: workout.startedAt) - 1]
            summary += "\n### \(dayName)\n"

            for exercise in workout.exercises {
                let sets = exercise.sets
                    .filter { $0.isCompleted }
                    .compactMap { set -> String? in
                        guard let weight = set.weight, let reps = set.reps else { return nil }
                        return "\(Int(weight))×\(reps)"
                    }
                    .joined(separator: ", ")

                if !sets.isEmpty {
                    summary += "- \(exercise.exerciseName): \(sets)\n"
                }
            }
        }

        return summary
    }

    private func getBodyWeightTrend() async throws -> String? {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: .now)!
        let weights = try await healthKitService.fetchBodyWeightHistory(from: twoWeeksAgo)

        guard weights.count >= 2 else { return nil }

        let firstWeek = Array(weights.prefix(weights.count / 2)).map(\.weight).average
        let secondWeek = Array(weights.suffix(weights.count / 2)).map(\.weight).average
        let diff = secondWeek - firstWeek

        if abs(diff) < 0.5 {
            return "Stable around \(String(format: "%.1f", secondWeek)) lbs"
        } else if diff > 0 {
            return "Up \(String(format: "%.1f", diff)) lbs (now \(String(format: "%.1f", secondWeek)) lbs)"
        } else {
            return "Down \(String(format: "%.1f", abs(diff))) lbs (now \(String(format: "%.1f", secondWeek)) lbs)"
        }
    }

    private func getStreak(for userId: UUID) async throws -> UserStreak? {
        let descriptor = FetchDescriptor<UserStreak>(
            predicate: #Predicate<UserStreak> { $0.userId == userId }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func getWorkoutCount(for weekId: String, userId: UUID) async throws -> Int {
        let (startDate, endDate) = dateRange(for: weekId)

        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.userId == userId &&
                workout.completedAt != nil &&
                workout.startedAt >= startDate &&
                workout.startedAt <= endDate
            }
        )

        return try modelContext.fetchCount(descriptor)
    }

    private func getPRCount(for weekId: String, userId: UUID) async throws -> Int {
        let (startDate, endDate) = dateRange(for: weekId)

        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate<PersonalRecord> { pr in
                pr.userId == userId &&
                pr.date >= startDate &&
                pr.date <= endDate
            }
        )

        return try modelContext.fetchCount(descriptor)
    }

    private func dateRange(for weekId: String) -> (start: Date, end: Date) {
        // Parse week ID (format: "2024-W5")
        let parts = weekId.split(separator: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1]) else {
            return (.distantPast, .distantFuture)
        }

        let calendar = Calendar.current
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = calendar.firstWeekday

        guard let startDate = calendar.date(from: components) else {
            return (.distantPast, .distantFuture)
        }

        let endDate = calendar.date(byAdding: .day, value: 7, to: startDate) ?? .distantFuture

        return (startDate, endDate)
    }
}

// MARK: - Weekly Review History

/// Manages cached weekly reviews
actor WeeklyReviewCache {
    private var cache: [String: WeeklyReview] = [:]

    func get(for weekId: String) -> WeeklyReview? {
        cache[weekId]
    }

    func store(_ review: WeeklyReview) {
        cache[review.weekId] = review
    }

    func clear() {
        cache.removeAll()
    }
}
