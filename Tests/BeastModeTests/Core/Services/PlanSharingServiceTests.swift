// PlanSharingServiceTests.swift
// BeastModeTests
// Unit tests for plan sharing service using Swift Testing

import Testing
import SwiftData
import Foundation
@testable import BeastMode

@Suite("Plan Sharing Service")
struct PlanSharingServiceTests {

    // MARK: - Export

    @Suite("Plan Export")
    struct ExportTests {

        @Test("Exports plan with all metadata")
        @MainActor
        func exportsFullMetadata() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let plan = WorkoutFixtures.pplSplit(userId: userId)
            container.mainContext.insert(plan)
            try container.mainContext.save()

            let service = PlanSharingService(modelContext: container.mainContext)
            let data = try await service.exportPlan(plan)

            let exported = try JSONDecoder().decode(ShareablePlan.self, from: data)

            #expect(exported.version == 1)
            #expect(exported.name == plan.name)
            #expect(exported.difficulty == plan.difficulty.rawValue)
            #expect(exported.daysPerWeek == plan.daysPerWeek)
        }

        @Test("Exports all days and exercises")
        @MainActor
        func exportsAllDaysAndExercises() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let plan = WorkoutFixtures.pplSplit(userId: userId)
            container.mainContext.insert(plan)
            try container.mainContext.save()

            let service = PlanSharingService(modelContext: container.mainContext)
            let data = try await service.exportPlan(plan)

            let exported = try JSONDecoder().decode(ShareablePlan.self, from: data)

            #expect(exported.days.count == plan.days.count)

            // Verify exercises match
            let exportedExerciseCount = exported.days.reduce(0) { $0 + $1.exercises.count }
            let originalExerciseCount = plan.days.reduce(0) { $0 + $1.exercises.count }
            #expect(exportedExerciseCount == originalExerciseCount)
        }

        @Test("Export is valid JSON")
        @MainActor
        func exportIsValidJSON() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let plan = WorkoutFixtures.pplSplit(userId: userId)
            container.mainContext.insert(plan)
            try container.mainContext.save()

            let service = PlanSharingService(modelContext: container.mainContext)
            let data = try await service.exportPlan(plan)

            // Should not throw
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json != nil)
            #expect(json?["name"] != nil)
        }

        @Test("Export round-trips correctly")
        @MainActor
        func exportRoundTrips() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let original = WorkoutFixtures.pplSplit(userId: userId)
            container.mainContext.insert(original)
            try container.mainContext.save()

            let service = PlanSharingService(modelContext: container.mainContext)
            let data = try await service.exportPlan(original)

            // Should round-trip
            let decoded = try JSONDecoder().decode(ShareablePlan.self, from: data)
            #expect(decoded.name == original.name)
        }
    }

    // MARK: - Import

    @Suite("Plan Import")
    struct ImportTests {

        @Test("Imports plan from valid JSON")
        @MainActor
        func importsFromJSON() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PlanSharingService(modelContext: container.mainContext)

            let json = """
            {
                "version": 1,
                "name": "Test Plan",
                "description": "A test plan",
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "authorName": "Test Author",
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
                                "rpe": null,
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

            let data = json.data(using: .utf8)!
            let imported = try await service.importPlan(from: data, userId: UUID())

            #expect(imported.name == "Test Plan")
            #expect(imported.planDescription == "A test plan")
            #expect(imported.difficulty == .intermediate)
            #expect(imported.authorName == "Test Author")
            #expect(imported.days.count == 1)
            #expect(imported.days.first?.exercises.count == 1)
        }

        @Test("Import creates valid model objects")
        @MainActor
        func importCreatesValidModels() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            // Create and export a plan
            let original = WorkoutFixtures.pplSplit(userId: userId)
            container.mainContext.insert(original)
            try container.mainContext.save()

            let service = PlanSharingService(modelContext: container.mainContext)
            let data = try await service.exportPlan(original)

            // Import to new user
            let newUserId = UUID()
            let imported = try await service.importPlan(from: data, userId: newUserId)

            #expect(imported.userId == newUserId)
            #expect(imported.name == original.name)
            #expect(imported.days.count == original.days.count)

            // Verify exercises
            let originalExercises = original.days.flatMap(\.exercises)
            let importedExercises = imported.days.flatMap(\.exercises)
            #expect(importedExercises.count == originalExercises.count)
        }

        @Test("Throws on invalid JSON")
        @MainActor
        func throwsOnInvalidJSON() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PlanSharingService(modelContext: container.mainContext)

            let invalidJSON = "{ invalid json }"
            let data = invalidJSON.data(using: .utf8)!

            await #expect(throws: Error.self) {
                try await service.importPlan(from: data, userId: UUID())
            }
        }

        @Test("Throws on missing required fields")
        @MainActor
        func throwsOnMissingFields() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PlanSharingService(modelContext: container.mainContext)

            let incompleteJSON = """
            {
                "version": 1,
                "name": "Incomplete"
            }
            """
            let data = incompleteJSON.data(using: .utf8)!

            await #expect(throws: Error.self) {
                try await service.importPlan(from: data, userId: UUID())
            }
        }

        @Test("Throws on unsupported version")
        @MainActor
        func throwsOnUnsupportedVersion() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PlanSharingService(modelContext: container.mainContext)

            let futureVersionJSON = """
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
            let data = futureVersionJSON.data(using: .utf8)!

            await #expect(throws: PlanSharingError.self) {
                _ = try await service.validatePlanData(data)
            }
        }
    }

    // MARK: - Share Code

    @Suite("Share Code Generation")
    struct ShareCodeTests {

        @Test("Generates 8-character code")
        @MainActor
        func generates8CharCode() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let plan = WorkoutFixtures.pplSplit(userId: userId)
            container.mainContext.insert(plan)
            try container.mainContext.save()

            let service = PlanSharingService(modelContext: container.mainContext)
            let code = try await service.generateShareCode(for: plan)

            #expect(code.count == 8)
        }

        @Test("Uses only URL-safe characters")
        @MainActor
        func usesURLSafeChars() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()
            let allowedChars = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

            // Generate many codes to test randomness
            for _ in 0..<100 {
                let plan = WorkoutFixtures.emptyPlan(userId: userId)
                container.mainContext.insert(plan)

                let service = PlanSharingService(modelContext: container.mainContext)
                let code = try await service.generateShareCode(for: plan)

                let codeChars = CharacterSet(charactersIn: code)
                #expect(allowedChars.isSuperset(of: codeChars))
            }
        }

        @Test("Generates unique codes")
        @MainActor
        func generatesUniqueCodes() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()
            var codes: Set<String> = []

            for _ in 0..<100 {
                let plan = WorkoutFixtures.emptyPlan(userId: userId)
                container.mainContext.insert(plan)

                let service = PlanSharingService(modelContext: container.mainContext)
                let code = try await service.generateShareCode(for: plan)
                codes.insert(code)
            }

            // Should have very high uniqueness (allow for rare collisions)
            #expect(codes.count >= 95)
        }

        @Test("Sets share code on plan")
        @MainActor
        func setsShareCodeOnPlan() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let plan = WorkoutFixtures.pplSplit(userId: userId)
            container.mainContext.insert(plan)
            try container.mainContext.save()

            #expect(plan.shareCode == nil)

            let service = PlanSharingService(modelContext: container.mainContext)
            let code = try await service.generateShareCode(for: plan)

            #expect(plan.shareCode == code)
        }
    }

    // MARK: - Share Link

    @Suite("Share Link Generation")
    struct ShareLinkTests {

        @Test("Generates valid URL")
        @MainActor
        func generatesValidURL() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let plan = WorkoutFixtures.pplSplit(userId: userId)
            container.mainContext.insert(plan)
            try container.mainContext.save()

            let service = PlanSharingService(modelContext: container.mainContext)
            let url = try await service.generateShareLink(plan)

            #expect(url.scheme == "beastmode")
            #expect(url.host == "import")
            #expect(url.absoluteString.contains("plan="))
        }

        @Test("Share link contains base64 encoded plan")
        @MainActor
        func containsEncodedPlan() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let plan = WorkoutFixtures.pplSplit(userId: userId)
            container.mainContext.insert(plan)
            try container.mainContext.save()

            let service = PlanSharingService(modelContext: container.mainContext)
            let url = try await service.generateShareLink(plan)

            // Extract plan parameter
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let planParam = components?.queryItems?.first { $0.name == "plan" }?.value

            #expect(planParam != nil)

            // Should be valid base64
            let decoded = Data(base64Encoded: planParam!)
            #expect(decoded != nil)
        }

        @Test("Share link can be imported")
        @MainActor
        func shareLinkCanBeImported() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let userId = UUID()

            let original = WorkoutFixtures.pplSplit(userId: userId)
            container.mainContext.insert(original)
            try container.mainContext.save()

            let service = PlanSharingService(modelContext: container.mainContext)
            let url = try await service.generateShareLink(original)

            // Import from URL
            let newUserId = UUID()
            let imported = try await service.importPlanFromURL(url, userId: newUserId)

            #expect(imported.name == original.name)
            #expect(imported.days.count == original.days.count)
        }
    }

    // MARK: - Validation

    @Suite("Plan Validation")
    struct ValidationTests {

        @Test("Validates required name field")
        @MainActor
        func validatesName() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PlanSharingService(modelContext: container.mainContext)

            let json = """
            {
                "version": 1,
                "name": "",
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [],
                "createdAt": "2024-01-15T10:00:00Z"
            }
            """
            let data = json.data(using: .utf8)!

            await #expect(throws: PlanSharingError.self) {
                _ = try await service.validatePlanData(data)
            }
        }

        @Test("Validates at least one day")
        @MainActor
        func validatesHasDays() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PlanSharingService(modelContext: container.mainContext)

            let json = """
            {
                "version": 1,
                "name": "Empty Plan",
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [],
                "createdAt": "2024-01-15T10:00:00Z"
            }
            """
            let data = json.data(using: .utf8)!

            await #expect(throws: PlanSharingError.self) {
                _ = try await service.validatePlanData(data)
            }
        }

        @Test("Valid plan passes validation")
        @MainActor
        func validPlanPasses() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PlanSharingService(modelContext: container.mainContext)

            let json = """
            {
                "version": 1,
                "name": "Valid Plan",
                "difficulty": "Intermediate",
                "goal": "Strength",
                "daysPerWeek": 4,
                "estimatedDuration": 8,
                "days": [
                    {
                        "weekday": 2,
                        "name": "Day 1",
                        "isRestDay": false,
                        "exercises": []
                    }
                ],
                "createdAt": "2024-01-15T10:00:00Z"
            }
            """
            let data = json.data(using: .utf8)!

            let validated = try await service.validatePlanData(data)
            #expect(validated.name == "Valid Plan")
        }
    }
}
