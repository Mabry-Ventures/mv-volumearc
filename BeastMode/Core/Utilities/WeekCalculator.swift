import Foundation

/// Utility for week-based calculations
struct WeekCalculator {
    let calendar: Calendar
    let weekStartsOn: Weekday

    init(calendar: Calendar = .current, weekStartsOn: Weekday = .monday) {
        var cal = calendar
        cal.firstWeekday = weekStartsOn.rawValue
        self.calendar = cal
        self.weekStartsOn = weekStartsOn
    }

    /// Get the ISO week ID for a date (e.g., "2025-W28")
    func weekId(for date: Date) -> String {
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    /// Get the start date of a week
    func startOfWeek(containing date: Date) -> Date {
        let currentWeekday = calendar.component(.weekday, from: date)
        let daysFromStart = (currentWeekday - weekStartsOn.rawValue + 7) % 7
        return calendar.date(byAdding: .day, value: -daysFromStart, to: calendar.startOfDay(for: date))!
    }

    /// Get the end date of a week
    func endOfWeek(containing date: Date) -> Date {
        let start = startOfWeek(containing: date)
        return calendar.date(byAdding: .day, value: 6, to: start)!
    }

    /// Get all dates in a week containing the given date
    func datesInWeek(containing date: Date) -> [Date] {
        let start = startOfWeek(containing: date)
        return (0..<7).map { offset in
            calendar.date(byAdding: .day, value: offset, to: start)!
        }
    }

    /// Get the weekday for a given date
    func weekday(for date: Date) -> Weekday {
        let weekdayNumber = calendar.component(.weekday, from: date)
        return Weekday(rawValue: weekdayNumber) ?? .monday
    }

    /// Get the date for a specific weekday in a given week
    func date(for weekday: Weekday, in weekContaining: Date) -> Date {
        let start = startOfWeek(containing: weekContaining)
        let daysToAdd = (weekday.rawValue - weekStartsOn.rawValue + 7) % 7
        return calendar.date(byAdding: .day, value: daysToAdd, to: start)!
    }

    /// Check if two dates are in the same week
    func areInSameWeek(_ date1: Date, _ date2: Date) -> Bool {
        weekId(for: date1) == weekId(for: date2)
    }

    /// Get the number of weeks between two dates
    func weeksBetween(_ startDate: Date, _ endDate: Date) -> Int {
        let components = calendar.dateComponents([.weekOfYear], from: startDate, to: endDate)
        return components.weekOfYear ?? 0
    }

    /// Get week information for display
    func weekInfo(for date: Date) -> WeekInfo {
        let start = startOfWeek(containing: date)
        let end = endOfWeek(containing: date)
        let weekNumber = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)

        return WeekInfo(
            weekId: weekId(for: date),
            weekNumber: weekNumber,
            year: year,
            startDate: start,
            endDate: end,
            dates: datesInWeek(containing: date)
        )
    }
}

/// Information about a specific week
struct WeekInfo {
    let weekId: String
    let weekNumber: Int
    let year: Int
    let startDate: Date
    let endDate: Date
    let dates: [Date]

    var displayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)
        return "Week \(weekNumber): \(startStr) - \(endStr)"
    }

    var shortDisplayString: String {
        "Week \(weekNumber)"
    }
}
