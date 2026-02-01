// PRDetectionTests.swift
// BeastModeTests
// Unit tests for PR detection logic

import XCTest
import SwiftData
@testable import BeastMode

final class PRDetectionTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            PersonalRecord.self,
            UserProfile.self,
            UserStreak.self,
            Exercise.self,
            Workout.self,
            WorkoutExercise.self,
            SetLog.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
    }

    // MARK: - E1RM Formula Tests

    func testE1RMCalculation_SingleRep() async {
        let service = PRDetectionService(modelContext: modelContext)
        let e1rm = await service.calculateE1RM(weight: 225, reps: 1)
        XCTAssertEqual(e1rm, 225, accuracy: 0.01, "1RM should equal the weight lifted")
    }

    func testE1RMCalculation_FiveReps() async {
        let service = PRDetectionService(modelContext: modelContext)
        let e1rm = await service.calculateE1RM(weight: 185, reps: 5)

        // Brzycki formula: 185 * (36 / (37 - 5)) = 185 * (36/32) = 208.125
        let expected = 185.0 * (36.0 / 32.0)
        XCTAssertEqual(e1rm, expected, accuracy: 0.01)
    }

    func testE1RMCalculation_TenReps() async {
        let service = PRDetectionService(modelContext: modelContext)
        let e1rm = await service.calculateE1RM(weight: 135, reps: 10)

        // Brzycki formula: 135 * (36 / (37 - 10)) = 135 * (36/27) = 180
        let expected = 135.0 * (36.0 / 27.0)
        XCTAssertEqual(e1rm, expected, accuracy: 0.01)
    }

    func testE1RMCalculation_HighReps_CappedAt12() async {
        let service = PRDetectionService(modelContext: modelContext)
        let e1rm_15reps = await service.calculateE1RM(weight: 100, reps: 15)
        let e1rm_12reps = await service.calculateE1RM(weight: 100, reps: 12)

        // Both should use 12 reps for calculation
        XCTAssertEqual(e1rm_15reps, e1rm_12reps, accuracy: 0.01)
    }

    // MARK: - PR Detection Tests

    func testPRDetection_FirstTime() async throws {
        let service = PRDetectionService(modelContext: modelContext)
        let userId = UUID()

        let result = await service.checkForPR(
            exerciseName: "Bench Press",
            weight: 135,
            reps: 10,
            userId: userId
        )

        XCTAssertEqual(result, .firstTime)
    }

    func testPRDetection_EstimatedMax() async throws {
        let service = PRDetectionService(modelContext: modelContext)
        let userId = UUID()

        // Create existing PR
        let existingPR = PersonalRecord(
            exerciseName: "Bench Press",
            weight: 135,
            reps: 10,
            estimatedOneRepMax: 180,
            userId: userId
        )
        modelContext.insert(existingPR)
        try modelContext.save()

        // Check for new PR with higher E1RM
        let result = await service.checkForPR(
            exerciseName: "Bench Press",
            weight: 185,
            reps: 5,
            userId: userId
        )

        // 185 x 5 = ~208 E1RM, which is higher than 180
        if case .estimatedMax(let improvement) = result {
            XCTAssertGreaterThan(improvement, 0)
        } else {
            XCTFail("Expected estimatedMax PR type")
        }
    }

    func testPRDetection_HeaviestWeight() async throws {
        let service = PRDetectionService(modelContext: modelContext)
        let userId = UUID()

        // Create existing PR with higher E1RM but lower weight
        let existingPR = PersonalRecord(
            exerciseName: "Bench Press",
            weight: 185,
            reps: 5,
            estimatedOneRepMax: 208,
            userId: userId
        )
        modelContext.insert(existingPR)
        try modelContext.save()

        // Lift heavier weight but with lower E1RM
        let result = await service.checkForPR(
            exerciseName: "Bench Press",
            weight: 200,
            reps: 1,
            userId: userId
        )

        // 200 x 1 = 200 E1RM (less than 208), but heavier weight
        if case .heaviestWeight(let weight) = result {
            XCTAssertEqual(weight, 200)
        } else {
            XCTFail("Expected heaviestWeight PR type, got \(String(describing: result))")
        }
    }

    func testPRDetection_RepRecord() async throws {
        let service = PRDetectionService(modelContext: modelContext)
        let userId = UUID()

        // Create existing PR
        let existingPR = PersonalRecord(
            exerciseName: "Bench Press",
            weight: 185,
            reps: 5,
            estimatedOneRepMax: 208,
            userId: userId
        )
        modelContext.insert(existingPR)
        try modelContext.save()

        // More reps at same weight but still lower E1RM than max
        let result = await service.checkForPR(
            exerciseName: "Bench Press",
            weight: 185,
            reps: 8,
            userId: userId
        )

        // 185 x 8 = 227 E1RM (higher than 208), so this should be estimatedMax
        if case .estimatedMax = result {
            // This is correct - more reps at same weight increases E1RM
        } else if case .repRecord = result {
            // Also acceptable
        } else {
            XCTFail("Expected PR detection, got \(String(describing: result))")
        }
    }

    func testPRDetection_NoPR() async throws {
        let service = PRDetectionService(modelContext: modelContext)
        let userId = UUID()

        // Create existing PR
        let existingPR = PersonalRecord(
            exerciseName: "Bench Press",
            weight: 225,
            reps: 5,
            estimatedOneRepMax: 253,
            userId: userId
        )
        modelContext.insert(existingPR)
        try modelContext.save()

        // Lift less weight and reps
        let result = await service.checkForPR(
            exerciseName: "Bench Press",
            weight: 135,
            reps: 10,
            userId: userId
        )

        XCTAssertNil(result, "Should not detect PR for lower performance")
    }

    func testPRDetection_ZeroWeight_ReturnsNil() async {
        let service = PRDetectionService(modelContext: modelContext)

        let result = await service.checkForPR(
            exerciseName: "Bench Press",
            weight: 0,
            reps: 10,
            userId: UUID()
        )

        XCTAssertNil(result)
    }

    func testPRDetection_ZeroReps_ReturnsNil() async {
        let service = PRDetectionService(modelContext: modelContext)

        let result = await service.checkForPR(
            exerciseName: "Bench Press",
            weight: 135,
            reps: 0,
            userId: UUID()
        )

        XCTAssertNil(result)
    }
}

// MARK: - PR Type Tests

final class PRTypeTests: XCTestCase {
    func testPRType_Title() {
        XCTAssertEqual(PRType.firstTime.title, "FIRST PR!")
        XCTAssertEqual(PRType.estimatedMax(improvement: 10).title, "NEW MAX!")
        XCTAssertEqual(PRType.heaviestWeight(weight: 225).title, "HEAVIEST EVER!")
        XCTAssertEqual(PRType.repRecord(atWeight: 185, reps: 8).title, "REP RECORD!")
    }

    func testPRType_Subtitle() {
        XCTAssertEqual(PRType.firstTime.subtitle, "You're on the board!")
        XCTAssertEqual(PRType.estimatedMax(improvement: 15).subtitle, "+15 lbs estimated 1RM")
        XCTAssertEqual(PRType.heaviestWeight(weight: 225).subtitle, "225 lbs is your new best")
        XCTAssertEqual(PRType.repRecord(atWeight: 185, reps: 8).subtitle, "8 reps @ 185 lbs")
    }

    func testPRType_RawValueRoundTrip() {
        let types: [PRType] = [
            .firstTime,
            .estimatedMax(improvement: 15.5),
            .heaviestWeight(weight: 225),
            .repRecord(atWeight: 185, reps: 8)
        ]

        for type in types {
            let rawValue = type.rawValue
            let restored = PRType(rawValue: rawValue)
            XCTAssertEqual(type, restored, "Round-trip failed for \(type)")
        }
    }
}
