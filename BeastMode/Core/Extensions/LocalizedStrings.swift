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
        static let nameUppercase = String(localized: "app.name_uppercase")
        static let loadingData = String(localized: "app.loading_data")
        static let somethingWentWrong = String(localized: "app.something_went_wrong")
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
        static let tryAgain = String(localized: "common.try_again")
        static let contactSupport = String(localized: "common.contact_support")
        static let today = String(localized: "common.today")
        static let active = String(localized: "common.active")
        static let noData = String(localized: "common.no_data")
        static let notes = String(localized: "common.notes")
        static let advanced = String(localized: "common.advanced")
        static let copiedToClipboard = String(localized: "common.copied_to_clipboard")
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
        static let startWorkout = String(localized: "workout.start_workout")
        static let beginNewSession = String(localized: "workout.begin_new_session")
        static let recentWorkouts = String(localized: "workout.recent_workouts")
        static let startFirstWorkout = String(localized: "workout.start_first_workout")
        static let readyToTrain = String(localized: "workout.ready_to_train")
        static let startNewSession = String(localized: "workout.start_new_session")
        static let duration = String(localized: "workout.duration")
        static let volume = String(localized: "workout.volume")
        static let compound = String(localized: "workout.compound")
        static let distance = String(localized: "workout.distance")
        static let rpe = String(localized: "workout.rpe")
        static func setNumber(_ number: Int) -> String {
            String(localized: "workout.set_number \(number)")
        }
    }

    // MARK: - Streak
    enum Streak {
        static let dayStreak = String(localized: "streak.day_streak")
        static let thisWeek = String(localized: "streak.this_week")
        static let workoutsOfGoal = String(localized: "streak.workouts_of_goal")
        static let totalVolumLifted = String(localized: "streak.total_volume_lifted")
        static let weeklyGoal = String(localized: "streak.weekly_goal")
        static let goalReached = String(localized: "streak.goal_reached")
    }

    // MARK: - Badge
    enum Badge {
        static let newBadge = String(localized: "badge.new_badge")
        static let awesome = String(localized: "badge.awesome")
        static let earned = String(localized: "badge.earned")
        static let locked = String(localized: "badge.locked")
        static let recentBadges = String(localized: "badge.recent_badges")
        static let earnedOn = String(localized: "badge.earned_on")
        static let requirement = String(localized: "badge.requirement")
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
        static let analyzingProgress = String(localized: "analytics.analyzing_progress")
        static let noDataYet = String(localized: "analytics.no_data_yet")
        static let completeWorkoutsToSee = String(localized: "analytics.complete_workouts_to_see")
        static let noExercisesTracked = String(localized: "analytics.no_exercises_tracked")
        static let weeklyVolume = String(localized: "analytics.weekly_volume")
        static let average = String(localized: "analytics.average")
        static let recentSets = String(localized: "analytics.recent_sets")
        static func e1rm(_ value: Int) -> String {
            String(localized: "analytics.e1rm \(value)")
        }
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
        static let quickActions = String(localized: "plan.quick_actions")
        static let myPlans = String(localized: "plan.my_plans")
        static let activePlan = String(localized: "plan.active_plan")
        static let createFirstPlan = String(localized: "plan.create_first_plan")
        static let weekAtAGlance = String(localized: "plan.week_at_a_glance")
        static let viewPlan = String(localized: "plan.view_plan")
        static let daysPerWeek = String(localized: "plan.days_per_week")
        static let dayInfo = String(localized: "plan.day_info")
        static let addExercisesToDay = String(localized: "plan.add_exercises_to_day")
        static let superset = String(localized: "plan.superset")
        static let repRange = String(localized: "plan.rep_range")
        static let prescription = String(localized: "plan.prescription")
        static let targetRpe = String(localized: "plan.target_rpe")
        static let intensity = String(localized: "plan.intensity")
        static let rpeDescription = String(localized: "plan.rpe_description")
        static let restBetweenSets = String(localized: "plan.rest_between_sets")
        static let supersetDescription = String(localized: "plan.superset_description")
        static let quickPresets = String(localized: "plan.quick_presets")
        static let customizeAfterAdding = String(localized: "plan.customize_after_adding")
        static let deleteConfirmation = String(localized: "plan.delete_confirmation")
        static let tapDayToConfigure = String(localized: "plan.tap_day_to_configure")
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
        static let version = String(localized: "settings.version")
        static let signOutMessage = String(localized: "settings.sign_out_message")
    }

    // MARK: - Health
    enum Health {
        static let bodyWeight = String(localized: "health.body_weight")
        static let noWeightData = String(localized: "health.no_weight_data")
        static let connectToHealth = String(localized: "health.connect_to_health")
        static let dataSource = String(localized: "health.data_source")
        static let dataSourceDescription = String(localized: "health.data_source_description")
    }

    // MARK: - AI Coach
    enum AICoach {
        static let weeklyReview = String(localized: "ai_coach.weekly_review")
        static let analyzingWeek = String(localized: "ai_coach.analyzing_week")
        static let mayTakeMoment = String(localized: "ai_coach.may_take_moment")
        static let couldntGenerate = String(localized: "ai_coach.couldnt_generate")
        static let getInsights = String(localized: "ai_coach.get_insights")
        static let aiSuggestion = String(localized: "ai_coach.ai_suggestion")
        static let nextSession = String(localized: "ai_coach.next_session")
    }

    // MARK: - Sharing
    enum Sharing {
        static let shareMethod = String(localized: "sharing.share_method")
        static let exportDesc = String(localized: "sharing.export_desc")
        static let exportFile = String(localized: "sharing.export_file")
        static let generateLinkDesc = String(localized: "sharing.generate_link_desc")
        static let generateLink = String(localized: "sharing.generate_link")
        static let shareCodeDesc = String(localized: "sharing.share_code_desc")
        static let generateCode = String(localized: "sharing.generate_code")
        static let shareCodeNote = String(localized: "sharing.share_code_note")
        static let importFrom = String(localized: "sharing.import_from")
        static let importFile = String(localized: "sharing.import_file")
        static let selectPlanFile = String(localized: "sharing.select_plan_file")
        static let enterShareCode = String(localized: "sharing.enter_share_code")
        static let enterCodeDesc = String(localized: "sharing.enter_code_desc")
        static let importPlan = String(localized: "sharing.import_plan")
        static let planFound = String(localized: "sharing.plan_found")
        static let createdBy = String(localized: "sharing.created_by")
        static let importThisPlan = String(localized: "sharing.import_this_plan")
        static let planImported = String(localized: "sharing.plan_imported")
        static let couldntLoadPlan = String(localized: "sharing.couldnt_load_plan")
    }

    // MARK: - Network
    enum Network {
        static let youreOffline = String(localized: "network.youre_offline")
        static let willSyncWhenConnected = String(localized: "network.will_sync_when_connected")
    }

    // MARK: - Debug
    enum Debug {
        static let noErrorsRecorded = String(localized: "debug.no_errors_recorded")
    }

    // MARK: - Sync
    enum Sync {
        static let syncing = String(localized: "sync.syncing")
        static let synced = String(localized: "sync.synced")
        static let pending = String(localized: "sync.pending")
        static let conflict = String(localized: "sync.conflict")
        static let error = String(localized: "sync.error")
        static let iCloudSync = String(localized: "sync.icloud_sync")
        static let syncNow = String(localized: "sync.sync_now")
        static let lastSyncedNever = String(localized: "sync.last_synced_never")
        static let iCloudRequired = String(localized: "sync.icloud_required")
        static let signInToSync = String(localized: "sync.sign_in_to_sync")
        static let syncInProgress = String(localized: "sync.sync_in_progress")
        static let conflictResolved = String(localized: "sync.conflict_resolved")
        static let offlineChangesQueued = String(localized: "sync.offline_changes_queued")
        static func pendingChanges(_ count: Int) -> String {
            String(localized: "sync.pending_changes \(count)")
        }
        static func lastSynced(_ time: String) -> String {
            String(localized: "sync.last_synced \(time)")
        }
        static func syncFailed(_ reason: String) -> String {
            String(localized: "sync.sync_failed \(reason)")
        }
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
        static let locked = String(localized: "biometric.locked")
        static let unlockWith = String(localized: "biometric.unlock_with")
        static let security = String(localized: "biometric.security")
        static let use = String(localized: "biometric.use")
        static let requireOnLaunch = String(localized: "biometric.require_on_launch")
        static let askWhenOpening = String(localized: "biometric.ask_when_opening")
        static let protectData = String(localized: "biometric.protect_data")
        static let notEnrolled = String(localized: "biometric.not_enrolled")
        static let notAvailable = String(localized: "biometric.not_available")
    }

    // MARK: - Units
    enum Units {
        static let pounds = String(localized: "units.pounds")
        static let kilograms = String(localized: "units.kilograms")
        static let lbs = String(localized: "units.lbs")
        static let kg = String(localized: "units.kg")
        static let repsAbbrev = String(localized: "units.reps_abbrev")
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

    // MARK: - Notifications
    enum Notification {
        // Weekly Review
        static let weeklyReviewTitle = String(localized: "notification.weekly_review.title")
        static let weeklyReviewBody = String(localized: "notification.weekly_review.body")
        static let weeklyReviewHiddenPreview = String(localized: "notification.weekly_review.hidden_preview")

        // Streak Reminder
        static let streakReminderTitle = String(localized: "notification.streak_reminder.title")
        static func streakReminderBody(streak: Int) -> String {
            String(localized: "notification.streak_reminder.body \(streak)")
        }
        static let streakReminderHiddenPreview = String(localized: "notification.streak_reminder.hidden_preview")

        // Streak At Risk
        static let streakAtRiskTitle = String(localized: "notification.streak_at_risk.title")
        static func streakAtRiskBody(streak: Int) -> String {
            String(localized: "notification.streak_at_risk.body \(streak)")
        }

        // Workout Reminder
        static let workoutReminderTitle = String(localized: "notification.workout_reminder.title")
        static func workoutReminderBody(dayName: String) -> String {
            String(localized: "notification.workout_reminder.body \(dayName)")
        }
        static let workoutReminderHiddenPreview = String(localized: "notification.workout_reminder.hidden_preview")

        // Congratulations
        static let congratulationsTitle = String(localized: "notification.congratulations.title")
        static func congratulationsBody(badge: String) -> String {
            String(localized: "notification.congratulations.body \(badge)")
        }

        // Snooze
        static let snoozeTitle = String(localized: "notification.snooze.title")
        static let snoozeBody = String(localized: "notification.snooze.body")

        // Actions
        static let actionViewReview = String(localized: "notification.action.view_review")
        static let actionDismiss = String(localized: "notification.action.dismiss")
        static let actionStartWorkout = String(localized: "notification.action.start_workout")
        static let actionSnooze = String(localized: "notification.action.snooze")

        // Settings
        static let notificationsTitle = String(localized: "notification.settings.title")
        static let weeklyReviewNotifications = String(localized: "notification.settings.weekly_review")
        static let streakReminders = String(localized: "notification.settings.streak_reminders")
        static let workoutReminders = String(localized: "notification.settings.workout_reminders")
        static let reminderTime = String(localized: "notification.settings.reminder_time")
        static let reminderDays = String(localized: "notification.settings.reminder_days")
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
