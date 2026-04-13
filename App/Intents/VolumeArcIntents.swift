import AppIntents
import Foundation
import VolumeArcCore

struct StartNextWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Next Workout"
    static let description = IntentDescription("Open VolumeArc directly to today’s next workout.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let workoutTitle = PlatformSurfaceDefaultsReader.loadWidgetSnapshot()?.nextWorkoutTitle ?? "your next VolumeArc workout"
        let dialogText = "Opening \(workoutTitle)."
        return .result(
            opensIntent: OpenURLIntent(VolumeArcDeepLink.url(for: .nextWorkout)),
            dialog: IntentDialog(stringLiteral: dialogText)
        )
    }
}

struct AskCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask the Coach"
    static let description = IntentDescription("Open VolumeArc Coach with a specific workout question.")
    static let openAppWhenRun = true

    @Parameter(title: "Prompt")
    var prompt: String

    init() {
        self.prompt = ""
    }

    init(prompt: String) {
        self.prompt = prompt
    }

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let resolvedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (PlatformSurfaceDefaultsReader.loadWidgetSnapshot()?.coachPrompt ?? "What should I do next?")
            : prompt
        return .result(
            opensIntent: OpenURLIntent(VolumeArcDeepLink.url(for: .coach(prompt: resolvedPrompt))),
            dialog: "Opening VolumeArc Coach."
        )
    }
}

struct OpenSignalsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Training Signals"
    static let description = IntentDescription("Open VolumeArc to readiness and progression signals.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let snapshot = PlatformSurfaceDefaultsReader.loadWidgetSnapshot()
        let dialog = snapshot.map { "Opening your signals. Readiness is \($0.readinessScore). \($0.syncSummary)" }
            ?? "Opening your training signals."
        return .result(
            opensIntent: OpenURLIntent(VolumeArcDeepLink.url(for: .signals)),
            dialog: IntentDialog(stringLiteral: dialog)
        )
    }
}

struct StartWorkoutSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Workout Session"
    static let description = IntentDescription("Launch VolumeArc and begin a live workout session.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        .result(
            opensIntent: OpenURLIntent(VolumeArcDeepLink.url(for: .action(.startWorkoutSession))),
            dialog: "Opening VolumeArc and starting your live session."
        )
    }
}

struct LogRecommendedSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Recommended Set"
    static let description = IntentDescription("Launch VolumeArc and log the current recommended set.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        .result(
            opensIntent: OpenURLIntent(VolumeArcDeepLink.url(for: .action(.logRecommendedSet))),
            dialog: "Opening VolumeArc and logging the recommended set."
        )
    }
}

struct SyncVolumeArcIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync VolumeArc"
    static let description = IntentDescription("Launch VolumeArc and run a manual cloud sync.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        .result(
            opensIntent: OpenURLIntent(VolumeArcDeepLink.url(for: .action(.syncNow))),
            dialog: "Opening VolumeArc and refreshing sync."
        )
    }
}

struct VolumeArcShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartNextWorkoutIntent(),
            phrases: [
                "Start my next workout in \(.applicationName)",
                "Open today’s workout in \(.applicationName)",
            ],
            shortTitle: "Start Workout",
            systemImageName: "figure.strengthtraining.traditional"
        )

        AppShortcut(
            intent: AskCoachIntent(prompt: "That last set felt heavy. Should I still move up?"),
            phrases: [
                "Ask \(.applicationName) coach",
                "Check my next set in \(.applicationName)",
            ],
            shortTitle: "Ask Coach",
            systemImageName: "waveform.and.mic"
        )

        AppShortcut(
            intent: OpenSignalsIntent(),
            phrases: [
                "Open my training signals in \(.applicationName)",
                "Show readiness in \(.applicationName)",
            ],
            shortTitle: "Open Signals",
            systemImageName: "chart.line.uptrend.xyaxis"
        )

        AppShortcut(
            intent: StartWorkoutSessionIntent(),
            phrases: [
                "Start my live session in \(.applicationName)",
                "Begin my workout session in \(.applicationName)",
            ],
            shortTitle: "Start Session",
            systemImageName: "play.circle.fill"
        )

        AppShortcut(
            intent: LogRecommendedSetIntent(),
            phrases: [
                "Log my recommended set in \(.applicationName)",
                "Save my next set in \(.applicationName)",
            ],
            shortTitle: "Log Set",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: SyncVolumeArcIntent(),
            phrases: [
                "Sync \(.applicationName)",
                "Refresh my data in \(.applicationName)",
            ],
            shortTitle: "Sync",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
