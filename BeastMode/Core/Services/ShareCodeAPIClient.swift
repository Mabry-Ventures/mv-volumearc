// ShareCodeAPIClient.swift
// BeastMode
// API client for managing plan share codes with backend service

import Foundation
import os

// MARK: - Share Code API Configuration

/// Configuration for the Share Code API
enum ShareCodeAPIConfiguration {
    /// Base URL for the share code API
    static let baseURL = "https://api.beastmode.app/v1"

    /// Default expiration period in days
    static let defaultExpirationDays: Int = 30

    /// Share code length
    static let codeLength: Int = 8

    /// Maximum codes per user
    static let maxCodesPerUser: Int = 50

    /// Rate limit window in seconds
    static let rateLimitWindow: TimeInterval = 60

    /// Maximum requests per rate limit window
    static let maxRequestsPerWindow: Int = 30
}

// MARK: - Request Models

/// Request to create a new share code
struct ShareCodeCreateRequest: Codable {
    let planData: ShareablePlan
    let expirationDays: Int?
    let authorName: String?

    init(plan: ShareablePlan, expirationDays: Int? = nil, authorName: String? = nil) {
        self.planData = plan
        self.expirationDays = expirationDays
        self.authorName = authorName
    }
}

// MARK: - Response Models

/// Response from creating a share code
struct ShareCodeCreateResponse: Codable {
    let code: String
    let expiresAt: Date
    let planId: String
    let createdAt: Date
}

/// Response from retrieving a share code
struct ShareCodeRetrieveResponse: Codable {
    let code: String
    let planData: ShareablePlan
    let expiresAt: Date
    let authorName: String?
    let downloadCount: Int
    let createdAt: Date
    let isExpired: Bool
}

/// Response from revoking a share code
struct ShareCodeRevokeResponse: Codable {
    let code: String
    let revoked: Bool
    let revokedAt: Date
}

/// Generic API error response
struct ShareCodeAPIErrorResponse: Codable {
    let error: String
    let code: String
    let message: String
}

// MARK: - Local Storage Models

/// Locally stored share code for user management
struct LocalShareCode: Codable, Identifiable, Equatable {
    let id: UUID
    let code: String
    let planId: UUID
    let planName: String
    let createdAt: Date
    let expiresAt: Date
    var isRevoked: Bool

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isActive: Bool {
        !isExpired && !isRevoked
    }

    var daysUntilExpiration: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expiresAt)
        return max(0, components.day ?? 0)
    }

    var formattedExpiration: String {
        if isExpired {
            return "Expired"
        }
        let days = daysUntilExpiration
        if days == 0 {
            return "Expires today"
        } else if days == 1 {
            return "Expires tomorrow"
        } else {
            return "Expires in \(days) days"
        }
    }
}

// MARK: - API Errors

/// Errors from the Share Code API
enum ShareCodeAPIError: LocalizedError {
    case invalidCode
    case codeExpired
    case codeNotFound
    case codeAlreadyRevoked
    case rateLimited(retryAfter: TimeInterval)
    case maxCodesReached
    case networkError(Error)
    case serverError(statusCode: Int, message: String)
    case decodingError(Error)
    case encodingError(Error)
    case unauthorized
    case invalidResponse
    case offline
    case mockModeOnly

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "The share code format is invalid"
        case .codeExpired:
            return "This share code has expired"
        case .codeNotFound:
            return "Share code not found"
        case .codeAlreadyRevoked:
            return "This share code has already been revoked"
        case .rateLimited(let retryAfter):
            return "Too many requests. Please try again in \(Int(retryAfter)) seconds"
        case .maxCodesReached:
            return "Maximum number of share codes reached. Please revoke some existing codes"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(_, let message):
            return "Server error: \(message)"
        case .decodingError:
            return "Failed to parse server response"
        case .encodingError:
            return "Failed to prepare request data"
        case .unauthorized:
            return "Authentication required. Please sign in"
        case .invalidResponse:
            return "Invalid response from server"
        case .offline:
            return "No internet connection. Please check your network"
        case .mockModeOnly:
            return "Share codes require backend service (mock mode active)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .codeExpired:
            return "Request a new share code from the plan owner"
        case .rateLimited:
            return "Wait a moment before trying again"
        case .maxCodesReached:
            return "Go to Settings > Share Codes to manage your existing codes"
        case .offline:
            return "Connect to the internet and try again"
        default:
            return nil
        }
    }
}

// MARK: - Share Code API Client

/// Client for managing workout plan share codes
/// Supports both live API and mock mode for development/testing
actor ShareCodeAPIClient {

    // MARK: - Properties

    private let session: URLSession
    private let baseURL: String
    private let useMockMode: Bool

    // Rate limiting
    private var requestTimestamps: [Date] = []

    // Local storage
    private let localStorageKey = "com.beastmode.shareCodes"
    private var cachedLocalCodes: [LocalShareCode]?

    // Mock data storage (for development)
    private var mockCodes: [String: ShareCodeRetrieveResponse] = [:]

    // MARK: - Initialization

    /// Initialize the share code API client
    /// - Parameters:
    ///   - session: URLSession for network requests (defaults to shared)
    ///   - baseURL: Base URL for API (defaults to production)
    ///   - useMockMode: If true, uses mock responses instead of real API
    init(
        session: URLSession = .shared,
        baseURL: String = ShareCodeAPIConfiguration.baseURL,
        useMockMode: Bool = false
    ) {
        self.session = session
        self.baseURL = baseURL

        #if DEBUG
        // In debug builds, check if we should use mock mode
        self.useMockMode = useMockMode || AppConfiguration.useMockData
        #else
        self.useMockMode = useMockMode
        #endif

        // Pre-populate mock data for testing
        if self.useMockMode {
            setupMockData()
        }
    }

    // MARK: - Public API

    /// Create a share code for a workout plan
    /// - Parameters:
    ///   - plan: The shareable plan data
    ///   - expirationDays: Days until expiration (defaults to 30)
    ///   - authorName: Optional author name to display
    ///   - planId: UUID of the local plan for tracking
    ///   - planName: Name of the plan for local display
    /// - Returns: The created share code response
    func createShareCode(
        for plan: ShareablePlan,
        expirationDays: Int = ShareCodeAPIConfiguration.defaultExpirationDays,
        authorName: String? = nil,
        planId: UUID,
        planName: String
    ) async throws -> ShareCodeCreateResponse {
        Logger.network.info("Creating share code for plan: \(planName)")

        try checkRateLimit()

        if useMockMode {
            return try await createMockShareCode(
                plan: plan,
                expirationDays: expirationDays,
                authorName: authorName,
                planId: planId,
                planName: planName
            )
        }

        // Build request
        let request = ShareCodeCreateRequest(
            plan: plan,
            expirationDays: expirationDays,
            authorName: authorName
        )

        let urlRequest = try buildRequest(
            endpoint: "/codes",
            method: "POST",
            body: request
        )

        // Execute request
        let (data, response) = try await executeRequest(urlRequest)

        // Parse response
        let createResponse: ShareCodeCreateResponse = try decodeResponse(data, response: response)

        // Store locally for user management
        let localCode = LocalShareCode(
            id: UUID(),
            code: createResponse.code,
            planId: planId,
            planName: planName,
            createdAt: createResponse.createdAt,
            expiresAt: createResponse.expiresAt,
            isRevoked: false
        )

        try await saveLocalCode(localCode)

        Logger.network.info("Share code created successfully: \(createResponse.code)")
        return createResponse
    }

    /// Retrieve plan data by share code
    /// - Parameter code: The 8-character share code
    /// - Returns: The share code response with plan data
    func retrieveByCode(_ code: String) async throws -> ShareCodeRetrieveResponse {
        let normalizedCode = normalizeCode(code)

        Logger.network.info("Retrieving plan for share code: \(normalizedCode)")

        guard isValidCodeFormat(normalizedCode) else {
            throw ShareCodeAPIError.invalidCode
        }

        try checkRateLimit()

        if useMockMode {
            return try retrieveMockShareCode(normalizedCode)
        }

        // Build request
        let urlRequest = try buildRequest(
            endpoint: "/codes/\(normalizedCode)",
            method: "GET"
        )

        // Execute request
        let (data, response) = try await executeRequest(urlRequest)

        // Parse response
        let retrieveResponse: ShareCodeRetrieveResponse = try decodeResponse(data, response: response)

        // Check if expired
        if retrieveResponse.isExpired {
            throw ShareCodeAPIError.codeExpired
        }

        Logger.network.info("Successfully retrieved plan for code: \(normalizedCode)")
        return retrieveResponse
    }

    /// Revoke a share code (makes it unusable)
    /// - Parameter code: The 8-character share code to revoke
    /// - Returns: The revocation response
    func revokeCode(_ code: String) async throws -> ShareCodeRevokeResponse {
        let normalizedCode = normalizeCode(code)

        Logger.network.info("Revoking share code: \(normalizedCode)")

        guard isValidCodeFormat(normalizedCode) else {
            throw ShareCodeAPIError.invalidCode
        }

        try checkRateLimit()

        if useMockMode {
            return try await revokeMockShareCode(normalizedCode)
        }

        // Build request
        let urlRequest = try buildRequest(
            endpoint: "/codes/\(normalizedCode)",
            method: "DELETE"
        )

        // Execute request
        let (data, response) = try await executeRequest(urlRequest)

        // Parse response
        let revokeResponse: ShareCodeRevokeResponse = try decodeResponse(data, response: response)

        // Update local storage
        try await markLocalCodeAsRevoked(normalizedCode)

        Logger.network.info("Share code revoked successfully: \(normalizedCode)")
        return revokeResponse
    }

    // MARK: - Local Code Management

    /// Get all locally stored share codes created by the user
    func getLocalCodes() async -> [LocalShareCode] {
        if let cached = cachedLocalCodes {
            return cached
        }

        guard let data = UserDefaults.standard.data(forKey: localStorageKey),
              let codes = try? JSONDecoder().decode([LocalShareCode].self, from: data) else {
            return []
        }

        cachedLocalCodes = codes
        return codes
    }

    /// Get only active (non-expired, non-revoked) local codes
    func getActiveLocalCodes() async -> [LocalShareCode] {
        let codes = await getLocalCodes()
        return codes.filter { $0.isActive }
    }

    /// Get only expired local codes
    func getExpiredLocalCodes() async -> [LocalShareCode] {
        let codes = await getLocalCodes()
        return codes.filter { $0.isExpired }
    }

    /// Delete a local code record (does not revoke on server)
    func deleteLocalCode(_ code: String) async throws {
        var codes = await getLocalCodes()
        codes.removeAll { $0.code == code }
        try await saveLocalCodes(codes)
        Logger.network.info("Deleted local code record: \(code)")
    }

    /// Clean up expired codes from local storage
    func cleanupExpiredCodes() async throws {
        var codes = await getLocalCodes()
        let expiredCount = codes.filter { $0.isExpired }.count
        codes.removeAll { $0.isExpired && $0.isRevoked }
        try await saveLocalCodes(codes)
        Logger.network.info("Cleaned up \(expiredCount) expired codes from local storage")
    }

    // MARK: - Validation

    /// Check if a code has a valid format
    func isValidCodeFormat(_ code: String) -> Bool {
        let normalizedCode = normalizeCode(code)
        // Valid: 8 alphanumeric characters (no O, 0, I, 1 to avoid confusion)
        let validCharacters = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return normalizedCode.count == ShareCodeAPIConfiguration.codeLength &&
               normalizedCode.unicodeScalars.allSatisfy { validCharacters.contains($0) }
    }

    /// Normalize a share code (uppercase, trim whitespace)
    func normalizeCode(_ code: String) -> String {
        code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Helpers

    private func buildRequest<T: Encodable>(
        endpoint: String,
        method: String,
        body: T? = nil as String?
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL + endpoint) else {
            throw ShareCodeAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add auth token if available
        if let token = KeychainService.shared.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add body if provided
        if let body = body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    private func buildRequest(
        endpoint: String,
        method: String
    ) throws -> URLRequest {
        try buildRequest(endpoint: endpoint, method: method, body: nil as String?)
    }

    private func executeRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        recordRequestTimestamp()

        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw ShareCodeAPIError.offline
            }
            throw ShareCodeAPIError.networkError(error)
        } catch {
            throw ShareCodeAPIError.networkError(error)
        }
    }

    private func decodeResponse<T: Decodable>(_ data: Data, response: URLResponse) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareCodeAPIError.invalidResponse
        }

        // Handle error status codes
        switch httpResponse.statusCode {
        case 200...299:
            break // Success
        case 401:
            throw ShareCodeAPIError.unauthorized
        case 404:
            throw ShareCodeAPIError.codeNotFound
        case 410:
            throw ShareCodeAPIError.codeExpired
        case 429:
            let retryAfter = TimeInterval(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw ShareCodeAPIError.rateLimited(retryAfter: retryAfter)
        default:
            // Try to parse error response
            if let errorResponse = try? JSONDecoder().decode(ShareCodeAPIErrorResponse.self, from: data) {
                throw ShareCodeAPIError.serverError(statusCode: httpResponse.statusCode, message: errorResponse.message)
            }
            throw ShareCodeAPIError.serverError(statusCode: httpResponse.statusCode, message: "Unknown error")
        }

        // Decode success response
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Logger.network.error("Failed to decode response: \(error.localizedDescription)")
            throw ShareCodeAPIError.decodingError(error)
        }
    }

    // MARK: - Rate Limiting

    private func checkRateLimit() throws {
        let now = Date()
        let windowStart = now.addingTimeInterval(-ShareCodeAPIConfiguration.rateLimitWindow)

        // Remove old timestamps
        requestTimestamps.removeAll { $0 < windowStart }

        if requestTimestamps.count >= ShareCodeAPIConfiguration.maxRequestsPerWindow {
            let oldestInWindow = requestTimestamps.min() ?? now
            let retryAfter = oldestInWindow.addingTimeInterval(ShareCodeAPIConfiguration.rateLimitWindow).timeIntervalSince(now)
            throw ShareCodeAPIError.rateLimited(retryAfter: max(1, retryAfter))
        }
    }

    private func recordRequestTimestamp() {
        requestTimestamps.append(Date())
    }

    // MARK: - Local Storage

    private func saveLocalCode(_ code: LocalShareCode) async throws {
        var codes = await getLocalCodes()

        // Check max codes limit
        if codes.count >= ShareCodeAPIConfiguration.maxCodesPerUser {
            throw ShareCodeAPIError.maxCodesReached
        }

        codes.append(code)
        try await saveLocalCodes(codes)
    }

    private func saveLocalCodes(_ codes: [LocalShareCode]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(codes)
            UserDefaults.standard.set(data, forKey: localStorageKey)
            cachedLocalCodes = codes
        } catch {
            Logger.network.error("Failed to save local codes: \(error.localizedDescription)")
            throw ShareCodeAPIError.encodingError(error)
        }
    }

    private func markLocalCodeAsRevoked(_ code: String) async throws {
        var codes = await getLocalCodes()

        if let index = codes.firstIndex(where: { $0.code == code }) {
            codes[index].isRevoked = true
            try await saveLocalCodes(codes)
        }
    }

    // MARK: - Mock Implementation

    private func setupMockData() {
        // Pre-populate with some sample codes for testing
        let samplePlan = ShareablePlan(
            from: createMockWorkoutPlan()
        )

        let expiresAt = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

        mockCodes["TEST1234"] = ShareCodeRetrieveResponse(
            code: "TEST1234",
            planData: samplePlan,
            expiresAt: expiresAt,
            authorName: "Beast Mode",
            downloadCount: 42,
            createdAt: Date().addingTimeInterval(-86400 * 7),
            isExpired: false
        )

        // Add an expired code for testing
        mockCodes["EXPR5678"] = ShareCodeRetrieveResponse(
            code: "EXPR5678",
            planData: samplePlan,
            expiresAt: Date().addingTimeInterval(-86400),
            authorName: "Test User",
            downloadCount: 5,
            createdAt: Date().addingTimeInterval(-86400 * 31),
            isExpired: true
        )
    }

    private func createMockWorkoutPlan() -> WorkoutPlan {
        // Create a simple mock plan for testing
        let plan = WorkoutPlan(
            userId: UUID(),
            name: "Push Pull Legs",
            description: "Classic 6-day split for muscle building",
            daysPerWeek: 6,
            difficulty: .intermediate,
            targetGoal: .hypertrophy
        )
        plan.authorName = "Beast Mode"
        return plan
    }

    private func createMockShareCode(
        plan: ShareablePlan,
        expirationDays: Int,
        authorName: String?,
        planId: UUID,
        planName: String
    ) async throws -> ShareCodeCreateResponse {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Generate code
        let code = generateMockCode()
        let now = Date()
        let expiresAt = Calendar.current.date(byAdding: .day, value: expirationDays, to: now) ?? now

        // Store in mock storage
        mockCodes[code] = ShareCodeRetrieveResponse(
            code: code,
            planData: plan,
            expiresAt: expiresAt,
            authorName: authorName,
            downloadCount: 0,
            createdAt: now,
            isExpired: false
        )

        // Store locally
        let localCode = LocalShareCode(
            id: UUID(),
            code: code,
            planId: planId,
            planName: planName,
            createdAt: now,
            expiresAt: expiresAt,
            isRevoked: false
        )
        try await saveLocalCode(localCode)

        Logger.network.info("[MOCK] Created share code: \(code)")

        return ShareCodeCreateResponse(
            code: code,
            expiresAt: expiresAt,
            planId: planId.uuidString,
            createdAt: now
        )
    }

    private func retrieveMockShareCode(_ code: String) throws -> ShareCodeRetrieveResponse {
        guard let response = mockCodes[code] else {
            throw ShareCodeAPIError.codeNotFound
        }

        if response.isExpired {
            throw ShareCodeAPIError.codeExpired
        }

        Logger.network.info("[MOCK] Retrieved share code: \(code)")
        return response
    }

    private func revokeMockShareCode(_ code: String) async throws -> ShareCodeRevokeResponse {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

        guard mockCodes[code] != nil else {
            throw ShareCodeAPIError.codeNotFound
        }

        mockCodes.removeValue(forKey: code)

        // Update local storage
        try await markLocalCodeAsRevoked(code)

        Logger.network.info("[MOCK] Revoked share code: \(code)")

        return ShareCodeRevokeResponse(
            code: code,
            revoked: true,
            revokedAt: Date()
        )
    }

    private func generateMockCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<8).map { _ in chars.randomElement()! })
    }
}

// MARK: - Convenience Extensions

extension ShareCodeAPIClient {
    /// Shared instance for app-wide use
    static let shared = ShareCodeAPIClient()

    /// Create a mock-only instance for testing
    static func mock() -> ShareCodeAPIClient {
        ShareCodeAPIClient(useMockMode: true)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension ShareCodeAPIClient {
    /// Sample share codes for previews
    static var previewLocalCodes: [LocalShareCode] {
        [
            LocalShareCode(
                id: UUID(),
                code: "PUSH2024",
                planId: UUID(),
                planName: "Push Day Workout",
                createdAt: Date().addingTimeInterval(-86400 * 5),
                expiresAt: Date().addingTimeInterval(86400 * 25),
                isRevoked: false
            ),
            LocalShareCode(
                id: UUID(),
                code: "LEGS4EVR",
                planId: UUID(),
                planName: "Leg Day Destroyer",
                createdAt: Date().addingTimeInterval(-86400 * 20),
                expiresAt: Date().addingTimeInterval(86400 * 10),
                isRevoked: false
            ),
            LocalShareCode(
                id: UUID(),
                code: "EXPR1234",
                planId: UUID(),
                planName: "Old Plan",
                createdAt: Date().addingTimeInterval(-86400 * 35),
                expiresAt: Date().addingTimeInterval(-86400 * 5),
                isRevoked: false
            ),
            LocalShareCode(
                id: UUID(),
                code: "RVKD5678",
                planId: UUID(),
                planName: "Revoked Plan",
                createdAt: Date().addingTimeInterval(-86400 * 10),
                expiresAt: Date().addingTimeInterval(86400 * 20),
                isRevoked: true
            )
        ]
    }
}
#endif
