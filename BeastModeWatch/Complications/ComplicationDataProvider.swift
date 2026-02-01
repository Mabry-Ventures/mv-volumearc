// ComplicationDataProvider.swift
// BeastModeWatch
// Data provider for Apple Watch complications

import Foundation
import WidgetKit
import SwiftUI

// MARK: - Complication Data

/// Data shared between iPhone and Watch via App Groups
struct ComplicationData: Codable {
    let currentStreak: Int
    let todayWorkout: TodayWorkoutData?
    let weeklyProgress: WeeklyProgressData
    let lastUpdated: Date

    static let empty = ComplicationData(
        currentStreak: 0,
        todayWorkout: nil,
        weeklyProgress: WeeklyProgressData(completed: 0, target: 4),
        lastUpdated: .now
    )
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

    private let appGroupIdentifier = "group.com.beastmode.app"
    private let dataKey = "complicationData"

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private init() {}

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
    func updateStreak(_ streak: Int) {
        var data = loadData()
        data = ComplicationData(
            currentStreak: streak,
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
