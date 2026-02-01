// RestTimerSettingsView.swift
// BeastMode
// Settings view for customizing rest timer durations

import SwiftUI
import SwiftData

/// Main settings view for rest timer configuration
struct RestTimerSettingsView: View {
    @Bindable var profile: UserProfile
    @State private var showExerciseOverrides = false

    var body: some View {
        List {
            // Default timers section
            Section {
                TimerStepper(
                    title: "Compound Lifts",
                    subtitle: "Squat, Bench, Deadlift, etc.",
                    value: Binding(
                        get: { profile.restTimerCompound },
                        set: { profile.restTimerCompound = $0 }
                    ),
                    range: 60...300,
                    step: 15
                )

                TimerStepper(
                    title: "Isolation Exercises",
                    subtitle: "Curls, Extensions, Flyes",
                    value: Binding(
                        get: { profile.restTimerIsolation },
                        set: { profile.restTimerIsolation = $0 }
                    ),
                    range: 30...180,
                    step: 15
                )

                TimerStepper(
                    title: "Default",
                    subtitle: "Everything else",
                    value: Binding(
                        get: { profile.restTimerDefault },
                        set: { profile.restTimerDefault = $0 }
                    ),
                    range: 30...300,
                    step: 15
                )
            } header: {
                Text("Default Rest Times")
            } footer: {
                Text("Compound movements typically need longer rest for strength recovery.")
            }

            // Per-exercise overrides
            Section {
                Button {
                    showExerciseOverrides = true
                } label: {
                    HStack {
                        Label("Per-Exercise Overrides", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text("\(profile.exerciseRestTimers.count)")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("Per-exercise overrides")
                .accessibilityValue("\(profile.exerciseRestTimers.count) custom timers")
                .accessibilityHint("Double tap to manage custom rest times for specific exercises")
            } header: {
                Text("Custom")
            } footer: {
                Text("Set specific rest times for individual exercises.")
            }

            // Sound and vibration
            Section {
                Toggle(isOn: Binding(
                    get: { profile.restTimerSoundEnabled },
                    set: { profile.restTimerSoundEnabled = $0 }
                )) {
                    Label("Timer Sound", systemImage: "speaker.wave.2.fill")
                }

                Toggle(isOn: Binding(
                    get: { profile.restTimerVibrationEnabled },
                    set: { profile.restTimerVibrationEnabled = $0 }
                )) {
                    Label("Vibration", systemImage: "iphone.radiowaves.left.and.right")
                }
            } header: {
                Text("Alerts")
            }
        }
        .navigationTitle("Rest Timer")
        .sheet(isPresented: $showExerciseOverrides) {
            ExerciseRestOverridesView(profile: profile)
        }
    }
}

// MARK: - Timer Stepper

struct TimerStepper: View {
    let title: String
    let subtitle: String
    @Binding var value: TimeInterval
    let range: ClosedRange<TimeInterval>
    let step: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    // Decrease button
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            value = max(range.lowerBound, value - step)
                        }
                        hapticFeedback()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(value <= range.lowerBound ? .gray : .blue)
                    }
                    .disabled(value <= range.lowerBound)
                    .accessibilityLabel("Decrease")
                    .accessibilityHint("Decrease rest time by \(Int(step)) seconds")

                    // Time display
                    Text(formatTime(value))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 60)
                        .contentTransition(.numericText())
                        .accessibilityHidden(true)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)

                    // Increase button
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            value = min(range.upperBound, value + step)
                        }
                        hapticFeedback()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(value >= range.upperBound ? .gray : .blue)
                    }
                    .disabled(value >= range.upperBound)
                    .accessibilityLabel("Increase")
                    .accessibilityHint("Increase rest time by \(Int(step)) seconds")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) rest timer")
        .accessibilityValue(formatTime(value))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return secs == 0 ? "\(mins)m" : "\(mins):\(String(format: "%02d", secs))"
    }

    private func hapticFeedback() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Exercise Rest Overrides View

struct ExerciseRestOverridesView: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @State private var showAddExercise = false
    @State private var searchText = ""

    private var sortedOverrides: [(String, TimeInterval)] {
        profile.exerciseRestTimers
            .sorted { $0.key < $1.key }
            .filter { searchText.isEmpty || $0.key.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if sortedOverrides.isEmpty {
                    ContentUnavailableView {
                        Label("No Custom Timers", systemImage: "timer")
                    } description: {
                        Text("Add custom rest times for specific exercises.")
                    } actions: {
                        Button("Add Exercise") {
                            showAddExercise = true
                        }
                    }
                } else {
                    ForEach(sortedOverrides, id: \.0) { exercise, duration in
                        ExerciseOverrideRow(
                            exerciseName: exercise,
                            duration: duration,
                            onUpdate: { newDuration in
                                profile.setRestTimer(for: exercise, duration: newDuration)
                            }
                        )
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let exercise = sortedOverrides[index].0
                            profile.removeRestTimer(for: exercise)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Custom Rest Times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddExercise = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseOverrideView(profile: profile)
            }
        }
    }
}

// MARK: - Exercise Override Row

struct ExerciseOverrideRow: View {
    let exerciseName: String
    let duration: TimeInterval
    let onUpdate: (TimeInterval) -> Void

    @State private var isEditing = false
    @State private var editedDuration: TimeInterval

    init(exerciseName: String, duration: TimeInterval, onUpdate: @escaping (TimeInterval) -> Void) {
        self.exerciseName = exerciseName
        self.duration = duration
        self.onUpdate = onUpdate
        self._editedDuration = State(initialValue: duration)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(exerciseName)
                    .font(.body)
            }

            Spacer()

            if isEditing {
                Stepper(
                    value: $editedDuration,
                    in: 30...300,
                    step: 15
                ) {
                    Text(formatTime(editedDuration))
                        .font(.system(.body, design: .rounded))
                        .monospacedDigit()
                }
                .onChange(of: editedDuration) { _, newValue in
                    onUpdate(newValue)
                }
            } else {
                Text(formatTime(duration))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isEditing.toggle()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exerciseName) custom rest timer")
        .accessibilityValue(formatTime(duration))
        .accessibilityHint(isEditing ? "Tap to close editor" : "Tap to edit rest time")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return secs == 0 ? "\(mins)m" : "\(mins):\(String(format: "%02d", secs))"
    }
}

// MARK: - Add Exercise Override View

struct AddExerciseOverrideView: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @State private var exerciseName = ""
    @State private var duration: TimeInterval = 120

    private let commonExercises = [
        "Barbell Bench Press",
        "Incline Dumbbell Press",
        "Barbell Squats",
        "Deadlift",
        "Overhead Press",
        "Barbell Rows",
        "Pull-ups",
        "Bicep Curls",
        "Tricep Pushdowns",
        "Leg Press"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise Name", text: $exerciseName)
                        .autocorrectionDisabled()
                } header: {
                    Text("Exercise")
                }

                Section {
                    ForEach(commonExercises.filter { name in
                        !profile.exerciseRestTimers.keys.contains(name)
                    }, id: \.self) { exercise in
                        Button {
                            exerciseName = exercise
                        } label: {
                            Text(exercise)
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("Quick Add")
                }

                Section {
                    VStack(spacing: 16) {
                        Text(formatTime(duration))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .accessibilityHidden(true)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

                        Slider(value: $duration, in: 30...300, step: 15)
                            .accessibilityLabel("Rest duration")
                            .accessibilityValue(formatTime(duration))
                    }
                    .padding(.vertical)
                } header: {
                    Text("Rest Duration")
                }
            }
            .navigationTitle("Add Custom Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        profile.setRestTimer(for: exerciseName, duration: duration)
                        dismiss()
                    }
                    .disabled(exerciseName.isEmpty)
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return secs == 0 ? "\(mins):00" : "\(mins):\(String(format: "%02d", secs))"
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        RestTimerSettingsView(profile: UserProfile(displayName: "Test User"))
    }
}
