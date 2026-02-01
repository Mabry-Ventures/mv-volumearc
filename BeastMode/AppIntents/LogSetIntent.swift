import AppIntents
import SwiftUI

/// Intent to log a completed set
struct LogSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Set"
    static var description = IntentDescription("Log a completed set to your workout")

    @Parameter(title: "Exercise")
    var exercise: String

    @Parameter(title: "Weight", description: "Weight in pounds")
    var weight: Double

    @Parameter(title: "Reps")
    var reps: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // In production, this would interact with DataService
        // For now, we'll store in UserDefaults for the app to pick up
        let setData: [String: Any] = [
            "exercise": exercise,
            "weight": weight,
            "reps": reps,
            "timestamp": Date().timeIntervalSince1970
        ]

        if var pendingSets = UserDefaults.standard.array(forKey: "pendingSetsFromShortcuts") as? [[String: Any]] {
            pendingSets.append(setData)
            UserDefaults.standard.set(pendingSets, forKey: "pendingSetsFromShortcuts")
        } else {
            UserDefaults.standard.set([setData], forKey: "pendingSetsFromShortcuts")
        }

        return .result(dialog: "Logged \(reps) reps at \(Int(weight)) lbs for \(exercise)")
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$reps) reps of \(\.$exercise) at \(\.$weight) lbs")
    }
}

// MARK: - Log Cardio Intent

struct LogCardioIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Cardio"
    static var description = IntentDescription("Log a cardio session")

    @Parameter(title: "Activity")
    var activity: CardioActivityEntity

    @Parameter(title: "Duration (minutes)")
    var duration: Int

    @Parameter(title: "Distance (miles)", default: nil)
    var distance: Double?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var message = "Logged \(duration) minutes of \(activity.name)"
        if let distance = distance {
            message += " (\(String(format: "%.1f", distance)) miles)"
        }

        return .result(dialog: "\(message)")
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$duration) minutes of \(\.$activity)")
    }
}

// MARK: - Cardio Activity Entity

struct CardioActivityEntity: AppEntity {
    var id: String
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Cardio Activity"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var defaultQuery = CardioActivityQuery()
}

struct CardioActivityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CardioActivityEntity] {
        let allActivities = await suggestedEntities()
        return allActivities.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async -> [CardioActivityEntity] {
        [
            CardioActivityEntity(id: "running", name: "Running"),
            CardioActivityEntity(id: "cycling", name: "Cycling"),
            CardioActivityEntity(id: "rowing", name: "Rowing"),
            CardioActivityEntity(id: "elliptical", name: "Elliptical"),
            CardioActivityEntity(id: "stairmaster", name: "Stair Climber"),
            CardioActivityEntity(id: "walking", name: "Walking")
        ]
    }
}
