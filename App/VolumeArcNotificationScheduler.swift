#if canImport(UserNotifications)
import Foundation
// VOL-128: `@preconcurrency` treats Sendable-related diagnostics from
// the UserNotifications module as warnings instead of errors. Apple's
// `UNUserNotificationCenter` is not yet Sendable-audited (as of iOS 26.4),
// so capturing it in a @Sendable completion closure trips
// "non-Sendable type" diagnostics. The framework is documented as
// thread-safe at runtime; once Apple ships proper Sendable conformance,
// the @preconcurrency annotation can be dropped.
@preconcurrency import UserNotifications
import VolumeArcCore

struct VolumeArcNotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return settings.authorizationStatus == .authorized
        }

        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleRestTimerNotification(after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rest Complete", comment: "Rest timer notification title")
        content.body = String(localized: "Time to hit your next set.", comment: "Rest timer notification body")
        content.sound = .default
        content.categoryIdentifier = "REST_TIMER"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: "rest-timer", content: content, trigger: trigger)

        center.add(request)
    }

    func scheduleWorkoutReminder(title: String, at dateComponents: DateComponents) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Workout Today", comment: "Workout reminder notification title")
        content.body = String(localized: "\(title) is scheduled. Ready when you are.", comment: "Workout reminder notification body")
        content.sound = .default
        content.categoryIdentifier = "WORKOUT_REMINDER"

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "workout-reminder-\(dateComponents.weekday ?? 0)", content: content, trigger: trigger)

        center.add(request)
    }

    func cancelRestTimerNotification() {
        center.removePendingNotificationRequests(withIdentifiers: ["rest-timer"])
    }

    func cancelAllWorkoutReminders() {
        center.getPendingNotificationRequests { requests in
            let reminderIDs = requests
                .filter { $0.identifier.hasPrefix("workout-reminder-") }
                .map(\.identifier)
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: reminderIDs)
        }
    }

    func registerCategories() {
        let startAction = UNNotificationAction(
            identifier: "START_WORKOUT",
            title: String(localized: "Start Workout", comment: "Notification action button"),
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: String(localized: "Dismiss", comment: "Notification dismiss button"),
            options: [.destructive]
        )

        let restCategory = UNNotificationCategory(
            identifier: "REST_TIMER",
            actions: [dismissAction],
            intentIdentifiers: []
        )
        let workoutCategory = UNNotificationCategory(
            identifier: "WORKOUT_REMINDER",
            actions: [startAction, dismissAction],
            intentIdentifiers: []
        )

        center.setNotificationCategories([restCategory, workoutCategory])
    }
}
#endif
