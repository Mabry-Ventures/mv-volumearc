import AppIntents
import SwiftUI

/// Intent to ask the AI coach a question
struct AskCoachIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Beast Mode Coach"
    static var description = IntentDescription("Get AI coaching advice for your training")

    @Parameter(title: "Question")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let response = try await AICoachService.shared.askCoach(question: question)
            return .result(dialog: "\(response)")
        } catch {
            return .result(dialog: "Sorry, I couldn't get an answer right now. Please try again later.")
        }
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Ask coach: \(\.$question)")
    }
}

// MARK: - Get Form Tips Intent

struct GetFormTipsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Form Tips"
    static var description = IntentDescription("Get form tips for an exercise")

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let response = try await AICoachService.shared.getFormCheck(for: exercise.name)
            return .result(dialog: "\(response.rawText)")
        } catch {
            return .result(dialog: "Sorry, I couldn't get form tips right now. Please try again later.")
        }
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Get form tips for \(\.$exercise)")
    }
}

// MARK: - Exercise Entity

struct ExerciseEntity: AppEntity {
    var id: String
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Exercise"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var defaultQuery = ExerciseEntityQuery()
}

struct ExerciseEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ExerciseEntity] {
        let allExercises = await suggestedEntities()
        return allExercises.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async -> [ExerciseEntity] {
        // Common exercises
        [
            ExerciseEntity(id: "bench-press", name: "Bench Press"),
            ExerciseEntity(id: "squat", name: "Squat"),
            ExerciseEntity(id: "deadlift", name: "Deadlift"),
            ExerciseEntity(id: "overhead-press", name: "Overhead Press"),
            ExerciseEntity(id: "barbell-row", name: "Barbell Row"),
            ExerciseEntity(id: "pull-up", name: "Pull-ups"),
            ExerciseEntity(id: "dip", name: "Dips"),
            ExerciseEntity(id: "lunge", name: "Lunges"),
            ExerciseEntity(id: "romanian-deadlift", name: "Romanian Deadlift"),
            ExerciseEntity(id: "lat-pulldown", name: "Lat Pulldown")
        ]
    }

    func defaultResult() async -> ExerciseEntity? {
        ExerciseEntity(id: "bench-press", name: "Bench Press")
    }
}

// MARK: - Get Weekly Review Intent

struct GetWeeklyReviewIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Weekly Review"
    static var description = IntentDescription("Get an AI-powered review of your training week")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // In production, this would fetch actual logs from DataService
        return .result(dialog: "Open Beast Mode to see your full weekly review with detailed analytics and personalized insights.")
    }
}
