// BeastModeApp.swift
// BeastMode
// Main app entry point

import SwiftUI
import SwiftData

@main
struct BeastModeApp: App {
    let modelContainer: ModelContainer
    @StateObject private var deepLinkHandler = DeepLinkHandler()

    init() {
        do {
            // Configure the schema with all models
            let schema = Schema([
                UserProfile.self,
                UserStreak.self,
                Exercise.self,
                Workout.self,
                WorkoutExercise.self,
                SetLog.self,
                PersonalRecord.self,
                WorkoutPlan.self,
                PlanDay.self,
                PlanExercise.self
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )

            // Initialize default data if needed
            Task {
                await initializeDefaultData()
            }
        } catch {
            fatalError("Failed to initialize model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deepLinkHandler)
                .onOpenURL { url in
                    deepLinkHandler.handleURL(url)
                }
                .sheet(isPresented: $deepLinkHandler.showImportSheet) {
                    if let url = deepLinkHandler.pendingImport {
                        DeepLinkImportView(url: url)
                            .onDisappear {
                                deepLinkHandler.clearPendingImport()
                            }
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private func initializeDefaultData() async {
        let context = modelContainer.mainContext

        // Check if we have a user profile
        let profileDescriptor = FetchDescriptor<UserProfile>()
        let profiles = try? context.fetch(profileDescriptor)

        if profiles?.isEmpty ?? true {
            // Create default profile
            let defaultProfile = UserProfile(displayName: "Athlete")
            context.insert(defaultProfile)

            // Create default streak
            let defaultStreak = UserStreak(userId: defaultProfile.id)
            context.insert(defaultStreak)
        }

        // Check if we have exercises
        let exerciseDescriptor = FetchDescriptor<Exercise>()
        let exercises = try? context.fetch(exerciseDescriptor)

        if exercises?.isEmpty ?? true {
            // Seed default exercises
            seedDefaultExercises(context: context)
        }

        try? context.save()
    }

    private func seedDefaultExercises(context: ModelContext) {
        let defaultExercises: [(String, ExerciseCategory, Bool, [String])] = [
            // Chest
            ("Barbell Bench Press", .chest, true, ["Chest", "Triceps", "Shoulders"]),
            ("Incline Dumbbell Press", .chest, true, ["Upper Chest", "Shoulders", "Triceps"]),
            ("Dumbbell Flyes", .chest, false, ["Chest"]),
            ("Cable Crossovers", .chest, false, ["Chest"]),
            ("Push-ups", .chest, true, ["Chest", "Triceps", "Core"]),

            // Back
            ("Deadlift", .back, true, ["Back", "Glutes", "Hamstrings", "Core"]),
            ("Barbell Rows", .back, true, ["Back", "Biceps"]),
            ("Pull-ups", .back, true, ["Back", "Biceps"]),
            ("Lat Pulldown", .back, true, ["Lats", "Biceps"]),
            ("Seated Cable Rows", .back, true, ["Back", "Biceps"]),
            ("Dumbbell Rows", .back, true, ["Back", "Biceps"]),

            // Shoulders
            ("Overhead Press", .shoulders, true, ["Shoulders", "Triceps"]),
            ("Lateral Raises", .shoulders, false, ["Side Delts"]),
            ("Front Raises", .shoulders, false, ["Front Delts"]),
            ("Face Pulls", .shoulders, false, ["Rear Delts", "Traps"]),
            ("Arnold Press", .shoulders, true, ["Shoulders"]),

            // Legs
            ("Barbell Squats", .legs, true, ["Quads", "Glutes", "Hamstrings", "Core"]),
            ("Leg Press", .legs, true, ["Quads", "Glutes"]),
            ("Romanian Deadlift", .legs, true, ["Hamstrings", "Glutes", "Back"]),
            ("Leg Curls", .legs, false, ["Hamstrings"]),
            ("Leg Extensions", .legs, false, ["Quads"]),
            ("Calf Raises", .legs, false, ["Calves"]),
            ("Bulgarian Split Squats", .legs, true, ["Quads", "Glutes"]),

            // Biceps
            ("Barbell Curls", .biceps, false, ["Biceps"]),
            ("Dumbbell Curls", .biceps, false, ["Biceps"]),
            ("Hammer Curls", .biceps, false, ["Biceps", "Forearms"]),
            ("Preacher Curls", .biceps, false, ["Biceps"]),
            ("Concentration Curls", .biceps, false, ["Biceps"]),

            // Triceps
            ("Tricep Pushdowns", .triceps, false, ["Triceps"]),
            ("Skull Crushers", .triceps, false, ["Triceps"]),
            ("Overhead Tricep Extension", .triceps, false, ["Triceps"]),
            ("Tricep Dips", .triceps, true, ["Triceps", "Chest", "Shoulders"]),
            ("Close-Grip Bench Press", .triceps, true, ["Triceps", "Chest"]),

            // Core
            ("Plank", .core, false, ["Core"]),
            ("Crunches", .core, false, ["Abs"]),
            ("Hanging Leg Raises", .core, false, ["Abs", "Hip Flexors"]),
            ("Russian Twists", .core, false, ["Obliques"]),
            ("Ab Wheel Rollouts", .core, false, ["Core"])
        ]

        for (name, category, isCompound, muscles) in defaultExercises {
            let exercise = Exercise(
                name: name,
                category: category,
                exerciseType: .weightAndReps,
                muscleGroups: muscles,
                isCompound: isCompound,
                isCustom: false
            )
            context.insert(exercise)
        }
    }
}
