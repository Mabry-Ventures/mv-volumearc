// ComplicationDataProvider.swift
// BeastModeWatch
// Data provider for Apple Watch complications

import Foundation
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Configuration Models

/// Display mode for streak complication
enum StreakDisplayMode: String, Codable, CaseIterable, AppEnum {
    case currentStreak = "current"
    case longestStreak = "longest"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Streak Display Mode")
    }

    static var caseDisplayRepresentations: [StreakDisplayMode: DisplayRepresentation] {
        [
            .currentStreak: DisplayRepresentation(title: "Current Streak", subtitle: "Show your active streak"),
            .longestStreak: DisplayRepresentation(title: "Longest Streak", subtitle: "Show your all-time best")
        ]
    }

    var displayName: String {
        switch self {
        case .currentStreak: return "Current"
        case .longestStreak: return "Longest"
        }
    }
}

/// Display mode for today's workout complication
enum WorkoutDisplayMode: String, Codable, CaseIterable, AppEnum {
    case exerciseCount = "count"
    case workoutName = "name"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Workout Display Mode")
    }

    static var caseDisplayRepresentations: [WorkoutDisplayMode: DisplayRepresentation] {
        [
            .exerciseCount: DisplayRepresentation(title: "Exercise Count", subtitle: "Show number of exercises"),
            .workoutName: DisplayRepresentation(title: "Workout Name", subtitle: "Show the workout day name")
        ]
    }

    var displayName: String {
        switch self {
        case .exerciseCount: return "Exercises"
        case .workoutName: return "Name"
        }
    }
}

/// Weekly goal options for the progress widget
enum WeeklyGoalOption: Int, Codable, CaseIterable, AppEnum {
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Weekly Goal")
    }

    static var caseDisplayRepresentations: [WeeklyGoalOption: DisplayRepresentation] {
        [
            .three: DisplayRepresentation(title: "3 workouts/week"),
            .four: DisplayRepresentation(title: "4 workouts/week"),
            .five: DisplayRepresentation(title: "5 workouts/week"),
            .six: DisplayRepresentation(title: "6 workouts/week"),
            .seven: DisplayRepresentation(title: "7 workouts/week")
        ]
    }

    var displayName: String {
        "\(rawValue)/week"
    }
}

/// Configuration model for all widget preferences
struct WidgetConfigurationModel: Codable {
    var streakDisplayMode: StreakDisplayMode
    var workoutDisplayMode: WorkoutDisplayMode
    var weeklyGoal: WeeklyGoalOption

    static let `default` = WidgetConfigurationModel(
        streakDisplayMode: .currentStreak,
        workoutDisplayMode: .exerciseCount,
        weeklyGoal: .four
    )
}

// MARK: - Complication Data

/// Data shared between iPhone and Watch via App Groups
struct ComplicationData: Codable {
    let currentStreak: Int
    let longestStreak: Int
    let todayWorkout: TodayWorkoutData?
    let weeklyProgress: WeeklyProgressData
    let lastUpdated: Date

    static let empty = ComplicationData(
        currentStreak: 0,
        longestStreak: 0,
        todayWorkout: nil,
        weeklyProgress: WeeklyProgressData(completed: 0, target: 4),
        lastUpdated: .now
    )

    /// Returns the appropriate streak value based on display mode
    func streak(for mode: StreakDisplayMode) -> Int {
        switch mode {
        case .currentStreak: return currentStreak
        case .longestStreak: return longestStreak
        }
    }
}

struct TodayWorkoutData: Codable {
    let dayName: String
    let exerciseCount: Int
    let isRestDay: Bool
    let isCompleted: Bool
}

struct WeeklyProgressData: Codable {
    let completed: Int
    let target: Int

    var progressPercentage: Double {
        guard target > 0 else { return 0 }
        return Double(completed) / Double(target)
    }
}

// MARK: - Complication Data Manager

/// Manages complication data shared via App Groups
class ComplicationDataManager {
    static let shared = ComplicationDataManager()

    private let dataKey = WatchConfiguration.complicationDataKey
    private let configurationKey = "widgetConfiguration"

    private var defaults: UserDefaults? {
        WatchConfiguration.sharedUserDefaults
    }

    private init() {}

    // MARK: - Widget Configuration

    /// Save widget configuration preferences
    func saveConfiguration(_ config: WidgetConfigurationModel) {
        guard let defaults else { return }

        do {
            let encoded = try JSONEncoder().encode(config)
            defaults.set(encoded, forKey: configurationKey)

            // Request complication update when configuration changes
            #if os(watchOS)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            print("Failed to save widget configuration: \(error)")
        }
    }

    /// Load widget configuration preferences
    func loadConfiguration() -> WidgetConfigurationModel {
        guard let defaults,
              let data = defaults.data(forKey: configurationKey) else {
            return .default
        }

        do {
            return try JSONDecoder().decode(WidgetConfigurationModel.self, from: data)
        } catch {
            print("Failed to load widget configuration: \(error)")
            return .default
        }
    }

    /// Update streak display mode
    func updateStreakDisplayMode(_ mode: StreakDisplayMode) {
        var config = loadConfiguration()
        config.streakDisplayMode = mode
        saveConfiguration(config)
    }

    /// Update workout display mode
    func updateWorkoutDisplayMode(_ mode: WorkoutDisplayMode) {
        var config = loadConfiguration()
        config.workoutDisplayMode = mode
        saveConfiguration(config)
    }

    /// Update weekly goal
    func updateWeeklyGoal(_ goal: WeeklyGoalOption) {
        var config = loadConfiguration()
        config.weeklyGoal = goal
        saveConfiguration(config)
    }

    /// Save complication data (called from iPhone app)
    func saveData(_ data: ComplicationData) {
        guard let defaults else { return }

        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: dataKey)

            // Request complication update
            #if os(watchOS)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            print("Failed to save complication data: \(error)")
        }
    }

    /// Load complication data (called from Watch)
    func loadData() -> ComplicationData {
        guard let defaults,
              let data = defaults.data(forKey: dataKey) else {
            return .empty
        }

        do {
            return try JSONDecoder().decode(ComplicationData.self, from: data)
        } catch {
            print("Failed to load complication data: \(error)")
            return .empty
        }
    }

    /// Update just the streak (convenience method)
    func updateStreak(current: Int, longest: Int) {
        var data = loadData()
        data = ComplicationData(
            currentStreak: current,
            longestStreak: longest,
            todayWorkout: data.todayWorkout,
            weeklyProgress: data.weeklyProgress,
            lastUpdated: .now
        )
        saveData(data)
    }

    /// Update today's workout info
    func updateTodayWorkout(_ workout: TodayWorkoutData?) {
        var data = loadData()
        data = ComplicationData(
            currentStreak: data.currentStreak,
            longestStreak: data.longestStreak,
            todayWorkout: workout,
            weeklyProgress: data.weeklyProgress,
            lastUpdated: .now
        )
        saveData(data)
    }

    /// Update weekly progress
    func updateWeeklyProgress(completed: Int, target: Int) {
        var data = loadData()
        data = ComplicationData(
            currentStreak: data.currentStreak,
            longestStreak: data.longestStreak,
            todayWorkout: data.todayWorkout,
            weeklyProgress: WeeklyProgressData(completed: completed, target: target),
            lastUpdated: .now
        )
        saveData(data)
    }
}

// MARK: - Timeline Entry

struct BeastModeTimelineEntry: TimelineEntry {
    let date: Date
    let data: ComplicationData
}

// MARK: - Timeline Provider

struct BeastModeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BeastModeTimelineEntry {
        BeastModeTimelineEntry(
            date: .now,
            data: ComplicationData(
                currentStreak: 7,
                longestStreak: 14,
                todayWorkout: TodayWorkoutData(
                    dayName: "Push Day",
                    exerciseCount: 6,
                    isRestDay: false,
                    isCompleted: false
                ),
                weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
                lastUpdated: .now
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BeastModeTimelineEntry) -> Void) {
        let data = ComplicationDataManager.shared.loadData()
        let entry = BeastModeTimelineEntry(date: .now, data: data)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BeastModeTimelineEntry>) -> Void) {
        let data = ComplicationDataManager.shared.loadData()
        let entry = BeastModeTimelineEntry(date: .now, data: data)

        // Update every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }
}

// MARK: - Configurable Timeline Entries

/// Timeline entry for configurable streak widget
struct StreakTimelineEntry: TimelineEntry {
    let date: Date
    let data: ComplicationData
    let configuration: StreakWidgetConfigurationIntent
}

/// Timeline entry for configurable workout widget
struct WorkoutTimelineEntry: TimelineEntry {
    let date: Date
    let data: ComplicationData
    let configuration: WorkoutWidgetConfigurationIntent
}

/// Timeline entry for configurable weekly progress widget
struct WeeklyProgressTimelineEntry: TimelineEntry {
    let date: Date
    let data: ComplicationData
    let configuration: WeeklyProgressWidgetConfigurationIntent
}

// MARK: - Widget Configuration Intents

/// Configuration intent for Streak Widget
struct StreakWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Streak Configuration"
    static var description = IntentDescription("Configure how the streak is displayed")

    @Parameter(title: "Display Mode", default: .currentStreak)
    var displayMode: StreakDisplayMode

    init() {}

    init(displayMode: StreakDisplayMode) {
        self.displayMode = displayMode
    }
}

/// Configuration intent for Workout Widget
struct WorkoutWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Workout Configuration"
    static var description = IntentDescription("Configure how today's workout is displayed")

    @Parameter(title: "Display Mode", default: .exerciseCount)
    var displayMode: WorkoutDisplayMode

    init() {}

    init(displayMode: WorkoutDisplayMode) {
        self.displayMode = displayMode
    }
}

/// Configuration intent for Weekly Progress Widget
struct WeeklyProgressWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Weekly Goal Configuration"
    static var description = IntentDescription("Set your weekly workout goal")

    @Parameter(title: "Weekly Goal", default: .four)
    var weeklyGoal: WeeklyGoalOption

    init() {}

    init(weeklyGoal: WeeklyGoalOption) {
        self.weeklyGoal = weeklyGoal
    }
}

// MARK: - Configurable Timeline Providers

/// Timeline provider for configurable streak widget
struct StreakTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = StreakTimelineEntry
    typealias Intent = StreakWidgetConfigurationIntent

    func placeholder(in context: Context) -> StreakTimelineEntry {
        StreakTimelineEntry(
            date: .now,
            data: ComplicationData(
                currentStreak: 7,
                longestStreak: 14,
                todayWorkout: nil,
                weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
                lastUpdated: .now
            ),
            configuration: StreakWidgetConfigurationIntent()
        )
    }

    func snapshot(for configuration: StreakWidgetConfigurationIntent, in context: Context) async -> StreakTimelineEntry {
        let data = ComplicationDataManager.shared.loadData()
        return StreakTimelineEntry(date: .now, data: data, configuration: configuration)
    }

    func timeline(for configuration: StreakWidgetConfigurationIntent, in context: Context) async -> Timeline<StreakTimelineEntry> {
        let data = ComplicationDataManager.shared.loadData()
        let entry = StreakTimelineEntry(date: .now, data: data, configuration: configuration)

        // Save configuration preference
        ComplicationDataManager.shared.updateStreakDisplayMode(configuration.displayMode)

        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

/// Timeline provider for configurable workout widget
struct WorkoutTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = WorkoutTimelineEntry
    typealias Intent = WorkoutWidgetConfigurationIntent

    func placeholder(in context: Context) -> WorkoutTimelineEntry {
        WorkoutTimelineEntry(
            date: .now,
            data: ComplicationData(
                currentStreak: 7,
                longestStreak: 14,
                todayWorkout: TodayWorkoutData(
                    dayName: "Push Day",
                    exerciseCount: 6,
                    isRestDay: false,
                    isCompleted: false
                ),
                weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
                lastUpdated: .now
            ),
            configuration: WorkoutWidgetConfigurationIntent()
        )
    }

    func snapshot(for configuration: WorkoutWidgetConfigurationIntent, in context: Context) async -> WorkoutTimelineEntry {
        let data = ComplicationDataManager.shared.loadData()
        return WorkoutTimelineEntry(date: .now, data: data, configuration: configuration)
    }

    func timeline(for configuration: WorkoutWidgetConfigurationIntent, in context: Context) async -> Timeline<WorkoutTimelineEntry> {
        let data = ComplicationDataManager.shared.loadData()
        let entry = WorkoutTimelineEntry(date: .now, data: data, configuration: configuration)

        // Save configuration preference
        ComplicationDataManager.shared.updateWorkoutDisplayMode(configuration.displayMode)

        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

/// Timeline provider for configurable weekly progress widget
struct WeeklyProgressTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = WeeklyProgressTimelineEntry
    typealias Intent = WeeklyProgressWidgetConfigurationIntent

    func placeholder(in context: Context) -> WeeklyProgressTimelineEntry {
        WeeklyProgressTimelineEntry(
            date: .now,
            data: ComplicationData(
                currentStreak: 7,
                longestStreak: 14,
                todayWorkout: nil,
                weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
                lastUpdated: .now
            ),
            configuration: WeeklyProgressWidgetConfigurationIntent()
        )
    }

    func snapshot(for configuration: WeeklyProgressWidgetConfigurationIntent, in context: Context) async -> WeeklyProgressTimelineEntry {
        let data = ComplicationDataManager.shared.loadData()
        return WeeklyProgressTimelineEntry(date: .now, data: data, configuration: configuration)
    }

    func timeline(for configuration: WeeklyProgressWidgetConfigurationIntent, in context: Context) async -> Timeline<WeeklyProgressTimelineEntry> {
        let data = ComplicationDataManager.shared.loadData()
        let entry = WeeklyProgressTimelineEntry(date: .now, data: data, configuration: configuration)

        // Save configuration preference
        ComplicationDataManager.shared.updateWeeklyGoal(configuration.weeklyGoal)

        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}
