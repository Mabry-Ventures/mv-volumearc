// NotificationService.swift
// BeastMode
// Service for managing push notifications and local notifications

import Foundation
import UserNotifications
import UIKit

// MARK: - UserDefaults Keys for Notification Preferences

enum NotificationPreferenceKeys {
    static let notificationsEnabled = "notifications.enabled"
    static let weeklyReviewEnabled = "notifications.weekly_review.enabled"
    static let weeklyReviewDay = "notifications.weekly_review.day" // 1 = Sunday, 2 = Monday
    static let weeklyReviewHour = "notifications.weekly_review.hour"
    static let weeklyReviewMinute = "notifications.weekly_review.minute"
    static let streakRemindersEnabled = "notifications.streak_reminders.enabled"
    static let streakReminderHour = "notifications.streak_reminders.hour"
    static let streakReminderMinute = "notifications.streak_reminders.minute"
    static let workoutRemindersEnabled = "notifications.workout_reminders.enabled"
    static let workoutReminderHour = "notifications.workout_reminders.hour"
    static let workoutReminderMinute = "notifications.workout_reminders.minute"
    static let workoutReminderDays = "notifications.workout_reminders.days" // Array of weekday integers
    static let lastScheduledDate = "notifications.last_scheduled_date"
    static let badgeCount = "notifications.badge_count"
}

// MARK: - Notification Identifiers

enum NotificationIdentifiers {
    // Category identifiers
    static let weeklyReviewCategory = "WEEKLY_REVIEW_CATEGORY"
    static let streakReminderCategory = "STREAK_REMINDER_CATEGORY"
    static let workoutReminderCategory = "WORKOUT_REMINDER_CATEGORY"

    // Action identifiers
    static let viewReviewAction = "VIEW_REVIEW_ACTION"
    static let dismissAction = "DISMISS_ACTION"
    static let startWorkoutAction = "START_WORKOUT_ACTION"
    static let snoozeAction = "SNOOZE_ACTION"

    // Request identifiers (prefixes)
    static let weeklyReviewPrefix = "weekly-review-"
    static let streakReminderPrefix = "streak-reminder-"
    static let workoutReminderPrefix = "workout-reminder-"
}

// MARK: - Notification Content

enum NotificationContent {
    case weeklyReviewAvailable
    case streakReminder(currentStreak: Int)
    case streakAtRisk(currentStreak: Int)
    case workoutReminder(dayName: String)
    case congratulations(badge: String)

    var title: String {
        switch self {
        case .weeklyReviewAvailable:
            return String(localized: "notification.weekly_review.title")
        case .streakReminder:
            return String(localized: "notification.streak_reminder.title")
        case .streakAtRisk:
            return String(localized: "notification.streak_at_risk.title")
        case .workoutReminder:
            return String(localized: "notification.workout_reminder.title")
        case .congratulations:
            return String(localized: "notification.congratulations.title")
        }
    }

    var body: String {
        switch self {
        case .weeklyReviewAvailable:
            return String(localized: "notification.weekly_review.body")
        case .streakReminder(let streak):
            return String(localized: "notification.streak_reminder.body \(streak)")
        case .streakAtRisk(let streak):
            return String(localized: "notification.streak_at_risk.body \(streak)")
        case .workoutReminder(let dayName):
            return String(localized: "notification.workout_reminder.body \(dayName)")
        case .congratulations(let badge):
            return String(localized: "notification.congratulations.body \(badge)")
        }
    }

    var categoryIdentifier: String {
        switch self {
        case .weeklyReviewAvailable:
            return NotificationIdentifiers.weeklyReviewCategory
        case .streakReminder, .streakAtRisk:
            return NotificationIdentifiers.streakReminderCategory
        case .workoutReminder:
            return NotificationIdentifiers.workoutReminderCategory
        case .congratulations:
            return NotificationIdentifiers.weeklyReviewCategory
        }
    }

    var sound: UNNotificationSound {
        switch self {
        case .streakAtRisk:
            return .defaultCritical
        default:
            return .default
        }
    }
}

// MARK: - Notification Service

/// Service for managing all app notifications
final class NotificationService: NSObject, @unchecked Sendable {

    // MARK: - Singleton

    static let shared = NotificationService()

    // MARK: - Properties

    private let notificationCenter = UNUserNotificationCenter.current()
    private let userDefaults: UserDefaults
    private let calendar = Calendar.current

    /// Current authorization status
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Initialization

    private override init() {
        self.userDefaults = AppConfiguration.sharedUserDefaults ?? .standard
        super.init()
        setupNotificationCategories()
        notificationCenter.delegate = self
    }

    // MARK: - Authorization

    /// Request notification permissions from the user
    /// - Returns: Whether permissions were granted
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound, .providesAppNotificationSettings]
            let granted = try await notificationCenter.requestAuthorization(options: options)

            await updateAuthorizationStatus()

            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                userDefaults.set(true, forKey: NotificationPreferenceKeys.notificationsEnabled)
            }

            return granted
        } catch {
            print("NotificationService: Failed to request authorization: \(error)")
            return false
        }
    }

    /// Update the current authorization status
    func updateAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Check if notifications are authorized
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // MARK: - Notification Categories Setup

    private func setupNotificationCategories() {
        // Weekly Review Category
        let viewReviewAction = UNNotificationAction(
            identifier: NotificationIdentifiers.viewReviewAction,
            title: String(localized: "notification.action.view_review"),
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: NotificationIdentifiers.dismissAction,
            title: String(localized: "notification.action.dismiss"),
            options: [.destructive]
        )

        let weeklyReviewCategory = UNNotificationCategory(
            identifier: NotificationIdentifiers.weeklyReviewCategory,
            actions: [viewReviewAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(localized: "notification.weekly_review.hidden_preview"),
            options: [.customDismissAction]
        )

        // Streak Reminder Category
        let startWorkoutAction = UNNotificationAction(
            identifier: NotificationIdentifiers.startWorkoutAction,
            title: String(localized: "notification.action.start_workout"),
            options: [.foreground]
        )

        let snoozeAction = UNNotificationAction(
            identifier: NotificationIdentifiers.snoozeAction,
            title: String(localized: "notification.action.snooze"),
            options: []
        )

        let streakReminderCategory = UNNotificationCategory(
            identifier: NotificationIdentifiers.streakReminderCategory,
            actions: [startWorkoutAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(localized: "notification.streak_reminder.hidden_preview"),
            options: [.customDismissAction]
        )

        // Workout Reminder Category
        let workoutReminderCategory = UNNotificationCategory(
            identifier: NotificationIdentifiers.workoutReminderCategory,
            actions: [startWorkoutAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(localized: "notification.workout_reminder.hidden_preview"),
            options: [.customDismissAction]
        )

        notificationCenter.setNotificationCategories([
            weeklyReviewCategory,
            streakReminderCategory,
            workoutReminderCategory
        ])
    }

    // MARK: - Weekly Review Notifications

    /// Schedule weekly review reminder notifications
    /// - Parameters:
    ///   - day: Day of the week (1 = Sunday, 2 = Monday, etc.)
    ///   - hour: Hour of the day (0-23)
    ///   - minute: Minute of the hour (0-59)
    func scheduleWeeklyReviewNotification(day: Int = 1, hour: Int = 9, minute: Int = 0) async {
        guard isAuthorized else {
            print("NotificationService: Not authorized to schedule notifications")
            return
        }

        // Remove existing weekly review notifications
        await removeNotifications(withPrefix: NotificationIdentifiers.weeklyReviewPrefix)

        // Save preferences
        userDefaults.set(true, forKey: NotificationPreferenceKeys.weeklyReviewEnabled)
        userDefaults.set(day, forKey: NotificationPreferenceKeys.weeklyReviewDay)
        userDefaults.set(hour, forKey: NotificationPreferenceKeys.weeklyReviewHour)
        userDefaults.set(minute, forKey: NotificationPreferenceKeys.weeklyReviewMinute)

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = NotificationContent.weeklyReviewAvailable.title
        content.body = NotificationContent.weeklyReviewAvailable.body
        content.sound = NotificationContent.weeklyReviewAvailable.sound
        content.categoryIdentifier = NotificationContent.weeklyReviewAvailable.categoryIdentifier
        content.badge = NSNumber(value: getBadgeCount() + 1)
        content.userInfo = [
            "type": "weekly_review",
            "deepLink": "\(AppConfiguration.urlScheme)://weekly-review"
        ]

        // Create trigger for specified day and time
        var dateComponents = DateComponents()
        dateComponents.weekday = day
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let identifier = "\(NotificationIdentifiers.weeklyReviewPrefix)\(day)-\(hour)-\(minute)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
            print("NotificationService: Scheduled weekly review notification for day \(day) at \(hour):\(minute)")
        } catch {
            print("NotificationService: Failed to schedule weekly review notification: \(error)")
        }
    }

    /// Cancel weekly review notifications
    func cancelWeeklyReviewNotifications() async {
        await removeNotifications(withPrefix: NotificationIdentifiers.weeklyReviewPrefix)
        userDefaults.set(false, forKey: NotificationPreferenceKeys.weeklyReviewEnabled)
    }

    // MARK: - Streak Reminder Notifications

    /// Schedule streak reminder notifications
    /// - Parameters:
    ///   - hour: Hour of the day (0-23)
    ///   - minute: Minute of the hour (0-59)
    ///   - currentStreak: Current streak count for personalized messaging
    func scheduleStreakReminderNotification(hour: Int = 18, minute: Int = 0, currentStreak: Int = 0) async {
        guard isAuthorized else {
            print("NotificationService: Not authorized to schedule notifications")
            return
        }

        // Remove existing streak reminder notifications
        await removeNotifications(withPrefix: NotificationIdentifiers.streakReminderPrefix)

        // Save preferences
        userDefaults.set(true, forKey: NotificationPreferenceKeys.streakRemindersEnabled)
        userDefaults.set(hour, forKey: NotificationPreferenceKeys.streakReminderHour)
        userDefaults.set(minute, forKey: NotificationPreferenceKeys.streakReminderMinute)

        // Create notification content
        let notificationContent: NotificationContent = currentStreak > 0
            ? .streakAtRisk(currentStreak: currentStreak)
            : .streakReminder(currentStreak: currentStreak)

        let content = UNMutableNotificationContent()
        content.title = notificationContent.title
        content.body = notificationContent.body
        content.sound = notificationContent.sound
        content.categoryIdentifier = notificationContent.categoryIdentifier
        content.badge = NSNumber(value: getBadgeCount() + 1)
        content.userInfo = [
            "type": "streak_reminder",
            "currentStreak": currentStreak,
            "deepLink": "\(AppConfiguration.urlScheme)://workout/start"
        ]

        // Create daily trigger
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let identifier = "\(NotificationIdentifiers.streakReminderPrefix)\(hour)-\(minute)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
            print("NotificationService: Scheduled streak reminder notification at \(hour):\(minute)")
        } catch {
            print("NotificationService: Failed to schedule streak reminder notification: \(error)")
        }
    }

    /// Cancel streak reminder notifications
    func cancelStreakReminderNotifications() async {
        await removeNotifications(withPrefix: NotificationIdentifiers.streakReminderPrefix)
        userDefaults.set(false, forKey: NotificationPreferenceKeys.streakRemindersEnabled)
    }

    /// Update streak reminder with current streak value (for personalized messaging)
    func updateStreakReminder(currentStreak: Int) async {
        guard userDefaults.bool(forKey: NotificationPreferenceKeys.streakRemindersEnabled) else { return }

        let hour = userDefaults.integer(forKey: NotificationPreferenceKeys.streakReminderHour)
        let minute = userDefaults.integer(forKey: NotificationPreferenceKeys.streakReminderMinute)

        await scheduleStreakReminderNotification(hour: hour, minute: minute, currentStreak: currentStreak)
    }

    // MARK: - Workout Reminder Notifications

    /// Schedule workout reminder notifications for specific days
    /// - Parameters:
    ///   - days: Array of weekday integers (1 = Sunday, 2 = Monday, etc.)
    ///   - hour: Hour of the day (0-23)
    ///   - minute: Minute of the hour (0-59)
    func scheduleWorkoutReminderNotifications(days: [Int], hour: Int = 7, minute: Int = 0) async {
        guard isAuthorized else {
            print("NotificationService: Not authorized to schedule notifications")
            return
        }

        // Remove existing workout reminder notifications
        await removeNotifications(withPrefix: NotificationIdentifiers.workoutReminderPrefix)

        // Save preferences
        userDefaults.set(true, forKey: NotificationPreferenceKeys.workoutRemindersEnabled)
        userDefaults.set(hour, forKey: NotificationPreferenceKeys.workoutReminderHour)
        userDefaults.set(minute, forKey: NotificationPreferenceKeys.workoutReminderMinute)
        userDefaults.set(days, forKey: NotificationPreferenceKeys.workoutReminderDays)

        let weekdaySymbols = calendar.weekdaySymbols

        for day in days {
            guard day >= 1 && day <= 7 else { continue }

            let dayName = weekdaySymbols[day - 1]
            let notificationContent = NotificationContent.workoutReminder(dayName: dayName)

            let content = UNMutableNotificationContent()
            content.title = notificationContent.title
            content.body = notificationContent.body
            content.sound = notificationContent.sound
            content.categoryIdentifier = notificationContent.categoryIdentifier
            content.badge = NSNumber(value: getBadgeCount() + 1)
            content.userInfo = [
                "type": "workout_reminder",
                "dayOfWeek": day,
                "deepLink": "\(AppConfiguration.urlScheme)://workout/start"
            ]

            var dateComponents = DateComponents()
            dateComponents.weekday = day
            dateComponents.hour = hour
            dateComponents.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

            let identifier = "\(NotificationIdentifiers.workoutReminderPrefix)\(day)-\(hour)-\(minute)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await notificationCenter.add(request)
                print("NotificationService: Scheduled workout reminder for \(dayName) at \(hour):\(minute)")
            } catch {
                print("NotificationService: Failed to schedule workout reminder for \(dayName): \(error)")
            }
        }
    }

    /// Cancel workout reminder notifications
    func cancelWorkoutReminderNotifications() async {
        await removeNotifications(withPrefix: NotificationIdentifiers.workoutReminderPrefix)
        userDefaults.set(false, forKey: NotificationPreferenceKeys.workoutRemindersEnabled)
    }

    // MARK: - Immediate Notifications

    /// Send an immediate notification (e.g., for badge earned)
    /// - Parameters:
    ///   - content: The notification content type
    ///   - delay: Optional delay in seconds before showing (default: 1)
    func sendImmediateNotification(_ notificationContent: NotificationContent, delay: TimeInterval = 1) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = notificationContent.title
        content.body = notificationContent.body
        content.sound = notificationContent.sound
        content.categoryIdentifier = notificationContent.categoryIdentifier
        content.badge = NSNumber(value: getBadgeCount() + 1)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)

        let identifier = UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
            incrementBadgeCount()
        } catch {
            print("NotificationService: Failed to send immediate notification: \(error)")
        }
    }

    // MARK: - Badge Management

    /// Get the current badge count
    func getBadgeCount() -> Int {
        userDefaults.integer(forKey: NotificationPreferenceKeys.badgeCount)
    }

    /// Set the badge count
    func setBadgeCount(_ count: Int) {
        userDefaults.set(count, forKey: NotificationPreferenceKeys.badgeCount)
        Task { @MainActor in
            if #available(iOS 16.0, *) {
                try? await UNUserNotificationCenter.current().setBadgeCount(count)
            } else {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
    }

    /// Increment the badge count by 1
    func incrementBadgeCount() {
        setBadgeCount(getBadgeCount() + 1)
    }

    /// Clear the badge count
    func clearBadgeCount() {
        setBadgeCount(0)
    }

    // MARK: - Notification Management

    /// Remove all pending notifications with a specific prefix
    private func removeNotifications(withPrefix prefix: String) async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix(prefix) }
            .map(\.identifier)

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    /// Remove all pending and delivered notifications
    func removeAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        clearBadgeCount()
    }

    /// Get all pending notification requests
    func getPendingNotifications() async -> [UNNotificationRequest] {
        await notificationCenter.pendingNotificationRequests()
    }

    /// Get all delivered notifications
    func getDeliveredNotifications() async -> [UNNotification] {
        await notificationCenter.deliveredNotifications()
    }

    // MARK: - Preference Helpers

    /// Check if weekly review notifications are enabled
    var isWeeklyReviewEnabled: Bool {
        userDefaults.bool(forKey: NotificationPreferenceKeys.weeklyReviewEnabled)
    }

    /// Check if streak reminder notifications are enabled
    var isStreakRemindersEnabled: Bool {
        userDefaults.bool(forKey: NotificationPreferenceKeys.streakRemindersEnabled)
    }

    /// Check if workout reminder notifications are enabled
    var isWorkoutRemindersEnabled: Bool {
        userDefaults.bool(forKey: NotificationPreferenceKeys.workoutRemindersEnabled)
    }

    /// Get configured workout reminder days
    var workoutReminderDays: [Int] {
        userDefaults.array(forKey: NotificationPreferenceKeys.workoutReminderDays) as? [Int] ?? []
    }

    // MARK: - Reschedule All Notifications

    /// Reschedule all enabled notifications (useful after app update or settings change)
    func rescheduleAllNotifications() async {
        await updateAuthorizationStatus()

        guard isAuthorized else {
            print("NotificationService: Not authorized, skipping reschedule")
            return
        }

        // Reschedule weekly review if enabled
        if isWeeklyReviewEnabled {
            let day = userDefaults.integer(forKey: NotificationPreferenceKeys.weeklyReviewDay)
            let hour = userDefaults.integer(forKey: NotificationPreferenceKeys.weeklyReviewHour)
            let minute = userDefaults.integer(forKey: NotificationPreferenceKeys.weeklyReviewMinute)
            await scheduleWeeklyReviewNotification(day: day > 0 ? day : 1, hour: hour, minute: minute)
        }

        // Reschedule streak reminders if enabled
        if isStreakRemindersEnabled {
            let hour = userDefaults.integer(forKey: NotificationPreferenceKeys.streakReminderHour)
            let minute = userDefaults.integer(forKey: NotificationPreferenceKeys.streakReminderMinute)
            await scheduleStreakReminderNotification(hour: hour > 0 ? hour : 18, minute: minute)
        }

        // Reschedule workout reminders if enabled
        if isWorkoutRemindersEnabled {
            let days = workoutReminderDays
            let hour = userDefaults.integer(forKey: NotificationPreferenceKeys.workoutReminderHour)
            let minute = userDefaults.integer(forKey: NotificationPreferenceKeys.workoutReminderMinute)
            if !days.isEmpty {
                await scheduleWorkoutReminderNotifications(days: days, hour: hour > 0 ? hour : 7, minute: minute)
            }
        }

        userDefaults.set(Date(), forKey: NotificationPreferenceKeys.lastScheduledDate)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap or action
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        switch actionIdentifier {
        case NotificationIdentifiers.viewReviewAction:
            handleViewReviewAction(userInfo: userInfo)

        case NotificationIdentifiers.startWorkoutAction:
            handleStartWorkoutAction(userInfo: userInfo)

        case NotificationIdentifiers.snoozeAction:
            handleSnoozeAction(userInfo: userInfo)

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            handleNotificationTap(userInfo: userInfo)

        case UNNotificationDismissActionIdentifier:
            // User dismissed the notification
            break

        default:
            break
        }

        // Decrement badge count when notification is interacted with
        let currentBadge = getBadgeCount()
        if currentBadge > 0 {
            setBadgeCount(currentBadge - 1)
        }

        completionHandler()
    }

    /// Handle opening notification settings
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        // Post notification to open settings
        NotificationCenter.default.post(
            name: .openNotificationSettings,
            object: nil,
            userInfo: nil
        )
    }

    // MARK: - Action Handlers

    private func handleViewReviewAction(userInfo: [AnyHashable: Any]) {
        if let deepLink = userInfo["deepLink"] as? String,
           let url = URL(string: deepLink) {
            NotificationCenter.default.post(
                name: .handleDeepLink,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    private func handleStartWorkoutAction(userInfo: [AnyHashable: Any]) {
        if let deepLink = userInfo["deepLink"] as? String,
           let url = URL(string: deepLink) {
            NotificationCenter.default.post(
                name: .handleDeepLink,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    private func handleSnoozeAction(userInfo: [AnyHashable: Any]) {
        // Schedule a reminder for 1 hour from now
        Task {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "notification.snooze.title")
            content.body = String(localized: "notification.snooze.body")
            content.sound = .default
            content.categoryIdentifier = NotificationIdentifiers.workoutReminderCategory

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)

            let request = UNNotificationRequest(
                identifier: "snooze-\(UUID().uuidString)",
                content: content,
                trigger: trigger
            )

            try? await notificationCenter.add(request)
        }
    }

    private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        if let deepLink = userInfo["deepLink"] as? String,
           let url = URL(string: deepLink) {
            NotificationCenter.default.post(
                name: .handleDeepLink,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openNotificationSettings = Notification.Name("openNotificationSettings")
    static let handleDeepLink = Notification.Name("handleDeepLink")
}

// MARK: - Default Schedule Configuration

extension NotificationService {

    /// Configure default notification schedule for new users
    func configureDefaultSchedule() async {
        // Weekly review on Sunday at 9 AM
        await scheduleWeeklyReviewNotification(day: 1, hour: 9, minute: 0)

        // Streak reminder at 6 PM daily
        await scheduleStreakReminderNotification(hour: 18, minute: 0)

        // Workout reminders on weekdays at 7 AM
        await scheduleWorkoutReminderNotifications(days: [2, 3, 4, 5, 6], hour: 7, minute: 0)
    }

    /// Quick setup for common configurations
    enum QuickSetup {
        case morningPerson    // Early reminders (6-7 AM)
        case eveningPerson    // Evening reminders (6-7 PM)
        case weekendWarrior   // Saturday/Sunday focus
        case everyday         // Daily reminders
        case custom([Int], Int, Int)  // Custom days and time

        var days: [Int] {
            switch self {
            case .morningPerson, .eveningPerson:
                return [2, 3, 4, 5, 6]  // Monday-Friday
            case .weekendWarrior:
                return [1, 7]  // Sunday, Saturday
            case .everyday:
                return [1, 2, 3, 4, 5, 6, 7]  // All days
            case .custom(let days, _, _):
                return days
            }
        }

        var hour: Int {
            switch self {
            case .morningPerson:
                return 6
            case .eveningPerson:
                return 18
            case .weekendWarrior:
                return 9
            case .everyday:
                return 7
            case .custom(_, let hour, _):
                return hour
            }
        }

        var minute: Int {
            switch self {
            case .custom(_, _, let minute):
                return minute
            default:
                return 0
            }
        }
    }

    /// Apply a quick setup configuration
    func applyQuickSetup(_ setup: QuickSetup) async {
        await scheduleWorkoutReminderNotifications(
            days: setup.days,
            hour: setup.hour,
            minute: setup.minute
        )
    }
}
