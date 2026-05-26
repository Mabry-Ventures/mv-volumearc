import AppIntents
import Foundation
import VolumeArcCore

// VOL-212: App Intent titles, descriptions, parameter titles, dialogs,
// and shortcut short titles use `LocalizedStringResource` so the strings
// ship through the App Intents string-catalog mechanism. Shortcut phrases
// use Apple's `AppShortcutPhrase` interpolation so `.applicationName`
// remains a system token.
//
// Telemetry: each intent's `perform()` attaches `?source=intent&intent=<name>`
// to the outgoing deep link. The app's URL handler in
// `VolumeArcApp.handle(url:)` reads those query items and records an
// `intent.<name>.invoked` event so operators can see Shortcut /
// App-Intent usage alongside in-app navigation.

private enum IntentTelemetry {
    /// Add `source=intent` + `intent=<name>` query params to the URL
    /// the intent's `perform()` returns so `VolumeArcApp.handle(url:)`
    /// can emit a typed telemetry event for the invocation.
    static func attribute(_ url: URL, intent: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "source", value: "intent"))
        items.append(URLQueryItem(name: "intent", value: intent))
        components.queryItems = items
        return components.url ?? url
    }
}

struct StartNextWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Next Workout"
    static let description = IntentDescription(
        LocalizedStringResource("Open VolumeArc directly to today’s next workout.", comment: "App Intent description — start next workout")
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let workoutTitle = PlatformSurfaceDefaultsReader.loadWidgetSnapshot()?.nextWorkoutTitle
            ?? String(localized: "your next VolumeArc workout", comment: "Intent dialog fallback when no widget snapshot is cached")
        let dialogText = String(
            localized: "Opening \(workoutTitle).",
            comment: "Intent dialog: Opening <workout title>."
        )
        return .result(
            opensIntent: OpenURLIntent(
                IntentTelemetry.attribute(
                    VolumeArcDeepLink.url(for: .action(.startWorkoutSession)),
                    intent: "start_next_workout"
                )
            ),
            dialog: IntentDialog(stringLiteral: dialogText)
        )
    }
}

struct AskCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask the Coach"
    static let description = IntentDescription(
        LocalizedStringResource("Open VolumeArc Coach with a specific workout question.", comment: "App Intent description — ask coach")
    )
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("Prompt", comment: "App Intent parameter — coach prompt text"))
    var prompt: String

    init() {
        self.prompt = ""
    }

    init(prompt: String) {
        self.prompt = prompt
    }

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let fallbackPrompt = String(
            localized: "What should I do next?",
            comment: "Default coach prompt when no widget snapshot is cached"
        )
        let resolvedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (PlatformSurfaceDefaultsReader.loadWidgetSnapshot()?.coachPrompt ?? fallbackPrompt)
            : prompt
        return .result(
            opensIntent: OpenURLIntent(
                IntentTelemetry.attribute(VolumeArcDeepLink.url(for: .coach(prompt: resolvedPrompt)), intent: "ask_coach")
            ),
            dialog: IntentDialog(
                LocalizedStringResource("Opening VolumeArc Coach.", comment: "Intent dialog — opening coach")
            )
        )
    }
}

struct OpenSignalsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Training Signals"
    static let description = IntentDescription(
        LocalizedStringResource("Open VolumeArc to readiness and progression signals.", comment: "App Intent description — open signals")
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let snapshot = PlatformSurfaceDefaultsReader.loadWidgetSnapshot()
        let dialog = snapshot.map {
            String(
                localized: "Opening your signals. Readiness is \($0.readinessScore). \($0.syncSummary)",
                comment: "Intent dialog — opening signals with readiness + sync summary"
            )
        } ?? String(localized: "Opening your training signals.", comment: "Intent dialog — opening signals fallback")
        return .result(
            opensIntent: OpenURLIntent(
                IntentTelemetry.attribute(VolumeArcDeepLink.url(for: .signals), intent: "open_signals")
            ),
            dialog: IntentDialog(stringLiteral: dialog)
        )
    }
}

struct StartWorkoutSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Workout Session"
    static let description = IntentDescription(
        LocalizedStringResource("Launch VolumeArc and begin a live workout session.", comment: "App Intent description — start session")
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        .result(
            opensIntent: OpenURLIntent(
                IntentTelemetry.attribute(
                    VolumeArcDeepLink.url(for: .action(.startWorkoutSession)),
                    intent: "start_workout_session"
                )
            ),
            dialog: IntentDialog(
                LocalizedStringResource("Opening VolumeArc and starting your live session.", comment: "Intent dialog — starting session")
            )
        )
    }
}

struct LogRecommendedSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Recommended Set"
    static let description = IntentDescription(
        LocalizedStringResource("Launch VolumeArc and log the current recommended set.", comment: "App Intent description — log recommended set")
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        .result(
            opensIntent: OpenURLIntent(
                IntentTelemetry.attribute(
                    VolumeArcDeepLink.url(for: .action(.logRecommendedSet)),
                    intent: "log_recommended_set"
                )
            ),
            dialog: IntentDialog(
                LocalizedStringResource("Opening VolumeArc and logging the recommended set.", comment: "Intent dialog — logging set")
            )
        )
    }
}

struct SyncVolumeArcIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync VolumeArc"
    static let description = IntentDescription(
        LocalizedStringResource("Launch VolumeArc and run a manual cloud sync.", comment: "App Intent description — sync now")
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        .result(
            opensIntent: OpenURLIntent(
                IntentTelemetry.attribute(VolumeArcDeepLink.url(for: .action(.syncNow)), intent: "sync_now")
            ),
            dialog: IntentDialog(
                LocalizedStringResource("Opening VolumeArc and refreshing sync.", comment: "Intent dialog — refreshing sync")
            )
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
            shortTitle: LocalizedStringResource("Start Workout", comment: "App Shortcut short title - start next workout"),
            systemImageName: "figure.strengthtraining.traditional"
        )

        AppShortcut(
            intent: AskCoachIntent(prompt: "That last set felt heavy. Should I still move up?"),
            phrases: [
                "Ask \(.applicationName) coach",
                "Check my next set in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Ask Coach", comment: "App Shortcut short title - ask coach"),
            systemImageName: "waveform.and.mic"
        )

        AppShortcut(
            intent: OpenSignalsIntent(),
            phrases: [
                "Open my training signals in \(.applicationName)",
                "Show readiness in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Open Signals", comment: "App Shortcut short title - open signals"),
            systemImageName: "chart.line.uptrend.xyaxis"
        )

        AppShortcut(
            intent: StartWorkoutSessionIntent(),
            phrases: [
                "Start my live session in \(.applicationName)",
                "Begin my workout session in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Start Session", comment: "App Shortcut short title - start workout session"),
            systemImageName: "play.circle.fill"
        )

        AppShortcut(
            intent: LogRecommendedSetIntent(),
            phrases: [
                "Log my recommended set in \(.applicationName)",
                "Save my next set in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Log Set", comment: "App Shortcut short title - log recommended set"),
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: SyncVolumeArcIntent(),
            phrases: [
                "Sync \(.applicationName)",
                "Refresh my data in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Sync", comment: "App Shortcut short title - sync VolumeArc"),
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
