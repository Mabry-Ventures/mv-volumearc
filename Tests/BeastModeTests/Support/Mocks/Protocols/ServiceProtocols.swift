// ServiceProtocols.swift
// BeastModeTests
// Protocol definitions to enable service mocking

import Foundation
@testable import BeastMode

// MARK: - AI Coach Service Protocol

/// Protocol for AI Coach service to enable mocking
protocol AICoachServiceProtocol: Actor {
    func getFormCheck(for exercise: String) async throws -> FormCheckResponse
    func getAlternatives(for exercise: String, equipment: [String]) async throws -> [ExerciseAlternative]
    func generateWeeklyReview(workoutData: String) async throws -> WeeklyReview
    func suggestProgressiveOverload(
        for exerciseName: String,
        recentPerformance: [SetPerformance],
        currentTrend: ProgressTrend
    ) async throws -> WeightSuggestion
}

// MARK: - HealthKit Service Protocol

/// Protocol for HealthKit service to enable mocking
protocol HealthKitServiceProtocol: Actor {
    func requestAuthorization() async throws
    func fetchBodyWeightHistory(from startDate: Date, to endDate: Date) async throws -> [BodyWeightEntry]
    func fetchLatestBodyWeight() async throws -> BodyWeightEntry?
    func observeBodyWeightChanges(handler: @escaping (BodyWeightEntry) -> Void) async throws
}

// MARK: - Supporting Types for Protocols

/// Form check response from AI coach
struct FormCheckResponse: Codable, Equatable {
    let cues: [String]
    let commonMistake: String
    let motivation: String
}

/// Exercise alternative suggestion
struct ExerciseAlternative: Codable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let reason: String
}

/// Weekly review from AI coach
struct WeeklyReview: Codable, Equatable, Identifiable {
    var id: String { weekId }
    let weekId: String
    let generatedAt: Date
    let summary: String
    let highlights: [String]
    let areasForImprovement: [String]
    let motivationalNote: String
}

/// Set performance data for progressive overload calculation
struct SetPerformance: Codable, Equatable {
    let date: Date
    let weight: Double
    let reps: Int
    let estimatedOneRepMax: Double
}

/// Body weight entry from HealthKit
struct BodyWeightEntry: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let weight: Double
    let source: String
}

// MARK: - PR Detection Service Protocol

/// Protocol for PR detection service
protocol PRDetectionServiceProtocol: Actor {
    func checkForPR(
        exerciseName: String,
        weight: Double,
        reps: Int,
        userId: UUID
    ) async -> PRType?

    func calculateE1RM(weight: Double, reps: Int) -> Double

    func savePR(
        exerciseName: String,
        weight: Double,
        reps: Int,
        estimatedOneRepMax: Double,
        userId: UUID
    ) async throws
}

// MARK: - Streak Service Protocol

/// Protocol for streak tracking service
protocol StreakServiceProtocol: Actor {
    func recordWorkout(for userId: UUID, completedAt: Date) async throws -> [Badge]
    func getStreak(for userId: UUID) async throws -> UserStreak?
    func checkAndAwardBadges(for streak: UserStreak, completedAt: Date) async -> [Badge]
}

// MARK: - Analytics Service Protocol

/// Protocol for analytics service
protocol AnalyticsServiceProtocol: Actor {
    func generateExerciseAnalytics(
        exerciseName: String,
        timeRange: ChartTimeRange
    ) async throws -> ExerciseAnalytics?

    func generateOverview(timeRange: ChartTimeRange) async throws -> AnalyticsOverview

    func calculateProgressTrend(from dataPoints: [AnalyticsDataPoint]) -> ProgressTrend
}

// MARK: - Plan Sharing Service Protocol

/// Protocol for plan sharing service
protocol PlanSharingServiceProtocol: Actor {
    func exportPlan(_ plan: WorkoutPlan) async throws -> Data
    func importPlan(from data: Data, userId: UUID) async throws -> WorkoutPlan
    func generateShareLink(_ plan: WorkoutPlan) async throws -> URL
    func generateShareCode(for plan: WorkoutPlan) async throws -> String
    func validatePlanData(_ data: Data) async throws -> ShareablePlan
}

// MARK: - Rest Timer Service Protocol

/// Protocol for rest timer service
protocol RestTimerServiceProtocol {
    func getRestDuration(
        for exerciseName: String,
        isCompound: Bool,
        userProfile: UserProfile
    ) -> Int

    func formatDuration(_ seconds: Int) -> String
}

// MARK: - Complication Update Service Protocol

/// Protocol for Watch complication updates
protocol ComplicationUpdateServiceProtocol: Actor {
    func updateAllComplications(for userId: UUID) async throws
    func updateStreakComplication(_ streak: Int)
    func updateTodayWorkoutComplication(for userId: UUID) async throws
    func markTodayCompleted() async
}
