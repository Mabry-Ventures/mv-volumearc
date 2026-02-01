// KeychainServiceTests.swift
// BeastModeTests
// Unit tests for KeychainService secure storage

import Testing
import Foundation
@testable import BeastMode

@Suite("KeychainService Tests")
struct KeychainServiceTests {

    // MARK: - String Storage Tests

    @Test("String storage and retrieval")
    func stringStorageAndRetrieval() throws {
        let service = KeychainService.shared
        let testKey = "test.string.key.\(UUID().uuidString)"
        let testValue = "Test String Value"

        // Store
        let storeResult = service.setString(testValue, forKey: testKey)
        #expect(storeResult == true)

        // Retrieve
        let retrieved = service.getString(forKey: testKey)
        #expect(retrieved == testValue)

        // Cleanup
        service.delete(forKey: testKey)
    }

    @Test("String retrieval returns nil for non-existent key")
    func stringRetrievalNonExistent() {
        let service = KeychainService.shared
        let result = service.getString(forKey: "non.existent.key.\(UUID().uuidString)")
        #expect(result == nil)
    }

    // MARK: - Data Storage Tests

    @Test("Data storage and retrieval")
    func dataStorageAndRetrieval() throws {
        let service = KeychainService.shared
        let testKey = "test.data.key.\(UUID().uuidString)"
        let testData = "Test Data Content".data(using: .utf8)!

        // Store
        let storeResult = service.setData(testData, forKey: testKey)
        #expect(storeResult == true)

        // Retrieve
        let retrieved = service.getData(forKey: testKey)
        #expect(retrieved == testData)

        // Cleanup
        service.delete(forKey: testKey)
    }

    // MARK: - Delete Tests

    @Test("Delete removes stored item")
    func deleteRemovesItem() {
        let service = KeychainService.shared
        let testKey = "test.delete.key.\(UUID().uuidString)"

        // Store
        service.setString("value", forKey: testKey)
        #expect(service.getString(forKey: testKey) != nil)

        // Delete
        let deleteResult = service.delete(forKey: testKey)
        #expect(deleteResult == true)

        // Verify deleted
        #expect(service.getString(forKey: testKey) == nil)
    }

    @Test("Delete non-existent item returns true")
    func deleteNonExistentItem() {
        let service = KeychainService.shared
        let result = service.delete(forKey: "non.existent.key.\(UUID().uuidString)")
        #expect(result == true)
    }

    // MARK: - Codable Storage Tests

    struct TestCodable: Codable, Equatable {
        let id: Int
        let name: String
        let isActive: Bool
    }

    @Test("Codable object storage and retrieval")
    func codableStorageAndRetrieval() throws {
        let service = KeychainService.shared
        let testKey = "test.codable.key.\(UUID().uuidString)"
        let testObject = TestCodable(id: 42, name: "Test", isActive: true)

        // Store
        let storeResult = service.setCodable(testObject, forKey: testKey)
        #expect(storeResult == true)

        // Retrieve
        let retrieved = service.getCodable(TestCodable.self, forKey: testKey)
        #expect(retrieved == testObject)

        // Cleanup
        service.delete(forKey: testKey)
    }

    // MARK: - API Key Tests

    @Test("API key storage and retrieval")
    func apiKeyStorageAndRetrieval() {
        let service = KeychainService.shared
        let testAPIKey = "sk-test-api-key-\(UUID().uuidString)"

        // Store
        let storeResult = service.setAPIKey(testAPIKey)
        #expect(storeResult == true)

        // Retrieve (note: may also check environment variable fallback)
        let retrieved = service.getAPIKey()
        #expect(retrieved != nil)

        // Cleanup - delete the API key
        service.delete(forKey: "com.beastmode.api.key")
    }

    @Test("hasAPIKey property works correctly")
    func hasAPIKeyProperty() {
        let service = KeychainService.shared
        let testAPIKey = "sk-test-has-key-\(UUID().uuidString)"

        // Store
        service.setAPIKey(testAPIKey)

        // Check property
        #expect(service.hasAPIKey == true)

        // Cleanup
        service.delete(forKey: "com.beastmode.api.key")
    }

    // MARK: - Auth Token Tests

    @Test("Auth token storage and retrieval")
    func authTokenStorageAndRetrieval() {
        let service = KeychainService.shared
        let accessToken = "access-token-\(UUID().uuidString)"
        let refreshToken = "refresh-token-\(UUID().uuidString)"

        // Store
        let storeResult = service.setAuthTokens(accessToken: accessToken, refreshToken: refreshToken)
        #expect(storeResult == true)

        // Retrieve
        #expect(service.getAccessToken() == accessToken)
        #expect(service.getRefreshToken() == refreshToken)

        // Clear
        let clearResult = service.clearAuthTokens()
        #expect(clearResult == true)

        // Verify cleared
        #expect(service.getAccessToken() == nil)
        #expect(service.getRefreshToken() == nil)
    }

    // MARK: - Overwrite Tests

    @Test("Storing with same key overwrites previous value")
    func overwritesPreviousValue() {
        let service = KeychainService.shared
        let testKey = "test.overwrite.key.\(UUID().uuidString)"

        // Store first value
        service.setString("first", forKey: testKey)
        #expect(service.getString(forKey: testKey) == "first")

        // Store second value with same key
        service.setString("second", forKey: testKey)
        #expect(service.getString(forKey: testKey) == "second")

        // Cleanup
        service.delete(forKey: testKey)
    }
}
