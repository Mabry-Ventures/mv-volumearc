// DayEditorView.swift
// BeastMode
// View for editing a single day in a workout plan

import SwiftUI
import SwiftData

/// Sheet for editing a single day in a workout plan
struct DayEditorSheet: View {
    @Binding var day: EditablePlanDay
    @Environment(\.dismiss) private var dismiss

    @State private var showAddExercise = false
    @State private var editingExerciseIndex: Int?

    var body: some View {
        NavigationStack {
            Form {
                // Day info
                dayInfoSection

                // Exercises
                if !day.isRestDay {
                    exercisesSection
                }

                // Notes
                notesSection
            }
            .navigationTitle(day.weekdayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseSheet { exercise in
                    day.exercises.append(exercise)
                }
            }
            .sheet(item: $editingExerciseIndex) { index in
                ExerciseEditorSheet(exercise: $day.exercises[index])
            }
        }
    }

    // MARK: - Sections

    private var dayInfoSection: some View {
        Section {
            TextField("Day Name", text: $day.name)

            Toggle("Rest Day", isOn: $day.isRestDay)
                .onChange(of: day.isRestDay) { _, isRest in
                    if isRest {
                        day.name = "Rest"
                    } else if day.name == "Rest" {
                        day.name = "Training Day"
                    }
                }
        } header: {
            Text("Day Info")
        }
    }

    private var exercisesSection: some View {
        Section {
            if day.exercises.isEmpty {
                ContentUnavailableView {
                    Label("No Exercises", systemImage: "figure.strengthtraining.traditional")
                } description: {
                    Text("Add exercises to this training day")
                } actions: {
                    Button("Add Exercise") {
                        showAddExercise = true
                    }
                    .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array(day.exercises.enumerated()), id: \.element.id) { index, exercise in
                    ExerciseRowView(exercise: exercise) {
                        editingExerciseIndex = index
                    }
                }
                .onDelete(perform: deleteExercises)
                .onMove(perform: moveExercises)

                Button {
                    showAddExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                }
            }
        } header: {
            HStack {
                Text("Exercises")
                Spacer()
                Text("\(day.exercises.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notesSection: some View {
        Section {
            TextField("Notes (optional)", text: Binding(
                get: { day.notes ?? "" },
                set: { day.notes = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(2...4)
        } header: {
            Text("Notes")
        }
    }

    // MARK: - Actions

    private func deleteExercises(at offsets: IndexSet) {
        day.exercises.remove(atOffsets: offsets)
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        day.exercises.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Exercise Row View

struct ExerciseRowView: View {
    let exercise: EditablePlanExercise
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(exercise.exerciseName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if exercise.superset {
                            Text("SS")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.purple))
                        }
                    }

                    HStack(spacing: 12) {
                        Label(exercise.prescriptionText, systemImage: "number")

                        if let rpe = exercise.targetRPE {
                            Label("RPE \(Int(rpe))", systemImage: "flame")
                        }

                        Label("\(exercise.restSeconds)s", systemImage: "timer")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Exercise Editor Sheet

struct ExerciseEditorSheet: View {
    @Binding var exercise: EditablePlanExercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Exercise name (read-only)
                Section {
                    HStack {
                        Text("Exercise")
                        Spacer()
                        Text(exercise.exerciseName)
                            .foregroundStyle(.secondary)
                    }
                }

                // Sets and reps
                Section {
                    Stepper("Sets: \(exercise.targetSets)", value: $exercise.targetSets, in: 1...10)

                    HStack {
                        Text("Rep Range")
                        Spacer()

                        Picker("Min", selection: $exercise.targetRepsMin) {
                            ForEach(1...30, id: \.self) { rep in
                                Text("\(rep)").tag(rep)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 60)

                        Text("-")

                        Picker("Max", selection: $exercise.targetRepsMax) {
                            ForEach(1...30, id: \.self) { rep in
                                Text("\(rep)").tag(rep)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 60)
                    }
                    .onChange(of: exercise.targetRepsMin) { _, newValue in
                        if newValue > exercise.targetRepsMax {
                            exercise.targetRepsMax = newValue
                        }
                    }
                } header: {
                    Text("Prescription")
                }

                // Intensity
                Section {
                    Toggle("Use RPE", isOn: Binding(
                        get: { exercise.targetRPE != nil },
                        set: { exercise.targetRPE = $0 ? 8.0 : nil }
                    ))

                    if let rpe = exercise.targetRPE {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Target RPE")
                                Spacer()
                                Text("\(Int(rpe))")
                                    .font(.headline)
                            }

                            Slider(
                                value: Binding(
                                    get: { rpe },
                                    set: { exercise.targetRPE = $0 }
                                ),
                                in: 5...10,
                                step: 0.5
                            )

                            Text(rpeDescription(for: rpe))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Intensity")
                } footer: {
                    Text("RPE (Rate of Perceived Exertion) helps guide intensity without specific weights")
                }

                // Rest
                Section {
                    Picker("Rest Time", selection: $exercise.restSeconds) {
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                        Text("90s").tag(90)
                        Text("2 min").tag(120)
                        Text("3 min").tag(180)
                        Text("4 min").tag(240)
                        Text("5 min").tag(300)
                    }
                } header: {
                    Text("Rest Between Sets")
                }

                // Advanced
                Section {
                    Toggle("Superset", isOn: $exercise.superset)

                    TextField("Notes", text: Binding(
                        get: { exercise.notes ?? "" },
                        set: { exercise.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(2...4)
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Superset exercises have minimal rest before the next exercise")
                }
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func rpeDescription(for rpe: Double) -> String {
        switch rpe {
        case 10:
            return "Maximum effort - could not do another rep"
        case 9..<10:
            return "Very hard - 1 rep left in the tank"
        case 8..<9:
            return "Hard - 2 reps left in the tank"
        case 7..<8:
            return "Moderately hard - 3 reps left"
        case 6..<7:
            return "Moderate - 4+ reps left"
        default:
            return "Light effort"
        }
    }
}

// MARK: - Int Extension for Identifiable

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Preview

#Preview {
    @Previewable @State var day = EditablePlanDay(
        weekday: 2,
        name: "Push Day",
        isRestDay: false,
        exercises: [
            EditablePlanExercise(
                exerciseId: UUID(),
                exerciseName: "Bench Press",
                targetSets: 4,
                targetRepsMin: 6,
                targetRepsMax: 8
            ),
            EditablePlanExercise(
                exerciseId: UUID(),
                exerciseName: "Incline Dumbbell Press",
                targetSets: 3,
                targetRepsMin: 8,
                targetRepsMax: 12
            )
        ]
    )

    return DayEditorSheet(day: $day)
}
