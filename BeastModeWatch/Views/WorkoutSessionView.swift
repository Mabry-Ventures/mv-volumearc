import SwiftUI
import WatchKit

/// Active workout session view
struct WorkoutSessionView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Exercise view
            ExercisePickerView()
                .tag(0)

            // Set logger
            SetLoggerView()
                .tag(1)

            // Rest timer
            RestTimerView(duration: 90)
                .tag(2)

            // Quick stats
            QuickStatsView()
                .tag(3)
        }
        .tabViewStyle(.verticalPage)
        .environmentObject(workoutManager)
    }
}

// MARK: - Exercise Picker View

struct ExercisePickerView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Select Exercise")
                    .font(.headline)
                    .padding(.bottom, 4)

                if let exercises = workoutManager.todayExercises {
                    ForEach(exercises) { exercise in
                        Button {
                            workoutManager.selectExercise(exercise)
                        } label: {
                            HStack {
                                Text(exercise.name)
                                    .font(.caption)
                                    .lineLimit(2)
                                Spacer()
                                if workoutManager.currentExercise?.id == exercise.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Set Logger View (with Digital Crown)

struct SetLoggerView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager
    @State private var weight: Double = 135
    @State private var reps: Int = 8
    @State private var focusedField: LoggerField = .weight

    enum LoggerField {
        case weight, reps
    }

    var body: some View {
        VStack(spacing: 8) {
            // Exercise name
            Text(workoutManager.currentExercise?.name ?? "Select Exercise")
                .font(.headline)
                .lineLimit(1)

            Text("Set \(workoutManager.currentSetNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // Weight input (Digital Crown)
            VStack(spacing: 2) {
                Text("WEIGHT")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("\(Int(weight)) lbs")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(focusedField == .weight ? .blue : .primary)
            }
            .focusable(focusedField == .weight)
            .digitalCrownRotation(
                $weight,
                from: 0,
                through: 1000,
                by: 2.5,
                sensitivity: .medium,
                isContinuous: false
            )
            .onTapGesture { focusedField = .weight }

            // Reps input
            VStack(spacing: 2) {
                Text("REPS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("\(reps)")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(focusedField == .reps ? .blue : .primary)
            }
            .focusable(focusedField == .reps)
            .digitalCrownRotation(
                Binding(
                    get: { Double(reps) },
                    set: { reps = Int($0) }
                ),
                from: 0,
                through: 100,
                by: 1,
                sensitivity: .low
            )
            .onTapGesture { focusedField = .reps }

            // Log button
            Button {
                workoutManager.logSet(weight: weight, reps: reps)
            } label: {
                Label("Log Set", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(workoutManager.currentExercise == nil)
        }
        .padding()
    }
}

// MARK: - Rest Timer View

struct RestTimerView: View {
    @State private var timeRemaining: TimeInterval
    @State private var isRunning = false
    let defaultDuration: TimeInterval

    init(duration: TimeInterval = 90) {
        self.defaultDuration = duration
        self._timeRemaining = State(initialValue: duration)
    }

    var body: some View {
        VStack {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(lineWidth: 8)
                    .opacity(0.3)
                    .foregroundStyle(.blue)

                Circle()
                    .trim(from: 0, to: timeRemaining / defaultDuration)
                    .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timeRemaining)

                VStack {
                    Text(timeString)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                    Text("REST")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            HStack(spacing: 20) {
                Button {
                    timeRemaining = max(0, timeRemaining - 15)
                } label: {
                    Image(systemName: "minus")
                }

                Button {
                    isRunning.toggle()
                } label: {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                }

                Button {
                    timeRemaining = min(defaultDuration, timeRemaining + 15)
                } label: {
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(.bordered)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard isRunning, timeRemaining > 0 else { return }
            timeRemaining -= 1

            if timeRemaining == 10 {
                WKInterfaceDevice.current().play(.notification)
            } else if timeRemaining == 0 {
                WKInterfaceDevice.current().play(.success)
                isRunning = false
                timeRemaining = defaultDuration
            }
        }
    }

    var timeString: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Quick Stats View

struct QuickStatsView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager

    var body: some View {
        VStack(spacing: 12) {
            Text("Workout Stats")
                .font(.headline)

            VStack(spacing: 8) {
                statRow(label: "Time", value: workoutManager.formattedElapsedTime)
                statRow(label: "Heart Rate", value: "\(Int(workoutManager.heartRate)) bpm")
                statRow(label: "Calories", value: "\(Int(workoutManager.activeCalories))")
                statRow(label: "Sets", value: "\(workoutManager.completedSets)")
            }

            Button(role: .destructive) {
                Task {
                    try? await workoutManager.endWorkout()
                }
            } label: {
                Label("End Workout", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}

// MARK: - Preview

#Preview {
    WorkoutSessionView()
        .environmentObject(WatchWorkoutManager())
}
