// UserFixtures.swift
// BeastModeTests
// Pre-built user test data

import Foundation
@testable import BeastMode

/// Fixtures for UserProfile testing
enum UserFixtures {

    /// Standard test user with typical settings
    static var standardUser: UserProfile {
        let user = UserProfile(displayName: "Test Athlete")
        user.defaultRestDuration = 120
        user.compoundRestDuration = 180
        user.isolationRestDuration = 90
        return user
    }

    /// User preferring metric units
    static var metricUser: UserProfile {
        let user = UserProfile(displayName: "Metric User")
        user.preferKilograms = true
        user.defaultRestDuration = 120
        return user
    }

    /// Brand new user with no history
    static var newUser: UserProfile {
        UserProfile(displayName: "New User")
    }

    /// User with custom rest timer settings
    static var customTimerUser: UserProfile {
        let user = UserProfile(displayName: "Timer User")
        user.defaultRestDuration = 90
        user.compoundRestDuration = 240
        user.isolationRestDuration = 60
        user.exerciseRestTimers = [
            "Barbell Squats": 300,
            "Deadlift": 300,
            "Barbell Bench Press": 180
        ]
        return user
    }

    /// User with earned badges
    static func userWithBadges(_ badges: [Badge]) -> UserProfile {
        let user = UserProfile(displayName: "Badge User")
        // Badges would be on the UserStreak model
        return user
    }
}

/// Fixtures for UserStreak testing
enum StreakFixtures {

    /// New streak with no history
    static func newStreak(userId: UUID) -> UserStreak {
        UserStreak(userId: userId)
    }

    /// Active streak
    static func activeStreak(userId: UUID, days: Int) -> UserStreak {
        let streak = UserStreak(userId: userId)
        streak.currentStreak = days
        streak.longestStreak = max(days, 10)
        streak.lastWorkoutDate = .now
        return streak
    }

    /// Streak with badges
    static func streakWithBadges(userId: UUID, badges: [Badge]) -> UserStreak {
        let streak = UserStreak(userId: userId)
        streak.currentStreak = 30
        streak.longestStreak = 45
        streak.earnedBadges = badges
        streak.lastWorkoutDate = .now
        return streak
    }

    /// Week warrior streak (7+ days)
    static func weekWarriorStreak(userId: UUID) -> UserStreak {
        let streak = UserStreak(userId: userId)
        streak.currentStreak = 7
        streak.longestStreak = 7
        streak.earnedBadges = [.firstWorkout, .weekWarrior]
        streak.lastWorkoutDate = .now
        return streak
    }

    /// Long streak for milestone testing
    static func milestoneStreak(userId: UUID, days: Int) -> UserStreak {
        let streak = UserStreak(userId: userId)
        streak.currentStreak = days
        streak.longestStreak = days

        var badges: [Badge] = [.firstWorkout]
        if days >= 7 { badges.append(.weekWarrior) }
        if days >= 14 { badges.append(.twoWeekTitan) }
        if days >= 30 { badges.append(.monthlyBeast) }
        if days >= 100 { badges.append(.centurion) }

        streak.earnedBadges = badges
        streak.lastWorkoutDate = .now
        return streak
    }
}
