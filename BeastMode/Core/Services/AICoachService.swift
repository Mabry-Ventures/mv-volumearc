// AICoachService.swift
// BeastMode
// Service for AI-powered coaching features using Claude API

import Foundation
import os

// MARK: - Configuration

/// Configuration for AI service request behavior
struct AIRequestConfiguration {
    /// Timeout duration for requests (default: 30 seconds)
    var timeout: TimeInterval = 30

    /// Maximum number of retry attempts for transient errors
    var maxRetryAttempts: Int = 3

    /// Base delay for exponential backoff (default: 1 second)
    var baseRetryDelay: TimeInterval = 1.0

    /// Maximum delay between retries (default: 30 seconds)
    var maxRetryDelay: TimeInterval = 30.0

    /// Whether to use cached responses
    var useCache: Bool = true

    /// Default configuration
    static let `default` = AIRequestConfiguration()

    /// Configuration with longer timeout for complex requests
    static let extended = AIRequestConfiguration(
        timeout: 60,
        maxRetryAttempts: 5,
        baseRetryDelay: 2.0,
        maxRetryDelay: 60.0
    )
}

/// Service for generating AI-powered coaching insights
actor AICoachService {
    private let keychainService: KeychainService
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private var cachedResponses: [String: CachedResponse] = [:]
    private let cacheExpirationInterval: TimeInterval = 3600 // 1 hour

    /// Default request configuration
    private var defaultConfiguration: AIRequestConfiguration = .default

    /// Track rate limit state
    private var rateLimitResetTime: Date?
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures: Int = 5

    struct CachedResponse {
        let response: String
        let timestamp: Date
        let expirationInterval: TimeInterval

        init(response: String, timestamp: Date = Date(), expirationInterval: TimeInterval = 3600) {
            self.response = response
            self.timestamp = timestamp
            self.expirationInterval = expirationInterval
        }

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > expirationInterval
        }
    }

    init(apiKey: String? = nil, configuration: AIRequestConfiguration = .default) {
        self.keychainService = KeychainService.shared
        self.defaultConfiguration = configuration

        // If an API key is provided, store it securely
        if let apiKey = apiKey {
            keychainService.setAPIKey(apiKey)
        }
    }

    /// Update the default configuration
    func updateConfiguration(_ configuration: AIRequestConfiguration) {
        self.defaultConfiguration = configuration
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
            throw AIError.invalidResponse(reason: "Response is not valid UTF-8")
        }

        // Try to extract JSON from the response (Claude may wrap it in text)
        let jsonString = extractJSON(from: response)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIError.invalidResponse(reason: "Extracted JSON is not valid UTF-8")
        }

        do {
            var suggestion = try JSONDecoder().decode(WeightSuggestion.self, from: jsonData)
            suggestion.exerciseName = exerciseName
            return suggestion
        } catch let error as DecodingError {
            throw AIError.decodingError(error, context: describeDecodingError(error))
        }
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

    private func makeRequest(
        prompt: String,
        maxTokens: Int,
        useCache: Bool = true,
        configuration: AIRequestConfiguration? = nil
    ) async throws -> String {
        let config = configuration ?? defaultConfiguration

        // Check cache first if enabled
        let cacheKey = prompt.hashValue.description
        if useCache && config.useCache, let cached = cachedResponses[cacheKey], !cached.isExpired {
            Logger.network.debug("Returning cached AI response")
            return cached.response
        }

        guard let apiKey else {
            #if DEBUG
            Logger.network.info("No API key configured, returning mock response (DEBUG mode)")
            return generateMockResponse(for: prompt)
            #else
            Logger.network.warning("No API key configured - AI features unavailable in production")
            throw AIError.noAPIKey
            #endif
        }

        // Check if we're in a rate limit cooldown period
        if let resetTime = rateLimitResetTime, Date() < resetTime {
            let waitTime = resetTime.timeIntervalSinceNow
            Logger.network.warning("Rate limited, waiting \(Int(waitTime)) seconds")

            // Return cached response if available during rate limit
            if let cached = cachedResponses[cacheKey] {
                Logger.network.info("Returning cached response during rate limit")
                return cached.response
            }

            throw AIError.rateLimited(retryAfter: waitTime)
        }

        // Check for circuit breaker (too many consecutive failures)
        if consecutiveFailures >= maxConsecutiveFailures {
            Logger.network.error("Circuit breaker open - too many consecutive failures")
            throw AIError.circuitBreakerOpen(failures: consecutiveFailures)
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

        // Execute request with retry logic
        return try await executeWithRetry(
            prompt: prompt,
            maxTokens: maxTokens,
            cacheKey: cacheKey,
            configuration: config
        )
    }

    /// Execute request with exponential backoff retry logic
    private func executeWithRetry(
        prompt: String,
        maxTokens: Int,
        cacheKey: String,
        configuration: AIRequestConfiguration
    ) async throws -> String {
        var lastError: Error?

        for attempt in 0..<configuration.maxRetryAttempts {
            do {
                let result = try await executeSingleRequest(
                    prompt: prompt,
                    maxTokens: maxTokens,
                    timeout: configuration.timeout
                )

                // Reset failure counter on success
                consecutiveFailures = 0
                rateLimitResetTime = nil

                // Cache successful response
                cachedResponses[cacheKey] = CachedResponse(response: result, timestamp: Date())
                Logger.network.debug("AI request successful on attempt \(attempt + 1)")

                return result

            } catch let error as AIError {
                lastError = error

                // Determine if we should retry based on error type
                guard error.isRetryable else {
                    consecutiveFailures += 1
                    throw error
                }

                // Handle rate limiting specifically
                if case .rateLimited(let retryAfter) = error {
                    rateLimitResetTime = Date().addingTimeInterval(retryAfter ?? 60)
                }

                // Calculate exponential backoff delay
                let delay = calculateBackoffDelay(
                    attempt: attempt,
                    baseDelay: configuration.baseRetryDelay,
                    maxDelay: configuration.maxRetryDelay
                )

                Logger.network.info("Retry attempt \(attempt + 1)/\(configuration.maxRetryAttempts) after \(String(format: "%.1f", delay))s delay")

                // Wait before retrying
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            } catch let error as URLError {
                lastError = error

                // URLError timeout should be retried
                if error.code == .timedOut {
                    let delay = calculateBackoffDelay(
                        attempt: attempt,
                        baseDelay: configuration.baseRetryDelay,
                        maxDelay: configuration.maxRetryDelay
                    )
                    Logger.network.info("Timeout, retrying after \(String(format: "%.1f", delay))s delay")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    consecutiveFailures += 1

                    // Return cached response on network error
                    if let cached = cachedResponses[cacheKey] {
                        Logger.network.info("Returning cached response due to network error")
                        return cached.response
                    }

                    throw AIError.networkError(error)
                }
            } catch {
                lastError = error
                consecutiveFailures += 1
                throw error
            }
        }

        // All retries exhausted
        consecutiveFailures += 1

        // Try to return cached response as last resort
        if let cached = cachedResponses[cacheKey] {
            Logger.network.info("All retries exhausted, returning cached response")
            return cached.response
        }

        throw AIError.maxRetriesExceeded(
            attempts: configuration.maxRetryAttempts,
            lastError: lastError
        )
    }

    /// Execute a single API request
    private func executeSingleRequest(
        prompt: String,
        maxTokens: Int,
        timeout: TimeInterval
    ) async throws -> String {
        guard let apiKey else {
            throw AIError.noAPIKey
        }

        guard let url = URL(string: baseURL) else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = timeout

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.network.debug("Making AI API request with timeout \(timeout)s")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse(reason: "Response is not HTTP")
        }

        // Handle specific HTTP status codes
        switch httpResponse.statusCode {
        case 200:
            break // Success, continue processing

        case 429:
            // Rate limited - extract retry-after header if available
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) } ?? 60
            Logger.network.warning("Rate limited, retry after \(retryAfter)s")
            throw AIError.rateLimited(retryAfter: retryAfter)

        case 408, 504:
            // Timeout from server
            Logger.network.warning("Server timeout (status \(httpResponse.statusCode))")
            throw AIError.timeout(duration: timeout)

        case 500, 502, 503:
            // Server errors - retryable
            Logger.network.error("Server error: \(httpResponse.statusCode)")
            throw AIError.serverError(statusCode: httpResponse.statusCode)

        case 400:
            // Bad request - parse error message
            let errorMessage = parseErrorMessage(from: data)
            Logger.network.error("Bad request: \(errorMessage ?? "unknown")")
            throw AIError.badRequest(message: errorMessage)

        case 401:
            Logger.network.error("Authentication failed - invalid API key")
            throw AIError.authenticationFailed

        case 403:
            Logger.network.error("Access forbidden")
            throw AIError.forbidden

        default:
            Logger.network.error("AI API error: \(httpResponse.statusCode)")
            CrashReporter.shared.recordNonFatalError(
                "AI API Error",
                properties: ["statusCode": httpResponse.statusCode]
            )
            throw AIError.apiError(statusCode: httpResponse.statusCode)
        }

        // Parse and validate response
        return try parseAndValidateResponse(data: data)
    }

    /// Parse and validate the API response
    private func parseAndValidateResponse(data: Data) throws -> String {
        // Validate that data is not empty
        guard !data.isEmpty else {
            throw AIError.emptyResponse
        }

        // Try to parse as JSON first to validate structure
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Check if it's a partial/streaming response
            if let partialString = String(data: data, encoding: .utf8) {
                if partialString.contains("event:") || partialString.contains("data:") {
                    throw AIError.unexpectedStreamingResponse(partial: partialString)
                }
            }
            throw AIError.malformedJSON(dataPreview: String(data: data.prefix(200), encoding: .utf8))
        }

        // Validate required fields exist
        guard json["content"] != nil else {
            // Check for error response
            if let errorInfo = json["error"] as? [String: Any] {
                let errorType = errorInfo["type"] as? String ?? "unknown"
                let errorMessage = errorInfo["message"] as? String ?? "Unknown error"
                throw AIError.apiErrorResponse(type: errorType, message: errorMessage)
            }
            throw AIError.invalidResponseStructure(missingField: "content")
        }

        // Decode using Codable for type safety
        let decoder = JSONDecoder()
        let apiResponse: ClaudeResponse

        do {
            apiResponse = try decoder.decode(ClaudeResponse.self, from: data)
        } catch let decodingError as DecodingError {
            throw AIError.decodingError(decodingError, context: describeDecodingError(decodingError))
        }

        // Validate content array
        guard !apiResponse.content.isEmpty else {
            throw AIError.emptyContentArray
        }

        // Extract text content
        let textBlocks = apiResponse.content.compactMap { $0.text }
        guard !textBlocks.isEmpty else {
            // Check if there are other content types
            let contentTypes = apiResponse.content.map { $0.type }
            throw AIError.noTextContent(foundTypes: contentTypes)
        }

        // Join all text blocks (handles multi-part responses)
        let fullContent = textBlocks.joined(separator: "\n")

        // Validate content is not just whitespace
        guard !fullContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyResponse
        }

        // Check for truncation indicator
        if let stopReason = apiResponse.stopReason, stopReason == "max_tokens" {
            Logger.network.warning("Response was truncated due to max_tokens limit")
        }

        return fullContent
    }

    /// Calculate exponential backoff delay with jitter
    private func calculateBackoffDelay(
        attempt: Int,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval
    ) -> TimeInterval {
        // Exponential backoff: base * 2^attempt
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt))

        // Add jitter (random 0-25% of delay) to prevent thundering herd
        let jitter = Double.random(in: 0...0.25) * exponentialDelay

        // Cap at maximum delay
        return min(exponentialDelay + jitter, maxDelay)
    }

    /// Parse error message from API error response
    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data, encoding: .utf8)
        }
        return message
    }

    /// Describe a DecodingError for better error messages
    private func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "Missing value for \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .dataCorrupted(let context):
            return "Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error"
        }
    }

    /// Reset the circuit breaker (call after successful recovery)
    func resetCircuitBreaker() {
        consecutiveFailures = 0
        rateLimitResetTime = nil
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
        // Return mock responses for development/testing only
        // These responses simulate what the AI would return
        if prompt.contains("weekly review") || prompt.contains("Weekly Review") {
            return """
            **💪 Wins This Week** _(Demo)_
            - Hit a new PR on Bench Press at 205 lbs!
            - Maintained your 7-day workout streak

            **📈 Progress Check**
            Your upper body lifts are showing solid progression. Squat volume has plateaued - consider adding pause reps.

            **🎯 Focus for Next Week**
            Try adding one more set to your squat sessions to break through the plateau.

            **🔥 Coach's Note**
            You're building real momentum. Keep showing up and the gains will follow!

            _Note: This is demo content. Configure your API key for personalized AI coaching._
            """
        } else if prompt.contains("progressive overload") {
            return """
            {
                "suggestedWeight": 190,
                "suggestedReps": 6,
                "confidence": "high",
                "reasoning": "Demo: You've been hitting 8+ reps consistently. Consider increasing weight.",
                "alternativeApproach": null
            }
            """
        } else {
            return "Keep pushing! Your consistency is paying off. 💪 (Demo response - configure API key for personalized coaching)"
        }
    }
}

// MARK: - API Response Types

private struct ClaudeResponse: Codable {
    let id: String?
    let type: String?
    let role: String?
    let content: [ContentBlock]
    let model: String?
    let stopReason: String?
    let stopSequence: String?
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }

    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }

    struct Usage: Codable {
        let inputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

// MARK: - Errors

/// Comprehensive error types for AI service operations
enum AIError: Error, LocalizedError, Equatable {
    // MARK: - Configuration Errors
    case noAPIKey
    case invalidURL

    // MARK: - Network Errors
    case offline
    case networkError(URLError)
    case timeout(duration: TimeInterval)

    // MARK: - HTTP Errors
    case rateLimited(retryAfter: TimeInterval?)
    case authenticationFailed
    case forbidden
    case badRequest(message: String?)
    case serverError(statusCode: Int)
    case apiError(statusCode: Int)

    // MARK: - Response Parsing Errors
    case invalidResponse(reason: String)
    case emptyResponse
    case emptyContentArray
    case malformedJSON(dataPreview: String?)
    case unexpectedStreamingResponse(partial: String)
    case invalidResponseStructure(missingField: String)
    case noTextContent(foundTypes: [String])
    case apiErrorResponse(type: String, message: String)
    case decodingError(DecodingError, context: String)

    // MARK: - Retry/Circuit Breaker Errors
    case maxRetriesExceeded(attempts: Int, lastError: Error?)
    case circuitBreakerOpen(failures: Int)

    // MARK: - Equatable Conformance

    static func == (lhs: AIError, rhs: AIError) -> Bool {
        switch (lhs, rhs) {
        case (.noAPIKey, .noAPIKey),
             (.invalidURL, .invalidURL),
             (.offline, .offline),
             (.authenticationFailed, .authenticationFailed),
             (.forbidden, .forbidden),
             (.emptyResponse, .emptyResponse),
             (.emptyContentArray, .emptyContentArray):
            return true
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return lhsError.code == rhsError.code
        case (.timeout(let lhsDuration), .timeout(let rhsDuration)):
            return lhsDuration == rhsDuration
        case (.rateLimited(let lhsRetry), .rateLimited(let rhsRetry)):
            return lhsRetry == rhsRetry
        case (.badRequest(let lhsMsg), .badRequest(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
        case (.apiError(let lhsCode), .apiError(let rhsCode)):
            return lhsCode == rhsCode
        case (.invalidResponse(let lhsReason), .invalidResponse(let rhsReason)):
            return lhsReason == rhsReason
        case (.malformedJSON(let lhsPreview), .malformedJSON(let rhsPreview)):
            return lhsPreview == rhsPreview
        case (.unexpectedStreamingResponse(let lhsPartial), .unexpectedStreamingResponse(let rhsPartial)):
            return lhsPartial == rhsPartial
        case (.invalidResponseStructure(let lhsField), .invalidResponseStructure(let rhsField)):
            return lhsField == rhsField
        case (.noTextContent(let lhsTypes), .noTextContent(let rhsTypes)):
            return lhsTypes == rhsTypes
        case (.apiErrorResponse(let lhsType, let lhsMsg), .apiErrorResponse(let rhsType, let rhsMsg)):
            return lhsType == rhsType && lhsMsg == rhsMsg
        case (.decodingError(_, let lhsContext), .decodingError(_, let rhsContext)):
            return lhsContext == rhsContext
        case (.maxRetriesExceeded(let lhsAttempts, _), .maxRetriesExceeded(let rhsAttempts, _)):
            return lhsAttempts == rhsAttempts
        case (.circuitBreakerOpen(let lhsFailures), .circuitBreakerOpen(let rhsFailures)):
            return lhsFailures == rhsFailures
        default:
            return false
        }
    }

    // MARK: - Error Descriptions

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return String(localized: "No API key configured. Please add your Claude API key in settings.")
        case .invalidURL:
            return String(localized: "Invalid API URL configuration.")
        case .offline:
            return String(localized: "You're offline. AI features require an internet connection.")
        case .networkError(let error):
            return String(localized: "Network error: \(error.localizedDescription)")
        case .timeout(let duration):
            return String(localized: "Request timed out after \(Int(duration)) seconds. Please try again.")
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return String(localized: "Too many requests. Please try again in \(Int(seconds)) seconds.")
            }
            return String(localized: "Too many requests. Please try again in a few minutes.")
        case .authenticationFailed:
            return String(localized: "Authentication failed. Please check your API key.")
        case .forbidden:
            return String(localized: "Access forbidden. Your API key may not have the required permissions.")
        case .badRequest(let message):
            return String(localized: "Invalid request: \(message ?? "Unknown error")")
        case .serverError(let statusCode):
            return String(localized: "Server error (\(statusCode)). The AI service is temporarily unavailable.")
        case .apiError(let code):
            return String(localized: "API error: \(code)")
        case .invalidResponse(let reason):
            return String(localized: "Invalid response from AI service: \(reason)")
        case .emptyResponse:
            return String(localized: "The AI service returned an empty response.")
        case .emptyContentArray:
            return String(localized: "The AI response contained no content blocks.")
        case .malformedJSON(let preview):
            let previewText = preview.map { " Preview: \($0.prefix(50))..." } ?? ""
            return String(localized: "Received malformed JSON response.\(previewText)")
        case .unexpectedStreamingResponse:
            return String(localized: "Received unexpected streaming response format.")
        case .invalidResponseStructure(let missingField):
            return String(localized: "Invalid response structure: missing '\(missingField)' field.")
        case .noTextContent(let foundTypes):
            return String(localized: "No text content in response. Found content types: \(foundTypes.joined(separator: ", "))")
        case .apiErrorResponse(let type, let message):
            return String(localized: "API error (\(type)): \(message)")
        case .decodingError(_, let context):
            return String(localized: "Failed to decode response: \(context)")
        case .maxRetriesExceeded(let attempts, let lastError):
            let errorInfo = lastError.map { " Last error: \($0.localizedDescription)" } ?? ""
            return String(localized: "Request failed after \(attempts) attempts.\(errorInfo)")
        case .circuitBreakerOpen(let failures):
            return String(localized: "Service temporarily disabled after \(failures) consecutive failures. Please try again later.")
        }
    }

    // MARK: - Error Classification

    /// Whether this error is potentially recoverable with a retry
    var isRecoverable: Bool {
        switch self {
        case .offline, .networkError, .timeout, .rateLimited, .serverError:
            return true
        case .maxRetriesExceeded, .circuitBreakerOpen:
            return true // Can recover after waiting
        default:
            return false
        }
    }

    /// Whether this error should trigger a retry attempt
    var isRetryable: Bool {
        switch self {
        case .timeout, .serverError, .rateLimited:
            return true
        case .networkError(let urlError):
            // Retry on temporary network issues
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    /// Whether this error indicates an authentication/configuration issue
    var isConfigurationError: Bool {
        switch self {
        case .noAPIKey, .authenticationFailed, .forbidden, .invalidURL:
            return true
        default:
            return false
        }
    }

    /// Suggested user action for this error
    var suggestedAction: String {
        switch self {
        case .noAPIKey:
            return String(localized: "Go to Settings to add your API key.")
        case .authenticationFailed:
            return String(localized: "Check your API key in Settings.")
        case .forbidden:
            return String(localized: "Verify your API key has the correct permissions.")
        case .offline:
            return String(localized: "Check your internet connection.")
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return String(localized: "Wait \(Int(seconds)) seconds before trying again.")
            }
            return String(localized: "Wait a few minutes before trying again.")
        case .timeout, .serverError, .networkError:
            return String(localized: "Try again in a moment.")
        case .circuitBreakerOpen:
            return String(localized: "Wait a few minutes for the service to recover.")
        case .maxRetriesExceeded:
            return String(localized: "Check your connection and try again later.")
        default:
            return String(localized: "Try again or contact support if the problem persists.")
        }
    }

    /// HTTP status code if applicable
    var statusCode: Int? {
        switch self {
        case .rateLimited:
            return 429
        case .authenticationFailed:
            return 401
        case .forbidden:
            return 403
        case .badRequest:
            return 400
        case .serverError(let code):
            return code
        case .apiError(let code):
            return code
        default:
            return nil
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
