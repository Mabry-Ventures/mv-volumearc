import SwiftUI
import SwiftData

/// Weekly plan view showing the 7-day workout schedule
struct WeeklyPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<WorkoutPlan> { $0.isActive }, sort: \WorkoutPlan.createdAt)
    private var activePlans: [WorkoutPlan]

    @State private var selectedDay: PlannedDay?
    @State private var showingExerciseInfo: PlannedExercise?
    @State private var showingResetConfirmation = false

    private var activePlan: WorkoutPlan? {
        activePlans.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let plan = activePlan {
                    weeklyPlanContent(plan)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Weekly Plan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Reset to Beast Mode Default", systemImage: "arrow.counterclockwise") {
                            showingResetConfirmation = true
                        }
                        Button("Import Plan...", systemImage: "square.and.arrow.down") {
                            // Import action
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "Reset Workout Plan?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset to Default", role: .destructive) {
                    resetToDefaultPlan()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will replace your current plan with the default Beast Mode split.")
            }
            .sheet(item: $showingExerciseInfo) { exercise in
                ExerciseInfoSheet(exercise: exercise)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private func weeklyPlanContent(_ plan: WorkoutPlan) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(plan.sortedDays) { day in
                    DayCardView(
                        day: day,
                        onExerciseInfoTap: { exercise in
                            showingExerciseInfo = exercise
                        }
                    )
                    .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.8)
                            .scaleEffect(phase.isIdentity ? 1 : 0.95)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal, 20)
        .background {
            LinearGradient.beastBackgroundGradient
                .ignoresSafeArea()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Workout Plan")
                .font(.beastTitle2)

            Text("Create or load a workout plan to get started")
                .font(.beastBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TintedGlassButton("Load Beast Mode Split", icon: "dumbbell.fill") {
                resetToDefaultPlan()
            }
            .padding(.top, 20)
        }
        .padding()
    }

    private func resetToDefaultPlan() {
        // Delete existing active plans
        for plan in activePlans {
            modelContext.delete(plan)
        }

        // Load default plan from JSON
        DefaultPlanLoader.loadDefaultPlan(into: modelContext)
    }
}

// MARK: - Day Card View

struct DayCardView: View {
    @Bindable var day: PlannedDay
    var onExerciseInfoTap: ((PlannedExercise) -> Void)?

    private var isToday: Bool {
        day.weekday == Weekday.today
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.weekday.fullName)
                        .font(.beastHeadline)
                        .foregroundStyle(isToday ? .beastPrimary : .primary)

                    Text(day.focusArea)
                        .font(.beastTitle2)
                }

                Spacer()

                if isToday {
                    Text("TODAY")
                        .font(.beastCaption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.beastPrimary.opacity(0.2), in: Capsule())
                        .foregroundStyle(.beastPrimary)
                }
            }

            Divider()

            // Exercises
            if day.isRestDay {
                restDayContent
            } else {
                exercisesList
            }

            Spacer(minLength: 0)

            // Footer
            if !day.isRestDay {
                HStack {
                    Label("\(day.exercises.count) exercises", systemImage: "list.bullet")
                    Spacer()
                    Label("\(day.totalSets) sets", systemImage: "number")
                }
                .font(.beastCaption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassBackground(cornerRadius: 24)
    }

    private var restDayContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bed.double.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Rest & Recover")
                .font(.beastHeadline)
                .foregroundStyle(.secondary)

            Text("Your muscles grow during rest. Stay active with light movement if desired.")
                .font(.beastCaption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var exercisesList: some View {
        VStack(spacing: 12) {
            ForEach(day.sortedExercises) { exercise in
                ExerciseRowView(
                    exercise: exercise,
                    onInfoTap: {
                        onExerciseInfoTap?(exercise)
                    }
                )
            }
        }
    }
}

// MARK: - Exercise Row View

struct ExerciseRowView: View {
    @Bindable var exercise: PlannedExercise
    var onInfoTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Exercise type icon
            Image(systemName: exercise.exerciseType.icon)
                .font(.system(size: 14))
                .foregroundStyle(.beastPrimary)
                .frame(width: 24)

            // Exercise name
            Text(exercise.name)
                .font(.beastBody)
                .lineLimit(1)

            Spacer()

            // Sets x Reps
            Text(exercise.summaryString)
                .font(.beastCaption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())

            // Info button
            Button {
                onInfoTap?()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Exercise Info Sheet

struct ExerciseInfoSheet: View {
    let exercise: PlannedExercise
    @State private var exerciseInfo: ExerciseInfo?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Label(exercise.exerciseType.displayName, systemImage: exercise.exerciseType.icon)
                            .font(.beastCaption)
                            .foregroundStyle(.secondary)

                        Text(exercise.name)
                            .font(.beastTitle)

                        Text(exercise.summaryString)
                            .font(.beastBody)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // AI-generated info
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Getting exercise info...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if let info = exerciseInfo {
                        Text(info.rawText)
                            .font(.beastBody)
                    } else {
                        Text("Tap the button below to get AI-powered exercise tips.")
                            .font(.beastBody)
                            .foregroundStyle(.secondary)

                        TintedGlassButton("Get Exercise Tips", icon: "sparkles") {
                            loadExerciseInfo()
                        }
                    }

                    if let notes = exercise.notes, !notes.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.beastHeadline)
                            Text(notes)
                                .font(.beastBody)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Exercise Info")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func loadExerciseInfo() {
        isLoading = true
        Task {
            do {
                let info = try await AICoachService.shared.getExerciseInfo(for: exercise.name)
                await MainActor.run {
                    self.exerciseInfo = info
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WeeklyPlanView()
        .modelContainer(for: [WorkoutPlan.self, PlannedDay.self, PlannedExercise.self], inMemory: true)
}
