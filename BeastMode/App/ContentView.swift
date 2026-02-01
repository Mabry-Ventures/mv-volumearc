// ContentView.swift
// BeastMode
// Main content view with tab navigation and celebration overlay

import SwiftUI
import SwiftData

/// Main content view for the Beast Mode app
struct ContentView: View {
    @StateObject private var celebrationCoordinator = CelebrationCoordinator()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Home/Dashboard
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            // Workout
            WorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(1)

            // Progress/Stats
            ProgressView()
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)

            // Profile/Settings
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(3)
        }
        .environmentObject(celebrationCoordinator)
        .celebrationOverlay(coordinator: celebrationCoordinator)
    }
}

// MARK: - Home View

struct HomeView: View {
    @Query private var streaks: [UserStreak]
    @Query(sort: \Workout.startedAt, order: .reverse)
    private var recentWorkouts: [Workout]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Streak display
                    StreakDisplayView()
                        .padding(.horizontal)

                    // Recent badges
                    RecentBadgesView()
                        .padding(.horizontal)

                    // Quick start workout button
                    QuickStartButton()
                        .padding(.horizontal)

                    // Recent workouts
                    RecentWorkoutsSection(workouts: Array(recentWorkouts.prefix(5)))
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Beast Mode")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BadgeCollectionView()
                    } label: {
                        Image(systemName: "trophy.fill")
                    }
                }
            }
        }
    }
}

// MARK: - Quick Start Button

struct QuickStartButton: View {
    var body: some View {
        NavigationLink {
            WorkoutView()
        } label: {
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.title2)

                VStack(alignment: .leading) {
                    Text("Start Workout")
                        .font(.headline)
                    Text("Begin a new training session")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FF6B35"), Color(hex: "F7931A")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
    }
}

// MARK: - Recent Workouts Section

struct RecentWorkoutsSection: View {
    let workouts: [Workout]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Workouts")
                .font(.headline)

            if workouts.isEmpty {
                ContentUnavailableView {
                    Label("No Workouts Yet", systemImage: "figure.strengthtraining.traditional")
                } description: {
                    Text("Start your first workout to see it here.")
                }
                .frame(height: 150)
            } else {
                ForEach(workouts) { workout in
                    WorkoutRowView(workout: workout)
                }
            }
        }
    }
}

// MARK: - Workout Row View

struct WorkoutRowView: View {
    let workout: Workout

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name ?? "Workout")
                    .font(.headline)

                Text(workout.startedAt.formatted(.dateTime.weekday().month().day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(workout.exerciseCount) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if workout.totalVolume > 0 {
                    Text("\(Int(workout.totalVolume)) lbs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Workout View

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var celebrationCoordinator: CelebrationCoordinator
    @Query private var profiles: [UserProfile]

    @State private var activeWorkout: Workout?
    @State private var showExerciseSelector = false

    var body: some View {
        NavigationStack {
            if let workout = activeWorkout {
                ActiveWorkoutView(workout: workout)
            } else {
                StartWorkoutView(onStart: startWorkout)
            }
        }
    }

    private func startWorkout() {
        guard let userId = profiles.first?.id else { return }

        let workout = Workout(userId: userId)
        modelContext.insert(workout)
        activeWorkout = workout
    }
}

// MARK: - Start Workout View

struct StartWorkoutView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 80))
                .foregroundStyle(.orange)

            Text("Ready to Train?")
                .font(.title.weight(.bold))

            Text("Start a new workout session to begin tracking your lifts.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                onStart()
            } label: {
                Text("Start Workout")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "FF6B35"))
                    )
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .navigationTitle("Workout")
    }
}

// MARK: - Active Workout View

struct ActiveWorkoutView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var modelContext
    @State private var showAddExercise = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Workout header
                WorkoutHeaderView(workout: workout)

                // Exercises
                ForEach(workout.exercises.sorted(by: { $0.order < $1.order })) { exercise in
                    ExerciseCardView(exercise: exercise)
                }

                // Add exercise button
                Button {
                    showAddExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                                .foregroundStyle(.secondary)
                        )
                }
                .padding(.top)
            }
            .padding()
        }
        .navigationTitle(workout.name ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") {
                    finishWorkout()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showAddExercise) {
            ExerciseSelectorView(workout: workout)
        }
    }

    private func finishWorkout() {
        workout.completedAt = .now
        workout.totalVolume = workout.calculateTotalVolume()
        workout.exerciseCount = workout.exercises.count
        workout.setCount = workout.exercises.reduce(0) { $0 + $1.sets.count }
    }
}

// MARK: - Workout Header View

struct WorkoutHeaderView: View {
    let workout: Workout
    @State private var elapsed: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Duration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatDuration(elapsed))
                    .font(.title2.weight(.semibold).monospacedDigit())
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("Volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(workout.calculateTotalVolume())) lbs")
                    .font(.title2.weight(.semibold))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .onReceive(timer) { _ in
            elapsed = Date.now.timeIntervalSince(workout.startedAt)
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Exercise Card View

struct ExerciseCardView: View {
    @Bindable var exercise: WorkoutExercise
    @EnvironmentObject private var celebrationCoordinator: CelebrationCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Exercise header
            HStack {
                Text(exercise.exerciseName)
                    .font(.headline)

                Spacer()

                Menu {
                    Button("Add Set", systemImage: "plus") {
                        addSet()
                    }
                    Button("Remove Exercise", systemImage: "trash", role: .destructive) {
                        // Remove exercise
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }

            // Sets
            ForEach(exercise.sets.sorted(by: { $0.setNumber < $1.setNumber })) { set in
                SetInputView(
                    set: set,
                    exerciseType: .weightAndReps,  // Would be determined by exercise
                    exerciseName: exercise.exerciseName
                )
            }

            // Add set button
            Button {
                addSet()
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.blue.opacity(0.1))
                    )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
    }

    private func addSet() {
        let newSet = SetLog(
            exerciseId: exercise.exerciseId,
            setNumber: exercise.sets.count + 1
        )
        exercise.sets.append(newSet)
    }
}

// MARK: - Exercise Selector View

struct ExerciseSelectorView: View {
    let workout: Workout
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var exercises: [Exercise]

    @State private var searchText = ""

    private var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return exercises
        }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filteredExercises) { exercise in
                Button {
                    addExercise(exercise)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(exercise.name)
                                .font(.headline)
                            Text(exercise.category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if exercise.isCompound {
                            Text("Compound")
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.orange.opacity(0.2))
                                )
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
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

    private func addExercise(_ exercise: Exercise) {
        let workoutExercise = WorkoutExercise(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            order: workout.exercises.count
        )

        // Add initial set
        let firstSet = SetLog(exerciseId: exercise.id, setNumber: 1)
        workoutExercise.sets.append(firstSet)

        workout.exercises.append(workoutExercise)
        dismiss()
    }
}

// MARK: - Progress View (Placeholder)

struct ProgressView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    StreakStatsView()
                        .padding(.horizontal)

                    // PR History would go here
                    Text("PR History Coming Soon")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical)
            }
            .navigationTitle("Progress")
        }
    }
}

// MARK: - Profile View

struct ProfileView: View {
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? {
        profiles.first
    }

    var body: some View {
        NavigationStack {
            List {
                if let profile = profile {
                    Section {
                        HStack {
                            Circle()
                                .fill(.orange.gradient)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Text(String(profile.displayName.prefix(1)))
                                        .font(.title.weight(.bold))
                                        .foregroundStyle(.white)
                                )

                            VStack(alignment: .leading) {
                                Text(profile.displayName)
                                    .font(.headline)
                                if let email = profile.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Section("Preferences") {
                        NavigationLink {
                            RestTimerSettingsView(profile: profile)
                        } label: {
                            Label("Rest Timer", systemImage: "timer")
                        }

                        Picker(selection: Binding(
                            get: { profile.unitSystemEnum },
                            set: { profile.unitSystemEnum = $0 }
                        )) {
                            ForEach(UnitSystem.allCases, id: \.self) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        } label: {
                            Label("Units", systemImage: "scalemass")
                        }
                    }

                    Section("Achievements") {
                        NavigationLink {
                            BadgeCollectionView()
                        } label: {
                            Label("Badges", systemImage: "trophy.fill")
                        }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
