import SwiftUI
import SwiftData

@main
struct BeastModeWatchApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            WorkoutPlan.self,
            PlannedDay.self,
            PlannedExercise.self,
            DailyLog.self,
            ExerciseLog.self,
            SetLog.self,
            PersonalRecord.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.beastmode.BeastMode")
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @StateObject private var workoutManager = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if workoutManager.isWorkoutActive {
                    WorkoutSessionView()
                        .environmentObject(workoutManager)
                } else {
                    WatchHomeView()
                        .environmentObject(workoutManager)
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

/// Watch home view showing today's workout
struct WatchHomeView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<WorkoutPlan> { $0.isActive })
    private var activePlans: [WorkoutPlan]

    private var todayPlan: PlannedDay? {
        activePlans.first?.day(for: Weekday.today)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Today's focus
                if let plan = todayPlan {
                    VStack(spacing: 4) {
                        Text(plan.focusArea)
                            .font(.title2.bold())

                        Text("\(plan.exercises.count) exercises")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()

                    // Start button
                    if !plan.isRestDay {
                        Button {
                            startWorkout(plan)
                        } label: {
                            Label("Start", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .padding(.horizontal)
                    }

                    // Exercise list
                    ForEach(plan.sortedExercises.prefix(5)) { exercise in
                        HStack {
                            Text(exercise.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(exercise.summaryString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }
                } else {
                    Text("Rest Day")
                        .font(.title2.bold())

                    Text("Recovery is part of progress!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Beast Mode")
    }

    private func startWorkout(_ plan: PlannedDay) {
        Task {
            try? await workoutManager.startWorkout(for: plan)
        }
    }
}
