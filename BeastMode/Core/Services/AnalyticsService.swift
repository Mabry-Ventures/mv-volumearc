import Foundation
import TelemetryClient

/// Service for analytics using TelemetryDeck
final class AnalyticsService {
    static let shared = AnalyticsService()

    private var isInitialized = false

    private init() {}

    // MARK: - Configuration

    /// Initialize TelemetryDeck with app ID
    func configure() {
        guard !isInitialized else { return }

        let configuration = TelemetryManagerConfiguration(
            appID: Configuration.telemetryDeckAppID
        )

        TelemetryManager.initialize(with: configuration)
        isInitialized = true

        // Track app launch
        track(.appLaunched)
    }

    // MARK: - Track Events

    /// Track an analytics event
    func track(_ event: AnalyticsEvent) {
        guard isInitialized else { return }
        TelemetryManager.send(event.name, with: event.parameters)
    }

    /// Track an event with custom parameters
    func track(_ event: AnalyticsEvent, additionalParameters: [String: String]) {
        guard isInitialized else { return }
        var params = event.parameters
        params.merge(additionalParameters) { _, new in new }
        TelemetryManager.send(event.name, with: params)
    }
}

// MARK: - Analytics Events

enum AnalyticsEvent {
    // App Lifecycle
    case appLaunched
    case onboardingCompleted
    case onboardingSkipped

    // Workout Events
    case workoutStarted(focusArea: String)
    case workoutCompleted(focusArea: String, duration: TimeInterval, exerciseCount: Int, setCount: Int)
    case workoutCancelled(focusArea: String, duration: TimeInterval)

    // Exercise Logging
    case setLogged(exerciseName: String, isWarmup: Bool)
    case exerciseAdded(exerciseName: String, exerciseType: String)
    case exerciseDeleted(exerciseName: String)

    // Personal Records
    case prAchieved(exerciseName: String, weight: Double, reps: Int)
    case prViewed

    // AI Coach
    case aiCoachOpened
    case aiCoachQuestionAsked(questionType: String)
    case aiFormCheckRequested(exerciseName: String)
    case aiAlternativesRequested(exerciseName: String)
    case aiWeeklyReviewRequested

    // Plan Management
    case weeklyPlanViewed
    case planReset
    case planImported
    case exerciseInfoViewed(exerciseName: String)

    // Rest Timer
    case restTimerStarted(duration: TimeInterval)
    case restTimerCompleted
    case restTimerSkipped

    // Settings
    case settingsOpened
    case weightUnitChanged(unit: String)
    case restTimerDefaultChanged(duration: TimeInterval)
    case healthKitConnected
    case healthKitDenied

    // Widgets & Shortcuts
    case widgetTapped(widgetType: String)
    case shortcutUsed(shortcutName: String)

    // Watch
    case watchWorkoutStarted
    case watchWorkoutCompleted
    case watchSetLogged

    // Navigation
    case tabSelected(tab: String)

    var name: String {
        switch self {
        case .appLaunched: return "app_launched"
        case .onboardingCompleted: return "onboarding_completed"
        case .onboardingSkipped: return "onboarding_skipped"

        case .workoutStarted: return "workout_started"
        case .workoutCompleted: return "workout_completed"
        case .workoutCancelled: return "workout_cancelled"

        case .setLogged: return "set_logged"
        case .exerciseAdded: return "exercise_added"
        case .exerciseDeleted: return "exercise_deleted"

        case .prAchieved: return "pr_achieved"
        case .prViewed: return "pr_viewed"

        case .aiCoachOpened: return "ai_coach_opened"
        case .aiCoachQuestionAsked: return "ai_coach_question_asked"
        case .aiFormCheckRequested: return "ai_form_check_requested"
        case .aiAlternativesRequested: return "ai_alternatives_requested"
        case .aiWeeklyReviewRequested: return "ai_weekly_review_requested"

        case .weeklyPlanViewed: return "weekly_plan_viewed"
        case .planReset: return "plan_reset"
        case .planImported: return "plan_imported"
        case .exerciseInfoViewed: return "exercise_info_viewed"

        case .restTimerStarted: return "rest_timer_started"
        case .restTimerCompleted: return "rest_timer_completed"
        case .restTimerSkipped: return "rest_timer_skipped"

        case .settingsOpened: return "settings_opened"
        case .weightUnitChanged: return "weight_unit_changed"
        case .restTimerDefaultChanged: return "rest_timer_default_changed"
        case .healthKitConnected: return "healthkit_connected"
        case .healthKitDenied: return "healthkit_denied"

        case .widgetTapped: return "widget_tapped"
        case .shortcutUsed: return "shortcut_used"

        case .watchWorkoutStarted: return "watch_workout_started"
        case .watchWorkoutCompleted: return "watch_workout_completed"
        case .watchSetLogged: return "watch_set_logged"

        case .tabSelected: return "tab_selected"
        }
    }

    var parameters: [String: String] {
        switch self {
        case .appLaunched, .onboardingCompleted, .onboardingSkipped,
             .prViewed, .aiCoachOpened, .aiWeeklyReviewRequested,
             .weeklyPlanViewed, .planReset, .planImported,
             .restTimerCompleted, .restTimerSkipped,
             .settingsOpened, .healthKitConnected, .healthKitDenied,
             .watchWorkoutStarted, .watchWorkoutCompleted, .watchSetLogged:
            return [:]

        case .workoutStarted(let focusArea):
            return ["focus_area": focusArea]

        case .workoutCompleted(let focusArea, let duration, let exerciseCount, let setCount):
            return [
                "focus_area": focusArea,
                "duration_minutes": String(Int(duration / 60)),
                "exercise_count": String(exerciseCount),
                "set_count": String(setCount)
            ]

        case .workoutCancelled(let focusArea, let duration):
            return [
                "focus_area": focusArea,
                "duration_minutes": String(Int(duration / 60))
            ]

        case .setLogged(let exerciseName, let isWarmup):
            return [
                "exercise_name": exerciseName,
                "is_warmup": String(isWarmup)
            ]

        case .exerciseAdded(let exerciseName, let exerciseType):
            return [
                "exercise_name": exerciseName,
                "exercise_type": exerciseType
            ]

        case .exerciseDeleted(let exerciseName):
            return ["exercise_name": exerciseName]

        case .prAchieved(let exerciseName, let weight, let reps):
            return [
                "exercise_name": exerciseName,
                "weight": String(Int(weight)),
                "reps": String(reps)
            ]

        case .aiCoachQuestionAsked(let questionType):
            return ["question_type": questionType]

        case .aiFormCheckRequested(let exerciseName):
            return ["exercise_name": exerciseName]

        case .aiAlternativesRequested(let exerciseName):
            return ["exercise_name": exerciseName]

        case .exerciseInfoViewed(let exerciseName):
            return ["exercise_name": exerciseName]

        case .restTimerStarted(let duration):
            return ["duration_seconds": String(Int(duration))]

        case .weightUnitChanged(let unit):
            return ["unit": unit]

        case .restTimerDefaultChanged(let duration):
            return ["duration_seconds": String(Int(duration))]

        case .widgetTapped(let widgetType):
            return ["widget_type": widgetType]

        case .shortcutUsed(let shortcutName):
            return ["shortcut_name": shortcutName]

        case .tabSelected(let tab):
            return ["tab": tab]
        }
    }
}

// MARK: - Convenience Extensions

extension AnalyticsService {
    /// Track workout start
    func trackWorkoutStart(focusArea: String) {
        track(.workoutStarted(focusArea: focusArea))
    }

    /// Track workout completion with stats
    func trackWorkoutComplete(
        focusArea: String,
        duration: TimeInterval,
        exerciseCount: Int,
        setCount: Int
    ) {
        track(.workoutCompleted(
            focusArea: focusArea,
            duration: duration,
            exerciseCount: exerciseCount,
            setCount: setCount
        ))
    }

    /// Track a new PR
    func trackPR(exerciseName: String, weight: Double, reps: Int) {
        track(.prAchieved(exerciseName: exerciseName, weight: weight, reps: reps))
    }

    /// Track AI coach interaction
    func trackAICoach(action: String, exerciseName: String? = nil) {
        switch action {
        case "form_check":
            if let name = exerciseName {
                track(.aiFormCheckRequested(exerciseName: name))
            }
        case "alternatives":
            if let name = exerciseName {
                track(.aiAlternativesRequested(exerciseName: name))
            }
        case "weekly_review":
            track(.aiWeeklyReviewRequested)
        default:
            track(.aiCoachQuestionAsked(questionType: action))
        }
    }
}
