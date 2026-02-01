import SwiftUI
import SwiftData
import TelemetryClient

@main
struct BeastModeApp: App {
    init() {
        // Initialize analytics
        if Configuration.isAnalyticsEnabled {
            AnalyticsService.shared.configure()
        }
    }

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

    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .modelContainer(sharedModelContainer)
    }
}
