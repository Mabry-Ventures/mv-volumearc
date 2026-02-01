// MockAICoachService.swift
// BeastModeTests
// Controllable mock for AI Coach service testing

import Foundation
@testable import BeastMode

/// Controllable mock for AI Coach service testing
actor MockAICoachService: AICoachServiceProtocol {

    // MARK: - Configuration

    var formCheckResponse: FormCheckResponse?
    var alternativesResponse: [ExerciseAlternative] = []
    var weeklyReviewResponse: WeeklyReview?
    var weightSuggestionResponse: WeightSuggestion?

    var shouldThrowError: Error?
    var callDelay: Duration = .zero

    // MARK: - Call Tracking

    private(set) var formCheckCallCount = 0
    private(set) var lastFormCheckExercise: String?

    private(set) var alternativesCallCount = 0
    private(set) var lastAlternativesExercise: String?

    private(set) var weeklyReviewCallCount = 0
    private(set) var lastWeeklyReviewData: String?

    private(set) var weightSuggestionCallCount = 0
    private(set) var lastWeightSuggestionExercise: String?

    // MARK: - Protocol Implementation

    func getFormCheck(for exercise: String) async throws -> FormCheckResponse {
        formCheckCallCount += 1
        lastFormCheckExercise = exercise

        if callDelay > .zero {
            try await Task.sleep(for: callDelay)
        }

        if let error = shouldThrowError {
            throw error
        }

        return formCheckResponse ?? FormCheckResponse(
            cues: ["Keep back flat", "Drive through heels", "Brace core"],
            commonMistake: "Rounding lower back",
            motivation: "You've got this!"
        )
    }

    func getAlternatives(
        for exercise: String,
        equipment: [String]
    ) async throws -> [ExerciseAlternative] {
        alternativesCallCount += 1
        lastAlternativesExercise = exercise

        if let error = shouldThrowError {
            throw error
        }

        return alternativesResponse.isEmpty ? [
            ExerciseAlternative(name: "Dumbbell Press", reason: "Similar movement pattern"),
            ExerciseAlternative(name: "Machine Press", reason: "Easier to stabilize"),
            ExerciseAlternative(name: "Push-ups", reason: "No equipment needed")
        ] : alternativesResponse
    }

    func generateWeeklyReview(workoutData: String) async throws -> WeeklyReview {
        weeklyReviewCallCount += 1
        lastWeeklyReviewData = workoutData

        if let error = shouldThrowError {
            throw error
        }

        return weeklyReviewResponse ?? WeeklyReview(
            weekId: "2025-W28",
            generatedAt: .now,
            summary: "Great week! You hit all your targets.",
            highlights: ["Hit 3 new PRs", "Increased bench by 5 lbs"],
            areasForImprovement: ["Consider adding more leg volume"],
            motivationalNote: "Keep pushing - you're making great progress!"
        )
    }

    func suggestProgressiveOverload(
        for exerciseName: String,
        recentPerformance: [SetPerformance],
        currentTrend: ProgressTrend
    ) async throws -> WeightSuggestion {
        weightSuggestionCallCount += 1
        lastWeightSuggestionExercise = exerciseName

        if let error = shouldThrowError {
            throw error
        }

        return weightSuggestionResponse ?? WeightSuggestion(
            exerciseName: exerciseName,
            suggestedWeight: 225,
            suggestedReps: 6,
            confidence: .high,
            reasoning: "Based on your recent progress, you're ready to increase.",
            alternativeApproach: nil
        )
    }

    // MARK: - Test Helpers

    func reset() {
        formCheckResponse = nil
        alternativesResponse = []
        weeklyReviewResponse = nil
        weightSuggestionResponse = nil
        shouldThrowError = nil
        callDelay = .zero
        formCheckCallCount = 0
        lastFormCheckExercise = nil
        alternativesCallCount = 0
        lastAlternativesExercise = nil
        weeklyReviewCallCount = 0
        lastWeeklyReviewData = nil
        weightSuggestionCallCount = 0
        lastWeightSuggestionExercise = nil
    }

    func setError(_ error: Error) {
        shouldThrowError = error
    }

    func setDelay(_ delay: Duration) {
        callDelay = delay
    }
}

// MARK: - Mock Response Types

extension MockAICoachService {

    /// Pre-built form check responses for testing
    enum MockFormChecks {
        static let benchPress = FormCheckResponse(
            cues: ["Arch your back slightly", "Keep feet flat on floor", "Lower bar to chest"],
            commonMistake: "Flaring elbows too wide",
            motivation: "Time to move some weight!"
        )

        static let squat = FormCheckResponse(
            cues: ["Keep chest up", "Push knees out", "Hit parallel or below"],
            commonMistake: "Letting knees cave inward",
            motivation: "Every rep counts!"
        )

        static let deadlift = FormCheckResponse(
            cues: ["Keep bar close to body", "Drive through heels", "Lock out at top"],
            commonMistake: "Rounding lower back",
            motivation: "Pull that weight!"
        )
    }

    /// Pre-built weekly reviews for testing
    enum MockReviews {
        static let excellent = WeeklyReview(
            weekId: "2025-W28",
            generatedAt: .now,
            summary: "Outstanding week! You crushed every workout.",
            highlights: ["5 workouts completed", "3 new PRs", "Perfect consistency"],
            areasForImprovement: [],
            motivationalNote: "You're on fire! Keep it up!"
        )

        static let needsWork = WeeklyReview(
            weekId: "2025-W28",
            generatedAt: .now,
            summary: "Decent week with room for improvement.",
            highlights: ["Completed planned workouts"],
            areasForImprovement: ["Missed leg day", "Rest times were long"],
            motivationalNote: "Every week is a chance to get better!"
        )
    }
}

// MARK: - Test Errors

enum MockAIError: LocalizedError {
    case networkUnavailable
    case rateLimited
    case invalidResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network connection unavailable"
        case .rateLimited:
            return "Rate limit exceeded. Try again later."
        case .invalidResponse:
            return "Invalid response from AI service"
        case .timeout:
            return "Request timed out"
        }
    }
}
