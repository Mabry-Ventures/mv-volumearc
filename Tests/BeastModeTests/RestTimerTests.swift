// RestTimerTests.swift
// BeastModeTests
// Unit tests for rest timer logic

import XCTest
@testable import BeastMode

final class RestTimerTests: XCTestCase {
    var profile: UserProfile!

    override func setUpWithError() throws {
        profile = UserProfile(displayName: "Test User")
    }

    override func tearDownWithError() throws {
        profile = nil
    }

    // MARK: - Default Timer Tests

    func testDefaultTimers_InitialValues() {
        XCTAssertEqual(profile.restTimerCompound, 180)    // 3 minutes
        XCTAssertEqual(profile.restTimerIsolation, 90)   // 1.5 minutes
        XCTAssertEqual(profile.restTimerDefault, 120)     // 2 minutes
    }

    // MARK: - Rest Timer Service Tests

    func testRestTimerService_CompoundExercise() {
        let service = RestTimerService(profile: profile)

        XCTAssertEqual(service.getRestDuration(for: "Barbell Bench Press"), 180)
        XCTAssertEqual(service.getRestDuration(for: "Barbell Squats"), 180)
        XCTAssertEqual(service.getRestDuration(for: "Deadlift"), 180)
        XCTAssertEqual(service.getRestDuration(for: "Overhead Press"), 180)
    }

    func testRestTimerService_IsolationExercise() {
        let service = RestTimerService(profile: profile)

        XCTAssertEqual(service.getRestDuration(for: "Bicep Curls"), 90)
        XCTAssertEqual(service.getRestDuration(for: "Tricep Extension"), 90)
        XCTAssertEqual(service.getRestDuration(for: "Lateral Raises"), 90)
        XCTAssertEqual(service.getRestDuration(for: "Leg Curls"), 90)
    }

    func testRestTimerService_DefaultExercise() {
        let service = RestTimerService(profile: profile)

        // Generic exercises should use default
        XCTAssertEqual(service.getRestDuration(for: "Some Random Exercise"), 120)
    }

    func testRestTimerService_PerExerciseOverride() {
        // Set custom timer
        profile.setRestTimer(for: "Barbell Bench Press", duration: 240)

        let service = RestTimerService(profile: profile)

        // Override should take precedence over compound default
        XCTAssertEqual(service.getRestDuration(for: "Barbell Bench Press"), 240)
    }

    func testRestTimerService_CustomProfileValues() {
        profile.restTimerCompound = 300    // 5 minutes
        profile.restTimerIsolation = 60    // 1 minute

        let service = RestTimerService(profile: profile)

        XCTAssertEqual(service.getRestDuration(for: "Deadlift"), 300)
        XCTAssertEqual(service.getRestDuration(for: "Bicep Curls"), 60)
    }

    // MARK: - Compound Detection Tests

    func testIsCompoundExercise() {
        let service = RestTimerService(profile: profile)

        // Compound exercises
        XCTAssertTrue(service.isCompoundExercise("Barbell Bench Press"))
        XCTAssertTrue(service.isCompoundExercise("Squats"))
        XCTAssertTrue(service.isCompoundExercise("Deadlift"))
        XCTAssertTrue(service.isCompoundExercise("Overhead Press"))
        XCTAssertTrue(service.isCompoundExercise("Barbell Rows"))

        // Isolation exercises
        XCTAssertFalse(service.isCompoundExercise("Bicep Curls"))
        XCTAssertFalse(service.isCompoundExercise("Tricep Extension"))
        XCTAssertFalse(service.isCompoundExercise("Lateral Raises"))
    }

    // MARK: - Time Formatting Tests

    func testFormatTime_WholeMinutes() {
        XCTAssertEqual(RestTimerService.formatTime(60), "1m")
        XCTAssertEqual(RestTimerService.formatTime(120), "2m")
        XCTAssertEqual(RestTimerService.formatTime(180), "3m")
    }

    func testFormatTime_MinutesAndSeconds() {
        XCTAssertEqual(RestTimerService.formatTime(90), "1:30")
        XCTAssertEqual(RestTimerService.formatTime(150), "2:30")
        XCTAssertEqual(RestTimerService.formatTime(105), "1:45")
    }

    func testFormatTime_SecondsOnly() {
        XCTAssertEqual(RestTimerService.formatTime(30), "30s")
        XCTAssertEqual(RestTimerService.formatTime(45), "45s")
    }

    // MARK: - Per-Exercise Override Management

    func testExerciseRestTimers_SetAndGet() {
        profile.setRestTimer(for: "Exercise A", duration: 100)
        profile.setRestTimer(for: "Exercise B", duration: 200)

        XCTAssertEqual(profile.exerciseRestTimers["Exercise A"], 100)
        XCTAssertEqual(profile.exerciseRestTimers["Exercise B"], 200)
    }

    func testExerciseRestTimers_Remove() {
        profile.setRestTimer(for: "Exercise A", duration: 100)
        XCTAssertNotNil(profile.exerciseRestTimers["Exercise A"])

        profile.removeRestTimer(for: "Exercise A")
        XCTAssertNil(profile.exerciseRestTimers["Exercise A"])
    }

    func testExerciseRestTimers_Update() {
        profile.setRestTimer(for: "Exercise A", duration: 100)
        XCTAssertEqual(profile.exerciseRestTimers["Exercise A"], 100)

        profile.setRestTimer(for: "Exercise A", duration: 200)
        XCTAssertEqual(profile.exerciseRestTimers["Exercise A"], 200)
    }
}

// MARK: - Rest Timer Manager Tests

@MainActor
final class RestTimerManagerTests: XCTestCase {
    func testTimerManager_InitialState() {
        let manager = RestTimerManager()

        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.remainingTime, 0)
        XCTAssertEqual(manager.progress, 1.0)
    }

    func testTimerManager_Start() {
        let manager = RestTimerManager()

        manager.start(duration: 120)

        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(manager.totalTime, 120)
        XCTAssertEqual(manager.remainingTime, 120)
    }

    func testTimerManager_Stop() {
        let manager = RestTimerManager()

        manager.start(duration: 120)
        manager.stop()

        XCTAssertFalse(manager.isRunning)
    }

    func testTimerManager_Skip() {
        let manager = RestTimerManager()

        manager.start(duration: 120)
        manager.skip()

        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.remainingTime, 0)
        XCTAssertEqual(manager.progress, 0)
    }

    func testTimerManager_AddTime() {
        let manager = RestTimerManager()

        manager.start(duration: 120)
        manager.addTime(30)

        XCTAssertEqual(manager.remainingTime, 150)
        XCTAssertEqual(manager.totalTime, 150)
    }

    func testTimerManager_FormattedTime() {
        let manager = RestTimerManager()

        manager.start(duration: 125)

        XCTAssertEqual(manager.formattedTime, "2:05")
    }
}
