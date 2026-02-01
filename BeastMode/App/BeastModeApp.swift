// BeastModeApp.swift
// BeastMode
// Main app entry point

import SwiftUI
import SwiftData
import os

@main
struct BeastModeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var deepLinkHandler = DeepLinkHandler()
    @StateObject private var authenticationManager = AuthenticationManager()
    @StateObject private var onboardingManager = OnboardingManager()

    init() {
        // Configure logging
        Logger.app.info("Beast Mode app initializing")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch appState.initializationState {
                case .initializing:
                    AppLoadingView()
                case .failed(let error):
                    DatabaseErrorView(error: error, onRetry: {
                        Task { await appState.initialize() }
                    })
                case .ready:
                    if let container = appState.modelContainer {
                        // Show onboarding for new users, main app for returning users
                        if onboardingManager.isOnboardingComplete {
                            mainAppView(container: container)
                        } else {
                            OnboardingView()
                                .environmentObject(authenticationManager)
                                .environmentObject(onboardingManager)
                                .onChange(of: onboardingManager.isOnboardingComplete) { _, isComplete in
                                    if isComplete {
                                        Logger.app.info("Onboarding completed, showing main app")
                                    }
                                }
                        }
                    }
                }
            }
            .task {
                await appState.initialize()
            }
        }
    }

    @ViewBuilder
    private func mainAppView(container: ModelContainer) -> some View {
        ContentView()
            .environmentObject(deepLinkHandler)
            .environmentObject(authenticationManager)
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
            .modelContainer(container)
    }
}

// MARK: - App Initialization State

enum AppInitializationState {
    case initializing
    case ready
    case failed(AppInitializationError)
}

enum AppInitializationError: LocalizedError {
    case databaseInitializationFailed(underlying: Error)
    case migrationFailed(underlying: Error)
    case corruptedData

    var errorDescription: String? {
        switch self {
        case .databaseInitializationFailed(let error):
            return "Failed to initialize database: \(error.localizedDescription)"
        case .migrationFailed(let error):
            return "Failed to migrate data: \(error.localizedDescription)"
        case .corruptedData:
            return "Database appears to be corrupted"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .databaseInitializationFailed:
            return "Try restarting the app. If the problem persists, you may need to reinstall."
        case .migrationFailed:
            return "Your data format may be incompatible. Please contact support."
        case .corruptedData:
            return "Try clearing app data or reinstalling the app."
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published private(set) var initializationState: AppInitializationState = .initializing
    @Published private(set) var modelContainer: ModelContainer?

    func initialize() async {
        guard case .initializing = initializationState else {
            // Already initialized or failed, reset to initializing for retry
            if case .failed = initializationState {
                initializationState = .initializing
            } else {
                return
            }
        }

        Logger.app.info("Starting database initialization with migration support")

        do {
            // Use ModelContainerFactory for proper migration handling
            let container = try ModelContainerFactory.createContainer()

            // Initialize default data
            await initializeDefaultData(container: container)

            self.modelContainer = container
            self.initializationState = .ready

            Logger.app.info("Database initialization successful")

        } catch {
            Logger.app.error("Database initialization failed: \(error.localizedDescription)")
            CrashReporter.shared.recordError(error, context: "Database initialization")

            initializationState = .failed(.databaseInitializationFailed(underlying: error))
        }
    }

    private func initializeDefaultData(container: ModelContainer) async {
        let context = container.mainContext

        // Check if we have a user profile
        let profileDescriptor = FetchDescriptor<UserProfile>()
        let profiles = try? context.fetch(profileDescriptor)

        if profiles?.isEmpty ?? true {
            Logger.app.info("Creating default user profile")

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
            Logger.app.info("Seeding default exercises")
            seedDefaultExercises(context: context)
        }

        do {
            try context.save()
        } catch {
            Logger.app.error("Failed to save default data: \(error.localizedDescription)")
        }
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

// MARK: - App Loading View

struct AppLoadingView: View {
    @State private var animationPhase = 0.0

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "FF6B35"), Color(hex: "F7931A")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse, options: .repeating)

            Text("Beast Mode")
                .font(.largeTitle.weight(.bold))

            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color(hex: "FF6B35"))

            Text("Loading your training data...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Database Error View

struct DatabaseErrorView: View {
    let error: AppInitializationError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Something Went Wrong")
                .font(.title2.weight(.bold))

            Text(error.localizedDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button {
                    onRetry()
                } label: {
                    Text("Try Again")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "FF6B35"))
                        )
                }

                Button {
                    // Open support or help
                    if let url = URL(string: "mailto:support@beastmode.app") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Contact Support")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

// MARK: - Logger Extension

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.beastmode.app"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let database = Logger(subsystem: subsystem, category: "Database")
    static let authentication = Logger(subsystem: subsystem, category: "Authentication")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let healthKit = Logger(subsystem: subsystem, category: "HealthKit")
    static let workout = Logger(subsystem: subsystem, category: "Workout")
}
