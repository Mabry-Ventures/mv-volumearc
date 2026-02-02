// WatchWorkoutView.swift
// BeastModeWatch
// Main workout logging view for Apple Watch

import SwiftUI
import WatchKit

/// Main view for logging workouts on Apple Watch
struct WatchWorkoutView: View {
    @StateObject private var workoutManager = WatchWorkoutManager.shared
    @State private var showExerciseList = false
    @State private var showEndConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if workoutManager.isWorkoutActive {
                    activeWorkoutView
                } else {
                    startWorkoutView
                }
            }
            .navigationTitle("Beast Mode")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Start Workout View

    private var startWorkoutView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Ready to train?")
                .font(.headline)

            Button(action: { workoutManager.startWorkout() }) {
                Label("Start Workout", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            if !workoutManager.pendingWorkouts.isEmpty {
                Text("\(workoutManager.pendingWorkouts.count) pending sync")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Active Workout View

    private var activeWorkoutView: some View {
        VStack(spacing: 8) {
            // Timer header
            workoutTimerHeader

            if let exercise = workoutManager.currentExercise {
                // Current exercise logging
                exerciseLoggingView(exercise: exercise)
            } else {
                // No exercise selected - prompt to add
                noExercisePrompt
            }
        }
        .sheet(isPresented: $showExerciseList) {
            ExerciseListView(workoutManager: workoutManager)
        }
        .confirmationDialog(
            "End Workout?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save & End", role: .destructive) {
                workoutManager.endWorkout()
            }
            Button("Cancel", role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { showEndConfirmation = true }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Timer Header

    private var workoutTimerHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(formatDuration(workoutManager.elapsedTime))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.orange)

                if let workout = workoutManager.activeWorkout {
                    Text("\(workout.totalSets) sets")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: { showExerciseList = true }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    // MARK: - No Exercise Prompt

    private var noExercisePrompt: some View {
        VStack(spacing: 12) {
            Spacer()

            Text("Add an exercise to begin")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: { showExerciseList = true }) {
                Label("Add Exercise", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("End Workout") {
                showEndConfirmation = true
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    // MARK: - Exercise Logging View

    private func exerciseLoggingView(exercise: WatchExerciseLog) -> some View {
        VStack(spacing: 4) {
            // Exercise name
            Text(exercise.name)
                .font(.headline)
                .lineLimit(1)

            // Sets completed
            Text("\(exercise.sets.count) sets")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Weight/Reps input
            SetInputSection(workoutManager: workoutManager)

            // Log set button
            Button(action: { workoutManager.logSet() }) {
                Label("Log Set", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            // Previous sets display
            if !exercise.sets.isEmpty {
                previousSetsView(sets: exercise.sets)
            }
        }
        .padding(.horizontal)
    }

    private func previousSetsView(sets: [WatchSetLog]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sets.suffix(3)) { set in
                    VStack(spacing: 2) {
                        Text("\(set.setNumber)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Int(set.weight))x\(set.reps)")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Set Input Section

struct SetInputSection: View {
    @ObservedObject var workoutManager: WatchWorkoutManager
    @State private var focusedField: InputField = .weight

    enum InputField {
        case weight, reps
    }

    var body: some View {
        HStack(spacing: 12) {
            // Weight input
            VStack(spacing: 2) {
                Text("Weight")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("\(Int(workoutManager.inputWeight))")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(focusedField == .weight ? .orange : .primary)

                Text("lbs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = .weight
            }
            .focusable(focusedField == .weight)
            .digitalCrownRotation(
                Binding(
                    get: { workoutManager.inputWeight },
                    set: { workoutManager.setWeight($0) }
                ),
                from: 0,
                through: 1000,
                by: workoutManager.weightIncrement,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )

            Divider()
                .frame(height: 40)

            // Reps input
            VStack(spacing: 2) {
                Text("Reps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("\(workoutManager.inputReps)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(focusedField == .reps ? .orange : .primary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = .reps
            }
            .focusable(focusedField == .reps)
            .digitalCrownRotation(
                Binding(
                    get: { Double(workoutManager.inputReps) },
                    set: { workoutManager.setReps(Int($0)) }
                ),
                from: 1,
                through: 100,
                by: 1,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(.quaternary)
        .cornerRadius(10)
    }
}

// MARK: - Exercise List View

struct ExerciseListView: View {
    @ObservedObject var workoutManager: WatchWorkoutManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Quick templates section
                Section("Quick Add") {
                    ForEach(workoutManager.exerciseTemplates.prefix(6)) { template in
                        Button(action: {
                            workoutManager.addExercise(from: template)
                            dismiss()
                        }) {
                            HStack {
                                Text(template.name)
                                    .lineLimit(1)
                                Spacer()
                                Text(template.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Current workout exercises
                if let workout = workoutManager.activeWorkout, !workout.exercises.isEmpty {
                    Section("In Workout") {
                        ForEach(workout.exercises) { exercise in
                            Button(action: {
                                workoutManager.selectExercise(exercise)
                                dismiss()
                            }) {
                                HStack {
                                    Text(exercise.name)
                                    Spacer()
                                    Text("\(exercise.sets.count) sets")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // All templates
                Section("All Exercises") {
                    ForEach(workoutManager.exerciseTemplates) { template in
                        Button(action: {
                            workoutManager.addExercise(from: template)
                            dismiss()
                        }) {
                            VStack(alignment: .leading) {
                                Text(template.name)
                                Text(template.category)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Workout Summary View

struct WatchWorkoutSummaryView: View {
    let workout: WatchWorkoutSession

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Completion checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)

                Text("Workout Complete!")
                    .font(.headline)

                // Stats
                VStack(spacing: 8) {
                    StatRow(label: "Duration", value: workout.formattedDuration)
                    StatRow(label: "Exercises", value: "\(workout.exercises.count)")
                    StatRow(label: "Total Sets", value: "\(workout.totalSets)")
                    StatRow(label: "Volume", value: "\(Int(workout.totalVolume)) lbs")
                }
                .padding()
                .background(.quaternary)
                .cornerRadius(10)

                // Sync status
                HStack {
                    Image(systemName: workout.syncStatus == .synced ? "checkmark.icloud" : "icloud.and.arrow.up")
                    Text(workout.syncStatus == .synced ? "Synced" : "Pending sync")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - Preview

#Preview {
    WatchWorkoutView()
}
