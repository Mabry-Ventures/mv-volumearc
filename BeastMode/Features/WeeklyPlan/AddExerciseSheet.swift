// AddExerciseSheet.swift
// BeastMode
// Sheet for adding an exercise to a plan day

import SwiftUI
import SwiftData

/// Sheet for selecting and adding an exercise to a plan day
struct AddExerciseSheet: View {
    let onAdd: (EditablePlanExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var selectedCategory: ExerciseCategory?
    @State private var selectedExercise: Exercise?

    // Quick add settings
    @State private var targetSets: Int = 3
    @State private var targetRepsMin: Int = 8
    @State private var targetRepsMax: Int = 12

    private var filteredExercises: [Exercise] {
        var result = exercises

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return result
    }

    private var groupedExercises: [ExerciseCategory: [Exercise]] {
        Dictionary(grouping: filteredExercises) { $0.category }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let exercise = selectedExercise {
                    configureExerciseView(exercise)
                } else {
                    exerciseListView
                }
            }
            .navigationTitle(selectedExercise == nil ? "Add Exercise" : "Configure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedExercise != nil {
                        Button("Back") {
                            selectedExercise = nil
                        }
                    } else {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }

                if selectedExercise != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add") {
                            addExercise()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: - Exercise List View

    private var exerciseListView: some View {
        VStack(spacing: 0) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryFilterChip(
                        title: "All",
                        isSelected: selectedCategory == nil
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(ExerciseCategory.allCases, id: \.self) { category in
                        CategoryFilterChip(
                            title: category.rawValue,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)

            // Exercise list
            List {
                if selectedCategory != nil {
                    // Flat list for single category
                    ForEach(filteredExercises) { exercise in
                        ExerciseSelectRow(exercise: exercise) {
                            selectedExercise = exercise
                        }
                    }
                } else {
                    // Grouped by category
                    ForEach(Array(groupedExercises.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { category in
                        Section(category.rawValue) {
                            ForEach(groupedExercises[category] ?? []) { exercise in
                                ExerciseSelectRow(exercise: exercise) {
                                    selectedExercise = exercise
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .searchable(text: $searchText, prompt: "Search exercises")
    }

    // MARK: - Configure Exercise View

    private func configureExerciseView(_ exercise: Exercise) -> some View {
        Form {
            // Selected exercise info
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.headline)

                        HStack(spacing: 8) {
                            Text(exercise.category.rawValue)

                            if exercise.isCompound {
                                Text("•")
                                Text(L10n.Workout.compound)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: exercise.isCompound ? "flame.fill" : "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
            }

            // Quick presets
            Section {
                PresetButton(title: "Strength", sets: 5, repsMin: 3, repsMax: 5) {
                    targetSets = 5
                    targetRepsMin = 3
                    targetRepsMax = 5
                }

                PresetButton(title: "Hypertrophy", sets: 3, repsMin: 8, repsMax: 12) {
                    targetSets = 3
                    targetRepsMin = 8
                    targetRepsMax = 12
                }

                PresetButton(title: "Endurance", sets: 3, repsMin: 15, repsMax: 20) {
                    targetSets = 3
                    targetRepsMin = 15
                    targetRepsMax = 20
                }
            } header: {
                Text(L10n.Plan.quickPresets)
            }

            // Custom configuration
            Section {
                Stepper("Sets: \(targetSets)", value: $targetSets, in: 1...10)

                HStack {
                    Text(L10n.Plan.repRange)
                    Spacer()

                    Picker("Min", selection: $targetRepsMin) {
                        ForEach(1...30, id: \.self) { rep in
                            Text("\(rep)").tag(rep)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 60)

                    Text("-")

                    Picker("Max", selection: $targetRepsMax) {
                        ForEach(1...30, id: \.self) { rep in
                            Text("\(rep)").tag(rep)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 60)
                }
                .onChange(of: targetRepsMin) { _, newValue in
                    if newValue > targetRepsMax {
                        targetRepsMax = newValue
                    }
                }
            } header: {
                Text(L10n.RestTimer.custom)
            } footer: {
                Text(L10n.Plan.customizeAfterAdding)
            }

            // Preview
            Section {
                HStack {
                    Text(L10n.Plan.prescription)
                    Spacer()
                    Text("\(targetSets) × \(targetRepsMin == targetRepsMax ? "\(targetRepsMin)" : "\(targetRepsMin)-\(targetRepsMax)")")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Actions

    private func addExercise() {
        guard let exercise = selectedExercise else { return }

        let newExercise = EditablePlanExercise(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            targetSets: targetSets,
            targetRepsMin: targetRepsMin,
            targetRepsMax: targetRepsMax
        )

        // Set appropriate rest time based on exercise type
        if exercise.isCompound {
            newExercise.restSeconds = 180  // 3 min for compounds
        } else {
            newExercise.restSeconds = 90   // 90s for isolation
        }

        onAdd(newExercise)
        dismiss()
    }
}

// MARK: - Category Filter Chip

struct CategoryFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color(hex: "FF6B35") : Color.secondary.opacity(0.2))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Exercise Select Row

struct ExerciseSelectRow: View {
    let exercise: Exercise
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    if exercise.isCompound {
                        Text(L10n.Workout.compound)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Preset Button

struct PresetButton: View {
    let title: String
    let sets: Int
    let repsMin: Int
    let repsMax: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(sets) × \(repsMin)-\(repsMax)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Recently Used Section

struct RecentlyUsedSection: View {
    let exercises: [Exercise]
    let onSelect: (Exercise) -> Void

    var body: some View {
        if !exercises.isEmpty {
            Section {
                ForEach(exercises.prefix(5)) { exercise in
                    ExerciseSelectRow(exercise: exercise) {
                        onSelect(exercise)
                    }
                }
            } header: {
                Label("Recently Used", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AddExerciseSheet { exercise in
        print("Added: \(exercise.exerciseName)")
    }
}
