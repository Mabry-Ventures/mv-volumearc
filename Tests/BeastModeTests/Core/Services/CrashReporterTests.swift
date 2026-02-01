// CrashReporterTests.swift
// BeastModeTests
// Unit tests for CrashReporter error tracking

import Testing
import Foundation
@testable import BeastMode

@Suite("CrashReporter Tests")
struct CrashReporterTests {

    // MARK: - Error Recording Tests

    @Test("Record error captures error details")
    func recordErrorCapturesDetails() {
        let reporter = CrashReporter.shared

        // Clear previous errors
        reporter.clearErrorHistory()

        // Record an error
        let testError = NSError(
            domain: "TestDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Test error message"]
        )
        reporter.recordError(testError, context: "Unit Test")

        // Wait briefly for async processing
        Thread.sleep(forTimeInterval: 0.1)

        // Verify error was recorded
        let errors = reporter.getRecentErrors()
        #expect(errors.count >= 1)

        if let lastError = errors.last {
            #expect(lastError.context == "Unit Test")
            #expect(lastError.severity == "error")
        }
    }

    @Test("Record non-fatal error with properties")
    func recordNonFatalErrorWithProperties() {
        let reporter = CrashReporter.shared
        reporter.clearErrorHistory()

        // Record non-fatal error
        reporter.recordNonFatalError(
            "Non-fatal test error",
            properties: ["testKey": "testValue", "count": 42]
        )

        // Wait briefly for async processing
        Thread.sleep(forTimeInterval: 0.1)

        // Verify
        let errors = reporter.getRecentErrors()
        #expect(!errors.isEmpty)

        if let lastError = errors.last {
            #expect(lastError.message == "Non-fatal test error")
            #expect(lastError.severity == "warning")
        }
    }

    // MARK: - User Identifier Tests

    @Test("Set user identifier")
    func setUserIdentifier() {
        let reporter = CrashReporter.shared

        // Should not throw
        reporter.setUserIdentifier("test-user-123")
        reporter.setUserIdentifier(nil)  // Clear
    }

    // MARK: - Custom Value Tests

    @Test("Set and clear custom values")
    func setAndClearCustomValues() {
        let reporter = CrashReporter.shared

        // Set value
        reporter.setCustomValue("test-value", forKey: "testKey")

        // Clear value
        reporter.setCustomValue(nil, forKey: "testKey")

        // Should not throw
    }

    // MARK: - Breadcrumb Tests

    @Test("Leave breadcrumb")
    func leaveBreadcrumb() {
        let reporter = CrashReporter.shared

        // Should not throw
        reporter.leaveBreadcrumb("User tapped button", category: "UI")
        reporter.leaveBreadcrumb("API call completed", category: "Network")
    }

    // MARK: - Log Tests

    @Test("Log message")
    func logMessage() {
        let reporter = CrashReporter.shared

        // Should not throw
        reporter.log("Debug log message")
        reporter.log("Another message with special chars: @#$%")
    }

    // MARK: - Error History Tests

    @Test("Clear error history")
    func clearErrorHistory() {
        let reporter = CrashReporter.shared

        // Add some errors
        reporter.recordNonFatalError("Error 1", properties: nil)
        reporter.recordNonFatalError("Error 2", properties: nil)

        Thread.sleep(forTimeInterval: 0.1)

        // Clear
        reporter.clearErrorHistory()

        // Verify cleared
        let errors = reporter.getRecentErrors()
        #expect(errors.isEmpty)
    }

    @Test("Error history is capped at maximum")
    func errorHistoryCapped() {
        let reporter = CrashReporter.shared
        reporter.clearErrorHistory()

        // Add more than max errors (max is 100)
        for i in 0..<110 {
            reporter.recordNonFatalError("Error \(i)", properties: nil)
        }

        Thread.sleep(forTimeInterval: 0.5)

        // Verify capped
        let errors = reporter.getRecentErrors()
        #expect(errors.count <= 100)
    }

    // MARK: - Lifecycle Tests

    @Test("App lifecycle methods do not throw")
    func appLifecycleMethods() {
        let reporter = CrashReporter.shared

        // These should not throw
        reporter.appDidEnterBackground()
        reporter.appWillTerminate()
    }

    // MARK: - RecordedError Tests

    @Test("RecordedError initialization")
    func recordedErrorInitialization() {
        let error = RecordedError(
            message: "Test message",
            context: "Test context",
            severity: .error,
            stackTrace: "Stack trace here",
            properties: ["key": "value"]
        )

        #expect(error.message == "Test message")
        #expect(error.context == "Test context")
        #expect(error.severity == "error")
        #expect(error.stackTrace == "Stack trace here")
        #expect(error.properties["key"] == "value")
        #expect(error.timestamp <= Date())
    }

    @Test("RecordedError default values")
    func recordedErrorDefaults() {
        let error = RecordedError(message: "Simple error")

        #expect(error.message == "Simple error")
        #expect(error.context == nil)
        #expect(error.severity == "error")
        #expect(error.stackTrace == nil)
        #expect(error.properties.isEmpty)
    }

    // MARK: - ErrorSeverity Tests

    @Test("ErrorSeverity raw values")
    func errorSeverityRawValues() {
        #expect(ErrorSeverity.debug.rawValue == "debug")
        #expect(ErrorSeverity.info.rawValue == "info")
        #expect(ErrorSeverity.warning.rawValue == "warning")
        #expect(ErrorSeverity.error.rawValue == "error")
        #expect(ErrorSeverity.fatal.rawValue == "fatal")
    }
}
