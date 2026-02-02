// PlanMigrationService.swift
// BeastMode
// Service for migrating workout plans between schema versions

import Foundation
import SwiftData

// MARK: - Plan Migration Service

/// Service responsible for detecting and migrating workout plans between versions
actor PlanMigrationService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Version Detection

    /// Detect the version of a plan from JSON data
    static func detectVersion(from data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // First try to decode just the version field
        struct VersionOnly: Decodable {
            let version: Int?
        }

        let versionInfo = try decoder.decode(VersionOnly.self, from: data)

        // If no version field, assume V1 (legacy format)
        return versionInfo.version ?? 1
    }

    /// Check if a version is supported for import
    static func isVersionSupported(_ version: Int) -> Bool {
        version >= ShareablePlan.minimumSupportedVersion &&
        version <= ShareablePlan.currentExportVersion
    }

    /// Get the migration path from one version to another
    static func migrationPath(from: Int, to: Int) -> [Int] {
        guard from < to else { return [] }
        return Array((from + 1)...to)
    }

    // MARK: - Plan Migration

    /// Migrate a single plan to the current schema version
    func migratePlan(_ plan: WorkoutPlan) -> MigrationResult {
        let originalVersion = plan.schemaVersion

        guard plan.needsMigration else {
            return MigrationResult(
                planId: plan.id,
                originalVersion: originalVersion,
                targetVersion: kWorkoutPlanCurrentVersion,
                success: true,
                changes: []
            )
        }

        var changes: [MigrationChange] = []

        // Apply migrations sequentially
        for version in Self.migrationPath(from: plan.schemaVersion, to: kWorkoutPlanCurrentVersion) {
            let migrationChanges = applyMigration(to: plan, targetVersion: version)
            changes.append(contentsOf: migrationChanges)
        }

        // Update schema version
        plan.schemaVersion = kWorkoutPlanCurrentVersion
        plan.updatedAt = .now

        return MigrationResult(
            planId: plan.id,
            originalVersion: originalVersion,
            targetVersion: kWorkoutPlanCurrentVersion,
            success: true,
            changes: changes
        )
    }

    /// Migrate all plans in the database that need migration
    func migrateAllPlans() async throws -> BatchMigrationResult {
        let descriptor = FetchDescriptor<WorkoutPlan>()
        let allPlans = try modelContext.fetch(descriptor)

        var results: [MigrationResult] = []
        var successCount = 0
        var failureCount = 0

        for plan in allPlans {
            if plan.needsMigration {
                let result = migratePlan(plan)
                results.append(result)

                if result.success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
        }

        try modelContext.save()

        return BatchMigrationResult(
            totalPlans: allPlans.count,
            migratedCount: successCount,
            failedCount: failureCount,
            results: results
        )
    }

    // MARK: - Import Migration

    /// Migrate imported plan data to current version
    static func migrateImportData(_ data: Data) throws -> Data {
        let version = try detectVersion(from: data)

        guard isVersionSupported(version) else {
            throw PlanMigrationError.unsupportedVersion(version)
        }

        // If already at current version, return as-is
        guard version < ShareablePlan.currentExportVersion else {
            return data
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Decode the shareable plan
        let shareable = try decoder.decode(ShareablePlan.self, from: data)

        // Migrate to current version
        let migrated = shareable.migratedToCurrentVersion()

        // Re-encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(migrated)
    }

    /// Import and migrate plan data, returning the migrated plan
    func importAndMigrate(from data: Data, userId: UUID) throws -> (WorkoutPlan, MigrationResult?) {
        let version = try Self.detectVersion(from: data)

        guard Self.isVersionSupported(version) else {
            throw PlanMigrationError.unsupportedVersion(version)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let shareable = try decoder.decode(ShareablePlan.self, from: data)
        let plan = shareable.toPlan(userId: userId)

        // If imported from older version, migrate the plan
        var migrationResult: MigrationResult? = nil
        if plan.needsMigration {
            migrationResult = migratePlan(plan)
        }

        modelContext.insert(plan)

        return (plan, migrationResult)
    }

    // MARK: - Version-Specific Migrations

    /// Apply migration to a specific version
    private func applyMigration(to plan: WorkoutPlan, targetVersion: Int) -> [MigrationChange] {
        switch targetVersion {
        case 2:
            return migrateV1toV2(plan)
        default:
            return []
        }
    }

    /// Migrate from V1 to V2
    /// V2 adds: tags, equipmentRequired, targetMuscleGroups
    private func migrateV1toV2(_ plan: WorkoutPlan) -> [MigrationChange] {
        var changes: [MigrationChange] = []

        // Initialize new V2 fields with sensible defaults
        if plan.tags.isEmpty {
            // Auto-generate tags based on plan properties
            var autoTags: [String] = []

            // Add difficulty tag
            autoTags.append(plan.difficulty.rawValue.lowercased())

            // Add goal tag
            autoTags.append(plan.targetGoal.rawValue.lowercased())

            // Add days per week tag
            autoTags.append("\(plan.daysPerWeek)-day")

            plan.tags = autoTags
            changes.append(MigrationChange(
                field: "tags",
                oldValue: "[]",
                newValue: autoTags.joined(separator: ", "),
                description: "Auto-generated tags based on plan properties"
            ))
        }

        if plan.equipmentRequired.isEmpty {
            // Infer equipment from exercise names
            let equipment = inferEquipment(from: plan)
            if !equipment.isEmpty {
                plan.equipmentRequired = equipment
                changes.append(MigrationChange(
                    field: "equipmentRequired",
                    oldValue: "[]",
                    newValue: equipment.joined(separator: ", "),
                    description: "Inferred equipment from exercises"
                ))
            }
        }

        if plan.targetMuscleGroups.isEmpty {
            // Infer muscle groups from day names and exercises
            let muscleGroups = inferMuscleGroups(from: plan)
            if !muscleGroups.isEmpty {
                plan.targetMuscleGroups = muscleGroups
                changes.append(MigrationChange(
                    field: "targetMuscleGroups",
                    oldValue: "[]",
                    newValue: muscleGroups.joined(separator: ", "),
                    description: "Inferred muscle groups from plan structure"
                ))
            }
        }

        return changes
    }

    // MARK: - Inference Helpers

    /// Infer required equipment from exercise names
    private func inferEquipment(from plan: WorkoutPlan) -> [String] {
        var equipment: Set<String> = []

        let exerciseNames = plan.days
            .flatMap { $0.exercises }
            .map { $0.exerciseName.lowercased() }

        // Equipment inference rules
        let equipmentKeywords: [String: [String]] = [
            "Barbell": ["barbell", "squat", "deadlift", "bench press", "overhead press", "row"],
            "Dumbbells": ["dumbbell", "db", "dbell"],
            "Cable Machine": ["cable", "pulldown", "lat pull", "tricep push"],
            "Pull-up Bar": ["pull-up", "pullup", "chin-up", "chinup"],
            "Kettlebell": ["kettlebell", "kb"],
            "Resistance Bands": ["band", "resistance"],
            "Bench": ["bench", "incline", "decline"],
            "Squat Rack": ["squat", "rack"],
            "EZ Bar": ["ez bar", "ez curl", "preacher"]
        ]

        for (equipmentName, keywords) in equipmentKeywords {
            if exerciseNames.contains(where: { name in
                keywords.contains(where: { name.contains($0) })
            }) {
                equipment.insert(equipmentName)
            }
        }

        return Array(equipment).sorted()
    }

    /// Infer target muscle groups from plan structure
    private func inferMuscleGroups(from plan: WorkoutPlan) -> [String] {
        var muscleGroups: Set<String> = []

        // Check day names for common muscle group keywords
        let dayNames = plan.days.map { $0.name.lowercased() }

        let muscleKeywords: [String: [String]] = [
            "Chest": ["chest", "push", "pec"],
            "Back": ["back", "pull", "lat"],
            "Shoulders": ["shoulder", "delt", "push"],
            "Arms": ["arm", "bicep", "tricep"],
            "Legs": ["leg", "quad", "hamstring", "glute"],
            "Core": ["core", "ab", "abdominal"]
        ]

        for (muscle, keywords) in muscleKeywords {
            if dayNames.contains(where: { day in
                keywords.contains(where: { day.contains($0) })
            }) {
                muscleGroups.insert(muscle)
            }
        }

        // Also check exercise names
        let exerciseNames = plan.days
            .flatMap { $0.exercises }
            .map { $0.exerciseName.lowercased() }

        for (muscle, keywords) in muscleKeywords {
            if exerciseNames.contains(where: { name in
                keywords.contains(where: { name.contains($0) })
            }) {
                muscleGroups.insert(muscle)
            }
        }

        return Array(muscleGroups).sorted()
    }
}

// MARK: - Migration Types

/// Result of migrating a single plan
struct MigrationResult: Sendable {
    let planId: UUID
    let originalVersion: Int
    let targetVersion: Int
    let success: Bool
    let changes: [MigrationChange]

    var wasUpdated: Bool {
        !changes.isEmpty
    }
}

/// Result of batch migration
struct BatchMigrationResult: Sendable {
    let totalPlans: Int
    let migratedCount: Int
    let failedCount: Int
    let results: [MigrationResult]

    var allSuccessful: Bool {
        failedCount == 0
    }
}

/// A single change made during migration
struct MigrationChange: Sendable {
    let field: String
    let oldValue: String
    let newValue: String
    let description: String
}

// MARK: - Migration Errors

enum PlanMigrationError: LocalizedError {
    case unsupportedVersion(Int)
    case migrationFailed(String)
    case invalidData(String)
    case dataCorrupted

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Plan version \(version) is not supported. Please update the app."
        case .migrationFailed(let reason):
            return "Migration failed: \(reason)"
        case .invalidData(let details):
            return "Invalid plan data: \(details)"
        case .dataCorrupted:
            return "Plan data is corrupted and cannot be migrated"
        }
    }
}

// MARK: - Version History

/// Documents the version history for plan schemas
enum PlanVersionHistory {
    /// V1 (Initial): Basic plan structure
    /// - name, description, difficulty, goal
    /// - daysPerWeek, estimatedDuration
    /// - days with exercises
    static let v1Description = """
    Initial plan format with basic structure:
    - Plan metadata (name, description, difficulty, goal)
    - Schedule info (daysPerWeek, estimatedDuration)
    - Days containing exercises with sets/reps
    """

    /// V2 (Current): Enhanced metadata
    /// - Added: tags, equipmentRequired, targetMuscleGroups
    /// - Improved: Auto-inference of metadata from plan content
    static let v2Description = """
    Enhanced plan format with additional metadata:
    - Added tags for categorization and search
    - Added equipmentRequired for gym planning
    - Added targetMuscleGroups for program analysis
    - Auto-inference of new fields from existing content
    """

    /// Get description for a specific version
    static func description(for version: Int) -> String {
        switch version {
        case 1: return v1Description
        case 2: return v2Description
        default: return "Unknown version"
        }
    }
}
