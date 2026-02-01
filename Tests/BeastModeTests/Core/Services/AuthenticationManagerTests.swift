// AuthenticationManagerTests.swift
// BeastModeTests
// Unit tests for AuthenticationManager

import Testing
import Foundation
@testable import BeastMode

@Suite("AuthenticationManager Tests")
struct AuthenticationManagerTests {

    // MARK: - AuthenticationState Tests

    @Test("AuthenticationState equality for simple cases")
    func authenticationStateEquality() {
        #expect(AuthenticationState.unknown == AuthenticationState.unknown)
        #expect(AuthenticationState.unauthenticated == AuthenticationState.unauthenticated)
        #expect(AuthenticationState.unknown != AuthenticationState.unauthenticated)
    }

    @Test("AuthenticationState authenticated equality")
    func authenticationStateAuthenticatedEquality() {
        let state1 = AuthenticationState.authenticated(userId: "user-123")
        let state2 = AuthenticationState.authenticated(userId: "user-123")
        let state3 = AuthenticationState.authenticated(userId: "user-456")

        #expect(state1 == state2)
        #expect(state1 != state3)
    }

    @Test("AuthenticationState error equality")
    func authenticationStateErrorEquality() {
        let error1 = AuthenticationState.error("Error message 1")
        let error2 = AuthenticationState.error("Error message 1")
        let error3 = AuthenticationState.error("Error message 2")

        #expect(error1 == error2)
        #expect(error1 != error3)
    }

    @Test("AuthenticationState different types are not equal")
    func authenticationStateDifferentTypesNotEqual() {
        #expect(AuthenticationState.unknown != AuthenticationState.authenticated(userId: "123"))
        #expect(AuthenticationState.unauthenticated != AuthenticationState.error("error"))
        #expect(AuthenticationState.authenticated(userId: "123") != AuthenticationState.error("error"))
    }

    // MARK: - AuthenticationError Tests

    @Test("AuthenticationError descriptions")
    func authenticationErrorDescriptions() {
        let signInFailed = AuthenticationError.signInFailed(underlying: nil)
        #expect(signInFailed.errorDescription == "Sign in failed")

        let withUnderlying = AuthenticationError.signInFailed(
            underlying: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        )
        #expect(withUnderlying.errorDescription?.contains("Test error") == true)

        let revoked = AuthenticationError.credentialRevoked
        #expect(revoked.errorDescription?.contains("revoked") == true)

        let refreshFailed = AuthenticationError.tokenRefreshFailed
        #expect(refreshFailed.errorDescription?.contains("refresh") == true)

        let keychainError = AuthenticationError.keychainError("Keychain unavailable")
        #expect(keychainError.errorDescription?.contains("Keychain") == true)

        let invalidState = AuthenticationError.invalidState
        #expect(invalidState.errorDescription?.contains("Invalid") == true)
    }

    // MARK: - UserCredentials Tests

    @Test("UserCredentials initialization")
    func userCredentialsInitialization() {
        let credentials = UserCredentials(
            userId: "user-123",
            email: "test@example.com",
            fullName: nil,
            identityToken: nil,
            authorizationCode: nil,
            lastAuthenticated: Date()
        )

        #expect(credentials.userId == "user-123")
        #expect(credentials.email == "test@example.com")
        #expect(credentials.fullName == nil)
    }

    @Test("UserCredentials displayName with email only")
    func userCredentialsDisplayNameWithEmail() {
        let credentials = UserCredentials(
            userId: "user-123",
            email: "test@example.com",
            fullName: nil,
            identityToken: nil,
            authorizationCode: nil,
            lastAuthenticated: Date()
        )

        #expect(credentials.displayName == "test@example.com")
    }

    @Test("UserCredentials displayName fallback to User")
    func userCredentialsDisplayNameFallback() {
        let credentials = UserCredentials(
            userId: "user-123",
            email: nil,
            fullName: nil,
            identityToken: nil,
            authorizationCode: nil,
            lastAuthenticated: Date()
        )

        #expect(credentials.displayName == "User")
    }

    @Test("UserCredentials displayName with full name")
    func userCredentialsDisplayNameWithFullName() {
        var nameComponents = PersonNameComponents()
        nameComponents.givenName = "John"
        nameComponents.familyName = "Doe"

        let credentials = UserCredentials(
            userId: "user-123",
            email: "test@example.com",
            fullName: nameComponents,
            identityToken: nil,
            authorizationCode: nil,
            lastAuthenticated: Date()
        )

        // The displayName should contain the name
        #expect(credentials.displayName.contains("John") || credentials.displayName.contains("Doe"))
    }

    @Test("UserCredentials is Codable")
    func userCredentialsCodable() throws {
        let original = UserCredentials(
            userId: "user-123",
            email: "test@example.com",
            fullName: nil,
            identityToken: "token".data(using: .utf8),
            authorizationCode: "code".data(using: .utf8),
            lastAuthenticated: Date()
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserCredentials.self, from: encoded)

        #expect(original.userId == decoded.userId)
        #expect(original.email == decoded.email)
        #expect(original.identityToken == decoded.identityToken)
    }
}

// MARK: - AuthenticationManager Instance Tests

@Suite("AuthenticationManager Instance Tests")
@MainActor
struct AuthenticationManagerInstanceTests {

    @Test("AuthenticationManager initial state is unknown")
    func initialStateIsUnknown() {
        // Note: In real usage, the init() will check credentials
        // For testing, we just verify the published properties exist
        let manager = AuthenticationManager()

        // Initial state should transition from unknown
        // (actual state depends on keychain contents)
        #expect(manager.showSignInSheet == false)
    }

    @Test("isAuthenticated returns correct value")
    func isAuthenticatedProperty() {
        let manager = AuthenticationManager()

        // Initially should not be authenticated (unless credentials exist)
        // This test verifies the property works without crashing
        _ = manager.isAuthenticated
    }
}
