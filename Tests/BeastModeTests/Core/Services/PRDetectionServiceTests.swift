// PRDetectionServiceTests.swift
// BeastModeTests
// Unit tests for PR detection service using Swift Testing

import Testing
import SwiftData
import Foundation
@testable import BeastMode

@Suite("PR Detection Service")
struct PRDetectionServiceTests {

    // MARK: - First Time PR Detection

    @Suite("First Time PR")
    struct FirstTimePRTests {

        @Test("Detects first ever set as PR")
        @MainActor
        func detectsFirstEverSetAsPR() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PRDetectionService(modelContext: container.mainContext)

            let result = await service.checkForPR(
                exerciseName: "New Exercise",
                weight: 100,
                reps: 10,
                userId: UUID()
            )

            #expect(result == .firstTime)
        }

        @Test("First PR has correct properties")
        func firstPRProperties() {
            let prType = PRType.firstTime

            #expect(prType.title == "FIRST PR!")
            #expect(prType.subtitle == "You're on the board!")
            #expect(prType.isFirstTime)
        }

        @Test("First PR for new exercise with existing PRs")
        @MainActor
        func firstPRNewExerciseWithHistory() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Insert PR for different exercise
            let existingPR = PRFixtures.makePR(
                exercise: "Barbell Bench Press",
                weight: 185,
                reps: 8,
                userId: userId
            )
            context.insert(existingPR)
            try context.save()

            let service = PRDetectionService(modelContext: context)

            // Check for new exercise
            let result = await service.checkForPR(
                exerciseName: "Barbell Squats",
                weight: 135,
                reps: 10,
                userId: userId
            )

            #expect(result == .firstTime)
        }
    }

    // MARK: - Estimated 1RM PR Detection

    @Suite("Estimated 1RM PR")
    struct EstimatedMaxPRTests {

        @Test("Detects higher E1RM as new max")
        @MainActor
        func detectsHigherE1RM() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Insert existing PR: 205 × 6 = E1RM ~238
            let existingPR = PRFixtures.makePR(
                exercise: "Barbell Bench Press",
                weight: 205,
                reps: 6,
                userId: userId
            )
            context.insert(existingPR)
            try context.save()

            let service = PRDetectionService(modelContext: context)

            // Test: 225 × 5 = E1RM ~253 (higher)
            let result = await service.checkForPR(
                exerciseName: "Barbell Bench Press",
                weight: 225,
                reps: 5,
                userId: userId
            )

            guard case .estimatedMax(let improvement) = result else {
                Issue.record("Expected estimatedMax PR type, got \(String(describing: result))")
                return
            }
            #expect(improvement > 0)
        }

        @Test("E1RM improvements with various weights and reps",
              arguments: [
                (weight: 225.0, reps: 5, shouldBePR: true),
                (weight: 215.0, reps: 8, shouldBePR: true),
                (weight: 200.0, reps: 6, shouldBePR: false),
                (weight: 185.0, reps: 10, shouldBePR: false)
              ])
        @MainActor
        func e1rmVariations(weight: Double, reps: Int, shouldBePR: Bool) async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Insert existing PR: 205 × 6 = E1RM ~238
            let existingPR = PRFixtures.makePR(
                exercise: "Barbell Bench Press",
                weight: 205,
                reps: 6,
                userId: userId
            )
            context.insert(existingPR)
            try context.save()

            let service = PRDetectionService(modelContext: context)

            let result = await service.checkForPR(
                exerciseName: "Barbell Bench Press",
                weight: weight,
                reps: reps,
                userId: userId
            )

            if shouldBePR {
                #expect(result != nil, "Expected PR for \(weight)×\(reps)")
            } else {
                #expect(result == nil, "Expected no PR for \(weight)×\(reps)")
            }
        }

        @Test("E1RM calculation uses Brzycki formula")
        @MainActor
        func e1rmFormula() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PRDetectionService(modelContext: container.mainContext)

            // Brzycki: weight × (36 / (37 - reps))
            // 200 × 8 = 200 × (36/29) = 248.28
            let e1rm = service.calculateE1RM(weight: 200, reps: 8)

            #expect(e1rm.isApproximatelyEqual(to: 248.28, tolerance: 0.1))
        }

        @Test("E1RM returns weight for single rep")
        @MainActor
        func e1rmSingleRep() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PRDetectionService(modelContext: container.mainContext)

            let e1rm = service.calculateE1RM(weight: 315, reps: 1)

            #expect(e1rm == 315)
        }

        @Test("E1RM caps at 12 reps for accuracy")
        @MainActor
        func e1rmCapsAt12Reps() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PRDetectionService(modelContext: container.mainContext)

            let e1rm = service.calculateE1RM(weight: 135, reps: 20)

            // Should return raw weight when reps > 12
            #expect(e1rm == 135)
        }

        @Test("E1RM calculations for common rep ranges",
              arguments: [
                (reps: 1, multiplier: 1.0),
                (reps: 3, multiplier: 1.059),
                (reps: 5, multiplier: 1.125),
                (reps: 8, multiplier: 1.241),
                (reps: 10, multiplier: 1.333),
                (reps: 12, multiplier: 1.44)
              ])
        @MainActor
        func e1rmMultipliers(reps: Int, multiplier: Double) async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PRDetectionService(modelContext: container.mainContext)

            let baseWeight = 200.0
            let e1rm = service.calculateE1RM(weight: baseWeight, reps: reps)
            let expectedE1rm = baseWeight * multiplier

            #expect(e1rm.isApproximatelyEqual(to: expectedE1rm, tolerance: 1.0))
        }
    }

    // MARK: - Heaviest Weight PR Detection

    @Suite("Heaviest Weight PR")
    struct HeaviestWeightPRTests {

        @Test("Detects heaviest weight ever lifted")
        @MainActor
        func detectsHeaviestWeight() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Insert history with max weight of 215
            for pr in PRFixtures.benchPressPRHistory(userId: userId) {
                context.insert(pr)
            }
            try context.save()

            let service = PRDetectionService(modelContext: context)

            // Lift 225 (heavier than any previous)
            let result = await service.checkForPR(
                exerciseName: "Barbell Bench Press",
                weight: 225,
                reps: 3,
                userId: userId
            )

            guard case .heaviestWeight(let weight) = result else {
                Issue.record("Expected heaviestWeight PR type")
                return
            }
            #expect(weight == 225)
        }

        @Test("Does not trigger for lighter weight")
        @MainActor
        func noHeaviestForLighterWeight() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let existingPR = PRFixtures.makePR(
                exercise: "Barbell Bench Press",
                weight: 225,
                reps: 5,
                userId: userId
            )
            context.insert(existingPR)
            try context.save()

            let service = PRDetectionService(modelContext: context)

            // Lift 200 (lighter than previous max)
            let result = await service.checkForPR(
                exerciseName: "Barbell Bench Press",
                weight: 200,
                reps: 3,
                userId: userId
            )

            // Should be nil (not heavier, E1RM not higher)
            #expect(result == nil)
        }
    }

    // MARK: - Rep Record PR Detection

    @Suite("Rep Record PR")
    struct RepRecordPRTests {

        @Test("Detects more reps at same weight")
        @MainActor
        func detectsRepRecord() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Previous best: 185 × 8
            let existingPR = PRFixtures.makePR(
                exercise: "Barbell Bench Press",
                weight: 185,
                reps: 8,
                userId: userId
            )
            context.insert(existingPR)
            try context.save()

            let service = PRDetectionService(modelContext: context)

            // New: 185 × 10 (same weight, more reps)
            let result = await service.checkForPR(
                exerciseName: "Barbell Bench Press",
                weight: 185,
                reps: 10,
                userId: userId
            )

            guard case .repRecord(let atWeight, let reps) = result else {
                Issue.record("Expected repRecord PR type")
                return
            }
            #expect(atWeight == 185)
            #expect(reps == 10)
        }

        @Test("Does not trigger rep record for same reps")
        @MainActor
        func noRepRecordForSameReps() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let existingPR = PRFixtures.makePR(
                exercise: "Barbell Bench Press",
                weight: 185,
                reps: 8,
                userId: userId
            )
            context.insert(existingPR)
            try context.save()

            let service = PRDetectionService(modelContext: context)

            let result = await service.checkForPR(
                exerciseName: "Barbell Bench Press",
                weight: 185,
                reps: 8,
                userId: userId
            )

            #expect(result == nil)
        }

        @Test("Does not trigger rep record for fewer reps")
        @MainActor
        func noRepRecordForFewerReps() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let existingPR = PRFixtures.makePR(
                exercise: "Barbell Bench Press",
                weight: 185,
                reps: 8,
                userId: userId
            )
            context.insert(existingPR)
            try context.save()

            let service = PRDetectionService(modelContext: context)

            let result = await service.checkForPR(
                exerciseName: "Barbell Bench Press",
                weight: 185,
                reps: 6,
                userId: userId
            )

            #expect(result == nil)
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test("Handles zero weight gracefully")
        @MainActor
        func handlesZeroWeight() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PRDetectionService(modelContext: container.mainContext)

            let result = await service.checkForPR(
                exerciseName: "Bodyweight Exercise",
                weight: 0,
                reps: 20,
                userId: UUID()
            )

            // Should still detect as first time for this exercise
            #expect(result == .firstTime)
        }

        @Test("Handles zero reps gracefully")
        @MainActor
        func handlesZeroReps() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PRDetectionService(modelContext: container.mainContext)

            let result = await service.checkForPR(
                exerciseName: "Test Exercise",
                weight: 100,
                reps: 0,
                userId: UUID()
            )

            // Invalid set should not be a PR
            #expect(result == nil)
        }

        @Test("Handles negative weight gracefully")
        @MainActor
        func handlesNegativeWeight() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PRDetectionService(modelContext: container.mainContext)

            let result = await service.checkForPR(
                exerciseName: "Test Exercise",
                weight: -50,
                reps: 10,
                userId: UUID()
            )

            #expect(result == nil)
        }

        @Test("Exercise name matching is case-insensitive")
        @MainActor
        func caseInsensitiveMatching() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let existingPR = PRFixtures.makePR(
                exercise: "Barbell Bench Press",
                weight: 185,
                reps: 8,
                userId: userId
            )
            context.insert(existingPR)
            try context.save()

            let service = PRDetectionService(modelContext: context)

            // Query with different casing
            let result = await service.checkForPR(
                exerciseName: "BARBELL BENCH PRESS",
                weight: 185,
                reps: 10,
                userId: userId
            )

            // Should find existing PR and detect rep record
            #expect(result != nil)
        }

        @Test("Handles very high rep counts")
        @MainActor
        func handlesHighRepCounts() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PRDetectionService(modelContext: container.mainContext)

            let result = await service.checkForPR(
                exerciseName: "Push-ups",
                weight: 0,
                reps: 100,
                userId: UUID()
            )

            #expect(result == .firstTime)
        }

        @Test("Handles very heavy weights")
        @MainActor
        func handlesVeryHeavyWeights() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = PRDetectionService(modelContext: container.mainContext)

            let result = await service.checkForPR(
                exerciseName: "Deadlift",
                weight: 1000,
                reps: 1,
                userId: UUID()
            )

            #expect(result == .firstTime)
        }
    }

    // MARK: - PR Priority

    @Suite("PR Priority")
    struct PRPriorityTests {

        @Test("E1RM improvement takes priority over rep record")
        @MainActor
        func e1rmPriorityOverRepRecord() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Existing: 185 × 8 (E1RM ~229)
            let existingPR = PRFixtures.makePR(
                exercise: "Barbell Bench Press",
                weight: 185,
                reps: 8,
                userId: userId
            )
            context.insert(existingPR)
            try context.save()

            let service = PRDetectionService(modelContext: context)

            // New: 185 × 12 (E1RM ~266) - both rep record AND E1RM improvement
            let result = await service.checkForPR(
                exerciseName: "Barbell Bench Press",
                weight: 185,
                reps: 12,
                userId: userId
            )

            // Should return E1RM improvement (higher priority)
            guard case .estimatedMax = result else {
                Issue.record("Expected estimatedMax PR type for E1RM improvement")
                return
            }
        }
    }
}

// MARK: - Test Helpers

extension Double {
    func isApproximatelyEqual(to other: Double, tolerance: Double) -> Bool {
        abs(self - other) <= tolerance
    }
}
