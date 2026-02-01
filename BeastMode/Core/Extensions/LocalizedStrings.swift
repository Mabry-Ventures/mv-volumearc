// LocalizedStrings.swift
// BeastMode
// Type-safe localized string keys for the app

import Foundation

/// Type-safe access to localized strings
/// Usage: Text(L10n.Workout.completeSet)
enum L10n {
    // MARK: - App
    enum App {
        static let name = String(localized: "app.name")
    }

    // MARK: - Common
    enum Common {
        static let cancel = String(localized: "common.cancel")
        static let save = String(localized: "common.save")
        static let done = String(localized: "common.done")
        static let delete = String(localized: "common.delete")
        static let edit = String(localized: "common.edit")
    }

    // MARK: - Workout
    enum Workout {
        static let title = String(localized: "workout.title")
        static let completeSet = String(localized: "workout.complete_set")
        static let weight = String(localized: "workout.weight")
        static let reps = String(localized: "workout.reps")
        static let sets = String(localized: "workout.sets")
    }

    // MARK: - Streak
    enum Streak {
        static let dayStreak = String(localized: "streak.day_streak")
        static let thisWeek = String(localized: "streak.this_week")
    }

    // MARK: - Badge
    enum Badge {
        static let newBadge = String(localized: "badge.new_badge")
        static let awesome = String(localized: "badge.awesome")
    }

    // MARK: - PR (Personal Record)
    enum PR {
        static let personalRecord = String(localized: "pr.personal_record")
        static let keepGrinding = String(localized: "pr.keep_grinding")
        static let share = String(localized: "pr.share")
    }

    // MARK: - Analytics
    enum Analytics {
        static let title = String(localized: "analytics.title")
        static let workouts = String(localized: "analytics.workouts")
        static let totalVolume = String(localized: "analytics.total_volume")
        static let progressing = String(localized: "analytics.progressing")
        static let plateau = String(localized: "analytics.plateau")
    }

    // MARK: - Settings
    enum Settings {
        static let title = String(localized: "settings.title")
        static let restTimer = String(localized: "settings.rest_timer")
    }

    // MARK: - Onboarding
    enum Onboarding {
        static let welcome = String(localized: "onboarding.welcome")
        static let getStarted = String(localized: "onboarding.get_started")
        static let continueButton = String(localized: "onboarding.continue")
        static let skip = String(localized: "onboarding.skip")
        static let startTraining = String(localized: "onboarding.start_training")
    }

    // MARK: - Biometric
    enum Biometric {
        static let faceID = String(localized: "biometric.face_id")
        static let touchID = String(localized: "biometric.touch_id")
    }

    // MARK: - Units
    enum Units {
        static let pounds = String(localized: "units.pounds")
        static let kilograms = String(localized: "units.kilograms")
    }

    // MARK: - Time
    enum Time {
        static let week = String(localized: "time.week")
        static let weeks = String(localized: "time.weeks")
        static let days = String(localized: "time.days")
    }
}

// MARK: - Pluralization Helper

extension L10n {
    /// Returns the correct plural form based on count
    /// Usage: L10n.pluralize(count: 5, singular: "workout", plural: "workouts")
    static func pluralize(count: Int, singular: String, plural: String) -> String {
        count == 1 ? singular : plural
    }

    /// Returns "X workouts" with correct pluralization
    static func workoutCount(_ count: Int) -> String {
        "\(count) \(pluralize(count: count, singular: "workout", plural: "workouts"))"
    }

    /// Returns "X days" with correct pluralization
    static func dayCount(_ count: Int) -> String {
        "\(count) \(pluralize(count: count, singular: "day", plural: Time.days))"
    }

    /// Returns "X weeks" with correct pluralization
    static func weekCount(_ count: Int) -> String {
        "\(count) \(pluralize(count: count, singular: Time.week, plural: Time.weeks))"
    }
}
