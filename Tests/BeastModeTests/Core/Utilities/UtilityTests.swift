// UtilityTests.swift
// BeastModeTests
// Unit tests for utility functions using Swift Testing

import Testing
import Foundation
@testable import BeastMode

// MARK: - Week Calculator Tests

@Suite("Week Calculator")
struct WeekCalculatorTests {

    @Test("Generates correct ISO week ID",
          arguments: [
            (year: 2025, month: 7, day: 14, expected: "2025-W29"),
            (year: 2025, month: 1, day: 1, expected: "2025-W01"),
            (year: 2025, month: 12, day: 31, expected: "2026-W01"),
            (year: 2024, month: 12, day: 30, expected: "2025-W01")
          ])
    func generatesCorrectWeekId(
        year: Int,
        month: Int,
        day: Int,
        expected: String
    ) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2  // Monday
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            Issue.record("Could not create date")
            return
        }

        let weekId = WeekCalculator.weekId(for: date)

        #expect(weekId == expected)
    }

    @Test("Current week ID matches today")
    func currentWeekMatchesToday() {
        let currentWeekId = WeekCalculator.currentWeekId()
        let todayWeekId = WeekCalculator.weekId(for: .now)

        #expect(currentWeekId == todayWeekId)
    }

    @Test("Week ID format is valid")
    func weekIdFormatIsValid() {
        let weekId = WeekCalculator.currentWeekId()

        // Should match pattern YYYY-Www
        let regex = try! Regex("^\\d{4}-W(0[1-9]|[1-4]\\d|5[0-3])$")
        #expect(weekId.contains(regex))
    }

    @Test("Handles year boundaries correctly")
    func handlesYearBoundaries() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2

        // Test various year-end dates
        let dec28 = calendar.date(from: DateComponents(year: 2025, month: 12, day: 28))!
        let dec31 = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31))!
        let jan1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        let dec28Week = WeekCalculator.weekId(for: dec28)
        let dec31Week = WeekCalculator.weekId(for: dec31)
        let jan1Week = WeekCalculator.weekId(for: jan1)

        // Dec 31, 2025 and Jan 1, 2026 should be in week 1 of 2026
        #expect(dec31Week == jan1Week)
        // Dec 28 should still be in 2025
        #expect(dec28Week.hasPrefix("2025-"))
    }

    @Test("Same week dates have same week ID")
    func sameWeekSameId() {
        let calendar = Calendar.current
        let monday = calendar.date(from: DateComponents(year: 2025, month: 7, day: 14))!
        let wednesday = calendar.date(from: DateComponents(year: 2025, month: 7, day: 16))!
        let sunday = calendar.date(from: DateComponents(year: 2025, month: 7, day: 20))!

        let mondayWeek = WeekCalculator.weekId(for: monday)
        let wednesdayWeek = WeekCalculator.weekId(for: wednesday)
        let sundayWeek = WeekCalculator.weekId(for: sunday)

        #expect(mondayWeek == wednesdayWeek)
        #expect(wednesdayWeek == sundayWeek)
    }
}

// MARK: - Progressive Overload Calculator Tests

@Suite("Progressive Overload Calculator")
struct ProgressiveOverloadCalculatorTests {

    @Test("Suggests 5% increase when hitting top of rep range")
    func suggests5PercentIncrease() {
        let suggestion = ProgressiveOverloadCalculator.suggestNextWeight(
            currentWeight: 200,
            currentReps: 12,
            targetRepRange: 8...12
        )

        // 5% of 200 = 10, so suggested weight should be ~210
        #expect(suggestion.weight.isApproximatelyEqual(to: 210, tolerance: 5))
    }

    @Test("Suggests same weight when in middle of rep range")
    func suggestsSameWeightMidRange() {
        let suggestion = ProgressiveOverloadCalculator.suggestNextWeight(
            currentWeight: 185,
            currentReps: 10,
            targetRepRange: 8...12
        )

        #expect(suggestion.weight == 185)
        #expect(suggestion.targetReps == 11)  // Aim for +1 rep
    }

    @Test("Suggests deload when struggling below range")
    func suggestsDeloadBelowRange() {
        let suggestion = ProgressiveOverloadCalculator.suggestNextWeight(
            currentWeight: 225,
            currentReps: 4,  // Below 8-12 range
            targetRepRange: 8...12
        )

        // Should suggest ~10% decrease
        #expect(suggestion.weight < 225)
        #expect(suggestion.weight >= 200)
        #expect(suggestion.isDeload == true)
    }

    @Test("Rounds to nearest 2.5 lbs")
    func roundsToNearest2_5() {
        let suggestion = ProgressiveOverloadCalculator.suggestNextWeight(
            currentWeight: 187,  // Odd number
            currentReps: 12,
            targetRepRange: 8...12
        )

        let remainder = suggestion.weight.truncatingRemainder(dividingBy: 2.5)
        #expect(remainder.isApproximatelyEqual(to: 0, tolerance: 0.01))
    }

    @Test("Never suggests negative weight")
    func neverNegativeWeight() {
        let suggestion = ProgressiveOverloadCalculator.suggestNextWeight(
            currentWeight: 10,
            currentReps: 1,
            targetRepRange: 8...12
        )

        #expect(suggestion.weight > 0)
    }

    @Test("Handles bodyweight exercises (0 weight)")
    func handlesBodyweightExercises() {
        let suggestion = ProgressiveOverloadCalculator.suggestNextWeight(
            currentWeight: 0,
            currentReps: 15,
            targetRepRange: 10...15
        )

        // Should suggest adding reps or staying at bodyweight
        #expect(suggestion.weight >= 0)
    }

    @Test("Suggestions for various scenarios",
          arguments: [
            (weight: 100.0, reps: 8, range: 8...12, shouldIncrease: false),
            (weight: 100.0, reps: 12, range: 8...12, shouldIncrease: true),
            (weight: 100.0, reps: 6, range: 8...12, shouldIncrease: false),
            (weight: 200.0, reps: 5, range: 3...5, shouldIncrease: true)
          ])
    func variousScenarios(
        weight: Double,
        reps: Int,
        range: ClosedRange<Int>,
        shouldIncrease: Bool
    ) {
        let suggestion = ProgressiveOverloadCalculator.suggestNextWeight(
            currentWeight: weight,
            currentReps: reps,
            targetRepRange: range
        )

        if shouldIncrease {
            #expect(suggestion.weight > weight)
        } else {
            #expect(suggestion.weight <= weight)
        }
    }
}

// MARK: - E1RM Calculator Tests

@Suite("E1RM Calculator")
struct E1RMCalculatorTests {

    @Test("Brzycki formula calculation",
          arguments: [
            (weight: 200.0, reps: 1, expected: 200.0),
            (weight: 200.0, reps: 5, expected: 225.0),
            (weight: 200.0, reps: 8, expected: 248.28),
            (weight: 200.0, reps: 10, expected: 266.67),
            (weight: 200.0, reps: 12, expected: 288.0)
          ])
    func brzyckiFormula(weight: Double, reps: Int, expected: Double) {
        let e1rm = E1RMCalculator.calculate(weight: weight, reps: reps)

        #expect(e1rm.isApproximatelyEqual(to: expected, tolerance: 1.0))
    }

    @Test("Returns weight for single rep")
    func singleRepReturnsWeight() {
        let e1rm = E1RMCalculator.calculate(weight: 315, reps: 1)

        #expect(e1rm == 315)
    }

    @Test("Caps calculation at 12 reps")
    func capsAt12Reps() {
        let e1rm12 = E1RMCalculator.calculate(weight: 135, reps: 12)
        let e1rm15 = E1RMCalculator.calculate(weight: 135, reps: 15)
        let e1rm20 = E1RMCalculator.calculate(weight: 135, reps: 20)

        // Beyond 12 reps should return raw weight (unreliable)
        #expect(e1rm15 == 135)
        #expect(e1rm20 == 135)
        #expect(e1rm12 > 135)  // 12 reps should still calculate
    }

    @Test("Handles zero weight")
    func handlesZeroWeight() {
        let e1rm = E1RMCalculator.calculate(weight: 0, reps: 10)

        #expect(e1rm == 0)
    }

    @Test("Handles zero reps")
    func handlesZeroReps() {
        let e1rm = E1RMCalculator.calculate(weight: 100, reps: 0)

        #expect(e1rm == 0)
    }
}

// MARK: - Date Utilities Tests

@Suite("Date Utilities")
struct DateUtilitiesTests {

    @Test("Start of day returns midnight")
    func startOfDayReturnsMidnight() {
        let date = Date.now
        let startOfDay = Calendar.current.startOfDay(for: date)

        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: startOfDay)

        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test("Is same day comparison")
    func isSameDayComparison() {
        let calendar = Calendar.current

        let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: .now)!
        let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: .now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!

        #expect(calendar.isDate(morning, inSameDayAs: evening))
        #expect(!calendar.isDate(morning, inSameDayAs: tomorrow))
    }

    @Test("Days between dates")
    func daysBetweenDates() {
        let calendar = Calendar.current
        let today = Date.now
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!

        let days = calendar.dateComponents([.day], from: today, to: nextWeek).day!

        #expect(days == 7)
    }
}

// MARK: - Supporting Types

/// Week calculator utility
enum WeekCalculator {
    static func weekId(for date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2  // Monday

        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)

        return String(format: "%04d-W%02d", year, week)
    }

    static func currentWeekId() -> String {
        weekId(for: .now)
    }
}

/// Progressive overload calculator
enum ProgressiveOverloadCalculator {
    struct Suggestion {
        let weight: Double
        let targetReps: Int
        let isDeload: Bool
    }

    static func suggestNextWeight(
        currentWeight: Double,
        currentReps: Int,
        targetRepRange: ClosedRange<Int>
    ) -> Suggestion {
        // At top of range: increase weight by 5%
        if currentReps >= targetRepRange.upperBound {
            let newWeight = roundToNearest2_5(currentWeight * 1.05)
            return Suggestion(
                weight: newWeight,
                targetReps: targetRepRange.lowerBound,
                isDeload: false
            )
        }

        // Below range: deload by 10%
        if currentReps < targetRepRange.lowerBound {
            let newWeight = max(2.5, roundToNearest2_5(currentWeight * 0.9))
            return Suggestion(
                weight: newWeight,
                targetReps: targetRepRange.lowerBound,
                isDeload: true
            )
        }

        // In range: aim for one more rep
        return Suggestion(
            weight: currentWeight,
            targetReps: min(currentReps + 1, targetRepRange.upperBound),
            isDeload: false
        )
    }

    private static func roundToNearest2_5(_ value: Double) -> Double {
        (value / 2.5).rounded() * 2.5
    }
}

/// E1RM calculator using Brzycki formula
enum E1RMCalculator {
    static func calculate(weight: Double, reps: Int) -> Double {
        guard weight > 0 && reps > 0 else { return 0 }
        guard reps <= 12 else { return weight }  // Unreliable above 12 reps
        if reps == 1 { return weight }

        // Brzycki formula: weight × (36 / (37 - reps))
        return weight * (36.0 / (37.0 - Double(reps)))
    }
}
