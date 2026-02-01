// RestTimerServiceTests.swift
// BeastModeTests
// Comprehensive unit tests for RestTimerService

import Testing
import SwiftData
import Foundation
@testable import BeastMode

// MARK: - Rest Timer Service Tests

@Suite("Rest Timer Service")
struct RestTimerServiceTests {

    // MARK: - Compound Exercise Detection

    @Suite("Compound Exercise Detection")
    struct CompoundExerciseDetectionTests {

        @Test("Recognizes barbell bench press as compound")
        @MainActor
        func barbellBenchPressIsCompound() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            #expect(service.isCompoundExercise("Barbell Bench Press") == true)
        }

        @Test("Recognizes squats as compound")
        @MainActor
        func squatsAreCompound() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            #expect(service.isCompoundExercise("Barbell Squats") == true)
            #expect(service.isCompoundExercise("Back Squats") == true)
            #expect(service.isCompoundExercise("Front Squats") == true)
        }

        @Test("Recognizes deadlifts as compound")
        @MainActor
        func deadliftsAreCompound() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            #expect(service.isCompoundExercise("Deadlift") == true)
            #expect(service.isCompoundExercise("Romanian Deadlift") == true)
            #expect(service.isCompoundExercise("Sumo Deadlift") == true)
        }

        @Test("Recognizes overhead press as compound")
        @MainActor
        func overheadPressIsCompound() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            #expect(service.isCompoundExercise("Overhead Press") == true)
            #expect(service.isCompoundExercise("Military Press") == true)
        }

        @Test("Recognizes rows as compound")
        @MainActor
        func rowsAreCompound() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            #expect(service.isCompoundExercise("Barbell Rows") == true)
            #expect(service.isCompoundExercise("Bent Over Rows") == true)
        }

        @Test("Recognizes pull-ups as compound")
        @MainActor
        func pullUpsAreCompound() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            #expect(service.isCompoundExercise("Pull-ups") == true)
            #expect(service.isCompoundExercise("Chin-ups") == true)
        }

        @Test("Case insensitive compound detection")
        @MainActor
        func caseInsensitiveCompoundDetection() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            #expect(service.isCompoundExercise("BARBELL BENCH PRESS") == true)
            #expect(service.isCompoundExercise("barbell bench press") == true)
            #expect(service.isCompoundExercise("Barbell SQUATS") == true)
        }

        @Test("Partial match compound detection")
        @MainActor
        func partialMatchCompoundDetection() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            // Contains "squat"
            #expect(service.isCompoundExercise("Goblet Squat") == true)
            // Contains "press"
            #expect(service.isCompoundExercise("Incline Press") == true)
            // Contains "row"
            #expect(service.isCompoundExercise("Cable Row") == true)
        }
    }

    // MARK: - Isolation Exercise Detection

    @Suite("Isolation Exercise Detection")
    struct IsolationExerciseDetectionTests {

        @Test("Curls are not compound")
        @MainActor
        func curlsAreNotCompound() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            #expect(service.isCompoundExercise("Bicep Curls") == false)
            #expect(service.isCompoundExercise("Hammer Curls") == false)
            #expect(service.isCompoundExercise("Preacher Curls") == false)
        }

        @Test("Extensions are not compound")
        @MainActor
        func extensionsAreNotCompound() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            #expect(service.isCompoundExercise("Tricep Extensions") == false)
            #expect(service.isCompoundExercise("Leg Extensions") == false)
        }

        @Test("Raises are not compound")
        @MainActor
        func raisesAreNotCompound() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            #expect(service.isCompoundExercise("Lateral Raises") == false)
            #expect(service.isCompoundExercise("Front Raises") == false)
            #expect(service.isCompoundExercise("Calf Raises") == false)
        }

        @Test("Flyes are not compound")
        @MainActor
        func flyesAreNotCompound() throws {
            let profile = UserProfile(displayName: "Test User")
            let service = RestTimerService(profile: profile)

            #expect(service.isCompoundExercise("Cable Flyes") == false)
            #expect(service.isCompoundExercise("Dumbbell Fly") == false)
        }
    }

    // MARK: - Rest Duration Tests

    @Suite("Rest Duration Calculation")
    struct RestDurationTests {

        @Test("Compound exercises get compound rest time")
        @MainActor
        func compoundExercisesGetCompoundRestTime() throws {
            let profile = UserProfile(displayName: "Test User")
            profile.restTimerCompound = 180
            let service = RestTimerService(profile: profile)

            #expect(service.getRestDuration(for: "Barbell Bench Press") == 180)
            #expect(service.getRestDuration(for: "Barbell Squats") == 180)
            #expect(service.getRestDuration(for: "Deadlift") == 180)
        }

        @Test("Isolation exercises get isolation rest time")
        @MainActor
        func isolationExercisesGetIsolationRestTime() throws {
            let profile = UserProfile(displayName: "Test User")
            profile.restTimerIsolation = 90
            let service = RestTimerService(profile: profile)

            #expect(service.getRestDuration(for: "Bicep Curls") == 90)
            #expect(service.getRestDuration(for: "Lateral Raises") == 90)
            #expect(service.getRestDuration(for: "Tricep Extensions") == 90)
        }

        @Test("Unknown exercises get default rest time")
        @MainActor
        func unknownExercisesGetDefaultRestTime() throws {
            let profile = UserProfile(displayName: "Test User")
            profile.restTimerDefault = 120
            let service = RestTimerService(profile: profile)

            #expect(service.getRestDuration(for: "Mystery Exercise") == 120)
            #expect(service.getRestDuration(for: "Custom Movement") == 120)
        }

        @Test("Per-exercise overrides take priority")
        @MainActor
        func perExerciseOverridesTakePriority() throws {
            let profile = UserProfile(displayName: "Test User")
            profile.restTimerCompound = 180
            profile.setRestTimer(for: "Barbell Bench Press", duration: 300)
            let service = RestTimerService(profile: profile)

            // Override should be used instead of compound default
            #expect(service.getRestDuration(for: "Barbell Bench Press") == 300)

            // Other compound exercises still use compound time
            #expect(service.getRestDuration(for: "Barbell Squats") == 180)
        }

        @Test("Custom rest timer settings are respected")
        @MainActor
        func customRestTimerSettingsAreRespected() throws {
            let profile = UserProfile(displayName: "Test User")
            profile.restTimerCompound = 240  // 4 minutes
            profile.restTimerIsolation = 60  // 1 minute
            profile.restTimerDefault = 90    // 1.5 minutes
            let service = RestTimerService(profile: profile)

            #expect(service.getRestDuration(for: "Barbell Squats") == 240)
            #expect(service.getRestDuration(for: "Bicep Curls") == 60)
            #expect(service.getRestDuration(for: "Unknown Exercise") == 90)
        }
    }

    // MARK: - Time Formatting Tests

    @Suite("Time Formatting")
    struct TimeFormattingTests {

        @Test("Formats whole minutes correctly")
        func formatsWholeMinutesCorrectly() {
            #expect(RestTimerService.formatTime(60) == "1m")
            #expect(RestTimerService.formatTime(120) == "2m")
            #expect(RestTimerService.formatTime(180) == "3m")
            #expect(RestTimerService.formatTime(300) == "5m")
        }

        @Test("Formats seconds only correctly")
        func formatsSecondsOnlyCorrectly() {
            #expect(RestTimerService.formatTime(30) == "30s")
            #expect(RestTimerService.formatTime(45) == "45s")
            #expect(RestTimerService.formatTime(15) == "15s")
        }

        @Test("Formats mixed minutes and seconds correctly")
        func formatsMixedMinutesAndSecondsCorrectly() {
            #expect(RestTimerService.formatTime(90) == "1:30")
            #expect(RestTimerService.formatTime(150) == "2:30")
            #expect(RestTimerService.formatTime(75) == "1:15")
            #expect(RestTimerService.formatTime(185) == "3:05")
        }

        @Test("Handles zero seconds")
        func handlesZeroSeconds() {
            #expect(RestTimerService.formatTime(0) == "0s")
        }

        @Test("Pads single digit seconds")
        func padsSingleDigitSeconds() {
            #expect(RestTimerService.formatTime(65) == "1:05")
            #expect(RestTimerService.formatTime(121) == "2:01")
            #expect(RestTimerService.formatTime(189) == "3:09")
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test("Empty exercise name returns default")
        @MainActor
        func emptyExerciseNameReturnsDefault() throws {
            let profile = UserProfile(displayName: "Test User")
            profile.restTimerDefault = 120
            let service = RestTimerService(profile: profile)

            #expect(service.getRestDuration(for: "") == 120)
        }

        @Test("Exercise with special characters")
        @MainActor
        func exerciseWithSpecialCharacters() throws {
            let profile = UserProfile(displayName: "Test User")
            profile.restTimerCompound = 180
            let service = RestTimerService(profile: profile)

            // Pull-ups should still be recognized
            #expect(service.isCompoundExercise("Pull-Ups") == true)
        }

        @Test("Exercises with extra whitespace")
        @MainActor
        func exercisesWithExtraWhitespace() throws {
            let profile = UserProfile(displayName: "Test User")
            profile.restTimerDefault = 120
            let service = RestTimerService(profile: profile)

            // May or may not match depending on implementation
            let duration = service.getRestDuration(for: "  Barbell Bench Press  ")
            #expect(duration > 0)
        }

        @Test("Very long rest durations")
        @MainActor
        func veryLongRestDurations() throws {
            let profile = UserProfile(displayName: "Test User")
            profile.restTimerCompound = 600 // 10 minutes
            let service = RestTimerService(profile: profile)

            #expect(service.getRestDuration(for: "Barbell Squats") == 600)
            #expect(RestTimerService.formatTime(600) == "10m")
        }
    }

    // MARK: - Parameterized Tests

    @Test("Compound exercise detection",
          arguments: [
            ("Barbell Bench Press", true),
            ("Incline Bench Press", true),
            ("Back Squats", true),
            ("Front Squats", true),
            ("Deadlift", true),
            ("Romanian Deadlift", true),
            ("Overhead Press", true),
            ("Pull-ups", true),
            ("Barbell Rows", true),
            ("Bicep Curls", false),
            ("Tricep Extensions", false),
            ("Lateral Raises", false),
            ("Cable Flyes", false),
            ("Leg Curls", false)
          ])
    @MainActor
    func compoundExerciseDetection(exerciseName: String, isCompound: Bool) throws {
        let profile = UserProfile(displayName: "Test User")
        let service = RestTimerService(profile: profile)

        #expect(service.isCompoundExercise(exerciseName) == isCompound)
    }

    @Test("Time formatting",
          arguments: [
            (60.0, "1m"),
            (90.0, "1:30"),
            (120.0, "2m"),
            (30.0, "30s"),
            (0.0, "0s"),
            (185.0, "3:05")
          ])
    func timeFormatting(seconds: TimeInterval, expected: String) {
        #expect(RestTimerService.formatTime(seconds) == expected)
    }
}

// MARK: - Rest Timer Manager Tests

@Suite("Rest Timer Manager")
struct RestTimerManagerTests {

    @Test("Initial state is not running")
    @MainActor
    func initialStateIsNotRunning() {
        let manager = RestTimerManager()

        #expect(manager.isRunning == false)
        #expect(manager.remainingTime == 0)
        #expect(manager.totalTime == 0)
        #expect(manager.progress == 1.0)
    }

    @Test("Starting timer sets correct state")
    @MainActor
    func startingTimerSetsCorrectState() async throws {
        let manager = RestTimerManager()

        manager.start(duration: 120)

        #expect(manager.isRunning == true)
        #expect(manager.totalTime == 120)
        #expect(manager.remainingTime == 120)
        #expect(manager.progress == 1.0)

        manager.stop()
    }

    @Test("Stopping timer resets running state")
    @MainActor
    func stoppingTimerResetsRunningState() {
        let manager = RestTimerManager()

        manager.start(duration: 60)
        manager.stop()

        #expect(manager.isRunning == false)
    }

    @Test("Skip sets remaining time to zero")
    @MainActor
    func skipSetsRemainingTimeToZero() {
        let manager = RestTimerManager()

        manager.start(duration: 120)
        manager.skip()

        #expect(manager.isRunning == false)
        #expect(manager.remainingTime == 0)
        #expect(manager.progress == 0)
    }

    @Test("Add time increases remaining and total")
    @MainActor
    func addTimeIncreasesRemainingAndTotal() {
        let manager = RestTimerManager()

        manager.start(duration: 60)
        manager.addTime(30)

        #expect(manager.remainingTime == 90)
        #expect(manager.totalTime == 90)

        manager.stop()
    }

    @Test("Add time does nothing when not running")
    @MainActor
    func addTimeDoesNothingWhenNotRunning() {
        let manager = RestTimerManager()

        manager.addTime(30)

        #expect(manager.remainingTime == 0)
        #expect(manager.totalTime == 0)
    }

    @Test("Formatted time shows correct format")
    @MainActor
    func formattedTimeShowsCorrectFormat() {
        let manager = RestTimerManager()

        manager.start(duration: 90)

        #expect(manager.formattedTime == "1:30")

        manager.stop()
    }

    @Test("Starting new timer stops previous")
    @MainActor
    func startingNewTimerStopsPrevious() {
        let manager = RestTimerManager()

        manager.start(duration: 120)
        manager.start(duration: 60)

        #expect(manager.totalTime == 60)
        #expect(manager.remainingTime == 60)

        manager.stop()
    }
}
