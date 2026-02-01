import AppIntents

/// App Shortcuts provider for Beast Mode
struct BeastModeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Start Workout
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start my \(.applicationName) workout",
                "Begin \(.applicationName)",
                "Time to get beastly",
                "Start lifting with \(.applicationName)",
                "Let's workout with \(.applicationName)"
            ],
            shortTitle: "Start Workout",
            systemImageName: "figure.strengthtraining.traditional"
        )

        // Quick Start
        AppShortcut(
            intent: QuickStartWorkoutIntent(),
            phrases: [
                "Quick start \(.applicationName)",
                "Jump into \(.applicationName)",
                "Beast mode now"
            ],
            shortTitle: "Quick Start",
            systemImageName: "play.fill"
        )

        // Log Set
        AppShortcut(
            intent: LogSetIntent(),
            phrases: [
                "Log a set in \(.applicationName)",
                "Record my lift with \(.applicationName)",
                "Add a set to \(.applicationName)"
            ],
            shortTitle: "Log Set",
            systemImageName: "plus.circle"
        )

        // Ask Coach
        AppShortcut(
            intent: AskCoachIntent(),
            phrases: [
                "Ask \(.applicationName) coach",
                "Get workout advice from \(.applicationName)",
                "Ask my fitness coach",
                "What does \(.applicationName) suggest"
            ],
            shortTitle: "Ask Coach",
            systemImageName: "sparkles"
        )

        // Form Tips
        AppShortcut(
            intent: GetFormTipsIntent(),
            phrases: [
                "Get form tips from \(.applicationName)",
                "How do I do this exercise",
                "Check my form with \(.applicationName)"
            ],
            shortTitle: "Form Tips",
            systemImageName: "figure.stand"
        )

        // Weekly Review
        AppShortcut(
            intent: GetWeeklyReviewIntent(),
            phrases: [
                "Get my \(.applicationName) weekly review",
                "How was my training week",
                "Review my \(.applicationName) progress"
            ],
            shortTitle: "Weekly Review",
            systemImageName: "chart.bar"
        )
    }
}

// MARK: - Spotlight Integration

struct BeastModeSpotlightDonation {
    /// Donate workout start action to Spotlight
    static func donateWorkoutStart(focusArea: String) {
        let intent = StartWorkoutIntent()
        intent.focusArea = FocusAreaEntity(id: focusArea.lowercased(), name: focusArea)

        let interaction = INInteraction(intent: convertToINIntent(intent), response: nil)
        interaction.donate { error in
            if let error = error {
                print("Failed to donate to Spotlight: \(error)")
            }
        }
    }

    /// Donate exercise logging to Spotlight
    static func donateExerciseLog(exerciseName: String) {
        let intent = GetFormTipsIntent()
        intent.exercise = ExerciseEntity(
            id: exerciseName.lowercased().replacingOccurrences(of: " ", with: "-"),
            name: exerciseName
        )

        let interaction = INInteraction(intent: convertToINIntent(intent), response: nil)
        interaction.donate { error in
            if let error = error {
                print("Failed to donate to Spotlight: \(error)")
            }
        }
    }

    private static func convertToINIntent(_ appIntent: some AppIntent) -> INIntent {
        // This is a simplified conversion - in production you'd implement proper INIntent conversion
        return INIntent()
    }
}

import Intents

// MARK: - Intent Handling

extension StartWorkoutIntent {
    /// Update suggested intents based on user behavior
    static func updateSuggestions() {
        // Get the current day's focus area and suggest starting that workout
        let today = Weekday.today

        // In production, fetch from SwiftData
        let focusAreas: [Weekday: String] = [
            .monday: "Push",
            .tuesday: "Pull",
            .wednesday: "Legs",
            .thursday: "Push",
            .friday: "Pull",
            .saturday: "Legs",
            .sunday: "Rest"
        ]

        if let focus = focusAreas[today], focus != "Rest" {
            let intent = StartWorkoutIntent()
            intent.focusArea = FocusAreaEntity(id: focus.lowercased(), name: focus)

            // Create suggestion
            let suggestion = INShortcut(intent: INIntent())
            INVoiceShortcutCenter.shared.setShortcutSuggestions([suggestion])
        }
    }
}
