// StreakTests.swift
// BeastModeTests
// Unit tests for streak calculation logic

import XCTest
import SwiftData
@testable import BeastMode

final class StreakTests: XCTestCase {
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

    // MARK: - Streak Calculation Tests

    func testStreak_FirstWorkout() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()

        let badges = try await service.recordWorkout(for: userId, completedAt: .now)

        XCTAssertTrue(badges.contains(.firstWorkout))

        let streak = try await service.getStreak(for: userId)
        XCTAssertEqual(streak?.currentStreak, 1)
        XCTAssertEqual(streak?.totalWorkouts, 1)
    }

    func testStreak_ConsecutiveDays() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()
        let calendar = Calendar.current

        // Day 1
        let day1 = Date.now
        _ = try await service.recordWorkout(for: userId, completedAt: day1)

        // Day 2
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!
        _ = try await service.recordWorkout(for: userId, completedAt: day2)

        // Day 3
        let day3 = calendar.date(byAdding: .day, value: 2, to: day1)!
        _ = try await service.recordWorkout(for: userId, completedAt: day3)

        let streak = try await service.getStreak(for: userId)
        XCTAssertEqual(streak?.currentStreak, 3)
        XCTAssertEqual(streak?.totalWorkouts, 3)
    }

    func testStreak_BrokenAfterGap() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()
        let calendar = Calendar.current

        // Day 1
        let day1 = Date.now
        _ = try await service.recordWorkout(for: userId, completedAt: day1)

        // Day 2
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!
        _ = try await service.recordWorkout(for: userId, completedAt: day2)

        // Skip Day 3, workout on Day 4
        let day4 = calendar.date(byAdding: .day, value: 3, to: day1)!
        _ = try await service.recordWorkout(for: userId, completedAt: day4)

        let streak = try await service.getStreak(for: userId)
        XCTAssertEqual(streak?.currentStreak, 1, "Streak should reset after gap")
        XCTAssertEqual(streak?.totalWorkouts, 3)
    }

    func testStreak_SameDayDoesntDouble() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()

        let now = Date.now
        _ = try await service.recordWorkout(for: userId, completedAt: now)
        _ = try await service.recordWorkout(for: userId, completedAt: now)

        let streak = try await service.getStreak(for: userId)
        XCTAssertEqual(streak?.currentStreak, 1, "Same day shouldn't increase streak")
        XCTAssertEqual(streak?.totalWorkouts, 2, "But total workouts should increase")
    }

    func testStreak_LongestStreakTracked() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()
        let calendar = Calendar.current

        // Build 5-day streak
        var currentDate = Date.now
        for _ in 0..<5 {
            _ = try await service.recordWorkout(for: userId, completedAt: currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        // Break streak
        currentDate = calendar.date(byAdding: .day, value: 2, to: currentDate)!
        _ = try await service.recordWorkout(for: userId, completedAt: currentDate)

        let streak = try await service.getStreak(for: userId)
        XCTAssertEqual(streak?.longestStreak, 5)
        XCTAssertEqual(streak?.currentStreak, 1)
    }

    // MARK: - Badge Award Tests

    func testBadge_WeekWarrior() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()
        let calendar = Calendar.current

        var badges: [Badge] = []
        var currentDate = Date.now

        for _ in 0..<7 {
            let newBadges = try await service.recordWorkout(for: userId, completedAt: currentDate)
            badges.append(contentsOf: newBadges)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        XCTAssertTrue(badges.contains(.weekWarrior))
    }

    func testBadge_EarlyBird() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()

        // Workout at 6 AM
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date.now)
        components.hour = 6
        components.minute = 0
        let earlyMorning = calendar.date(from: components)!

        let badges = try await service.recordWorkout(for: userId, completedAt: earlyMorning)

        XCTAssertTrue(badges.contains(.earlyBird))
    }

    func testBadge_NightOwl() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()

        // Workout at 10 PM
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date.now)
        components.hour = 22
        components.minute = 0
        let lateNight = calendar.date(from: components)!

        let badges = try await service.recordWorkout(for: userId, completedAt: lateNight)

        XCTAssertTrue(badges.contains(.nightOwl))
    }

    func testBadge_TonLifter() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()

        let badges = try await service.recordWorkout(
            for: userId,
            completedAt: .now,
            sessionVolume: 2500
        )

        XCTAssertTrue(badges.contains(.tonLifter))
    }

    func testBadge_NoDuplicates() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()

        // Earn early bird badge
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date.now)
        components.hour = 6
        let earlyMorning = calendar.date(from: components)!

        let badges1 = try await service.recordWorkout(for: userId, completedAt: earlyMorning)
        XCTAssertTrue(badges1.contains(.earlyBird))

        // Another early workout next day
        components.day! += 1
        let nextEarlyMorning = calendar.date(from: components)!

        let badges2 = try await service.recordWorkout(for: userId, completedAt: nextEarlyMorning)
        XCTAssertFalse(badges2.contains(.earlyBird), "Badge should not be awarded twice")
    }

    // MARK: - PR Badge Tests

    func testPRBadge_FirstPR() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()

        // First need to record a workout
        _ = try await service.recordWorkout(for: userId, completedAt: .now)

        let badges = try await service.recordPR(for: userId)

        XCTAssertTrue(badges.contains(.firstPR))
    }

    func testPRBadge_PRHunter() async throws {
        let service = StreakService(modelContext: modelContext)
        let userId = UUID()

        _ = try await service.recordWorkout(for: userId, completedAt: .now)

        var allBadges: [Badge] = []
        for _ in 0..<10 {
            let badges = try await service.recordPR(for: userId)
            allBadges.append(contentsOf: badges)
        }

        XCTAssertTrue(allBadges.contains(.prHunter))
    }
}

// MARK: - Badge Tests

final class BadgeTests: XCTestCase {
    func testBadge_AllCasesHaveProperties() {
        for badge in Badge.allCases {
            XCTAssertFalse(badge.name.isEmpty, "\(badge) should have a name")
            XCTAssertFalse(badge.description.isEmpty, "\(badge) should have a description")
            XCTAssertFalse(badge.icon.isEmpty, "\(badge) should have an icon")
        }
    }

    func testBadge_StreakThresholds() {
        XCTAssertEqual(Badge.weekWarrior.threshold, 7)
        XCTAssertEqual(Badge.twoWeekTitan.threshold, 14)
        XCTAssertEqual(Badge.monthlyBeast.threshold, 30)
        XCTAssertEqual(Badge.centurion.threshold, 100)
    }

    func testBadge_PRThresholds() {
        XCTAssertEqual(Badge.prHunter.threshold, 10)
        XCTAssertEqual(Badge.prMachine.threshold, 50)
        XCTAssertEqual(Badge.legendary.threshold, 100)
    }
}
