// BeastModeWatchApp.swift
// BeastModeWatch
// Main entry point for the Beast Mode Apple Watch app

import SwiftUI
import WatchKit

@main
struct BeastModeWatchApp: App {
    @StateObject private var workoutManager = WatchWorkoutManager.shared
    @StateObject private var connectivityManager = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
                .environmentObject(connectivityManager)
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var workoutManager: WatchWorkoutManager
    @EnvironmentObject var connectivityManager: WatchConnectivityManager

    @State private var selectedTab: Tab = .workout

    enum Tab {
        case workout
        case history
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchWorkoutView()
                .tag(Tab.workout)

            WorkoutHistoryView()
                .tag(Tab.history)

            WatchSettingsView()
                .tag(Tab.settings)
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Workout History View

struct WorkoutHistoryView: View {
    @EnvironmentObject var workoutManager: WatchWorkoutManager

    var body: some View {
        NavigationStack {
            List {
                if workoutManager.pendingWorkouts.isEmpty {
                    ContentUnavailableView {
                        Label("No Workouts", systemImage: "figure.strengthtraining.traditional")
                    } description: {
                        Text("Completed workouts will appear here")
                    }
                } else {
                    ForEach(workoutManager.pendingWorkouts.sorted(by: { $0.startedAt > $1.startedAt })) { workout in
                        NavigationLink {
                            WatchWorkoutSummaryView(workout: workout)
                        } label: {
                            WorkoutHistoryRow(workout: workout)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct WorkoutHistoryRow: View {
    let workout: WatchWorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workout.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Sync status indicator
                Image(systemName: syncStatusIcon)
                    .foregroundStyle(syncStatusColor)
                    .font(.caption)
            }

            HStack {
                Text(workout.startedAt, style: .date)
                Text("-")
                Text(workout.formattedDuration)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text("\(workout.exercises.count) exercises, \(workout.totalSets) sets")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var syncStatusIcon: String {
        switch workout.syncStatus {
        case .pending: return "icloud.and.arrow.up"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }

    private var syncStatusColor: Color {
        switch workout.syncStatus {
        case .pending: return .orange
        case .syncing: return .blue
        case .synced: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Watch Settings View

struct WatchSettingsView: View {
    @EnvironmentObject var workoutManager: WatchWorkoutManager
    @EnvironmentObject var connectivityManager: WatchConnectivityManager

    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    @AppStorage("hapticFeedback") private var hapticFeedback: Bool = true

    var body: some View {
        NavigationStack {
            List {
                Section("Units") {
                    Picker("Weight", selection: $weightUnit) {
                        Text("lbs").tag("lbs")
                        Text("kg").tag("kg")
                    }
                }

                Section("Feedback") {
                    Toggle("Haptic Feedback", isOn: $hapticFeedback)
                }

                Section("Weight Increment") {
                    Picker("Increment", selection: Binding(
                        get: { workoutManager.weightIncrement },
                        set: { workoutManager.weightIncrement = $0 }
                    )) {
                        Text("2.5").tag(2.5)
                        Text("5").tag(5.0)
                        Text("10").tag(10.0)
                    }
                }

                Section("Sync") {
                    HStack {
                        Text("iPhone")
                        Spacer()
                        Image(systemName: connectivityManager.isReachable ? "iphone.badge.checkmark" : "iphone.slash")
                            .foregroundStyle(connectivityManager.isReachable ? .green : .red)
                    }

                    if let lastSync = connectivityManager.lastSyncDate {
                        HStack {
                            Text("Last Sync")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Sync Now") {
                        Task {
                            await connectivityManager.syncPendingWorkouts()
                        }
                    }
                    .disabled(!connectivityManager.isReachable)
                }

                Section("Data") {
                    HStack {
                        Text("Pending Workouts")
                        Spacer()
                        Text("\(workoutManager.pendingWorkouts.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(WatchWorkoutManager.shared)
        .environmentObject(WatchConnectivityManager.shared)
}
