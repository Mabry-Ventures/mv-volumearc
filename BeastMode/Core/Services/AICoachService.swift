import Foundation

/// Service for AI coaching features using Foundation Models and Claude API
actor AICoachService {
    static let shared = AICoachService()

    private let claudeAPIKey: String

    private init() {
        self.claudeAPIKey = Configuration.claudeAPIKey
    }

    // MARK: - AI Provider

    enum AIProvider {
        case onDevice      // Apple Foundation Models (iOS 26+)
        case cloud         // Claude API
    }

    /// Determine the best AI provider for a request
    private func preferredProvider(for requestType: RequestType) -> AIProvider {
        // For now, use cloud API
        // In iOS 26, we would check Foundation Models availability:
        // if FoundationModelSession.isAvailable { return .onDevice }
        return .cloud
    }

    enum RequestType {
        case formCheck
        case alternatives
        case weeklyReview
        case weightSuggestion
        case generalQuestion
    }

    // MARK: - Form Check

    /// Get form check tips for an exercise
    func getFormCheck(for exercise: String) async throws -> FormCheckResponse {
        let prompt = Prompts.formCheck(exercise: exercise)
        let response = try await sendClaudeRequest(prompt: prompt, maxTokens: 300)
        return FormCheckResponse(rawText: response)
    }

    // MARK: - Exercise Alternatives

    /// Get alternative exercises
    func getAlternatives(for exercise: String, equipment: [String] = []) async throws -> [ExerciseAlternative] {
        let prompt = Prompts.alternatives(exercise: exercise, equipment: equipment)
        let response = try await sendClaudeRequest(prompt: prompt, maxTokens: 500)

        // Try to parse as JSON
        if let data = response.data(using: .utf8),
           let alternatives = try? JSONDecoder().decode([ExerciseAlternative].self, from: data) {
            return alternatives
        }

        // Fallback: return empty array if parsing fails
        return []
    }

    // MARK: - Weekly Review

    /// Generate a weekly review based on workout logs
    func generateWeeklyReview(logs: [DailyLog]) async throws -> WeeklyReview {
        let summaries = logs.map { log in
            let exercises = log.sortedExerciseLogs.map { $0.summaryForAI }.joined(separator: "; ")
            return "\(log.weekday.fullName): \(exercises.isEmpty ? "Rest" : exercises)"
        }.joined(separator: "\n")

        let prompt = Prompts.weeklyReview(data: summaries)
        let response = try await sendClaudeRequest(prompt: prompt, maxTokens: 600)
        return WeeklyReview(rawText: response)
    }

    // MARK: - Weight Suggestions

    /// Get progressive overload suggestions based on recent PRs
    func suggestProgressiveOverload(records: [PersonalRecord]) async throws -> [WeightSuggestion] {
        guard !records.isEmpty else {
            return []
        }

        let recordSummaries = records.map { $0.summaryForAI }.joined(separator: "\n")
        let prompt = Prompts.weightSuggestions(records: recordSummaries)
        let response = try await sendClaudeRequest(prompt: prompt, maxTokens: 600)

        // Try to parse as JSON
        if let data = response.data(using: .utf8),
           let suggestions = try? JSONDecoder().decode([WeightSuggestionResponse].self, from: data) {
            return suggestions.map { suggestion in
                WeightSuggestion(
                    currentWeight: suggestion.currentWeight,
                    suggestedWeight: suggestion.suggestedWeight,
                    targetReps: suggestion.targetReps,
                    reasoning: suggestion.reasoning,
                    progressionType: suggestion.suggestedWeight > suggestion.currentWeight ? .increase : .maintain
                )
            }
        }

        return []
    }

    // MARK: - General Coach Question

    /// Ask the AI coach a general question
    func askCoach(question: String, context: String? = nil) async throws -> String {
        var fullPrompt = """
        You are Beast Mode's AI strength coach. You're knowledgeable, supportive, and give practical advice.
        Keep responses concise and actionable.

        """

        if let context = context {
            fullPrompt += "Context about the user's recent workouts:\n\(context)\n\n"
        }

        fullPrompt += "User question: \(question)"

        return try await sendClaudeRequest(prompt: fullPrompt, maxTokens: 400)
    }

    // MARK: - Exercise Info

    /// Get detailed information about an exercise
    func getExerciseInfo(for exercise: String) async throws -> ExerciseInfo {
        let prompt = Prompts.exerciseInfo(exercise: exercise)
        let response = try await sendClaudeRequest(prompt: prompt, maxTokens: 400)
        return ExerciseInfo(rawText: response, exerciseName: exercise)
    }

    // MARK: - Claude API

    private func sendClaudeRequest(prompt: String, maxTokens: Int) async throws -> String {
        guard !claudeAPIKey.isEmpty else {
            throw AICoachError.apiKeyMissing
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(claudeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AICoachError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AICoachError.apiError(statusCode: httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let text = result.content.first?.text else {
            throw AICoachError.emptyResponse
        }

        return text
    }
}

// MARK: - Prompts

enum Prompts {
    static func formCheck(exercise: String) -> String {
        """
        You are an expert strength coach giving quick, actionable form advice.

        Exercise: \(exercise)

        Provide:
        1. THREE main form cues (concise, memorable)
        2. The #1 mistake to avoid
        3. One motivating closer

        Keep total response under 100 words. Be punchy and energetic.
        """
    }

    static func exerciseInfo(exercise: String) -> String {
        """
        Provide a brief, helpful summary for: \(exercise)

        Format:
        **What is it?** (One sentence)
        **Key Form Points:** (3 bullet points)
        **Muscles Worked:** Primary and secondary

        Keep it concise and actionable.
        """
    }

    static func alternatives(exercise: String, equipment: [String]) -> String {
        let equipmentList = equipment.isEmpty ? "standard gym equipment" : equipment.joined(separator: ", ")
        return """
        Suggest 3 alternative exercises for: \(exercise)

        Available equipment: \(equipmentList)

        Return ONLY valid JSON array:
        [
          {"name": "Exercise Name", "reason": "Brief reason why it's a good swap"}
        ]
        """
    }

    static func weeklyReview(data: String) -> String {
        """
        You are a supportive, knowledgeable strength coach reviewing a week of training.

        Workout Data:
        \(data)

        Provide:
        1. **Highlights**: What went well (be specific, reference actual numbers)
        2. **Opportunities**: 1-2 actionable suggestions for next week
        3. **Motivation**: End with genuine encouragement

        Tone: Positive, specific, actionable. Like a coach who's been watching your progress.
        Keep under 200 words.
        """
    }

    static func weightSuggestions(records: String) -> String {
        """
        Analyze these recent lifts and suggest progressive overload targets.

        Recent PRs:
        \(records)

        For each exercise, suggest:
        - Target weight for next session (conservative progression)
        - Rep range to aim for
        - Brief reasoning

        Use standard progressive overload principles:
        - 5-10% weight increase when hitting top of rep range
        - If struggling, suggest deload or rep focus

        Return as JSON array:
        [{"exercise": "name", "currentWeight": 0, "suggestedWeight": 0, "targetReps": 0, "reasoning": "brief explanation"}]
        """
    }
}

// MARK: - Response Types

struct ClaudeResponse: Codable {
    let content: [ContentBlock]

    struct ContentBlock: Codable {
        let text: String?
        let type: String
    }
}

struct FormCheckResponse {
    let rawText: String

    var cues: [String] {
        // Parse cues from response
        rawText.components(separatedBy: "\n")
            .filter { $0.contains("1.") || $0.contains("2.") || $0.contains("3.") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

struct ExerciseAlternative: Codable, Identifiable {
    var id: String { name }
    let name: String
    let reason: String
}

struct WeeklyReview {
    let rawText: String

    var highlights: String {
        extractSection(marker: "**Highlights**") ?? rawText
    }

    var opportunities: String {
        extractSection(marker: "**Opportunities**") ?? ""
    }

    var motivation: String {
        extractSection(marker: "**Motivation**") ?? ""
    }

    private func extractSection(marker: String) -> String? {
        guard let range = rawText.range(of: marker) else { return nil }
        let afterMarker = String(rawText[range.upperBound...])
        if let nextMarker = afterMarker.range(of: "**") {
            return String(afterMarker[..<nextMarker.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return afterMarker.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WeightSuggestionResponse: Codable {
    let exercise: String
    let currentWeight: Double
    let suggestedWeight: Double
    let targetReps: Int
    let reasoning: String
}

struct ExerciseInfo {
    let rawText: String
    let exerciseName: String
}

// MARK: - Errors

enum AICoachError: LocalizedError {
    case apiKeyMissing
    case invalidResponse
    case emptyResponse
    case apiError(statusCode: Int)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "AI Coach API key is not configured"
        case .invalidResponse:
            return "Received an invalid response from AI Coach"
        case .emptyResponse:
            return "AI Coach returned an empty response"
        case .apiError(let statusCode):
            return "AI Coach API error (status: \(statusCode))"
        case .parsingError:
            return "Failed to parse AI Coach response"
        }
    }
}
