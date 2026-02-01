// PlanLibraryView.swift
// BeastMode
// View for browsing and managing workout plans

import SwiftUI
import SwiftData

/// Main view for browsing and managing workout plans
struct PlanLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutPlan.updatedAt, order: .reverse)
    private var plans: [WorkoutPlan]
    @Query private var profiles: [UserProfile]

    @State private var showCreatePlan = false
    @State private var showImportPlan = false
    @State private var showTemplates = false
    @State private var selectedPlan: WorkoutPlan?
    @State private var searchText = ""

    private var userId: UUID? {
        profiles.first?.id
    }

    private var filteredPlans: [WorkoutPlan] {
        if searchText.isEmpty {
            return plans
        }
        return plans.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var activePlan: WorkoutPlan? {
        plans.first { $0.isActive }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Active plan card
                    if let active = activePlan {
                        ActivePlanCard(plan: active)
                            .padding(.horizontal)
                    }

                    // Quick actions
                    quickActionsSection

                    // My plans
                    myPlansSection
                }
                .padding(.vertical)
            }
            .navigationTitle("My Plans")
            .searchable(text: $searchText, prompt: "Search plans")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCreatePlan = true
                        } label: {
                            Label("Create New Plan", systemImage: "plus")
                        }

                        Button {
                            showTemplates = true
                        } label: {
                            Label("Start from Template", systemImage: "doc.on.doc")
                        }

                        Divider()

                        Button {
                            showImportPlan = true
                        } label: {
                            Label("Import Plan", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showCreatePlan) {
                if let userId {
                    PlanEditorView(userId: userId, plan: nil)
                }
            }
            .sheet(isPresented: $showTemplates) {
                if let userId {
                    TemplatePickerSheet(userId: userId)
                }
            }
            .sheet(isPresented: $showImportPlan) {
                ImportPlanSheet()
            }
            .sheet(item: $selectedPlan) { plan in
                PlanEditorView(userId: plan.userId, plan: plan)
            }
        }
    }

    // MARK: - Subviews

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Plan.quickActions)
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    QuickActionButton(
                        icon: "plus.circle.fill",
                        title: "New Plan",
                        color: .orange
                    ) {
                        showCreatePlan = true
                    }

                    QuickActionButton(
                        icon: "doc.on.doc.fill",
                        title: "Templates",
                        color: .blue
                    ) {
                        showTemplates = true
                    }

                    QuickActionButton(
                        icon: "square.and.arrow.down.fill",
                        title: "Import",
                        color: .purple
                    ) {
                        showImportPlan = true
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var myPlansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.Plan.myPlans)
                    .font(.headline)

                Spacer()

                Text("\(filteredPlans.count) plans")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if filteredPlans.isEmpty {
                emptyStateView
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredPlans) { plan in
                        PlanRowView(plan: plan) {
                            selectedPlan = plan
                        }
                        .contextMenu {
                            planContextMenu(for: plan)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Plans Yet", systemImage: "calendar.badge.plus")
        } description: {
            Text(L10n.Plan.createFirstPlan)
        } actions: {
            Button("Create Plan") {
                showCreatePlan = true
            }
            .buttonStyle(.bordered)
        }
        .frame(height: 250)
    }

    @ViewBuilder
    private func planContextMenu(for plan: WorkoutPlan) -> some View {
        Button {
            selectedPlan = plan
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button {
            setActivePlan(plan)
        } label: {
            Label(plan.isActive ? "Deactivate" : "Set as Active", systemImage: plan.isActive ? "checkmark.circle.badge.xmark" : "checkmark.circle")
        }

        Divider()

        Button {
            duplicatePlan(plan)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button(role: .destructive) {
            deletePlan(plan)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func setActivePlan(_ plan: WorkoutPlan) {
        // Deactivate all other plans
        for p in plans {
            p.isActive = false
        }
        plan.isActive = true
    }

    private func duplicatePlan(_ plan: WorkoutPlan) {
        guard let userId else { return }

        let newPlan = WorkoutPlan(
            userId: userId,
            name: "\(plan.name) (Copy)",
            description: plan.planDescription,
            daysPerWeek: plan.daysPerWeek,
            difficulty: plan.difficulty,
            targetGoal: plan.targetGoal
        )

        // Copy days
        for day in plan.sortedDays {
            let newDay = PlanDay(
                weekday: day.weekday,
                name: day.name,
                isRestDay: day.isRestDay
            )
            newDay.notes = day.notes

            // Copy exercises
            for exercise in day.sortedExercises {
                let newExercise = PlanExercise(
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseName,
                    order: exercise.order,
                    targetSets: exercise.targetSets,
                    targetRepsMin: exercise.targetRepsMin,
                    targetRepsMax: exercise.targetRepsMax,
                    targetRPE: exercise.targetRPE,
                    restSeconds: exercise.restSeconds
                )
                newExercise.notes = exercise.notes
                newExercise.superset = exercise.superset
                newDay.exercises.append(newExercise)
            }

            newPlan.days.append(newDay)
        }

        modelContext.insert(newPlan)
    }

    private func deletePlan(_ plan: WorkoutPlan) {
        modelContext.delete(plan)
    }
}

// MARK: - Active Plan Card

struct ActivePlanCard: View {
    let plan: WorkoutPlan

    private var todayDay: PlanDay? {
        let weekday = Calendar.current.component(.weekday, from: .now)
        return plan.day(for: weekday)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(L10n.Plan.activePlan)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }

                    Text(plan.name)
                        .font(.title3.weight(.bold))
                }

                Spacer()

                NavigationLink {
                    PlanDetailView(plan: plan)
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Today's workout
            if let today = todayDay {
                HStack {
                    VStack(alignment: .leading) {
                        Text(L10n.Common.today)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(today.name)
                            .font(.headline)
                    }

                    Spacer()

                    if today.isRestDay {
                        Label("Rest Day", systemImage: "bed.double.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    } else {
                        Text("\(today.exercises.count) exercises")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FF6B35").opacity(0.15), Color(hex: "F7931A").opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(hex: "FF6B35").opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Plan Row View

struct PlanRowView: View {
    let plan: WorkoutPlan
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Plan icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: plan.difficulty.color).opacity(0.2))
                        .frame(width: 50, height: 50)

                    Image(systemName: plan.targetGoal.icon)
                        .font(.title3)
                        .foregroundStyle(Color(hex: plan.difficulty.color))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(plan.name)
                            .font(.headline)

                        if plan.isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    HStack(spacing: 8) {
                        Label("\(plan.daysPerWeek)/wk", systemImage: "calendar")
                        Text("•")
                        Text(plan.difficulty.rawValue)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(plan.totalExercises)")
                        .font(.headline)
                    Text("exercises")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(width: 80, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Template Picker Sheet

struct TemplatePickerSheet: View {
    let userId: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                ForEach(PlanTemplate.allCases) { template in
                    Button {
                        createFromTemplate(template)
                    } label: {
                        HStack {
                            Image(systemName: template.icon)
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .frame(width: 40)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.rawValue)
                                    .font(.headline)
                                Text(template.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(template.daysPerWeek) days")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Choose Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func createFromTemplate(_ template: PlanTemplate) {
        let plan = WorkoutPlan(
            userId: userId,
            name: template.rawValue,
            description: template.description,
            daysPerWeek: template.daysPerWeek
        )

        // Create days based on template
        switch template {
        case .ppl:
            createPPLDays(for: plan)
        case .upperLower:
            createUpperLowerDays(for: plan)
        case .fullBody:
            createFullBodyDays(for: plan)
        case .bro:
            createBroSplitDays(for: plan)
        case .powerbuilding:
            createPowerbuildingDays(for: plan)
        }

        modelContext.insert(plan)
        dismiss()
    }

    private func createPPLDays(for plan: WorkoutPlan) {
        let dayNames = ["Rest", "Push", "Pull", "Legs", "Push", "Pull", "Legs"]
        for (index, name) in dayNames.enumerated() {
            let day = PlanDay(weekday: index + 1, name: name, isRestDay: name == "Rest")
            plan.days.append(day)
        }
    }

    private func createUpperLowerDays(for plan: WorkoutPlan) {
        let dayNames = ["Rest", "Upper", "Lower", "Rest", "Upper", "Lower", "Rest"]
        for (index, name) in dayNames.enumerated() {
            let day = PlanDay(weekday: index + 1, name: name, isRestDay: name == "Rest")
            plan.days.append(day)
        }
    }

    private func createFullBodyDays(for plan: WorkoutPlan) {
        let dayNames = ["Rest", "Full Body A", "Rest", "Full Body B", "Rest", "Full Body C", "Rest"]
        for (index, name) in dayNames.enumerated() {
            let day = PlanDay(weekday: index + 1, name: name, isRestDay: name == "Rest")
            plan.days.append(day)
        }
    }

    private func createBroSplitDays(for plan: WorkoutPlan) {
        let dayNames = ["Rest", "Chest", "Back", "Shoulders", "Arms", "Legs", "Rest"]
        for (index, name) in dayNames.enumerated() {
            let day = PlanDay(weekday: index + 1, name: name, isRestDay: name == "Rest")
            plan.days.append(day)
        }
    }

    private func createPowerbuildingDays(for plan: WorkoutPlan) {
        let dayNames = ["Rest", "Squat Focus", "Bench Focus", "Rest", "Deadlift Focus", "Volume Day", "Rest"]
        for (index, name) in dayNames.enumerated() {
            let day = PlanDay(weekday: index + 1, name: name, isRestDay: name == "Rest")
            plan.days.append(day)
        }
    }
}

// MARK: - Plan Detail View

struct PlanDetailView: View {
    @Bindable var plan: WorkoutPlan
    @State private var showEditor = false
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                planHeaderView

                // Week overview
                weekOverviewView

                // Days detail
                ForEach(plan.sortedDays) { day in
                    DayCardView(day: day)
                }
            }
            .padding()
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }

                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            PlanEditorView(userId: plan.userId, plan: plan)
        }
        .sheet(isPresented: $showShareSheet) {
            SharePlanSheet(plan: plan)
        }
    }

    private var planHeaderView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.targetGoal.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(plan.name)
                        .font(.title.weight(.bold))
                }

                Spacer()

                Image(systemName: plan.difficulty.icon)
                    .font(.title)
                    .foregroundStyle(Color(hex: plan.difficulty.color))
            }

            if let description = plan.planDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Stats
            HStack(spacing: 20) {
                StatPill(icon: "calendar", value: "\(plan.daysPerWeek)", label: "days/week")
                StatPill(icon: "figure.strengthtraining.traditional", value: "\(plan.totalExercises)", label: "exercises")
                StatPill(icon: "number", value: "\(plan.totalSets)", label: "sets")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    private var weekOverviewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Plan.weekAtAGlance)
                .font(.headline)

            HStack(spacing: 4) {
                ForEach(plan.sortedDays) { day in
                    VStack(spacing: 4) {
                        Text(day.shortWeekdayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Circle()
                            .fill(day.isRestDay ? Color.gray.opacity(0.3) : Color(hex: "FF6B35"))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Group {
                                    if day.isRestDay {
                                        Image(systemName: "bed.double.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\(day.exercises.count)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Day Card View

struct DayCardView: View {
    let day: PlanDay
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.weekdayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(day.name)
                            .font(.headline)
                    }

                    Spacer()

                    if day.isRestDay {
                        Label("Rest", systemImage: "bed.double.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    } else {
                        Text("\(day.exercises.count) exercises")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            // Exercises (when expanded)
            if isExpanded && !day.isRestDay {
                Divider()

                ForEach(day.sortedExercises) { exercise in
                    HStack {
                        Text(exercise.exerciseName)
                            .font(.subheadline)

                        Spacer()

                        Text(exercise.prescriptionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(day.isRestDay ? Color.blue.opacity(0.1) : .ultraThinMaterial)
        )
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
    }
}

// MARK: - Preview

#Preview {
    PlanLibraryView()
}
