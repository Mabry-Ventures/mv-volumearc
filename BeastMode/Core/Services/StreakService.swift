// StreakService.swift
// BeastMode
// Service for managing workout streaks and badges

import Foundation
import SwiftData

/// Service for tracking workout streaks and awarding badges
actor StreakService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Records a workout completion and checks for new badges
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - completedAt: When the workout was completed
    ///   - sessionVolume: Total volume lifted in the session
    /// - Returns: Array of newly earned badges
    func recordWorkout(
        for userId: UUID,
        completedAt: Date,
        sessionVolume: Double = 0
    ) async throws -> [Badge] {
        let streak = try await getOrCreateStreak(for: userId)
        var newBadges: [Badge] = []

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: completedAt)

        // Update streak
        if let lastDate = streak.lastWorkoutDate {
            let lastDay = calendar.startOfDay(for: lastDate)
            let daysDiff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

            if daysDiff == 1 {
                // Consecutive day - extend streak
                streak.currentStreak += 1
            } else if daysDiff > 1 {
                // Streak broken - reset
                streak.currentStreak = 1
            }
            // daysDiff == 0 means same day, don't change streak
        } else {
            // First workout ever
            streak.currentStreak = 1
            if !streak.hasBadge(.firstWorkout) {
                streak.awardBadge(.firstWorkout)
                newBadges.append(.firstWorkout)
            }
        }

        // Update longest streak
        if streak.currentStreak > streak.longestStreak {
            streak.longestStreak = streak.currentStreak
        }

        streak.lastWorkoutDate = completedAt
        streak.totalWorkouts += 1

        // Update weekly count
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!

        if let existingWeekStart = streak.weekStartDate,
           !calendar.isDate(existingWeekStart, equalTo: weekStart, toGranularity: .weekOfYear) {
            // New week - reset count
            streak.currentWeekCount = 1
            streak.weekStartDate = weekStart
        } else if streak.weekStartDate == nil {
            streak.weekStartDate = weekStart
            streak.currentWeekCount = 1
        } else {
            streak.currentWeekCount += 1
        }

        // Update volume
        streak.totalVolumeLifted += sessionVolume

        // Check for weekend workout
        let weekday = calendar.component(.weekday, from: completedAt)
        if weekday == 1 || weekday == 7 {  // Sunday = 1, Saturday = 7
            streak.weekendWorkouts += 1
        }

        // Check for streak badges
        newBadges.append(contentsOf: checkAndAwardStreakBadges(streak: streak))

        // Check for time-based badges
        newBadges.append(contentsOf: checkAndAwardTimeBadges(streak: streak, completedAt: completedAt))

        // Check for volume badges
        newBadges.append(contentsOf: checkAndAwardVolumeBadges(streak: streak, sessionVolume: sessionVolume))

        // Check for weekend warrior badge
        newBadges.append(contentsOf: checkAndAwardWeekendBadge(streak: streak))

        try modelContext.save()

        return newBadges
    }

    /// Records a PR and checks for PR-related badges
    func recordPR(for userId: UUID) async throws -> [Badge] {
        let streak = try await getOrCreateStreak(for: userId)
        var newBadges: [Badge] = []

        streak.totalPRs += 1

        // Check for PR badges
        if streak.totalPRs == 1 && !streak.hasBadge(.firstPR) {
            streak.awardBadge(.firstPR)
            newBadges.append(.firstPR)
        }

        if streak.totalPRs >= 10 && !streak.hasBadge(.prHunter) {
            streak.awardBadge(.prHunter)
            newBadges.append(.prHunter)
        }

        if streak.totalPRs >= 50 && !streak.hasBadge(.prMachine) {
            streak.awardBadge(.prMachine)
            newBadges.append(.prMachine)
        }

        if streak.totalPRs >= 100 && !streak.hasBadge(.legendary) {
            streak.awardBadge(.legendary)
            newBadges.append(.legendary)
        }

        try modelContext.save()

        return newBadges
    }

    /// Get the current streak for a user
    func getStreak(for userId: UUID) async throws -> UserStreak? {
        let descriptor = FetchDescriptor<UserStreak>(
            predicate: #Predicate<UserStreak> { $0.userId == userId }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Get all earned badges for a user
    func getEarnedBadges(for userId: UUID) async throws -> [Badge] {
        guard let streak = try await getStreak(for: userId) else {
            return []
        }

        return streak.earnedBadges.compactMap { Badge(rawValue: $0) }
    }

    // MARK: - Private Helpers

    private func getOrCreateStreak(for userId: UUID) async throws -> UserStreak {
        let descriptor = FetchDescriptor<UserStreak>(
            predicate: #Predicate<UserStreak> { $0.userId == userId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let newStreak = UserStreak(userId: userId)
        modelContext.insert(newStreak)
        return newStreak
    }

    private func checkAndAwardStreakBadges(streak: UserStreak) -> [Badge] {
        var badges: [Badge] = []

        if streak.currentStreak >= 7 && !streak.hasBadge(.weekWarrior) {
            streak.awardBadge(.weekWarrior)
            badges.append(.weekWarrior)
        }

        if streak.currentStreak >= 14 && !streak.hasBadge(.twoWeekTitan) {
            streak.awardBadge(.twoWeekTitan)
            badges.append(.twoWeekTitan)
        }

        if streak.currentStreak >= 30 && !streak.hasBadge(.monthlyBeast) {
            streak.awardBadge(.monthlyBeast)
            badges.append(.monthlyBeast)
        }

        if streak.currentStreak >= 100 && !streak.hasBadge(.centurion) {
            streak.awardBadge(.centurion)
            badges.append(.centurion)
        }

        return badges
    }

    private func checkAndAwardTimeBadges(streak: UserStreak, completedAt: Date) -> [Badge] {
        var badges: [Badge] = []
        let hour = Calendar.current.component(.hour, from: completedAt)

        if hour < 7 && !streak.hasBadge(.earlyBird) {
            streak.awardBadge(.earlyBird)
            badges.append(.earlyBird)
        }

        if hour >= 21 && !streak.hasBadge(.nightOwl) {
            streak.awardBadge(.nightOwl)
            badges.append(.nightOwl)
        }

        return badges
    }

    private func checkAndAwardVolumeBadges(streak: UserStreak, sessionVolume: Double) -> [Badge] {
        var badges: [Badge] = []

        // Ton lifter - 2000 lbs in one session
        if sessionVolume >= 2000 && !streak.hasBadge(.tonLifter) {
            streak.awardBadge(.tonLifter)
            badges.append(.tonLifter)
        }

        // Volume king - 50,000 lbs lifetime
        if streak.totalVolumeLifted >= 50000 && !streak.hasBadge(.volumeKing) {
            streak.awardBadge(.volumeKing)
            badges.append(.volumeKing)
        }

        return badges
    }

    private func checkAndAwardWeekendBadge(streak: UserStreak) -> [Badge] {
        var badges: [Badge] = []

        if streak.weekendWorkouts >= 4 && !streak.hasBadge(.weekendWarrior) {
            streak.awardBadge(.weekendWarrior)
            badges.append(.weekendWarrior)
        }

        return badges
    }
}
