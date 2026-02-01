// CrashReporter.swift
// BeastMode
// Crash reporting and error tracking infrastructure

import Foundation
import os

// MARK: - Crash Reporter Protocol

protocol CrashReporting {
    func recordError(_ error: Error, context: String?)
    func recordNonFatalError(_ message: String, properties: [String: Any]?)
    func setUserIdentifier(_ identifier: String?)
    func setCustomValue(_ value: Any?, forKey key: String)
    func log(_ message: String)
}

// MARK: - Error Severity

enum ErrorSeverity: String {
    case debug
    case info
    case warning
    case error
    case fatal
}

// MARK: - Recorded Error

struct RecordedError: Codable {
    let timestamp: Date
    let message: String
    let context: String?
    let severity: String
    let stackTrace: String?
    let properties: [String: String]

    init(
        message: String,
        context: String? = nil,
        severity: ErrorSeverity = .error,
        stackTrace: String? = nil,
        properties: [String: String] = [:]
    ) {
        self.timestamp = Date()
        self.message = message
        self.context = context
        self.severity = severity.rawValue
        self.stackTrace = stackTrace
        self.properties = properties
    }
}

// MARK: - Crash Reporter

final class CrashReporter: CrashReporting, @unchecked Sendable {
    static let shared = CrashReporter()

    private var userIdentifier: String?
    private var customValues: [String: Any] = [:]
    private let errorQueue = DispatchQueue(label: "com.beastmode.crashreporter", qos: .utility)
    private var recentErrors: [RecordedError] = []
    private let maxStoredErrors = 100

    private init() {
        setupExceptionHandling()
        loadPersistedErrors()
    }

    // MARK: - CrashReporting Protocol

    /// Record an error with optional context
    func recordError(_ error: Error, context: String? = nil) {
        errorQueue.async { [weak self] in
            guard let self = self else { return }

            let nsError = error as NSError
            let message = "\(nsError.domain): \(nsError.localizedDescription)"

            Logger.app.error("Error recorded: \(message) - Context: \(context ?? "none")")

            let recordedError = RecordedError(
                message: message,
                context: context,
                severity: .error,
                stackTrace: Thread.callStackSymbols.joined(separator: "\n"),
                properties: self.buildProperties(for: nsError)
            )

            self.storeError(recordedError)

            // In production, this would send to a crash reporting service
            // like Crashlytics, Sentry, or Bugsnag
            #if DEBUG
            print("🔴 Error: \(message)")
            if let context = context {
                print("   Context: \(context)")
            }
            #endif
        }
    }

    /// Record a non-fatal error with a message
    func recordNonFatalError(_ message: String, properties: [String: Any]? = nil) {
        errorQueue.async { [weak self] in
            guard let self = self else { return }

            Logger.app.warning("Non-fatal error: \(message)")

            var stringProperties: [String: String] = [:]
            properties?.forEach { key, value in
                stringProperties[key] = String(describing: value)
            }

            let recordedError = RecordedError(
                message: message,
                context: nil,
                severity: .warning,
                stackTrace: nil,
                properties: stringProperties
            )

            self.storeError(recordedError)

            #if DEBUG
            print("🟡 Non-fatal: \(message)")
            #endif
        }
    }

    /// Set the user identifier for crash reports
    func setUserIdentifier(_ identifier: String?) {
        errorQueue.async { [weak self] in
            self?.userIdentifier = identifier
            Logger.app.info("User identifier set: \(identifier ?? "nil")")
        }
    }

    /// Set a custom value for crash reports
    func setCustomValue(_ value: Any?, forKey key: String) {
        errorQueue.async { [weak self] in
            if let value = value {
                self?.customValues[key] = value
            } else {
                self?.customValues.removeValue(forKey: key)
            }
        }
    }

    /// Log a message for debugging
    func log(_ message: String) {
        Logger.app.debug("\(message)")

        #if DEBUG
        print("📝 Log: \(message)")
        #endif
    }

    // MARK: - Error History

    /// Get recent errors for debugging
    func getRecentErrors() -> [RecordedError] {
        return errorQueue.sync { recentErrors }
    }

    /// Clear error history
    func clearErrorHistory() {
        errorQueue.async { [weak self] in
            self?.recentErrors.removeAll()
            self?.persistErrors()
        }
    }

    // MARK: - Breadcrumbs

    /// Leave a breadcrumb for debugging
    func leaveBreadcrumb(_ message: String, category: String = "general") {
        errorQueue.async { [weak self] in
            Logger.app.info("Breadcrumb [\(category)]: \(message)")

            self?.customValues["lastBreadcrumb"] = message
            self?.customValues["lastBreadcrumbTime"] = ISO8601DateFormatter().string(from: Date())
        }
    }

    // MARK: - App Lifecycle

    /// Called when app is about to terminate
    func appWillTerminate() {
        errorQueue.sync {
            persistErrors()
        }
    }

    /// Called when app enters background
    func appDidEnterBackground() {
        errorQueue.async { [weak self] in
            self?.persistErrors()
        }
    }

    // MARK: - Private Methods

    private func setupExceptionHandling() {
        // Set up uncaught exception handler
        NSSetUncaughtExceptionHandler { exception in
            let message = "Uncaught Exception: \(exception.name.rawValue)"
            let reason = exception.reason ?? "No reason"

            Logger.app.fault("CRASH: \(message) - \(reason)")

            let recordedError = RecordedError(
                message: message,
                context: reason,
                severity: .fatal,
                stackTrace: exception.callStackSymbols.joined(separator: "\n"),
                properties: ["exceptionName": exception.name.rawValue]
            )

            // Store synchronously since we're about to crash
            CrashReporter.shared.storeErrorSync(recordedError)
        }

        // Set up signal handlers for crashes
        setupSignalHandlers()
    }

    private func setupSignalHandlers() {
        // Handle common crash signals
        signal(SIGABRT) { _ in
            Logger.app.fault("CRASH: SIGABRT received")
        }

        signal(SIGSEGV) { _ in
            Logger.app.fault("CRASH: SIGSEGV received")
        }

        signal(SIGBUS) { _ in
            Logger.app.fault("CRASH: SIGBUS received")
        }

        signal(SIGFPE) { _ in
            Logger.app.fault("CRASH: SIGFPE received")
        }
    }

    private func buildProperties(for error: NSError) -> [String: String] {
        var properties: [String: String] = [
            "domain": error.domain,
            "code": String(error.code)
        ]

        if let userIdentifier = userIdentifier {
            properties["userId"] = userIdentifier
        }

        // Add custom values
        for (key, value) in customValues {
            properties[key] = String(describing: value)
        }

        // Add error user info
        for (key, value) in error.userInfo {
            if let stringKey = key as? String {
                properties["userInfo.\(stringKey)"] = String(describing: value)
            }
        }

        return properties
    }

    private func storeError(_ error: RecordedError) {
        recentErrors.append(error)

        // Keep only the most recent errors
        if recentErrors.count > maxStoredErrors {
            recentErrors.removeFirst(recentErrors.count - maxStoredErrors)
        }

        persistErrors()
    }

    private func storeErrorSync(_ error: RecordedError) {
        recentErrors.append(error)
        persistErrors()
    }

    private func persistErrors() {
        do {
            let data = try JSONEncoder().encode(recentErrors)
            guard let url = errorStorageURL else {
                Logger.app.error("Could not get error storage URL for persistence")
                return
            }
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.app.error("Failed to persist errors: \(error.localizedDescription)")
        }
    }

    private func loadPersistedErrors() {
        guard let url = errorStorageURL else {
            Logger.app.warning("Could not get error storage URL for loading")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            recentErrors = try JSONDecoder().decode([RecordedError].self, from: data)
        } catch {
            // File may not exist on first launch - this is expected
            if (error as NSError).code != NSFileReadNoSuchFileError {
                Logger.app.warning("Failed to load persisted errors: \(error.localizedDescription)")
            }
        }
    }

    private var errorStorageURL: URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Logger.app.error("Could not access documents directory")
            return nil
        }
        return documentsDirectory.appendingPathComponent("crash_reports.json")
    }
}

// MARK: - Debug View for Error History

#if DEBUG
import SwiftUI

struct ErrorHistoryView: View {
    @State private var errors: [RecordedError] = []

    var body: some View {
        NavigationStack {
            List {
                if errors.isEmpty {
                    ContentUnavailableView(
                        "No Errors",
                        systemImage: "checkmark.circle.fill",
                        description: Text("No errors have been recorded")
                    )
                } else {
                    ForEach(errors.indices, id: \.self) { index in
                        let error = errors[index]
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                severityBadge(error.severity)
                                Text(error.timestamp.formatted(.dateTime))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(error.message)
                                .font(.body)

                            if let context = error.context {
                                Text(context)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Error History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        CrashReporter.shared.clearErrorHistory()
                        errors = []
                    }
                    .disabled(errors.isEmpty)
                }
            }
            .onAppear {
                errors = CrashReporter.shared.getRecentErrors()
            }
        }
    }

    @ViewBuilder
    private func severityBadge(_ severity: String) -> some View {
        let color: Color = switch severity {
        case "fatal": .red
        case "error": .orange
        case "warning": .yellow
        case "info": .blue
        default: .gray
        }

        Text(severity.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .cornerRadius(4)
    }
}

#Preview {
    ErrorHistoryView()
}
#endif
