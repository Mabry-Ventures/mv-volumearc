// Streak.swift
// BeastMode
// Model for workout streaks and badge system

import Foundation
import SwiftData
import SwiftUI

/// Tracks user workout streaks and earned badges
@Model
final class UserStreak {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var currentStreak: Int
    var longestStreak: Int
    var lastWorkoutDate: Date?
    var weeklyGoal: Int           // Target workouts per week
    var currentWeekCount: Int
    var weekStartDate: Date?

    // Badge tracking - stored as JSON array of badge IDs
    var earnedBadgesData: Data?
    var badgeEarnedDatesData: Data?  // Track when each badge was earned

    // Statistics
    var totalWorkouts: Int
    var totalPRs: Int
    var totalVolumeLifted: Double    // Lifetime volume in lbs
    var weekendWorkouts: Int

    init(userId: UUID) {
        self.id = UUID()
        self.userId = userId
        self.currentStreak = 0
        self.longestStreak = 0
        self.weeklyGoal = 4
        self.currentWeekCount = 0
        self.earnedBadgesData = nil
        self.badgeEarnedDatesData = nil
        self.totalWorkouts = 0
        self.totalPRs = 0
        self.totalVolumeLifted = 0
        self.weekendWorkouts = 0
    }

    var earnedBadges: [String] {
        get {
            guard let data = earnedBadgesData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            earnedBadgesData = try? JSONEncoder().encode(newValue)
        }
    }

    var badgeEarnedDates: [String: Date] {
        get {
            guard let data = badgeEarnedDatesData else { return [:] }
            return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
        }
        set {
            badgeEarnedDatesData = try? JSONEncoder().encode(newValue)
        }
    }

    func hasBadge(_ badge: Badge) -> Bool {
        earnedBadges.contains(badge.rawValue)
    }

    func awardBadge(_ badge: Badge) {
        guard !hasBadge(badge) else { return }
        var badges = earnedBadges
        badges.append(badge.rawValue)
        earnedBadges = badges

        var dates = badgeEarnedDates
        dates[badge.rawValue] = .now
        badgeEarnedDates = dates
    }
}

// MARK: - Badge System

/// All available badges in Beast Mode
enum Badge: String, CaseIterable, Identifiable {
    // Streak badges
    case firstWorkout = "first_workout"
    case weekWarrior = "week_warrior"        // 7 day streak
    case twoWeekTitan = "two_week_titan"     // 14 day streak
    case monthlyBeast = "monthly_beast"      // 30 day streak
    case centurion = "centurion"             // 100 day streak

    // PR badges
    case firstPR = "first_pr"
    case prHunter = "pr_hunter"              // 10 PRs
    case prMachine = "pr_machine"            // 50 PRs
    case legendary = "legendary"             // 100 PRs

    // Consistency badges
    case earlyBird = "early_bird"            // Workout before 7am
    case nightOwl = "night_owl"              // Workout after 9pm
    case weekendWarrior = "weekend_warrior"  // 4 weekend workouts
    case ironWill = "iron_will"              // Completed workout on rest day

    // Volume badges
    case tonLifter = "ton_lifter"            // 2000 lbs in one session
    case volumeKing = "volume_king"          // 50,000 lbs lifetime

    var id: String { rawValue }

    var name: String {
        switch self {
        case .firstWorkout: return "First Step"
        case .weekWarrior: return "Week Warrior"
        case .twoWeekTitan: return "Two Week Titan"
        case .monthlyBeast: return "Monthly Beast"
        case .centurion: return "Centurion"
        case .firstPR: return "Record Breaker"
        case .prHunter: return "PR Hunter"
        case .prMachine: return "PR Machine"
        case .legendary: return "Legendary"
        case .earlyBird: return "Early Bird"
        case .nightOwl: return "Night Owl"
        case .weekendWarrior: return "Weekend Warrior"
        case .ironWill: return "Iron Will"
        case .tonLifter: return "Ton Lifter"
        case .volumeKing: return "Volume King"
        }
    }

    var description: String {
        switch self {
        case .firstWorkout: return "Complete your first workout"
        case .weekWarrior: return "7 day workout streak"
        case .twoWeekTitan: return "14 day workout streak"
        case .monthlyBeast: return "30 day workout streak"
        case .centurion: return "100 day workout streak"
        case .firstPR: return "Set your first personal record"
        case .prHunter: return "Set 10 personal records"
        case .prMachine: return "Set 50 personal records"
        case .legendary: return "Set 100 personal records"
        case .earlyBird: return "Start a workout before 7 AM"
        case .nightOwl: return "Complete a workout after 9 PM"
        case .weekendWarrior: return "Complete 4 weekend workouts"
        case .ironWill: return "Train on a scheduled rest day"
        case .tonLifter: return "Lift 2,000+ lbs in one session"
        case .volumeKing: return "Lift 50,000 lbs lifetime"
        }
    }

    var icon: String {
        switch self {
        case .firstWorkout: return "figure.walk"
        case .weekWarrior, .twoWeekTitan, .monthlyBeast, .centurion: return "flame.fill"
        case .firstPR, .prHunter, .prMachine, .legendary: return "trophy.fill"
        case .earlyBird: return "sunrise.fill"
        case .nightOwl: return "moon.stars.fill"
        case .weekendWarrior: return "calendar.badge.checkmark"
        case .ironWill: return "bolt.heart.fill"
        case .tonLifter, .volumeKing: return "scalemass.fill"
        }
    }

    var color: Color {
        switch self {
        case .firstWorkout: return .green
        case .weekWarrior: return .orange
        case .twoWeekTitan: return .red
        case .monthlyBeast: return .purple
        case .centurion: return .yellow
        case .firstPR: return .blue
        case .prHunter: return .cyan
        case .prMachine: return .indigo
        case .legendary: return .yellow
        case .earlyBird: return .orange
        case .nightOwl: return .indigo
        case .weekendWarrior: return .green
        case .ironWill: return .red
        case .tonLifter: return .gray
        case .volumeKing: return .yellow
        }
    }

    /// The threshold value required to earn this badge
    var threshold: Int? {
        switch self {
        case .weekWarrior: return 7
        case .twoWeekTitan: return 14
        case .monthlyBeast: return 30
        case .centurion: return 100
        case .prHunter: return 10
        case .prMachine: return 50
        case .legendary: return 100
        case .weekendWarrior: return 4
        case .tonLifter: return 2000
        case .volumeKing: return 50000
        default: return nil
        }
    }
}
