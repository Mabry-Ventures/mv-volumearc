// AICoachService.swift
// BeastMode
// Service for AI-powered coaching features using Claude API

import Foundation
import os

/// Service for generating AI-powered coaching insights
actor AICoachService {
    private let keychainService: KeychainService
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private var cachedResponses: [String: CachedResponse] = [:]
    private let cacheExpirationInterval: TimeInterval = 3600 // 1 hour

    struct CachedResponse {
        let response: String
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 3600
        }
    }

    init(apiKey: String? = nil) {
        self.keychainService = KeychainService.shared

        // If an API key is provided, store it securely
        if let apiKey = apiKey {
            keychainService.setAPIKey(apiKey)
        }
    }

    /// Get the API key from secure storage
    private var apiKey: String? {
        keychainService.getAPIKey()
    }

    /// Check if the service is configured with an API key
    var isConfigured: Bool {
        apiKey != nil
    }

    // MARK: - Weekly Review

    /// Generate an AI-powered weekly review
    func generateWeeklyReview(prompt: String) async throws -> String {
        try await makeRequest(prompt: prompt, maxTokens: 500)
    }

    // MARK: - Weight Progression Suggestion

    /// Generate weight progression suggestions for an exercise
    func suggestProgressiveOverload(
        for exerciseName: String,
        recentData: [AnalyticsDataPoint],
        currentTrend: ProgressTrend
    ) async throws -> WeightSuggestion {
        let dataString = recentData.suffix(10).map { point in
            "\(point.date.formatted(.dateTime.month().day())): \(Int(point.weight)) lbs × \(point.reps) reps"
        }.joined(separator: "\n")

        let prompt = """
        You are an expert strength coach analyzing lift data to suggest progressive overload.

        Exercise: \(exerciseName)
        Current Trend: \(currentTrend.description)

        Recent Performance:
        \(dataString)

        Based on progressive overload principles:
        - If consistently hitting 8+ reps, suggest 5-10% weight increase
        - If struggling (under 6 reps), suggest staying at current weight or slight decrease
        - For plateaus, suggest a deload week or rep scheme change

        Respond ONLY with valid JSON:
        {
            "suggestedWeight": <number>,
            "suggestedReps": <number>,
            "confidence": "<high|medium|low>",
            "reasoning": "<brief 1-2 sentence explanation>",
            "alternativeApproach": "<optional: if plateau, suggest a different strategy>"
        }
        """

        let response = try await makeRequest(prompt: prompt, maxTokens: 300)

        // Parse JSON response
        guard let data = response.data(using: .utf8) else {
            throw AIError.invalidResponse
        }

        // Try to extract JSON from the response (Claude may wrap it in text)
        let jsonString = extractJSON(from: response)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIError.invalidResponse
        }

        var suggestion = try JSONDecoder().decode(WeightSuggestion.self, from: jsonData)
        suggestion.exerciseName = exerciseName
        return suggestion
    }

    // MARK: - Motivational Messages

    /// Generate a motivational message based on context
    func generateMotivation(
        streakDays: Int,
        recentPRs: Int,
        workoutsThisWeek: Int
    ) async throws -> String {
        let prompt = """
        You are a supportive, energetic fitness coach. Generate a brief (2-3 sentences) motivational message.

        Context:
        - Current workout streak: \(streakDays) days
        - PRs this month: \(recentPRs)
        - Workouts this week: \(workoutsThisWeek)

        Be encouraging but not over-the-top. Reference their actual progress.
        """

        return try await makeRequest(prompt: prompt, maxTokens: 100)
    }

    // MARK: - Private Helpers

    private func makeRequest(prompt: String, maxTokens: Int, useCache: Bool = true) async throws -> String {
        // Check cache first if enabled
        let cacheKey = prompt.hashValue.description
        if useCache, let cached = cachedResponses[cacheKey], !cached.isExpired {
            Logger.network.debug("Returning cached AI response")
            return cached.response
        }

        guard let apiKey else {
            Logger.network.info("No API key configured, returning mock response")
            // Return mock response for development/testing
            return generateMockResponse(for: prompt)
        }

        // Check network connectivity
        let networkMonitor = await NetworkMonitor.shared
        guard await networkMonitor.isConnected else {
            Logger.network.warning("Offline - cannot make AI request")

            // Return cached response if available, even if expired
            if let cached = cachedResponses[cacheKey] {
                Logger.network.info("Returning stale cached response due to offline status")
                return cached.response
            }

            throw AIError.offline
        }

        guard let url = URL(string: baseURL) else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.network.debug("Making AI API request")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                Logger.network.error("AI API error: \(httpResponse.statusCode)")
                CrashReporter.shared.recordNonFatalError(
                    "AI API Error",
                    properties: ["statusCode": httpResponse.statusCode]
                )
                throw AIError.apiError(statusCode: httpResponse.statusCode)
            }

            let apiResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

            guard let content = apiResponse.content.first?.text else {
                throw AIError.emptyResponse
            }

            // Cache successful response
            cachedResponses[cacheKey] = CachedResponse(response: content, timestamp: Date())

            Logger.network.debug("AI request successful")
            return content

        } catch let error as URLError {
            Logger.network.error("Network error during AI request: \(error.localizedDescription)")

            // Return cached response on network error
            if let cached = cachedResponses[cacheKey] {
                Logger.network.info("Returning cached response due to network error")
                return cached.response
            }

            throw AIError.networkError(error)
        }
    }

    /// Clear cached responses
    func clearCache() {
        cachedResponses.removeAll()
    }

    private func extractJSON(from text: String) -> String {
        // Try to find JSON object in the response
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }

    private func generateMockResponse(for prompt: String) -> String {
        // Return mock responses for development
        if prompt.contains("weekly review") || prompt.contains("Weekly Review") {
            return """
            **💪 Wins This Week**
            - Hit a new PR on Bench Press at 205 lbs!
            - Maintained your 7-day workout streak

            **📈 Progress Check**
            Your upper body lifts are showing solid progression. Squat volume has plateaued - consider adding pause reps.

            **🎯 Focus for Next Week**
            Try adding one more set to your squat sessions to break through the plateau.

            **🔥 Coach's Note**
            You're building real momentum. Keep showing up and the gains will follow!
            """
        } else if prompt.contains("progressive overload") {
            return """
            {
                "suggestedWeight": 190,
                "suggestedReps": 6,
                "confidence": "high",
                "reasoning": "You've been hitting 8+ reps consistently at 185 lbs. Time to increase the weight and work back up to 8 reps.",
                "alternativeApproach": null
            }
            """
        } else {
            return "Keep pushing! Your consistency is paying off. 💪"
        }
    }
}

// MARK: - API Response Types

private struct ClaudeResponse: Codable {
    let content: [ContentBlock]

    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }
}

// MARK: - Errors

enum AIError: Error, LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case emptyResponse
    case apiError(statusCode: Int)
    case decodingError(Error)
    case offline
    case networkError(URLError)
    case rateLimited
    case timeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from AI service"
        case .emptyResponse:
            return "Empty response from AI service"
        case .apiError(let code):
            return "API error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .offline:
            return "You're offline. AI features require an internet connection."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited:
            return "Too many requests. Please try again in a few minutes."
        case .timeout:
            return "Request timed out. Please try again."
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .offline, .networkError, .rateLimited, .timeout:
            return true
        default:
            return false
        }
    }
}

// MARK: - Prompts

enum Prompts {
    /// Generate a weekly review prompt
    static func weeklyReview(
        workoutData: String,
        bodyWeightTrend: String?,
        progressingExercises: [String],
        plateauExercises: [String],
        streakDays: Int
    ) -> String {
        var prompt = """
        You are a supportive, knowledgeable strength coach reviewing a week of training.
        Your tone is encouraging but honest—like a coach who genuinely wants to see improvement.

        ## This Week's Data
        \(workoutData)

        ## Progress Summary
        - Current streak: \(streakDays) days
        - Exercises showing progress: \(progressingExercises.isEmpty ? "None yet" : progressingExercises.joined(separator: ", "))
        - Exercises at plateau: \(plateauExercises.isEmpty ? "None" : plateauExercises.joined(separator: ", "))
        """

        if let weight = bodyWeightTrend {
            prompt += "\n- Body weight trend: \(weight)"
        }

        prompt += """

        ## Your Task
        Provide a motivating weekly review with these sections:

        **💪 Wins This Week**
        Celebrate 2-3 specific achievements. Reference actual numbers from the data.

        **📈 Progress Check**
        Comment on the progression trends. If there are plateaus, acknowledge them constructively.

        **🎯 Focus for Next Week**
        Give 1-2 specific, actionable suggestions based on the data.

        **🔥 Coach's Note**
        End with personalized encouragement (2-3 sentences max).

        Keep the total response under 250 words. Be specific, not generic.
        """

        return prompt
    }

    /// Generate a plateau breakthrough prompt
    static func plateauBreakthrough(
        exerciseName: String,
        currentWeight: Double,
        currentReps: Int,
        weeksAtPlateau: Int
    ) -> String {
        """
        You are an expert strength coach helping someone break through a plateau.

        Exercise: \(exerciseName)
        Current: \(Int(currentWeight)) lbs × \(currentReps) reps
        Plateau duration: \(weeksAtPlateau) weeks

        Provide 3 specific strategies to break through this plateau. Each strategy should include:
        1. The technique name
        2. How to implement it
        3. Expected timeline to see results

        Be practical and specific. Avoid generic advice.
        """
    }
}
