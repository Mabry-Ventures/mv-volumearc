// AICoachServiceTests.swift
// BeastModeTests
// Comprehensive unit tests for AICoachService

import Testing
import Foundation
@testable import BeastMode

// MARK: - AI Coach Service Tests

@Suite("AI Coach Service")
struct AICoachServiceTests {

    // MARK: - Weekly Review Tests

    @Suite("Weekly Review Generation")
    struct WeeklyReviewTests {

        @Test("Generates weekly review with mock response")
        func generatesWeeklyReviewWithMockResponse() async throws {
            let service = AICoachService(apiKey: nil) // No API key = mock mode

            let prompt = Prompts.weeklyReview(
                workoutData: "Monday: Bench Press 185x5, 185x5, 185x5",
                bodyWeightTrend: "Stable at 180 lbs",
                progressingExercises: ["Bench Press"],
                plateauExercises: [],
                streakDays: 7
            )

            let review = try await service.generateWeeklyReview(prompt: prompt)

            #expect(review.isEmpty == false)
            #expect(review.contains("Week") || review.contains("Wins") || review.contains("Progress"))
        }

        @Test("Mock response contains expected sections")
        func mockResponseContainsExpectedSections() async throws {
            let service = AICoachService(apiKey: nil)

            let prompt = "Generate a weekly review"
            let response = try await service.generateWeeklyReview(prompt: prompt)

            // Mock should contain standard sections
            #expect(response.contains("💪") || response.contains("Wins"))
        }
    }

    // MARK: - Weight Suggestion Tests

    @Suite("Weight Progression Suggestions")
    struct WeightSuggestionTests {

        @Test("Parses weight suggestion from mock response")
        func parsesWeightSuggestionFromMockResponse() async throws {
            let service = AICoachService(apiKey: nil)

            let dataPoints = [
                AnalyticsDataPoint(
                    date: Date().addingTimeInterval(-7 * 86400),
                    weight: 185,
                    reps: 8,
                    volume: 185 * 8 * 3
                ),
                AnalyticsDataPoint(
                    date: Date(),
                    weight: 185,
                    reps: 8,
                    volume: 185 * 8 * 3
                )
            ]

            let suggestion = try await service.suggestProgressiveOverload(
                for: "Bench Press",
                recentData: dataPoints,
                currentTrend: .increasing(percentage: 5.0)
            )

            #expect(suggestion.suggestedWeight > 0)
            #expect(suggestion.suggestedReps > 0)
            #expect(suggestion.reasoning.isEmpty == false)
        }

        @Test("Weight suggestion includes confidence level")
        func weightSuggestionIncludesConfidenceLevel() async throws {
            let service = AICoachService(apiKey: nil)

            let dataPoints = [
                AnalyticsDataPoint(
                    date: Date(),
                    weight: 200,
                    reps: 6,
                    volume: 200 * 6 * 4
                )
            ]

            let suggestion = try await service.suggestProgressiveOverload(
                for: "Squats",
                recentData: dataPoints,
                currentTrend: .plateau(weeks: 2)
            )

            // Confidence should be one of the valid values
            let validConfidences = ["high", "medium", "low"]
            #expect(validConfidences.contains(suggestion.confidence.rawValue))
        }
    }

    // MARK: - Motivation Tests

    @Suite("Motivational Messages")
    struct MotivationTests {

        @Test("Generates motivational message")
        func generatesMotivationalMessage() async throws {
            let service = AICoachService(apiKey: nil)

            let message = try await service.generateMotivation(
                streakDays: 14,
                recentPRs: 3,
                workoutsThisWeek: 4
            )

            #expect(message.isEmpty == false)
        }

        @Test("Motivation message is concise")
        func motivationMessageIsConcise() async throws {
            let service = AICoachService(apiKey: nil)

            let message = try await service.generateMotivation(
                streakDays: 7,
                recentPRs: 1,
                workoutsThisWeek: 3
            )

            // Should be brief (under 500 characters for 2-3 sentences)
            #expect(message.count < 500)
        }
    }

    // MARK: - Error Handling Tests

    @Suite("Error Handling")
    struct ErrorHandlingTests {

        @Test("AIError has correct descriptions")
        func aiErrorHasCorrectDescriptions() {
            let noAPIKeyError = AIError.noAPIKey
            #expect(noAPIKeyError.errorDescription?.contains("API key") == true)

            let invalidURLError = AIError.invalidURL
            #expect(invalidURLError.errorDescription?.contains("URL") == true)

            let invalidResponseError = AIError.invalidResponse
            #expect(invalidResponseError.errorDescription?.contains("response") == true)

            let emptyResponseError = AIError.emptyResponse
            #expect(emptyResponseError.errorDescription?.contains("Empty") == true)

            let apiError = AIError.apiError(statusCode: 429)
            #expect(apiError.errorDescription?.contains("429") == true)
        }
    }

    // MARK: - Prompts Tests

    @Suite("Prompt Generation")
    struct PromptsTests {

        @Test("Weekly review prompt includes workout data")
        func weeklyReviewPromptIncludesWorkoutData() {
            let workoutData = "Monday: Bench Press 185x5"
            let prompt = Prompts.weeklyReview(
                workoutData: workoutData,
                bodyWeightTrend: nil,
                progressingExercises: [],
                plateauExercises: [],
                streakDays: 5
            )

            #expect(prompt.contains(workoutData))
        }

        @Test("Weekly review prompt includes streak days")
        func weeklyReviewPromptIncludesStreakDays() {
            let prompt = Prompts.weeklyReview(
                workoutData: "Test data",
                bodyWeightTrend: nil,
                progressingExercises: [],
                plateauExercises: [],
                streakDays: 14
            )

            #expect(prompt.contains("14"))
        }

        @Test("Weekly review prompt includes progressing exercises")
        func weeklyReviewPromptIncludesProgressingExercises() {
            let prompt = Prompts.weeklyReview(
                workoutData: "Test data",
                bodyWeightTrend: nil,
                progressingExercises: ["Bench Press", "Squats"],
                plateauExercises: [],
                streakDays: 7
            )

            #expect(prompt.contains("Bench Press"))
            #expect(prompt.contains("Squats"))
        }

        @Test("Weekly review prompt includes plateau exercises")
        func weeklyReviewPromptIncludesPlateauExercises() {
            let prompt = Prompts.weeklyReview(
                workoutData: "Test data",
                bodyWeightTrend: nil,
                progressingExercises: [],
                plateauExercises: ["Deadlift"],
                streakDays: 7
            )

            #expect(prompt.contains("Deadlift"))
        }

        @Test("Weekly review prompt includes body weight trend when provided")
        func weeklyReviewPromptIncludesBodyWeightTrend() {
            let prompt = Prompts.weeklyReview(
                workoutData: "Test data",
                bodyWeightTrend: "Up 2 lbs",
                progressingExercises: [],
                plateauExercises: [],
                streakDays: 7
            )

            #expect(prompt.contains("Up 2 lbs"))
        }

        @Test("Plateau breakthrough prompt includes exercise details")
        func plateauBreakthroughPromptIncludesExerciseDetails() {
            let prompt = Prompts.plateauBreakthrough(
                exerciseName: "Bench Press",
                currentWeight: 185,
                currentReps: 5,
                weeksAtPlateau: 3
            )

            #expect(prompt.contains("Bench Press"))
            #expect(prompt.contains("185"))
            #expect(prompt.contains("5"))
            #expect(prompt.contains("3"))
        }

        @Test("Weekly review prompt contains required sections")
        func weeklyReviewPromptContainsRequiredSections() {
            let prompt = Prompts.weeklyReview(
                workoutData: "Test",
                bodyWeightTrend: nil,
                progressingExercises: [],
                plateauExercises: [],
                streakDays: 7
            )

            #expect(prompt.contains("Wins This Week"))
            #expect(prompt.contains("Progress Check"))
            #expect(prompt.contains("Focus for Next Week"))
            #expect(prompt.contains("Coach's Note"))
        }
    }

    // MARK: - WeightSuggestion Model Tests

    @Suite("Weight Suggestion Model")
    struct WeightSuggestionModelTests {

        @Test("WeightSuggestion decodes from JSON")
        func weightSuggestionDecodesFromJSON() throws {
            let json = """
            {
                "suggestedWeight": 195,
                "suggestedReps": 6,
                "confidence": "high",
                "reasoning": "You've been hitting 8+ reps consistently",
                "alternativeApproach": null
            }
            """

            let data = json.data(using: .utf8)!
            let suggestion = try JSONDecoder().decode(WeightSuggestion.self, from: data)

            #expect(suggestion.suggestedWeight == 195)
            #expect(suggestion.suggestedReps == 6)
            #expect(suggestion.confidence == .high)
            #expect(suggestion.reasoning.contains("8+ reps"))
            #expect(suggestion.alternativeApproach == nil)
        }

        @Test("WeightSuggestion decodes with alternative approach")
        func weightSuggestionDecodesWithAlternativeApproach() throws {
            let json = """
            {
                "suggestedWeight": 180,
                "suggestedReps": 8,
                "confidence": "medium",
                "reasoning": "Plateau detected",
                "alternativeApproach": "Try pause reps"
            }
            """

            let data = json.data(using: .utf8)!
            let suggestion = try JSONDecoder().decode(WeightSuggestion.self, from: data)

            #expect(suggestion.alternativeApproach == "Try pause reps")
        }

        @Test("Confidence levels decode correctly",
              arguments: [
                ("high", Confidence.high),
                ("medium", Confidence.medium),
                ("low", Confidence.low)
              ])
        func confidenceLevelsDecodeCorrectly(rawValue: String, expected: Confidence) throws {
            let json = """
            {
                "suggestedWeight": 100,
                "suggestedReps": 5,
                "confidence": "\(rawValue)",
                "reasoning": "Test"
            }
            """

            let data = json.data(using: .utf8)!
            let suggestion = try JSONDecoder().decode(WeightSuggestion.self, from: data)

            #expect(suggestion.confidence == expected)
        }
    }
}

// MARK: - Mock AI Coach Service Tests

@Suite("Mock AI Coach Service")
struct MockAICoachServiceTests {

    @Test("Mock provides form check response")
    func mockProvidesFormCheckResponse() async throws {
        let mock = MockAICoachService()
        await mock.setFormCheckResponse("Lower the bar to your chest with control")

        let response = try await mock.generateFormCheck(for: "Bench Press", issue: "bar path")

        #expect(response == "Lower the bar to your chest with control")
    }

    @Test("Mock tracks call count")
    func mockTracksCallCount() async throws {
        let mock = MockAICoachService()
        await mock.setFormCheckResponse("Test response")

        _ = try await mock.generateFormCheck(for: "Exercise1", issue: "issue1")
        _ = try await mock.generateFormCheck(for: "Exercise2", issue: "issue2")

        let callCount = await mock.formCheckCallCount
        #expect(callCount == 2)
    }

    @Test("Mock can throw errors")
    func mockCanThrowErrors() async {
        let mock = MockAICoachService()
        await mock.setShouldThrowError(true)

        do {
            _ = try await mock.generateFormCheck(for: "Test", issue: "test")
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is AIError)
        }
    }

    @Test("Mock provides weight suggestion response")
    func mockProvidesWeightSuggestionResponse() async throws {
        let mock = MockAICoachService()
        let suggestion = WeightSuggestion(
            suggestedWeight: 200,
            suggestedReps: 5,
            confidence: .high,
            reasoning: "Ready for increase"
        )
        await mock.setWeightSuggestionResponse(suggestion)

        let result = try await mock.suggestWeight(for: "Squats", recentSets: [])

        #expect(result.suggestedWeight == 200)
        #expect(result.suggestedReps == 5)
    }

    @Test("Mock weekly review response")
    func mockWeeklyReviewResponse() async throws {
        let mock = MockAICoachService()
        await mock.setWeeklyReviewResponse("Great progress this week!")

        let result = try await mock.generateWeeklyReview(workoutData: "test")

        #expect(result == "Great progress this week!")
    }

    @Test("Mock default responses work")
    func mockDefaultResponsesWork() async throws {
        let mock = MockAICoachService()

        // Should return default responses when not configured
        let formCheck = try await mock.generateFormCheck(for: "Bench", issue: "depth")
        #expect(formCheck.isEmpty == false)

        let weeklyReview = try await mock.generateWeeklyReview(workoutData: "test")
        #expect(weeklyReview.isEmpty == false)
    }

    @Test("Mock simulates delay")
    func mockSimulatesDelay() async throws {
        let mock = MockAICoachService()
        await mock.setCallDelay(0.1) // 100ms delay

        let startTime = Date()
        _ = try await mock.generateFormCheck(for: "Test", issue: "test")
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(elapsed >= 0.1)
    }
}
