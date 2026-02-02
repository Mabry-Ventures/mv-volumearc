// PlanMigrationServiceTests.swift
// BeastModeTests
// Unit tests for plan migration service using Swift Testing

import Testing
import SwiftData
import Foundation
@testable import BeastMode

@Suite("Plan Migration Service")
struct PlanMigrationServiceTests {

    // MARK: - Version Detection

    @Suite("Version Detection")
    struct VersionDetectionTests {

        @Test("Detects V1 from legacy format without version field")
        func detectsV1FromLegacyFormat() throws {
            let legacyJSON = """
            {
                "name": "Legacy Plan",
                "description": null,
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [],
                "createdAt": "2024-01-15T10:00:00Z"
            }
            """

            let data = legacyJSON.data(using: .utf8)!
            let version = try PlanMigrationService.detectVersion(from: data)

            #expect(version == 1)
        }

        @Test("Detects V1 from explicit version field")
        func detectsV1FromExplicit() throws {
            let v1JSON = """
            {
                "version": 1,
                "name": "V1 Plan",
                "description": null,
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [],
                "createdAt": "2024-01-15T10:00:00Z"
            }
            """

            let data = v1JSON.data(using: .utf8)!
            let version = try PlanMigrationService.detectVersion(from: data)

            #expect(version == 1)
        }

        @Test("Detects V2 from version field")
        func detectsV2() throws {
            let v2JSON = """
            {
                "version": 2,
                "name": "V2 Plan",
                "description": null,
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [],
                "createdAt": "2024-01-15T10:00:00Z",
                "tags": ["strength", "4-day"],
                "equipmentRequired": ["Barbell"],
                "targetMuscleGroups": ["Chest", "Back"]
            }
            """

            let data = v2JSON.data(using: .utf8)!
            let version = try PlanMigrationService.detectVersion(from: data)

            #expect(version == 2)
        }

        @Test("Detects future versions")
        func detectsFutureVersion() throws {
            let futureJSON = """
            {
                "version": 99,
                "name": "Future Plan"
            }
            """

            let data = futureJSON.data(using: .utf8)!
            let version = try PlanMigrationService.detectVersion(from: data)

            #expect(version == 99)
        }
    }

    // MARK: - Version Support

    @Suite("Version Support")
    struct VersionSupportTests {

        @Test("V1 is supported")
        func v1IsSupported() {
            #expect(PlanMigrationService.isVersionSupported(1) == true)
        }

        @Test("V2 is supported")
        func v2IsSupported() {
            #expect(PlanMigrationService.isVersionSupported(2) == true)
        }

        @Test("V0 is not supported")
        func v0NotSupported() {
            #expect(PlanMigrationService.isVersionSupported(0) == false)
        }

        @Test("Future versions are not supported")
        func futureVersionNotSupported() {
            #expect(PlanMigrationService.isVersionSupported(99) == false)
        }
    }

    // MARK: - Migration Path

    @Suite("Migration Path")
    struct MigrationPathTests {

        @Test("V1 to V2 requires one migration step")
        func v1ToV2Path() {
            let path = PlanMigrationService.migrationPath(from: 1, to: 2)
            #expect(path == [2])
        }

        @Test("Same version requires no migration")
        func sameVersionPath() {
            let path = PlanMigrationService.migrationPath(from: 2, to: 2)
            #expect(path.isEmpty)
        }

        @Test("Downgrade returns empty path")
        func downgradePath() {
            let path = PlanMigrationService.migrationPath(from: 2, to: 1)
            #expect(path.isEmpty)
        }

        @Test("Multiple version jumps include all steps")
        func multipleVersionPath() {
            let path = PlanMigrationService.migrationPath(from: 1, to: 5)
            #expect(path == [2, 3, 4, 5])
        }
    }

    // MARK: - Plan Migration

    @Suite("Plan Migration")
    struct PlanMigrationTests {

        @Test("Migrates V1 plan to V2")
        @MainActor
        func migratesV1ToV2() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            // Create a V1 plan (manually set schema version)
            let plan = WorkoutPlan(
                userId: userId,
                name: "Push/Pull/Legs",
                description: "Classic 6-day split",
                daysPerWeek: 6,
                difficulty: .intermediate,
                targetGoal: .hypertrophy
            )
            plan.schemaVersion = 1  // Simulate V1 plan

            // Add a push day
            let pushDay = PlanDay(weekday: 2, name: "Push Day", isRestDay: false)
            pushDay.exercises.append(PlanExercise(
                exerciseId: UUID(),
                exerciseName: "Bench Press",
                order: 0,
                targetSets: 4
            ))
            plan.days.append(pushDay)

            container.mainContext.insert(plan)
            try container.mainContext.save()

            #expect(plan.needsMigration == true)

            // Migrate
            let service = PlanMigrationService(modelContext: container.mainContext)
            let result = await service.migratePlan(plan)

            #expect(result.success == true)
            #expect(result.originalVersion == 1)
            #expect(result.targetVersion == kWorkoutPlanCurrentVersion)
            #expect(plan.schemaVersion == kWorkoutPlanCurrentVersion)
            #expect(plan.needsMigration == false)
        }

        @Test("V1 to V2 migration adds tags")
        @MainActor
        func v1ToV2AddsTags() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let plan = WorkoutPlan(
                userId: userId,
                name: "Test Plan",
                daysPerWeek: 4,
                difficulty: .advanced,
                targetGoal: .strength
            )
            plan.schemaVersion = 1
            plan.tags = []  // Empty tags

            container.mainContext.insert(plan)

            let service = PlanMigrationService(modelContext: container.mainContext)
            let result = await service.migratePlan(plan)

            #expect(result.success == true)
            #expect(!plan.tags.isEmpty)
            #expect(plan.tags.contains("advanced"))
            #expect(plan.tags.contains("strength"))
            #expect(plan.tags.contains("4-day"))
        }

        @Test("V1 to V2 migration infers equipment")
        @MainActor
        func v1ToV2InfersEquipment() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let plan = WorkoutPlan(userId: userId, name: "Barbell Plan")
            plan.schemaVersion = 1

            let day = PlanDay(weekday: 2, name: "Strength", isRestDay: false)
            day.exercises.append(PlanExercise(
                exerciseId: UUID(),
                exerciseName: "Barbell Squat",
                order: 0
            ))
            day.exercises.append(PlanExercise(
                exerciseId: UUID(),
                exerciseName: "Bench Press",
                order: 1
            ))
            plan.days.append(day)

            container.mainContext.insert(plan)

            let service = PlanMigrationService(modelContext: container.mainContext)
            _ = await service.migratePlan(plan)

            #expect(plan.equipmentRequired.contains("Barbell"))
        }

        @Test("V1 to V2 migration infers muscle groups")
        @MainActor
        func v1ToV2InfersMuscleGroups() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let plan = WorkoutPlan(userId: userId, name: "Full Body")
            plan.schemaVersion = 1

            let day1 = PlanDay(weekday: 2, name: "Push Day", isRestDay: false)
            day1.exercises.append(PlanExercise(
                exerciseId: UUID(),
                exerciseName: "Chest Press",
                order: 0
            ))
            plan.days.append(day1)

            let day2 = PlanDay(weekday: 3, name: "Leg Day", isRestDay: false)
            day2.exercises.append(PlanExercise(
                exerciseId: UUID(),
                exerciseName: "Squat",
                order: 0
            ))
            plan.days.append(day2)

            container.mainContext.insert(plan)

            let service = PlanMigrationService(modelContext: container.mainContext)
            _ = await service.migratePlan(plan)

            #expect(plan.targetMuscleGroups.contains("Chest"))
            #expect(plan.targetMuscleGroups.contains("Legs"))
        }

        @Test("Already current version skips migration")
        @MainActor
        func currentVersionSkipsMigration() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let plan = WorkoutPlan(userId: userId, name: "Current Plan")
            // schemaVersion is already set to current by init

            container.mainContext.insert(plan)

            #expect(plan.needsMigration == false)

            let service = PlanMigrationService(modelContext: container.mainContext)
            let result = await service.migratePlan(plan)

            #expect(result.success == true)
            #expect(result.changes.isEmpty)
        }
    }

    // MARK: - Batch Migration

    @Suite("Batch Migration")
    struct BatchMigrationTests {

        @Test("Migrates multiple plans")
        @MainActor
        func migratesMultiplePlans() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            // Create multiple V1 plans
            for i in 1...5 {
                let plan = WorkoutPlan(userId: userId, name: "Plan \(i)")
                plan.schemaVersion = 1
                container.mainContext.insert(plan)
            }

            try container.mainContext.save()

            let service = PlanMigrationService(modelContext: container.mainContext)
            let result = try await service.migrateAllPlans()

            #expect(result.totalPlans == 5)
            #expect(result.migratedCount == 5)
            #expect(result.failedCount == 0)
            #expect(result.allSuccessful == true)
        }

        @Test("Skips already current plans in batch")
        @MainActor
        func skipsCurrentInBatch() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            // Create mix of V1 and current plans
            let v1Plan = WorkoutPlan(userId: userId, name: "V1 Plan")
            v1Plan.schemaVersion = 1
            container.mainContext.insert(v1Plan)

            let currentPlan = WorkoutPlan(userId: userId, name: "Current Plan")
            container.mainContext.insert(currentPlan)

            try container.mainContext.save()

            let service = PlanMigrationService(modelContext: container.mainContext)
            let result = try await service.migrateAllPlans()

            #expect(result.totalPlans == 2)
            #expect(result.migratedCount == 1)  // Only V1 plan migrated
        }
    }

    // MARK: - Import Migration

    @Suite("Import Migration")
    struct ImportMigrationTests {

        @Test("Migrates V1 import data to current version")
        func migratesV1ImportData() throws {
            let v1JSON = """
            {
                "version": 1,
                "name": "V1 Imported Plan",
                "description": "Test",
                "authorName": null,
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [
                    {
                        "weekday": 2,
                        "name": "Day 1",
                        "isRestDay": false,
                        "notes": null,
                        "exercises": []
                    }
                ],
                "createdAt": "2024-01-15T10:00:00Z"
            }
            """

            let data = v1JSON.data(using: .utf8)!
            let migratedData = try PlanMigrationService.migrateImportData(data)

            // Decode migrated data
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let migrated = try decoder.decode(ShareablePlan.self, from: migratedData)

            #expect(migrated.version == ShareablePlan.currentExportVersion)
            #expect(migrated.name == "V1 Imported Plan")
        }

        @Test("Current version data passes through unchanged")
        func currentVersionPassesThrough() throws {
            let v2JSON = """
            {
                "version": 2,
                "name": "V2 Plan",
                "description": null,
                "authorName": null,
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [
                    {
                        "weekday": 2,
                        "name": "Day 1",
                        "isRestDay": false,
                        "notes": null,
                        "exercises": []
                    }
                ],
                "createdAt": "2024-01-15T10:00:00Z",
                "tags": ["test"],
                "equipmentRequired": null,
                "targetMuscleGroups": null
            }
            """

            let data = v2JSON.data(using: .utf8)!
            let migratedData = try PlanMigrationService.migrateImportData(data)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let migrated = try decoder.decode(ShareablePlan.self, from: migratedData)

            #expect(migrated.version == 2)
            #expect(migrated.tags == ["test"])
        }

        @Test("Throws on unsupported version")
        func throwsOnUnsupportedVersion() throws {
            let futureJSON = """
            {
                "version": 99,
                "name": "Future Plan",
                "description": null,
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [],
                "createdAt": "2024-01-15T10:00:00Z"
            }
            """

            let data = futureJSON.data(using: .utf8)!

            #expect(throws: PlanMigrationError.self) {
                _ = try PlanMigrationService.migrateImportData(data)
            }
        }

        @Test("Import and migrate creates valid plan")
        @MainActor
        func importAndMigrateCreatesValidPlan() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let v1JSON = """
            {
                "version": 1,
                "name": "Imported PPL",
                "description": "Push Pull Legs",
                "authorName": "Test Author",
                "difficulty": "Advanced",
                "goal": "Hypertrophy",
                "daysPerWeek": 6,
                "estimatedDuration": 12,
                "days": [
                    {
                        "weekday": 2,
                        "name": "Push Day",
                        "isRestDay": false,
                        "notes": null,
                        "exercises": [
                            {
                                "name": "Bench Press",
                                "sets": 4,
                                "repsMin": 6,
                                "repsMax": 8,
                                "rpe": 8.0,
                                "restSeconds": 120,
                                "notes": null,
                                "superset": false
                            }
                        ]
                    }
                ],
                "createdAt": "2024-01-15T10:00:00Z"
            }
            """

            let data = v1JSON.data(using: .utf8)!

            let service = PlanMigrationService(modelContext: container.mainContext)
            let (plan, migrationResult) = try await service.importAndMigrate(from: data, userId: userId)

            #expect(plan.name == "Imported PPL")
            #expect(plan.schemaVersion == kWorkoutPlanCurrentVersion)
            #expect(plan.userId == userId)
            #expect(plan.days.count == 1)

            #expect(migrationResult != nil)
            #expect(migrationResult?.success == true)
        }
    }

    // MARK: - ShareablePlan Versioning

    @Suite("ShareablePlan Versioning")
    struct ShareablePlanVersioningTests {

        @Test("New plans export at current version")
        @MainActor
        func newPlansExportAtCurrentVersion() throws {
            let plan = WorkoutPlan(userId: UUID(), name: "Test Plan")
            let shareable = ShareablePlan(from: plan)

            #expect(shareable.version == ShareablePlan.currentExportVersion)
        }

        @Test("V2 fields are included in export")
        @MainActor
        func v2FieldsIncluded() throws {
            let plan = WorkoutPlan(userId: UUID(), name: "Test Plan")
            plan.tags = ["strength", "beginner"]
            plan.equipmentRequired = ["Barbell", "Dumbbells"]
            plan.targetMuscleGroups = ["Chest", "Back"]

            let shareable = ShareablePlan(from: plan)

            #expect(shareable.tags == ["strength", "beginner"])
            #expect(shareable.equipmentRequired == ["Barbell", "Dumbbells"])
            #expect(shareable.targetMuscleGroups == ["Chest", "Back"])
        }

        @Test("Empty V2 fields export as nil")
        @MainActor
        func emptyV2FieldsExportAsNil() throws {
            let plan = WorkoutPlan(userId: UUID(), name: "Test Plan")
            // Leave V2 fields empty (default)

            let shareable = ShareablePlan(from: plan)

            #expect(shareable.tags == nil)
            #expect(shareable.equipmentRequired == nil)
            #expect(shareable.targetMuscleGroups == nil)
        }

        @Test("V1 import sets empty V2 fields to defaults")
        func v1ImportSetsDefaults() throws {
            let v1JSON = """
            {
                "version": 1,
                "name": "V1 Plan",
                "description": null,
                "authorName": null,
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [],
                "createdAt": "2024-01-15T10:00:00Z"
            }
            """

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let shareable = try decoder.decode(ShareablePlan.self, from: v1JSON.data(using: .utf8)!)

            let plan = shareable.toPlan(userId: UUID())

            // V2 fields should be empty arrays (not nil)
            #expect(plan.tags.isEmpty)
            #expect(plan.equipmentRequired.isEmpty)
            #expect(plan.targetMuscleGroups.isEmpty)
        }

        @Test("isVersionSupported returns correct values")
        func isVersionSupportedCorrect() throws {
            // Create shareable plans with different versions for testing
            let v1JSON = """
            {
                "version": 1,
                "name": "V1",
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [],
                "createdAt": "2024-01-15T10:00:00Z"
            }
            """

            let v2JSON = """
            {
                "version": 2,
                "name": "V2",
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [],
                "createdAt": "2024-01-15T10:00:00Z"
            }
            """

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let v1 = try decoder.decode(ShareablePlan.self, from: v1JSON.data(using: .utf8)!)
            let v2 = try decoder.decode(ShareablePlan.self, from: v2JSON.data(using: .utf8)!)

            #expect(v1.isVersionSupported == true)
            #expect(v2.isVersionSupported == true)
            #expect(v1.needsMigration == true)
            #expect(v2.needsMigration == false)
        }
    }

    // MARK: - Migration Result

    @Suite("Migration Result")
    struct MigrationResultTests {

        @Test("Result tracks version changes")
        @MainActor
        func resultTracksVersionChanges() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let plan = WorkoutPlan(userId: UUID(), name: "Test")
            plan.schemaVersion = 1
            container.mainContext.insert(plan)

            let service = PlanMigrationService(modelContext: container.mainContext)
            let result = await service.migratePlan(plan)

            #expect(result.originalVersion == 1)
            #expect(result.targetVersion == kWorkoutPlanCurrentVersion)
            #expect(result.planId == plan.id)
        }

        @Test("Result includes change descriptions")
        @MainActor
        func resultIncludesChanges() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let plan = WorkoutPlan(userId: UUID(), name: "Test")
            plan.schemaVersion = 1
            container.mainContext.insert(plan)

            let service = PlanMigrationService(modelContext: container.mainContext)
            let result = await service.migratePlan(plan)

            #expect(result.wasUpdated == true)
            #expect(!result.changes.isEmpty)

            // Should have change for tags at minimum
            let tagChange = result.changes.first { $0.field == "tags" }
            #expect(tagChange != nil)
        }
    }
}
