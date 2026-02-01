import AppIntents
import SwiftUI

/// Intent to start a workout session
struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Workout"
    static var description = IntentDescription("Begin today's Beast Mode workout")

    static var openAppWhenRun = true

    @Parameter(title: "Focus Area")
    var focusArea: FocusAreaEntity?

    func perform() async throws -> some IntentResult & OpensIntent {
        // The app will handle starting the workout when opened
        // Store the focus area preference if provided
        if let focus = focusArea {
            UserDefaults.standard.set(focus.name, forKey: "pendingWorkoutFocusArea")
        }

        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$focusArea) workout")
    }
}

// MARK: - Focus Area Entity

struct FocusAreaEntity: AppEntity {
    var id: String
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Focus Area"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var defaultQuery = FocusAreaQuery()
}

struct FocusAreaQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FocusAreaEntity] {
        let allAreas = await suggestedEntities()
        return allAreas.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async -> [FocusAreaEntity] {
        [
            FocusAreaEntity(id: "push", name: "Push"),
            FocusAreaEntity(id: "pull", name: "Pull"),
            FocusAreaEntity(id: "legs", name: "Legs"),
            FocusAreaEntity(id: "core", name: "Core"),
            FocusAreaEntity(id: "upper", name: "Upper Body"),
            FocusAreaEntity(id: "lower", name: "Lower Body"),
            FocusAreaEntity(id: "full", name: "Full Body")
        ]
    }
}

// MARK: - Quick Start Intent (no parameters)

struct QuickStartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Start Workout"
    static var description = IntentDescription("Immediately start today's planned workout")

    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        UserDefaults.standard.set(true, forKey: "quickStartWorkout")
        return .result()
    }
}
