// PlanSharingService.swift
// BeastMode
// Service for sharing and importing workout plans

import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Service for sharing and importing workout plans
actor PlanSharingService {
    private let modelContext: ModelContext

    /// Custom file extension for Beast Mode plans
    static let fileExtension = "beastplan"

    /// URL scheme for deep linking
    static let urlScheme = "beastmode"

    /// MIME type for plan files
    static let mimeType = "application/x-beastmode-plan"

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Export

    /// Export a plan to shareable JSON data
    func exportPlan(_ plan: WorkoutPlan) throws -> Data {
        let shareable = ShareablePlan(from: plan)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(shareable)
    }

    /// Export a plan to a file URL
    func exportPlanToFile(_ plan: WorkoutPlan) throws -> URL {
        let data = try exportPlan(plan)

        // Create file in temp directory
        let fileName = sanitizeFileName(plan.name) + ".\(Self.fileExtension)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try data.write(to: tempURL)
        return tempURL
    }

    /// Generate a share link for a plan
    func generateShareLink(_ plan: WorkoutPlan) throws -> URL {
        let data = try exportPlan(plan)
        let base64 = data.base64EncodedString()

        // URL encode the base64 string
        guard let encoded = base64.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(Self.urlScheme)://import?plan=\(encoded)") else {
            throw PlanSharingError.invalidURL
        }

        return url
    }

    /// Generate a short share code for the plan
    func generateShareCode(for plan: WorkoutPlan) throws -> String {
        if plan.shareCode == nil {
            plan.generateShareCode()
        }
        return plan.shareCode ?? ""
    }

    // MARK: - Import

    /// Import a plan from JSON data with automatic version migration
    func importPlan(from data: Data, userId: UUID) throws -> WorkoutPlan {
        // Detect and validate version
        let version = try PlanMigrationService.detectVersion(from: data)

        guard PlanMigrationService.isVersionSupported(version) else {
            throw PlanSharingError.unsupportedVersion(version)
        }

        // Migrate data if needed
        let migratedData: Data
        if version < ShareablePlan.currentExportVersion {
            migratedData = try PlanMigrationService.migrateImportData(data)
        } else {
            migratedData = data
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let shareable = try decoder.decode(ShareablePlan.self, from: migratedData)
        let plan = shareable.toPlan(userId: userId)

        // Ensure plan is at current schema version
        if plan.needsMigration {
            let migrationService = PlanMigrationService(modelContext: modelContext)
            Task {
                await migrationService.migratePlan(plan)
            }
        }

        modelContext.insert(plan)

        return plan
    }

    /// Import a plan with detailed migration results
    func importPlanWithMigration(from data: Data, userId: UUID) throws -> (WorkoutPlan, MigrationResult?) {
        let migrationService = PlanMigrationService(modelContext: modelContext)
        return try migrationService.importAndMigrate(from: data, userId: userId)
    }

    /// Import a plan from a file URL
    func importPlanFromFile(_ url: URL, userId: UUID) throws -> WorkoutPlan {
        // Validate file extension
        guard url.pathExtension == Self.fileExtension else {
            throw PlanSharingError.invalidFileType
        }

        let data = try Data(contentsOf: url)
        return try importPlan(from: data, userId: userId)
    }

    /// Import a plan from a deep link URL
    func importPlanFromURL(_ url: URL, userId: UUID) throws -> WorkoutPlan {
        // Parse the URL
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.urlScheme,
              components.host == "import",
              let planParam = components.queryItems?.first(where: { $0.name == "plan" })?.value,
              let data = Data(base64Encoded: planParam) else {
            throw PlanSharingError.invalidURL
        }

        return try importPlan(from: data, userId: userId)
    }

    /// Import a plan from a share code
    func importPlanFromCode(_ code: String, userId: UUID) async throws -> WorkoutPlan {
        // In a real app, this would fetch from a server
        // For now, we'll throw an error as codes require backend support
        throw PlanSharingError.shareCodeNotSupported
    }

    // MARK: - Validation

    /// Validate plan data before import
    func validatePlanData(_ data: Data) throws -> ShareablePlan {
        // First check version
        let version = try PlanMigrationService.detectVersion(from: data)

        guard PlanMigrationService.isVersionSupported(version) else {
            throw PlanSharingError.unsupportedVersion(version)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let shareable = try decoder.decode(ShareablePlan.self, from: data)

        // Validate required fields
        guard !shareable.name.isEmpty else {
            throw PlanSharingError.invalidPlanData("Plan name is required")
        }

        guard !shareable.days.isEmpty else {
            throw PlanSharingError.invalidPlanData("Plan must have at least one day")
        }

        return shareable
    }

    /// Get version info for plan data without full validation
    func getPlanVersionInfo(_ data: Data) throws -> PlanVersionInfo {
        let version = try PlanMigrationService.detectVersion(from: data)
        let isSupported = PlanMigrationService.isVersionSupported(version)
        let needsMigration = version < ShareablePlan.currentExportVersion

        return PlanVersionInfo(
            version: version,
            currentVersion: ShareablePlan.currentExportVersion,
            isSupported: isSupported,
            needsMigration: needsMigration
        )
    }
}

/// Information about a plan's version status
struct PlanVersionInfo: Sendable {
    let version: Int
    let currentVersion: Int
    let isSupported: Bool
    let needsMigration: Bool

    var versionDescription: String {
        if !isSupported {
            return "Unsupported (v\(version))"
        } else if needsMigration {
            return "v\(version) (will upgrade to v\(currentVersion))"
        } else {
            return "v\(version) (current)"
        }
    }
}

// MARK: - PlanSharingService Helpers

private extension PlanSharingService {
    func sanitizeFileName(_ name: String) -> String {
        // Remove invalid characters for file names
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "-")
        return sanitized.isEmpty ? "plan" : sanitized
    }
}

// MARK: - Errors

enum PlanSharingError: LocalizedError {
    case invalidURL
    case invalidFileType
    case unsupportedVersion(Int)
    case invalidPlanData(String)
    case shareCodeNotSupported
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The share link is invalid or corrupted"
        case .invalidFileType:
            return "The file type is not supported. Please use a .beastplan file"
        case .unsupportedVersion(let version):
            return "This plan was created with a newer version (v\(version)). Please update the app"
        case .invalidPlanData(let message):
            return "Invalid plan data: \(message)"
        case .shareCodeNotSupported:
            return "Share codes require an internet connection"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - UTType Extension

extension UTType {
    static var beastModePlan: UTType {
        UTType(exportedAs: "com.beastmode.plan", conformingTo: .json)
    }
}

// MARK: - Plan File Document

import SwiftUI

/// Document type for Beast Mode plan files
struct PlanDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.beastModePlan, .json] }

    var planData: Data

    init(plan: WorkoutPlan) throws {
        let shareable = ShareablePlan(from: plan)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        self.planData = try encoder.encode(shareable)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw PlanSharingError.invalidFileType
        }
        self.planData = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: planData)
    }
}

// MARK: - Share Activity Item

/// Custom activity item for sharing plans
class PlanActivityItem: NSObject {
    let plan: WorkoutPlan
    let fileURL: URL

    init(plan: WorkoutPlan, fileURL: URL) {
        self.plan = plan
        self.fileURL = fileURL
    }
}

extension PlanActivityItem: UIActivityItemSource {
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "Check out my workout plan: \(plan.name)"
    }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return UTType.beastModePlan.identifier
    }
}

// MARK: - Deep Link Handler

/// Handler for deep link imports
@MainActor
class DeepLinkHandler: ObservableObject {
    @Published var pendingImport: URL?
    @Published var showImportSheet = false
    @Published var importError: Error?

    func handleURL(_ url: URL) {
        if url.scheme == PlanSharingService.urlScheme && url.host == "import" {
            pendingImport = url
            showImportSheet = true
        }
    }

    func clearPendingImport() {
        pendingImport = nil
        importError = nil
    }
}
