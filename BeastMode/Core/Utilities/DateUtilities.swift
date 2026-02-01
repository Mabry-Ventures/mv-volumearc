import Foundation

/// Date-related utility functions
enum DateUtilities {
    /// Get the start of today
    static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Get the end of today
    static var endOfToday: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!.addingTimeInterval(-1)
    }

    /// Check if a date is today
    static func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Check if a date is yesterday
    static func isYesterday(_ date: Date) -> Bool {
        Calendar.current.isDateInYesterday(date)
    }

    /// Check if a date is in the current week
    static func isThisWeek(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }

    /// Get relative date description
    static func relativeDescription(for date: Date) -> String {
        if isToday(date) {
            return "Today"
        } else if isYesterday(date) {
            return "Yesterday"
        } else if isThisWeek(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

    /// Get the date for a specific weekday in the current week
    static func date(for weekday: Weekday, in weekOf: Date = Date()) -> Date {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: weekOf)
        let daysToAdd = weekday.rawValue - currentWeekday
        return calendar.date(byAdding: .day, value: daysToAdd, to: calendar.startOfDay(for: weekOf))!
    }

    /// Format a time interval as MM:SS
    static func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Format a time interval as HH:MM:SS
    static func formatLongDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Get dates for the current week
    static func currentWeekDates(startingOn: Weekday = .monday) -> [Date] {
        let calendar = Calendar.current
        let today = Date()

        // Find the start of the week
        var startOfWeek = calendar.startOfDay(for: today)
        let currentWeekday = calendar.component(.weekday, from: today)
        let daysFromStart = (currentWeekday - startingOn.rawValue + 7) % 7
        startOfWeek = calendar.date(byAdding: .day, value: -daysFromStart, to: startOfWeek)!

        // Generate all 7 days
        return (0..<7).map { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek)!
        }
    }
}

// MARK: - Date Extensions

extension Date {
    /// Get the weekday for this date
    var weekday: Weekday {
        let weekdayNumber = Calendar.current.component(.weekday, from: self)
        return Weekday(rawValue: weekdayNumber) ?? .monday
    }

    /// Check if this date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Get the start of this day
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// Get the ISO week ID
    var weekId: String {
        DailyLog.calculateWeekId(from: self)
    }

    /// Format as short date
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: self)
    }

    /// Format as medium date
    var mediumDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: self)
    }
}
