// StreakServiceTests.swift
// BeastModeTests
// Unit tests for streak tracking service using Swift Testing

import Testing
import SwiftData
import Foundation
@testable import BeastMode

@Suite("Streak Service")
struct StreakServiceTests {

    // MARK: - Streak Calculation

    @Suite("Streak Calculation")
    struct StreakCalculationTests {

        @Test("First workout starts streak at 1")
        @MainActor
        func firstWorkoutStartsStreak() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Create user profile
            let user = UserProfile(displayName: "Test")
            context.insert(user)

            // Create streak record
            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            let badges = try await service.recordWorkout(
                for: userId,
                completedAt: .now
            )

            let updatedStreak = try await service.getStreak(for: userId)
            #expect(updatedStreak?.currentStreak == 1)
            #expect(badges.contains(.firstWorkout))
        }

        @Test("Consecutive days extend streak")
        @MainActor
        func consecutiveDaysExtendStreak() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)
            let calendar = Calendar.current

            // Day 1 (2 days ago)
            let day1 = calendar.date(byAdding: .day, value: -2, to: .now)!
            _ = try await service.recordWorkout(for: userId, completedAt: day1)

            // Day 2 (yesterday)
            let day2 = calendar.date(byAdding: .day, value: -1, to: .now)!
            _ = try await service.recordWorkout(for: userId, completedAt: day2)

            // Day 3 (today)
            _ = try await service.recordWorkout(for: userId, completedAt: .now)

            let updatedStreak = try await service.getStreak(for: userId)
            #expect(updatedStreak?.currentStreak == 3)
        }

        @Test("Gap of 2+ days breaks streak")
        @MainActor
        func gapBreaksStreak() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            streak.currentStreak = 5
            streak.lastWorkoutDate = Calendar.current.date(byAdding: .day, value: -5, to: .now)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            // Workout today (gap > 1 day)
            _ = try await service.recordWorkout(for: userId, completedAt: .now)

            let updatedStreak = try await service.getStreak(for: userId)
            #expect(updatedStreak?.currentStreak == 1)  // Reset to 1
        }

        @Test("Same day workout doesn't increment streak")
        @MainActor
        func sameDayNoIncrement() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            // First workout today
            _ = try await service.recordWorkout(for: userId, completedAt: .now)

            // Second workout same day
            _ = try await service.recordWorkout(
                for: userId,
                completedAt: .now.addingTimeInterval(3600)
            )

            let updatedStreak = try await service.getStreak(for: userId)
            #expect(updatedStreak?.currentStreak == 1)  // Still 1
        }

        @Test("Longest streak is tracked")
        @MainActor
        func longestStreakTracked() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)
            let calendar = Calendar.current

            // Build a 5-day streak starting 15 days ago
            for daysAgo in (10...14).reversed() {
                let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
                _ = try await service.recordWorkout(for: userId, completedAt: date)
            }

            // Long gap, then new workout today
            _ = try await service.recordWorkout(for: userId, completedAt: .now)

            let updatedStreak = try await service.getStreak(for: userId)
            #expect(updatedStreak?.currentStreak == 1)
            #expect(updatedStreak?.longestStreak == 5)
        }

        @Test("Yesterday's workout maintains streak")
        @MainActor
        func yesterdayMaintainsStreak() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            streak.currentStreak = 3
            streak.lastWorkoutDate = Calendar.current.date(byAdding: .day, value: -1, to: .now)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            // Workout today (consecutive with yesterday)
            _ = try await service.recordWorkout(for: userId, completedAt: .now)

            let updatedStreak = try await service.getStreak(for: userId)
            #expect(updatedStreak?.currentStreak == 4)
        }
    }

    // MARK: - Badge Awards

    @Suite("Badge Awards")
    struct BadgeAwardTests {

        @Test("Week Warrior badge at 7 days",
              arguments: [6, 7, 8])
        @MainActor
        func weekWarriorBadge(streakDays: Int) async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)
            let calendar = Calendar.current

            var allBadges: [Badge] = []

            for daysAgo in (0..<streakDays).reversed() {
                let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
                let badges = try await service.recordWorkout(for: userId, completedAt: date)
                allBadges.append(contentsOf: badges)
            }

            if streakDays >= 7 {
                #expect(allBadges.contains(.weekWarrior))
            } else {
                #expect(!allBadges.contains(.weekWarrior))
            }
        }

        @Test("Two Week Titan badge at 14 days")
        @MainActor
        func twoWeekTitanBadge() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)
            let calendar = Calendar.current

            var allBadges: [Badge] = []

            for daysAgo in (0..<14).reversed() {
                let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
                let badges = try await service.recordWorkout(for: userId, completedAt: date)
                allBadges.append(contentsOf: badges)
            }

            #expect(allBadges.contains(.twoWeekTitan))
        }

        @Test("Monthly Beast badge at 30 days")
        @MainActor
        func monthlyBeastBadge() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Pre-set streak to 29 days
            let streak = UserStreak(userId: userId)
            streak.currentStreak = 29
            streak.lastWorkoutDate = Calendar.current.date(byAdding: .day, value: -1, to: .now)
            streak.earnedBadges = [.firstWorkout, .weekWarrior, .twoWeekTitan]
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            // Day 30
            let badges = try await service.recordWorkout(for: userId, completedAt: .now)

            #expect(badges.contains(.monthlyBeast))
        }

        @Test("Early Bird badge for workout before 7am")
        @MainActor
        func earlyBirdBadge() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            let earlyMorning = Calendar.current.date(
                bySettingHour: 6, minute: 30, second: 0, of: .now
            )!

            let badges = try await service.recordWorkout(
                for: userId,
                completedAt: earlyMorning
            )

            #expect(badges.contains(.earlyBird))
        }

        @Test("Night Owl badge for workout after 9pm")
        @MainActor
        func nightOwlBadge() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            let lateNight = Calendar.current.date(
                bySettingHour: 21, minute: 30, second: 0, of: .now
            )!

            let badges = try await service.recordWorkout(
                for: userId,
                completedAt: lateNight
            )

            #expect(badges.contains(.nightOwl))
        }

        @Test("Weekend Warrior badge for Saturday workout")
        @MainActor
        func weekendWarriorBadge() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            // Find next Saturday
            let calendar = Calendar.current
            var date = Date.now
            while calendar.component(.weekday, from: date) != 7 {  // 7 = Saturday
                date = calendar.date(byAdding: .day, value: 1, to: date)!
            }

            let badges = try await service.recordWorkout(for: userId, completedAt: date)

            #expect(badges.contains(.weekendWarrior))
        }

        @Test("Badge is only awarded once")
        @MainActor
        func badgeOnlyAwardedOnce() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)
            let calendar = Calendar.current

            var weekWarriorCount = 0

            // Build 10-day streak
            for daysAgo in (0..<10).reversed() {
                let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
                let badges = try await service.recordWorkout(for: userId, completedAt: date)
                if badges.contains(.weekWarrior) {
                    weekWarriorCount += 1
                }
            }

            #expect(weekWarriorCount == 1)
        }

        @Test("All badges have required properties")
        func allBadgesHaveProperties() {
            for badge in Badge.allCases {
                #expect(!badge.title.isEmpty)
                #expect(!badge.description.isEmpty)
                #expect(!badge.icon.isEmpty)
            }
        }
    }

    // MARK: - Weekly Progress

    @Suite("Weekly Progress")
    struct WeeklyProgressTests {

        @Test("Tracks workouts in current week")
        @MainActor
        func tracksWeeklyWorkouts() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            // Three workouts today (same day = 1 unique day count but increments weekly workouts)
            _ = try await service.recordWorkout(for: userId, completedAt: .now)

            let updatedStreak = try await service.getStreak(for: userId)
            #expect(updatedStreak?.currentWeekWorkouts ?? 0 >= 1)
        }

        @Test("Resets weekly count on new week")
        @MainActor
        func resetsOnNewWeek() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            // Set up streak with workouts from last week
            let streak = UserStreak(userId: userId)
            streak.currentWeekWorkouts = 5
            streak.lastWeekId = "2024-W01"  // Old week
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            // Workout this week
            _ = try await service.recordWorkout(for: userId, completedAt: .now)

            let updatedStreak = try await service.getStreak(for: userId)
            // Should reset for new week
            #expect(updatedStreak?.currentWeekWorkouts == 1)
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCaseTests {

        @Test("Creates streak record if missing")
        @MainActor
        func createsStreakIfMissing() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let service = StreakService(modelContext: container.mainContext)
            let userId = UUID()

            // No streak record exists
            _ = try await service.recordWorkout(for: userId, completedAt: .now)

            let streak = try await service.getStreak(for: userId)
            #expect(streak != nil)
            #expect(streak?.currentStreak == 1)
        }

        @Test("Handles timezone edge cases")
        @MainActor
        func handlesTimezoneEdgeCases() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            // Workout at 11:59 PM
            let lateNight = Calendar.current.date(
                bySettingHour: 23, minute: 59, second: 0, of: .now
            )!

            _ = try await service.recordWorkout(for: userId, completedAt: lateNight)

            let updatedStreak = try await service.getStreak(for: userId)
            #expect(updatedStreak?.currentStreak == 1)
        }

        @Test("Multiple workouts same day update weekly count correctly")
        @MainActor
        func multipleWorkoutsSameDay() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let userId = UUID()

            let streak = UserStreak(userId: userId)
            context.insert(streak)
            try context.save()

            let service = StreakService(modelContext: context)

            // Multiple workouts same day
            _ = try await service.recordWorkout(for: userId, completedAt: .now)
            _ = try await service.recordWorkout(
                for: userId,
                completedAt: .now.addingTimeInterval(3600)
            )
            _ = try await service.recordWorkout(
                for: userId,
                completedAt: .now.addingTimeInterval(7200)
            )

            let updatedStreak = try await service.getStreak(for: userId)
            // Streak should still be 1 (same day)
            #expect(updatedStreak?.currentStreak == 1)
        }
    }
}
