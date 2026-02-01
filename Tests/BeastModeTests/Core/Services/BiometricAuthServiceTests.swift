// BiometricAuthServiceTests.swift
// BeastModeTests
// Unit tests for BiometricAuthService Face ID/Touch ID

import Testing
import Foundation
@testable import BeastMode

@Suite("BiometricAuthService Tests")
struct BiometricAuthServiceTests {

    // MARK: - BiometricType Tests

    @Test("BiometricType displayName values")
    func biometricTypeDisplayNames() {
        #expect(BiometricType.none.displayName == "None")
        #expect(BiometricType.touchID.displayName == "Touch ID")
        #expect(BiometricType.faceID.displayName == "Face ID")
        #expect(BiometricType.opticID.displayName == "Optic ID")
    }

    @Test("BiometricType iconName values")
    func biometricTypeIconNames() {
        #expect(BiometricType.none.iconName == "lock.fill")
        #expect(BiometricType.touchID.iconName == "touchid")
        #expect(BiometricType.faceID.iconName == "faceid")
        #expect(BiometricType.opticID.iconName == "opticid")
    }

    @Test("BiometricType raw values")
    func biometricTypeRawValues() {
        #expect(BiometricType.none.rawValue == "none")
        #expect(BiometricType.touchID.rawValue == "touchID")
        #expect(BiometricType.faceID.rawValue == "faceID")
        #expect(BiometricType.opticID.rawValue == "opticID")
    }

    // MARK: - BiometricError Tests

    @Test("BiometricError notAvailable description")
    func biometricErrorNotAvailableDescription() {
        let error = BiometricError.notAvailable
        #expect(error.errorDescription?.contains("not available") == true)
    }

    @Test("BiometricError notEnrolled description")
    func biometricErrorNotEnrolledDescription() {
        let error = BiometricError.notEnrolled
        #expect(error.errorDescription?.contains("enrolled") == true)
    }

    @Test("BiometricError authenticationFailed description")
    func biometricErrorAuthenticationFailedDescription() {
        let error = BiometricError.authenticationFailed
        #expect(error.errorDescription?.contains("failed") == true)
    }

    @Test("BiometricError userCancelled description")
    func biometricErrorUserCancelledDescription() {
        let error = BiometricError.userCancelled
        #expect(error.errorDescription?.contains("cancelled") == true)
    }

    @Test("BiometricError systemCancelled description")
    func biometricErrorSystemCancelledDescription() {
        let error = BiometricError.systemCancelled
        #expect(error.errorDescription?.contains("system") == true)
    }

    @Test("BiometricError passcodeNotSet description")
    func biometricErrorPasscodeNotSetDescription() {
        let error = BiometricError.passcodeNotSet
        #expect(error.errorDescription?.contains("passcode") == true)
    }

    @Test("BiometricError biometryLockout description")
    func biometricErrorBiometryLockoutDescription() {
        let error = BiometricError.biometryLockout
        #expect(error.errorDescription?.contains("locked") == true)
    }

    @Test("BiometricError invalidContext description")
    func biometricErrorInvalidContextDescription() {
        let error = BiometricError.invalidContext
        #expect(error.errorDescription?.contains("invalid") == true)
    }

    @Test("BiometricError unknown includes underlying error")
    func biometricErrorUnknownDescription() {
        let underlyingError = NSError(
            domain: "TestDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Test underlying error"]
        )
        let error = BiometricError.unknown(underlyingError)
        #expect(error.errorDescription?.contains("Test underlying error") == true)
    }

    // MARK: - BiometricError isRecoverable Tests

    @Test("BiometricError authenticationFailed is recoverable")
    func authenticationFailedIsRecoverable() {
        let error = BiometricError.authenticationFailed
        #expect(error.isRecoverable == true)
    }

    @Test("BiometricError userCancelled is recoverable")
    func userCancelledIsRecoverable() {
        let error = BiometricError.userCancelled
        #expect(error.isRecoverable == true)
    }

    @Test("BiometricError notAvailable is not recoverable")
    func notAvailableIsNotRecoverable() {
        let error = BiometricError.notAvailable
        #expect(error.isRecoverable == false)
    }

    @Test("BiometricError notEnrolled is not recoverable")
    func notEnrolledIsNotRecoverable() {
        let error = BiometricError.notEnrolled
        #expect(error.isRecoverable == false)
    }

    @Test("BiometricError biometryLockout is not recoverable")
    func biometryLockoutIsNotRecoverable() {
        let error = BiometricError.biometryLockout
        #expect(error.isRecoverable == false)
    }

    @Test("BiometricError passcodeNotSet is not recoverable")
    func passcodeNotSetIsNotRecoverable() {
        let error = BiometricError.passcodeNotSet
        #expect(error.isRecoverable == false)
    }

    @Test("BiometricError systemCancelled is not recoverable")
    func systemCancelledIsNotRecoverable() {
        let error = BiometricError.systemCancelled
        #expect(error.isRecoverable == false)
    }

    @Test("BiometricError invalidContext is not recoverable")
    func invalidContextIsNotRecoverable() {
        let error = BiometricError.invalidContext
        #expect(error.isRecoverable == false)
    }

    @Test("BiometricError unknown is not recoverable")
    func unknownIsNotRecoverable() {
        let error = BiometricError.unknown(NSError(domain: "Test", code: 0))
        #expect(error.isRecoverable == false)
    }

    // MARK: - BiometricError LocalizedError Conformance

    @Test("BiometricError conforms to LocalizedError")
    func biometricErrorConformsToLocalizedError() {
        let errors: [BiometricError] = [
            .notAvailable,
            .notEnrolled,
            .authenticationFailed,
            .userCancelled,
            .systemCancelled,
            .passcodeNotSet,
            .biometryLockout,
            .invalidContext,
            .unknown(NSError(domain: "Test", code: 0))
        ]

        for error in errors {
            // All errors should have a non-nil, non-empty description
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}

// MARK: - BiometricAuthService Shared Instance Tests

@Suite("BiometricAuthService Shared Instance Tests")
@MainActor
struct BiometricAuthServiceSharedTests {

    @Test("Shared instance exists")
    func sharedInstanceExists() {
        let service = BiometricAuthService.shared
        #expect(service != nil)
    }

    @Test("Biometric type is set after initialization")
    func biometricTypeIsSet() {
        let service = BiometricAuthService.shared

        // BiometricType should be one of the valid values
        let validTypes: [BiometricType] = [.none, .touchID, .faceID, .opticID]
        #expect(validTypes.contains(service.biometricType))
    }

    @Test("Published properties are accessible")
    func publishedPropertiesAreAccessible() {
        let service = BiometricAuthService.shared

        // Access all published properties without crashing
        _ = service.biometricType
        _ = service.isAvailable
        _ = service.isEnrolled
        _ = service.isEnabled
        _ = service.requireAuthOnLaunch
        _ = service.isAuthenticated
        _ = service.isAuthenticating
    }

    @Test("Check biometric availability does not throw")
    func checkBiometricAvailabilityDoesNotThrow() {
        let service = BiometricAuthService.shared
        service.checkBiometricAvailability()

        // Should complete without throwing
    }

    @Test("Reset authentication state works")
    func resetAuthenticationStateWorks() {
        let service = BiometricAuthService.shared

        // Reset should set isAuthenticated to false
        service.resetAuthenticationState()

        #expect(service.isAuthenticated == false)
    }

    @Test("Disable biometrics works")
    func disableBiometricsWorks() {
        let service = BiometricAuthService.shared

        // Disable biometrics
        service.disableBiometrics()

        #expect(service.isEnabled == false)
        #expect(service.requireAuthOnLaunch == false)
    }
}

// MARK: - BiometricAuthService Authentication Tests

@Suite("BiometricAuthService Authentication Tests")
@MainActor
struct BiometricAuthServiceAuthenticationTests {

    @Test("Authenticate returns failure when not available")
    func authenticateFailsWhenNotAvailable() async {
        // Create a service that simulates biometrics not being available
        // Note: In actual tests, we'd use dependency injection to mock LAContext
        // For now, we test the shared instance behavior
        let service = BiometricAuthService.shared

        // If biometrics are not available on the test device, this should fail
        if !service.isAvailable {
            let result = await service.authenticate()

            switch result {
            case .success:
                // If biometrics are not available, we shouldn't succeed
                Issue.record("Should not succeed when biometrics are not available")
            case .failure(let error):
                #expect(error == .notAvailable)
            }
        }
    }

    @Test("Authenticate returns failure when not enrolled")
    func authenticateFailsWhenNotEnrolled() async {
        let service = BiometricAuthService.shared

        // If biometrics are available but not enrolled, this should fail
        if service.isAvailable && !service.isEnrolled {
            let result = await service.authenticate()

            switch result {
            case .success:
                Issue.record("Should not succeed when biometrics are not enrolled")
            case .failure(let error):
                #expect(error == .notEnrolled)
            }
        }
    }

    @Test("isAuthenticating is false initially")
    func isAuthenticatingIsFalseInitially() {
        let service = BiometricAuthService.shared

        #expect(service.isAuthenticating == false)
    }
}

// MARK: - BiometricType Equatable Tests

@Suite("BiometricType Equatable Tests")
struct BiometricTypeEquatableTests {

    @Test("BiometricType equality")
    func biometricTypeEquality() {
        #expect(BiometricType.none == BiometricType.none)
        #expect(BiometricType.touchID == BiometricType.touchID)
        #expect(BiometricType.faceID == BiometricType.faceID)
        #expect(BiometricType.opticID == BiometricType.opticID)
    }

    @Test("BiometricType inequality")
    func biometricTypeInequality() {
        #expect(BiometricType.none != BiometricType.touchID)
        #expect(BiometricType.touchID != BiometricType.faceID)
        #expect(BiometricType.faceID != BiometricType.opticID)
        #expect(BiometricType.opticID != BiometricType.none)
    }
}
