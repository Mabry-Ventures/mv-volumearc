// SetInputView.swift
// BeastMode
// View for inputting set data with PR detection integration

import SwiftUI
import SwiftData

/// View for entering weight and reps for a set
struct SetInputView: View {
    @Bindable var set: SetLog
    let exerciseType: ExerciseType
    let exerciseName: String

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var celebrationCoordinator: CelebrationCoordinator
    @StateObject private var restTimerManager = RestTimerManager()

    @Query private var profiles: [UserProfile]
    @Query private var streaks: [UserStreak]

    @State private var weight: String = ""
    @State private var reps: String = ""
    @State private var isCompleting = false

    private var currentUser: UserProfile? {
        profiles.first
    }

    private var currentStreak: UserStreak? {
        streaks.first
    }

    var body: some View {
        VStack(spacing: 16) {
            // Set number indicator
            HStack {
                Text("Set \(set.setNumber)")
                    .font(.headline)

                Spacer()

                if set.isCompleted {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // Input fields based on exercise type
            switch exerciseType {
            case .weightAndReps:
                weightAndRepsInputs

            case .bodyweight:
                bodyweightInputs

            case .timed:
                timedInputs

            case .distance, .cardio:
                distanceInputs
            }

            // Complete button and rest timer
            HStack {
                if set.isCompleted {
                    // Show completed state
                    completedStateView
                } else {
                    // Complete set button
                    Button {
                        completeSet()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Complete Set")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canComplete ? Color.green : Color.gray.opacity(0.3))
                        )
                        .foregroundStyle(canComplete ? .white : .gray)
                    }
                    .disabled(!canComplete || isCompleting)
                }
            }

            // Rest timer display (when active)
            if restTimerManager.isRunning {
                RestTimerView(manager: restTimerManager)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .onAppear {
            loadExistingValues()
        }
    }

    // MARK: - Input Views

    private var weightAndRepsInputs: some View {
        HStack(spacing: 16) {
            // Weight input
            VStack(alignment: .leading, spacing: 4) {
                Text("Weight")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("0", text: $weight)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(width: 80)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.background)
                        )
                        .onChange(of: weight) { _, newValue in
                            set.weight = Double(newValue)
                        }

                    Text(currentUser?.unitSystemEnum.weightUnit ?? "lbs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Reps input
            VStack(alignment: .leading, spacing: 4) {
                Text("Reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("0", text: $reps)
                        .keyboardType(.numberPad)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(width: 80)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.background)
                        )
                        .onChange(of: reps) { _, newValue in
                            set.reps = Int(newValue)
                        }

                    Text("reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // RPE selector (optional)
            RPESelector(selectedRPE: Binding(
                get: { set.rpe },
                set: { set.rpe = $0 }
            ))
        }
    }

    private var bodyweightInputs: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("0", text: $reps)
                    .keyboardType(.numberPad)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(width: 100)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.background)
                    )
                    .onChange(of: reps) { _, newValue in
                        set.reps = Int(newValue)
                    }
            }

            Spacer()
        }
    }

    private var timedInputs: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Duration")
                .font(.caption)
                .foregroundStyle(.secondary)

            DurationPicker(duration: Binding(
                get: { set.duration ?? 0 },
                set: { set.duration = $0 }
            ))
        }
    }

    private var distanceInputs: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Distance")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("0", value: Binding(
                        get: { set.distance ?? 0 },
                        set: { set.distance = $0 }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.background)
                    )

                    Text(currentUser?.unitSystemEnum.distanceUnit ?? "mi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Duration")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DurationPicker(duration: Binding(
                    get: { set.duration ?? 0 },
                    set: { set.duration = $0 }
                ))
            }

            Spacer()
        }
    }

    private var completedStateView: some View {
        HStack {
            VStack(alignment: .leading) {
                if let weight = set.weight, let reps = set.reps {
                    Text("\(Int(weight)) lbs × \(reps) reps")
                        .font(.headline)
                }
                if let time = set.completedAt {
                    Text(time.formatted(.dateTime.hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                // Allow editing completed set
                set.completedAt = nil
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.green.opacity(0.1))
        )
    }

    // MARK: - Logic

    private var canComplete: Bool {
        switch exerciseType {
        case .weightAndReps:
            return (set.weight ?? 0) > 0 && (set.reps ?? 0) > 0
        case .bodyweight:
            return (set.reps ?? 0) > 0
        case .timed:
            return (set.duration ?? 0) > 0
        case .distance, .cardio:
            return (set.distance ?? 0) > 0
        }
    }

    private func loadExistingValues() {
        if let w = set.weight {
            weight = String(Int(w))
        }
        if let r = set.reps {
            reps = String(r)
        }
    }

    private func completeSet() {
        isCompleting = true
        set.completedAt = .now

        // Haptic feedback
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        // Check for PR (for weight-based exercises)
        if exerciseType == .weightAndReps || exerciseType == .bodyweight {
            checkForPR()
        }

        // Start rest timer
        startRestTimer()

        isCompleting = false
    }

    private func checkForPR() {
        guard let userId = currentUser?.id,
              let weight = set.weight,
              let reps = set.reps,
              weight > 0, reps > 0 else { return }

        Task {
            let prService = PRDetectionService(modelContext: modelContext)

            if let prType = await prService.checkForPR(
                exerciseName: exerciseName,
                weight: weight,
                reps: reps,
                userId: userId
            ) {
                // Save the PR
                try? await prService.savePR(
                    exerciseName: exerciseName,
                    weight: weight,
                    reps: reps,
                    prType: prType,
                    sourceSetId: set.id,
                    userId: userId
                )

                // Record PR for badge tracking
                let streakService = StreakService(modelContext: modelContext)
                _ = try? await streakService.recordPR(for: userId)

                // Trigger celebration
                await MainActor.run {
                    celebrationCoordinator.celebrate(
                        pr: prType,
                        exercise: exerciseName,
                        weight: weight,
                        reps: reps,
                        set: set,
                        streak: currentStreak?.currentStreak
                    )
                }
            }
        }
    }

    private func startRestTimer() {
        guard let profile = currentUser else { return }

        let timerService = RestTimerService(profile: profile)
        let duration = timerService.getRestDuration(for: exerciseName)

        restTimerManager.start(duration: duration) {
            // Timer completed - haptic and notification handled by manager
        }
    }
}

// MARK: - RPE Selector

struct RPESelector: View {
    @Binding var selectedRPE: Int?

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("RPE")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach([6, 7, 8, 9, 10], id: \.self) { rpe in
                    Button {
                        selectedRPE = rpe
                    } label: {
                        Text("\(rpe)")
                    }
                }

                if selectedRPE != nil {
                    Divider()
                    Button("Clear", role: .destructive) {
                        selectedRPE = nil
                    }
                }
            } label: {
                Text(selectedRPE.map { "\($0)" } ?? "-")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.background)
                    )
            }
        }
    }
}

// MARK: - Duration Picker

struct DurationPicker: View {
    @Binding var duration: TimeInterval

    private var minutes: Int {
        Int(duration) / 60
    }

    private var seconds: Int {
        Int(duration) % 60
    }

    var body: some View {
        HStack(spacing: 4) {
            Picker("Minutes", selection: Binding(
                get: { minutes },
                set: { duration = TimeInterval($0 * 60 + seconds) }
            )) {
                ForEach(0..<60) { min in
                    Text("\(min)").tag(min)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 60, height: 80)
            .clipped()

            Text(":")
                .font(.title2)

            Picker("Seconds", selection: Binding(
                get: { seconds },
                set: { duration = TimeInterval(minutes * 60 + $0) }
            )) {
                ForEach(0..<60) { sec in
                    Text(String(format: "%02d", sec)).tag(sec)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 60, height: 80)
            .clipped()
        }
    }
}

// MARK: - Rest Timer View

struct RestTimerView: View {
    @ObservedObject var manager: RestTimerManager

    var body: some View {
        VStack(spacing: 12) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: manager.progress)
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: manager.progress)

                Text(manager.formattedTime)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            // Controls
            HStack(spacing: 20) {
                Button {
                    manager.addTime(15)
                } label: {
                    Label("+15s", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    manager.skip()
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.blue.opacity(0.1))
        )
    }
}

// MARK: - Preview

#Preview {
    let set = SetLog(exerciseId: UUID(), setNumber: 1)

    return SetInputView(
        set: set,
        exerciseType: .weightAndReps,
        exerciseName: "Barbell Bench Press"
    )
    .environmentObject(CelebrationCoordinator())
    .padding()
}
