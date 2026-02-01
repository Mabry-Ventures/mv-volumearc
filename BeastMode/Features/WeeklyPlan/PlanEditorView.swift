// PlanEditorView.swift
// BeastMode
// View for creating and editing workout plans

import SwiftUI
import SwiftData

/// View for creating or editing a workout plan
struct PlanEditorView: View {
    let userId: UUID
    let plan: WorkoutPlan?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Plan properties
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var difficulty: PlanDifficulty = .intermediate
    @State private var goal: PlanGoal = .strength
    @State private var daysPerWeek: Int = 4
    @State private var estimatedDuration: Int = 8

    // Days
    @State private var days: [EditablePlanDay] = []

    // UI State
    @State private var selectedDayIndex: Int?
    @State private var showDayEditor = false
    @State private var showDeleteConfirmation = false

    private var isEditing: Bool {
        plan != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic info
                basicInfoSection

                // Goal and difficulty
                configurationSection

                // Weekly schedule
                scheduleSection

                // Days overview
                daysSection

                // Danger zone (for existing plans)
                if isEditing {
                    dangerZoneSection
                }
            }
            .navigationTitle(isEditing ? "Edit Plan" : "New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        savePlan()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showDayEditor) {
                if let index = selectedDayIndex {
                    DayEditorSheet(day: $days[index])
                }
            }
            .confirmationDialog(
                "Delete Plan",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deletePlan()
                }
            } message: {
                Text("Are you sure you want to delete this plan? This action cannot be undone.")
            }
            .onAppear {
                loadPlanData()
            }
        }
    }

    // MARK: - Sections

    private var basicInfoSection: some View {
        Section {
            TextField("Plan Name", text: $name)

            TextField("Description (optional)", text: $description, axis: .vertical)
                .lineLimit(2...4)
        } header: {
            Text("Basic Info")
        }
    }

    private var configurationSection: some View {
        Section {
            Picker("Goal", selection: $goal) {
                ForEach(PlanGoal.allCases, id: \.self) { g in
                    Label(g.rawValue, systemImage: g.icon)
                        .tag(g)
                }
            }

            Picker("Difficulty", selection: $difficulty) {
                ForEach(PlanDifficulty.allCases, id: \.self) { d in
                    Text(d.rawValue).tag(d)
                }
            }

            Stepper("Duration: \(estimatedDuration) weeks", value: $estimatedDuration, in: 1...52)
        } header: {
            Text("Configuration")
        } footer: {
            Text(goal.description)
        }
    }

    private var scheduleSection: some View {
        Section {
            Stepper("Training Days: \(daysPerWeek) per week", value: $daysPerWeek, in: 1...7)
                .onChange(of: daysPerWeek) { _, newValue in
                    updateDaysForSchedule()
                }
        } header: {
            Text("Schedule")
        } footer: {
            Text("Tap a day below to configure its exercises")
        }
    }

    private var daysSection: some View {
        Section {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                Button {
                    selectedDayIndex = index
                    showDayEditor = true
                } label: {
                    HStack {
                        // Weekday
                        Text(day.shortWeekdayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(day.isRestDay ? Color.gray : Color(hex: "FF6B35"))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.name)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if day.isRestDay {
                                Text("Rest Day")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(day.exercises.count) exercises")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        toggleRestDay(at: index)
                    } label: {
                        Label(
                            day.isRestDay ? "Training" : "Rest",
                            systemImage: day.isRestDay ? "figure.run" : "bed.double"
                        )
                    }
                    .tint(day.isRestDay ? .orange : .blue)
                }
            }
        } header: {
            Text("Weekly Schedule")
        }
    }

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Plan")
                }
            }
        } header: {
            Text("Danger Zone")
        }
    }

    // MARK: - Actions

    private func loadPlanData() {
        if let plan {
            // Editing existing plan
            name = plan.name
            description = plan.planDescription ?? ""
            difficulty = plan.difficulty
            goal = plan.targetGoal
            daysPerWeek = plan.daysPerWeek
            estimatedDuration = plan.estimatedDuration

            // Load days
            days = plan.sortedDays.map { EditablePlanDay(from: $0) }
        } else {
            // Creating new plan - initialize all 7 days
            initializeDays()
        }
    }

    private func initializeDays() {
        let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        days = (1...7).map { weekday in
            EditablePlanDay(
                weekday: weekday,
                name: weekdayNames[weekday - 1],
                isRestDay: true,
                exercises: []
            )
        }

        // Set some days as training based on daysPerWeek
        updateDaysForSchedule()
    }

    private func updateDaysForSchedule() {
        // Common patterns based on days per week
        let trainingDays: [Int]
        switch daysPerWeek {
        case 1:
            trainingDays = [2]  // Monday
        case 2:
            trainingDays = [2, 5]  // Mon, Thu
        case 3:
            trainingDays = [2, 4, 6]  // Mon, Wed, Fri
        case 4:
            trainingDays = [2, 3, 5, 6]  // Mon, Tue, Thu, Fri
        case 5:
            trainingDays = [2, 3, 4, 5, 6]  // Mon-Fri
        case 6:
            trainingDays = [2, 3, 4, 5, 6, 7]  // Mon-Sat
        case 7:
            trainingDays = [1, 2, 3, 4, 5, 6, 7]  // Every day
        default:
            trainingDays = [2, 4, 6]
        }

        for i in 0..<days.count {
            days[i].isRestDay = !trainingDays.contains(days[i].weekday)
            if days[i].isRestDay {
                days[i].name = "Rest"
            } else if days[i].name == "Rest" {
                // Give a default training name
                days[i].name = "Training Day"
            }
        }
    }

    private func toggleRestDay(at index: Int) {
        days[index].isRestDay.toggle()
        if days[index].isRestDay {
            days[index].name = "Rest"
        } else if days[index].name == "Rest" {
            days[index].name = "Training Day"
        }
    }

    private func savePlan() {
        if let plan {
            // Update existing plan
            plan.name = name
            plan.planDescription = description.isEmpty ? nil : description
            plan.difficulty = difficulty
            plan.targetGoal = goal
            plan.daysPerWeek = days.filter { !$0.isRestDay }.count
            plan.estimatedDuration = estimatedDuration
            plan.updatedAt = .now

            // Update days
            updatePlanDays(plan)
        } else {
            // Create new plan
            let newPlan = WorkoutPlan(
                userId: userId,
                name: name,
                description: description.isEmpty ? nil : description,
                daysPerWeek: days.filter { !$0.isRestDay }.count,
                difficulty: difficulty,
                targetGoal: goal
            )
            newPlan.estimatedDuration = estimatedDuration

            // Add days
            for editableDay in days {
                let day = PlanDay(
                    weekday: editableDay.weekday,
                    name: editableDay.name,
                    isRestDay: editableDay.isRestDay
                )
                day.notes = editableDay.notes

                // Add exercises
                for (index, exercise) in editableDay.exercises.enumerated() {
                    let planExercise = PlanExercise(
                        exerciseId: exercise.exerciseId,
                        exerciseName: exercise.exerciseName,
                        order: index,
                        targetSets: exercise.targetSets,
                        targetRepsMin: exercise.targetRepsMin,
                        targetRepsMax: exercise.targetRepsMax,
                        targetRPE: exercise.targetRPE,
                        restSeconds: exercise.restSeconds
                    )
                    planExercise.notes = exercise.notes
                    planExercise.superset = exercise.superset
                    day.exercises.append(planExercise)
                }

                newPlan.days.append(day)
            }

            modelContext.insert(newPlan)
        }

        dismiss()
    }

    private func updatePlanDays(_ plan: WorkoutPlan) {
        // Clear existing days
        for day in plan.days {
            modelContext.delete(day)
        }
        plan.days.removeAll()

        // Add updated days
        for editableDay in days {
            let day = PlanDay(
                weekday: editableDay.weekday,
                name: editableDay.name,
                isRestDay: editableDay.isRestDay
            )
            day.notes = editableDay.notes

            // Add exercises
            for (index, exercise) in editableDay.exercises.enumerated() {
                let planExercise = PlanExercise(
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseName,
                    order: index,
                    targetSets: exercise.targetSets,
                    targetRepsMin: exercise.targetRepsMin,
                    targetRepsMax: exercise.targetRepsMax,
                    targetRPE: exercise.targetRPE,
                    restSeconds: exercise.restSeconds
                )
                planExercise.notes = exercise.notes
                planExercise.superset = exercise.superset
                day.exercises.append(planExercise)
            }

            plan.days.append(day)
        }
    }

    private func deletePlan() {
        if let plan {
            modelContext.delete(plan)
        }
        dismiss()
    }
}

// MARK: - Editable Plan Day

/// Mutable version of PlanDay for editing
struct EditablePlanDay: Identifiable {
    let id: UUID
    var weekday: Int
    var name: String
    var isRestDay: Bool
    var notes: String?
    var exercises: [EditablePlanExercise]

    init(weekday: Int, name: String, isRestDay: Bool, exercises: [EditablePlanExercise]) {
        self.id = UUID()
        self.weekday = weekday
        self.name = name
        self.isRestDay = isRestDay
        self.notes = nil
        self.exercises = exercises
    }

    init(from day: PlanDay) {
        self.id = day.id
        self.weekday = day.weekday
        self.name = day.name
        self.isRestDay = day.isRestDay
        self.notes = day.notes
        self.exercises = day.sortedExercises.map { EditablePlanExercise(from: $0) }
    }

    var shortWeekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(weekday: weekday)) ?? .now
        return formatter.string(from: date)
    }

    var weekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(weekday: weekday)) ?? .now
        return formatter.string(from: date)
    }
}

// MARK: - Editable Plan Exercise

/// Mutable version of PlanExercise for editing
struct EditablePlanExercise: Identifiable {
    let id: UUID
    var exerciseId: UUID
    var exerciseName: String
    var targetSets: Int
    var targetRepsMin: Int
    var targetRepsMax: Int
    var targetRPE: Double?
    var restSeconds: Int
    var notes: String?
    var superset: Bool

    init(
        exerciseId: UUID,
        exerciseName: String,
        targetSets: Int = 3,
        targetRepsMin: Int = 8,
        targetRepsMax: Int = 12
    ) {
        self.id = UUID()
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.targetSets = targetSets
        self.targetRepsMin = targetRepsMin
        self.targetRepsMax = targetRepsMax
        self.targetRPE = nil
        self.restSeconds = 90
        self.notes = nil
        self.superset = false
    }

    init(from exercise: PlanExercise) {
        self.id = exercise.id
        self.exerciseId = exercise.exerciseId
        self.exerciseName = exercise.exerciseName
        self.targetSets = exercise.targetSets
        self.targetRepsMin = exercise.targetRepsMin
        self.targetRepsMax = exercise.targetRepsMax
        self.targetRPE = exercise.targetRPE
        self.restSeconds = exercise.restSeconds
        self.notes = exercise.notes
        self.superset = exercise.superset
    }

    var repRangeText: String {
        if targetRepsMin == targetRepsMax {
            return "\(targetRepsMin)"
        }
        return "\(targetRepsMin)-\(targetRepsMax)"
    }

    var prescriptionText: String {
        "\(targetSets) × \(repRangeText)"
    }
}

// MARK: - Preview

#Preview {
    PlanEditorView(userId: UUID(), plan: nil)
}
