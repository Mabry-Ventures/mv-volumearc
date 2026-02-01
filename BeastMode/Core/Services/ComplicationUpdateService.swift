// ComplicationUpdateService.swift
// BeastMode
// Service for updating Apple Watch complications from the iPhone app

import Foundation
import SwiftData
import WidgetKit

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Service for updating Apple Watch complications
actor ComplicationUpdateService {
    private let modelContext: ModelContext
    private let dataManager = ComplicationDataManager.shared

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// Update all complication data based on current app state
    func updateAllComplications(for userId: UUID) async throws {
        let streak = try await fetchCurrentStreak(for: userId)
        let todayWorkout = try await fetchTodayWorkout(for: userId)
        let weeklyProgress = try await fetchWeeklyProgress(for: userId)

        let data = ComplicationData(
            currentStreak: streak,
            todayWorkout: todayWorkout,
            weeklyProgress: weeklyProgress,
            lastUpdated: .now
        )

        dataManager.saveData(data)

        // Trigger widget reload
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Update just the streak complication
    func updateStreakComplication(_ streak: Int) {
        dataManager.updateStreak(streak)
        WidgetCenter.shared.reloadTimelines(ofKind: "Streak")
    }

    /// Update today's workout complication
    func updateTodayWorkoutComplication(for userId: UUID) async throws {
        let todayWorkout = try await fetchTodayWorkout(for: userId)
        dataManager.updateTodayWorkout(todayWorkout)
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayWorkout")
    }

    /// Update weekly progress complication
    func updateWeeklyProgressComplication(for userId: UUID) async throws {
        let progress = try await fetchWeeklyProgress(for: userId)
        dataManager.updateWeeklyProgress(completed: progress.completed, target: progress.target)
        WidgetCenter.shared.reloadTimelines(ofKind: "WeeklyProgress")
    }

    /// Mark today's workout as completed
    func markTodayCompleted() async {
        var data = dataManager.loadData()
        if var workout = data.todayWorkout {
            workout = TodayWorkoutData(
                dayName: workout.dayName,
                exerciseCount: workout.exerciseCount,
                isRestDay: workout.isRestDay,
                isCompleted: true
            )
            data = ComplicationData(
                currentStreak: data.currentStreak,
                todayWorkout: workout,
                weeklyProgress: WeeklyProgressData(
                    completed: data.weeklyProgress.completed + 1,
                    target: data.weeklyProgress.target
                ),
                lastUpdated: .now
            )
            dataManager.saveData(data)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Data Fetching

    private func fetchCurrentStreak(for userId: UUID) async throws -> Int {
        let descriptor = FetchDescriptor<UserStreak>(
            predicate: #Predicate { $0.userId == userId }
        )

        let streaks = try modelContext.fetch(descriptor)
        return streaks.first?.currentStreak ?? 0
    }

    private func fetchTodayWorkout(for userId: UUID) async throws -> TodayWorkoutData? {
        // Find active plan
        let planDescriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.userId == userId && $0.isActive }
        )

        guard let activePlan = try modelContext.fetch(planDescriptor).first else {
            return nil
        }

        // Get today's weekday
        let weekday = Calendar.current.component(.weekday, from: .now)

        // Find today's day in the plan
        guard let today = activePlan.day(for: weekday) else {
            return nil
        }

        // Check if completed today
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.userId == userId && $0.completedAt != nil }
        )

        let todayWorkouts = try modelContext.fetch(workoutDescriptor).filter {
            guard let completed = $0.completedAt else { return false }
            return completed >= startOfDay
        }

        let isCompleted = !todayWorkouts.isEmpty

        return TodayWorkoutData(
            dayName: today.name,
            exerciseCount: today.exercises.count,
            isRestDay: today.isRestDay,
            isCompleted: isCompleted
        )
    }

    private func fetchWeeklyProgress(for userId: UUID) async throws -> WeeklyProgressData {
        // Get start of current week (Sunday)
        let calendar = Calendar.current
        let now = Date.now
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now

        // Count completed workouts this week
        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.userId == userId && $0.completedAt != nil }
        )

        let allWorkouts = try modelContext.fetch(workoutDescriptor)
        let completedThisWeek = allWorkouts.filter { workout in
            guard let completed = workout.completedAt else { return false }
            return completed >= startOfWeek
        }.count

        // Get target from active plan
        let planDescriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.userId == userId && $0.isActive }
        )

        let activePlan = try modelContext.fetch(planDescriptor).first
        let target = activePlan?.daysPerWeek ?? 4

        return WeeklyProgressData(completed: completedThisWeek, target: target)
    }
}

// MARK: - Complication Data (iPhone side copy)

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
