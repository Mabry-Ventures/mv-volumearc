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
        static let add = String(localized: "common.add")
        static let skipForNow = String(localized: "common.skip_for_now")
    }

    // MARK: - Workout
    enum Workout {
        static let title = String(localized: "workout.title")
        static let completeSet = String(localized: "workout.complete_set")
        static let weight = String(localized: "workout.weight")
        static let reps = String(localized: "workout.reps")
        static let sets = String(localized: "workout.sets")
        static let exercises = String(localized: "workout.exercises")
        static let restDay = String(localized: "workout.rest_day")
        static let trainingDay = String(localized: "workout.training_day")
    }

    // MARK: - Streak
    enum Streak {
        static let dayStreak = String(localized: "streak.day_streak")
        static let thisWeek = String(localized: "streak.this_week")
        static let workoutsOfGoal = String(localized: "streak.workouts_of_goal")
    }

    // MARK: - Badge
    enum Badge {
        static let newBadge = String(localized: "badge.new_badge")
        static let awesome = String(localized: "badge.awesome")
        static let earned = String(localized: "badge.earned")
        static let locked = String(localized: "badge.locked")
        static let recentBadges = String(localized: "badge.recent_badges")
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
        static let plateaus = String(localized: "analytics.plateaus")
        static let needAttention = String(localized: "analytics.need_attention")
        static let exerciseTrends = String(localized: "analytics.exercise_trends")
        static let progressBreakdown = String(localized: "analytics.progress_breakdown")
        static let declining = String(localized: "analytics.declining")
        static let weekAvg = String(localized: "analytics.week_avg")
        static let weightTimesReps = String(localized: "analytics.weight_times_reps")
        static let exercisesImproving = String(localized: "analytics.exercises_improving")
    }

    // MARK: - Plan
    enum Plan {
        static let newPlan = String(localized: "plan.new_plan")
        static let editPlan = String(localized: "plan.edit_plan")
        static let planName = String(localized: "plan.plan_name")
        static let descriptionOptional = String(localized: "plan.description_optional")
        static let basicInfo = String(localized: "plan.basic_info")
        static let configuration = String(localized: "plan.configuration")
        static let goal = String(localized: "plan.goal")
        static let difficulty = String(localized: "plan.difficulty")
        static let duration = String(localized: "plan.duration")
        static let durationWeeks = String(localized: "plan.duration_weeks")
        static let schedule = String(localized: "plan.schedule")
        static let trainingDays = String(localized: "plan.training_days")
        static let trainingDaysPerWeek = String(localized: "plan.training_days_per_week")
        static let weeklySchedule = String(localized: "plan.weekly_schedule")
        static let dangerZone = String(localized: "plan.danger_zone")
        static let deletePlan = String(localized: "plan.delete_plan")
        static let makeTrainingDay = String(localized: "plan.make_training_day")
        static let makeRestDay = String(localized: "plan.make_rest_day")
    }

    // MARK: - Rest Timer
    enum RestTimer {
        static let title = String(localized: "rest_timer.title")
        static let defaultRestTimes = String(localized: "rest_timer.default_rest_times")
        static let compoundLifts = String(localized: "rest_timer.compound_lifts")
        static let compoundDescription = String(localized: "rest_timer.compound_description")
        static let isolationExercises = String(localized: "rest_timer.isolation_exercises")
        static let isolationDescription = String(localized: "rest_timer.isolation_description")
        static let defaultTimer = String(localized: "rest_timer.default")
        static let everythingElse = String(localized: "rest_timer.everything_else")
        static let custom = String(localized: "rest_timer.custom")
        static let perExerciseOverrides = String(localized: "rest_timer.per_exercise_overrides")
        static let customTimers = String(localized: "rest_timer.custom_timers")
        static let alerts = String(localized: "rest_timer.alerts")
        static let timerSound = String(localized: "rest_timer.timer_sound")
        static let vibration = String(localized: "rest_timer.vibration")
        static let noCustomTimers = String(localized: "rest_timer.no_custom_timers")
        static let addCustomTimer = String(localized: "rest_timer.add_custom_timer")
        static let customRestTimes = String(localized: "rest_timer.custom_rest_times")
        static let exerciseName = String(localized: "rest_timer.exercise_name")
        static let exercise = String(localized: "rest_timer.exercise")
        static let quickAdd = String(localized: "rest_timer.quick_add")
        static let restDuration = String(localized: "rest_timer.rest_duration")
    }

    // MARK: - Settings
    enum Settings {
        static let title = String(localized: "settings.title")
        static let restTimer = String(localized: "settings.rest_timer")
    }

    // MARK: - Onboarding
    enum Onboarding {
        static let welcome = String(localized: "onboarding.welcome")
        static let welcomeTo = String(localized: "onboarding.welcome_to")
        static let getStarted = String(localized: "onboarding.get_started")
        static let continueButton = String(localized: "onboarding.continue")
        static let skip = String(localized: "onboarding.skip")
        static let startTraining = String(localized: "onboarding.start_training")
        static let powerfulFeatures = String(localized: "onboarding.powerful_features")
        static let tagline = String(localized: "onboarding.tagline")
        // Features
        static let progressiveOverload = String(localized: "onboarding.progressive_overload")
        static let progressiveOverloadDesc = String(localized: "onboarding.progressive_overload_desc")
        static let personalRecords = String(localized: "onboarding.personal_records")
        static let personalRecordsDesc = String(localized: "onboarding.personal_records_desc")
        static let aiCoach = String(localized: "onboarding.ai_coach")
        static let aiCoachDesc = String(localized: "onboarding.ai_coach_desc")
        static let streakTracking = String(localized: "onboarding.streak_tracking")
        static let streakTrackingDesc = String(localized: "onboarding.streak_tracking_desc")
        static let watchSupport = String(localized: "onboarding.watch_support")
        static let watchSupportDesc = String(localized: "onboarding.watch_support_desc")
        // HealthKit
        static let healthData = String(localized: "onboarding.health_data")
        static let healthDataDesc = String(localized: "onboarding.health_data_desc")
        static let allowHealthAccess = String(localized: "onboarding.allow_health_access")
        // Notifications
        static let stayOnTrack = String(localized: "onboarding.stay_on_track")
        static let notificationsDesc = String(localized: "onboarding.notifications_desc")
        static let enableNotifications = String(localized: "onboarding.enable_notifications")
        // Biometric
        static let secureYourData = String(localized: "onboarding.secure_your_data")
        static let biometricDesc = String(localized: "onboarding.biometric_desc")
        // Sign In
        static let syncYourData = String(localized: "onboarding.sync_your_data")
        static let signInDesc = String(localized: "onboarding.sign_in_desc")
        static let continueWithoutSignIn = String(localized: "onboarding.continue_without_sign_in")
        // Complete
        static let youreAllSet = String(localized: "onboarding.youre_all_set")
        static let readyMessage = String(localized: "onboarding.ready_message")
        static let cloudSync = String(localized: "onboarding.cloud_sync")
        static let enabled = String(localized: "onboarding.enabled")
        static let notEnabled = String(localized: "onboarding.not_enabled")
    }

    // MARK: - Biometric
    enum Biometric {
        static let faceID = String(localized: "biometric.face_id")
        static let touchID = String(localized: "biometric.touch_id")
        static let opticID = String(localized: "biometric.optic_id")
        static let appLock = String(localized: "biometric.app_lock")
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
        static let requesting = String(localized: "time.requesting")
        static let enabling = String(localized: "time.enabling")
    }

    // MARK: - Accessibility
    enum Accessibility {
        static let decrease = String(localized: "accessibility.decrease")
        static let increase = String(localized: "accessibility.increase")
        static let doubleTapToEdit = String(localized: "accessibility.double_tap_to_edit")
        static let swipeForOptions = String(localized: "accessibility.swipe_for_options")
        static let doubleTapToViewDetails = String(localized: "accessibility.double_tap_to_view_details")
        static let dismissCelebration = String(localized: "accessibility.dismiss_celebration")
        static let loadingPleaseWait = String(localized: "accessibility.loading_please_wait")
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

    /// Returns "X exercises" with correct pluralization
    static func exerciseCount(_ count: Int) -> String {
        "\(count) \(pluralize(count: count, singular: "exercise", plural: Workout.exercises))"
    }
}
