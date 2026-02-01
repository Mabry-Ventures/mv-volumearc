// KeychainService.swift
// BeastMode
// Secure storage for sensitive data using iOS Keychain

import Foundation
import Security
import os

// MARK: - Keychain Error

enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain item not found"
        case .duplicateItem:
            return "Keychain item already exists"
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .encodingFailed:
            return "Failed to encode data for keychain"
        case .decodingFailed:
            return "Failed to decode data from keychain"
        }
    }
}

// MARK: - Keychain Service

final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()

    private let serviceName: String
    private let accessGroup: String?

    private init(
        serviceName: String = Bundle.main.bundleIdentifier ?? "com.beastmode.app",
        accessGroup: String? = nil
    ) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
    }

    // MARK: - String Operations

    /// Store a string value in the keychain
    @discardableResult
    func setString(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            Logger.app.error("Failed to encode string for keychain")
            return false
        }
        return setData(data, forKey: key)
    }

    /// Retrieve a string value from the keychain
    func getString(forKey key: String) -> String? {
        guard let data = getData(forKey: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Data Operations

    /// Store data in the keychain
    @discardableResult
    func setData(_ data: Data, forKey key: String) -> Bool {
        // First try to delete existing item
        delete(forKey: key)

        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            Logger.app.error("Failed to store data in keychain: \(status)")
            return false
        }

        return true
    }

    /// Retrieve data from the keychain
    func getData(forKey key: String) -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                Logger.app.error("Failed to retrieve data from keychain: \(status)")
            }
            return nil
        }

        return result as? Data
    }

    // MARK: - Delete Operations

    /// Delete an item from the keychain
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.app.error("Failed to delete keychain item: \(status)")
            return false
        }

        return true
    }

    /// Delete all items for this service
    @discardableResult
    func deleteAll() -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.app.error("Failed to delete all keychain items: \(status)")
            return false
        }

        return true
    }

    // MARK: - Codable Support

    /// Store a Codable object in the keychain
    @discardableResult
    func setCodable<T: Codable>(_ value: T, forKey key: String) -> Bool {
        do {
            let data = try JSONEncoder().encode(value)
            return setData(data, forKey: key)
        } catch {
            Logger.app.error("Failed to encode codable for keychain: \(error.localizedDescription)")
            return false
        }
    }

    /// Retrieve a Codable object from the keychain
    func getCodable<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = getData(forKey: key) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Logger.app.error("Failed to decode codable from keychain: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - API Key Management

    /// Store the API key securely
    @discardableResult
    func setAPIKey(_ apiKey: String) -> Bool {
        return setString(apiKey, forKey: "com.beastmode.api.key")
    }

    /// Retrieve the API key
    func getAPIKey() -> String? {
        // First check keychain
        if let key = getString(forKey: "com.beastmode.api.key") {
            return key
        }

        // Fallback to environment variable (for development)
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }

    /// Check if API key is stored
    var hasAPIKey: Bool {
        return getAPIKey() != nil
    }

    // MARK: - Private Helpers

    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}

// MARK: - Secure Credentials Storage

extension KeychainService {
    private static let authTokenKey = "com.beastmode.auth.token"
    private static let refreshTokenKey = "com.beastmode.auth.refreshToken"

    /// Store authentication tokens
    @discardableResult
    func setAuthTokens(accessToken: String, refreshToken: String? = nil) -> Bool {
        let accessResult = setString(accessToken, forKey: Self.authTokenKey)

        if let refreshToken = refreshToken {
            let refreshResult = setString(refreshToken, forKey: Self.refreshTokenKey)
            return accessResult && refreshResult
        }

        return accessResult
    }

    /// Retrieve access token
    func getAccessToken() -> String? {
        return getString(forKey: Self.authTokenKey)
    }

    /// Retrieve refresh token
    func getRefreshToken() -> String? {
        return getString(forKey: Self.refreshTokenKey)
    }

    /// Clear authentication tokens
    @discardableResult
    func clearAuthTokens() -> Bool {
        let accessResult = delete(forKey: Self.authTokenKey)
        let refreshResult = delete(forKey: Self.refreshTokenKey)
        return accessResult && refreshResult
    }
}
