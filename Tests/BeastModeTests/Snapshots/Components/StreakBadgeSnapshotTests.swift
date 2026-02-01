// StreakBadgeSnapshotTests.swift
// BeastModeTests
// Snapshot tests for streak and badge components

import Testing
import SwiftUI
@testable import BeastMode

@Suite("Streak Badge Snapshots")
struct StreakBadgeSnapshotTests {

    // MARK: - Streak Display Snapshots

    @Test("Streak display - active streak light mode")
    @MainActor
    func streakDisplayActiveLight() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            StreakDisplayView(
                currentStreak: 14,
                longestStreak: 21,
                isActive: true
            )
        }

        assertSnapshot(matching: view, named: "streak_display_active_light")
    }

    @Test("Streak display - active streak dark mode")
    @MainActor
    func streakDisplayActiveDark() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .dark
        ) {
            StreakDisplayView(
                currentStreak: 14,
                longestStreak: 21,
                isActive: true
            )
        }

        assertSnapshot(matching: view, named: "streak_display_active_dark")
    }

    @Test("Streak display - new user")
    @MainActor
    func streakDisplayNewUser() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            StreakDisplayView(
                currentStreak: 0,
                longestStreak: 0,
                isActive: false
            )
        }

        assertSnapshot(matching: view, named: "streak_display_new_user")
    }

    @Test("Streak display - milestone (30 days)")
    @MainActor
    func streakDisplayMilestone() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            StreakDisplayView(
                currentStreak: 30,
                longestStreak: 30,
                isActive: true
            )
        }

        assertSnapshot(matching: view, named: "streak_display_milestone")
    }

    // MARK: - Badge Snapshots

    @Test("Badge - first workout")
    @MainActor
    func badgeFirstWorkout() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            AchievementBadgeView(badge: .firstWorkout, isUnlocked: true)
        }

        assertSnapshot(matching: view, named: "badge_first_workout")
    }

    @Test("Badge - week warrior")
    @MainActor
    func badgeWeekWarrior() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            AchievementBadgeView(badge: .weekWarrior, isUnlocked: true)
        }

        assertSnapshot(matching: view, named: "badge_week_warrior")
    }

    @Test("Badge - streak master (30 days)")
    @MainActor
    func badgeStreakMaster() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            AchievementBadgeView(badge: .streakMaster, isUnlocked: true)
        }

        assertSnapshot(matching: view, named: "badge_streak_master")
    }

    @Test("Badge - locked state")
    @MainActor
    func badgeLocked() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            AchievementBadgeView(badge: .streakMaster, isUnlocked: false)
        }

        assertSnapshot(matching: view, named: "badge_locked")
    }

    @Test("Badge - early bird")
    @MainActor
    func badgeEarlyBird() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            AchievementBadgeView(badge: .earlyBird, isUnlocked: true)
        }

        assertSnapshot(matching: view, named: "badge_early_bird")
    }

    @Test("Badge - night owl")
    @MainActor
    func badgeNightOwl() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            AchievementBadgeView(badge: .nightOwl, isUnlocked: true)
        }

        assertSnapshot(matching: view, named: "badge_night_owl")
    }

    // MARK: - Badge Grid

    @Test("Badge grid - all unlocked")
    @MainActor
    func badgeGridAllUnlocked() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            BadgeGridView(
                unlockedBadges: [.firstWorkout, .weekWarrior, .earlyBird, .nightOwl, .streakMaster]
            )
        }

        assertSnapshot(matching: view, named: "badge_grid_all_unlocked")
    }

    @Test("Badge grid - partial unlock")
    @MainActor
    func badgeGridPartialUnlock() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            BadgeGridView(
                unlockedBadges: [.firstWorkout, .weekWarrior]
            )
        }

        assertSnapshot(matching: view, named: "badge_grid_partial")
    }

    // MARK: - Weekly Progress

    @Test("Weekly progress - in progress")
    @MainActor
    func weeklyProgressInProgress() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            WeeklyProgressView(completed: 3, target: 4)
        }

        assertSnapshot(matching: view, named: "weekly_progress_in_progress")
    }

    @Test("Weekly progress - completed")
    @MainActor
    func weeklyProgressCompleted() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            WeeklyProgressView(completed: 4, target: 4)
        }

        assertSnapshot(matching: view, named: "weekly_progress_completed")
    }

    @Test("Weekly progress - exceeded")
    @MainActor
    func weeklyProgressExceeded() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            WeeklyProgressView(completed: 6, target: 4)
        }

        assertSnapshot(matching: view, named: "weekly_progress_exceeded")
    }
}

// MARK: - Stub Views for Snapshot Testing

/// Stub Streak Display View
struct StreakDisplayView: View {
    let currentStreak: Int
    let longestStreak: Int
    let isActive: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Flame icon with streak count
            ZStack {
                Circle()
                    .fill(isActive ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 100, height: 100)

                VStack(spacing: 4) {
                    Image(systemName: isActive ? "flame.fill" : "flame")
                        .font(.system(size: 36))
                        .foregroundStyle(isActive ? .orange : .gray)

                    Text("\(currentStreak)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? .orange : .gray)
                }
            }

            // Labels
            VStack(spacing: 4) {
                Text("Day Streak")
                    .font(.headline)

                if longestStreak > 0 {
                    Text("Longest: \(longestStreak) days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Milestone indicator
            if currentStreak >= 30 {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("30-Day Milestone!")
                        .font(.subheadline.bold())
                        .foregroundStyle(.yellow)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.yellow.opacity(0.2))
                .clipShape(Capsule())
            }
        }
        .padding()
    }
}

/// Stub Achievement Badge View
struct AchievementBadgeView: View {
    let badge: BadgeType
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? badge.color.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 64, height: 64)

                Image(systemName: badge.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(isUnlocked ? badge.color : .gray)

                if !isUnlocked {
                    Circle()
                        .fill(.black.opacity(0.3))
                        .frame(width: 64, height: 64)

                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }

            Text(badge.title)
                .font(.caption)
                .foregroundStyle(isUnlocked ? .primary : .secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 80)
    }
}

/// Stub Badge Grid View
struct BadgeGridView: View {
    let unlockedBadges: [BadgeType]

    private let allBadges: [BadgeType] = [.firstWorkout, .weekWarrior, .earlyBird, .nightOwl, .streakMaster]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
            ForEach(allBadges, id: \.self) { badge in
                AchievementBadgeView(
                    badge: badge,
                    isUnlocked: unlockedBadges.contains(badge)
                )
            }
        }
        .padding()
    }
}

/// Stub Weekly Progress View
struct WeeklyProgressView: View {
    let completed: Int
    let target: Int

    private var isGoalMet: Bool { completed >= target }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Weekly Goal")
                    .font(.headline)
                Spacer()
                Text("\(completed)/\(target)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Day indicators
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { day in
                    Circle()
                        .fill(day < completed ? (isGoalMet ? Color.green : Color.blue) : Color.gray.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if day < completed {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                }
            }

            // Status text
            if isGoalMet {
                Label("Goal reached!", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Text("\(target - completed) more to go")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Badge type for testing
enum BadgeType: Hashable {
    case firstWorkout
    case weekWarrior
    case earlyBird
    case nightOwl
    case streakMaster

    var title: String {
        switch self {
        case .firstWorkout: return "First Workout"
        case .weekWarrior: return "Week Warrior"
        case .earlyBird: return "Early Bird"
        case .nightOwl: return "Night Owl"
        case .streakMaster: return "Streak Master"
        }
    }

    var icon: String {
        switch self {
        case .firstWorkout: return "star.fill"
        case .weekWarrior: return "calendar.badge.checkmark"
        case .earlyBird: return "sunrise.fill"
        case .nightOwl: return "moon.stars.fill"
        case .streakMaster: return "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .firstWorkout: return .blue
        case .weekWarrior: return .green
        case .earlyBird: return .orange
        case .nightOwl: return .purple
        case .streakMaster: return .red
        }
    }
}
