// SchemaMigration.swift
// BeastMode
// SwiftData schema versioning and migration support

import SwiftData
import Foundation

// MARK: - Schema Version 1.0

/// Initial schema version (V1.0)
/// This represents the baseline schema for the app
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            UserStreak.self,
            Exercise.self,
            Workout.self,
            WorkoutExercise.self,
            SetLog.self,
            PersonalRecord.self,
            WorkoutPlan.self,
            PlanDay.self,
            PlanExercise.self
        ]
    }
}

// MARK: - Current Schema

/// Type alias for the current schema version
/// Update this when adding new schema versions
typealias CurrentSchema = SchemaV1

// MARK: - Migration Plan

/// Migration plan defining how to migrate between schema versions
enum BeastModeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SchemaV1.self
            // Add new schema versions here as they are created:
            // SchemaV2.self,
            // SchemaV3.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            // Add migration stages here when creating new versions:
            // migrateV1toV2,
            // migrateV2toV3,
        ]
    }

    // MARK: - Migration Stages

    // Example migration stage (uncomment and modify when needed):
    /*
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
    */

    // For custom migrations that require data transformation:
    /*
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: { context in
            // Pre-migration logic (optional)
            // Run before SwiftData performs the migration
        },
        didMigrate: { context in
            // Post-migration logic
            // Transform data after migration
            let workouts = try context.fetch(FetchDescriptor<Workout>())
            for workout in workouts {
                // Apply data transformations
            }
            try context.save()
        }
    )
    */
}

// MARK: - Model Container Factory

/// Factory for creating properly configured ModelContainers
enum ModelContainerFactory {

    /// Create a model container with migration support
    static func createContainer(
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )

        // Create container with migration plan
        return try ModelContainer(
            for: schema,
            migrationPlan: BeastModeMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Create an in-memory container for testing/previews
    static func createPreviewContainer() throws -> ModelContainer {
        try createContainer(inMemory: true)
    }

    /// Create a container with sample data for previews
    static func createPreviewContainerWithSampleData() throws -> ModelContainer {
        let container = try createPreviewContainer()
        let context = container.mainContext

        // Add sample profile
        let profile = UserProfile(displayName: "Preview User")
        context.insert(profile)

        // Add sample streak
        let streak = UserStreak(userId: profile.id)
        streak.currentStreak = 7
        streak.longestStreak = 14
        context.insert(streak)

        // Add sample exercises
        let exercises = [
            Exercise(name: "Bench Press", category: .chest, exerciseType: .weightAndReps,
                    muscleGroups: ["Chest", "Triceps"], isCompound: true, isCustom: false),
            Exercise(name: "Squat", category: .legs, exerciseType: .weightAndReps,
                    muscleGroups: ["Quads", "Glutes"], isCompound: true, isCustom: false),
            Exercise(name: "Deadlift", category: .back, exerciseType: .weightAndReps,
                    muscleGroups: ["Back", "Hamstrings"], isCompound: true, isCustom: false)
        ]
        exercises.forEach { context.insert($0) }

        try context.save()

        return container
    }
}

// MARK: - Migration Guidelines

/*
 MIGRATION GUIDELINES
 ====================

 When you need to modify the data model, follow these steps:

 1. CREATE A NEW SCHEMA VERSION
    - Create a new enum (e.g., SchemaV2) conforming to VersionedSchema
    - Define the new versionIdentifier (increment appropriately)
    - List all models in the new schema

 2. UPDATE CURRENTSCHEMA
    - Change the typealias to point to the new schema

 3. ADD MIGRATION STAGE
    - Add the new schema to the `schemas` array in BeastModeMigrationPlan
    - Create a migration stage (lightweight or custom) in the `stages` array

 4. LIGHTWEIGHT VS CUSTOM MIGRATIONS
    - Lightweight: Simple changes like adding optional properties, renaming
    - Custom: Complex changes requiring data transformation

 EXAMPLE: Adding a new optional property to Workout

 1. Add the property to Workout model:
    @Attribute(.optional) var notes: String?

 2. Create SchemaV2 (copy SchemaV1, change version to 1.1.0)

 3. Add migration:
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )

 4. Update schemas array to include SchemaV2
 5. Update stages array to include migrateV1toV2
 6. Update CurrentSchema typealias to SchemaV2

 TESTING MIGRATIONS
 ==================
 Always test migrations before release:
 1. Create a database with the old schema
 2. Run the app with the new schema
 3. Verify data integrity
 4. Check for crashes or data loss

*/
