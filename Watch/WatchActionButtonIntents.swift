import AppIntents
import Foundation
import VolumeArcCore

#if canImport(WatchKit)
import WatchKit
#endif

enum VolumeArcActionButtonActionName {
    static let startActiveWorkout = "volumearc.start-active-workout"
    static let logNextSet = "volumearc.log-next-set"
}

enum VolumeArcActionButtonWorkoutStyle: String, AppEnum {
    case strength

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("VolumeArc Workout", comment: "Action Button workout style type")
    )

    static var caseDisplayRepresentations: [VolumeArcActionButtonWorkoutStyle: DisplayRepresentation] {
        [
            .strength: DisplayRepresentation(
                title: LocalizedStringResource("VolumeArc Strength Session", comment: "Action Button workout style")
            ),
        ]
    }
}

struct VolumeArcStartActionButtonWorkoutIntent: StartWorkoutIntent {
    static let title: LocalizedStringResource = "Start VolumeArc Workout"
    static let description = IntentDescription(
        LocalizedStringResource(
            "Start the next prescribed VolumeArc workout from the Action Button.",
            comment: "Action Button start workout intent description"
        )
    )
    static let suggestedWorkouts: [Self] = [Self(workoutStyle: .strength)]
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("Workout", comment: "Action Button workout style parameter"))
    var workoutStyle: VolumeArcActionButtonWorkoutStyle

    init() {
        workoutStyle = .strength
    }

    init(workoutStyle: VolumeArcActionButtonWorkoutStyle) {
        self.workoutStyle = workoutStyle
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource("VolumeArc Workout", comment: "Action Button start workout display title")
        )
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await WatchActionButtonRuntime.shared.fire(
            .startActiveWorkout,
            actionName: VolumeArcActionButtonActionName.startActiveWorkout
        )
        return .result(
            actionButtonIntent: VolumeArcLogNextSetActionButtonIntent(),
            activityIdentifier: "volumearc.active-workout",
            dialog: IntentDialog(
                LocalizedStringResource("Starting VolumeArc workout.", comment: "Action Button start workout dialog")
            )
        )
    }
}

struct VolumeArcLogNextSetActionButtonIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Next VolumeArc Set"
    static let description = IntentDescription(
        LocalizedStringResource(
            "Log the next prescribed set during an active VolumeArc workout.",
            comment: "Action Button log next set intent description"
        )
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await WatchActionButtonRuntime.shared.fire(
            .logNextSet,
            actionName: VolumeArcActionButtonActionName.logNextSet
        )
        return .result(
            dialog: IntentDialog(
                LocalizedStringResource("Logging next VolumeArc set.", comment: "Action Button log next set dialog")
            )
        )
    }
}

enum WatchActionButtonCommand: String, Codable, Sendable, Equatable {
    case startActiveWorkout
    case logNextSet
}

struct WatchActionButtonCommandRecord: Codable, Sendable, Equatable {
    let command: WatchActionButtonCommand
    let actionName: String
    let queuedAt: Date

    init(command: WatchActionButtonCommand, actionName: String, queuedAt: Date = .now) {
        self.command = command
        self.actionName = actionName
        self.queuedAt = queuedAt
    }
}

protocol WatchActionButtonCommandStoring: Sendable {
    func enqueue(_ record: WatchActionButtonCommandRecord) async
    func drain() async -> [WatchActionButtonCommandRecord]
}

protocol WatchActionButtonNextActionDonating: Sendable {
    func donateLogNextSet() async
}

struct AppIntentActionButtonNextActionDonor: WatchActionButtonNextActionDonating {
    func donateLogNextSet() async {
        _ = try? await VolumeArcLogNextSetActionButtonIntent().donate()
    }
}

actor UserDefaultsActionButtonCommandStore: WatchActionButtonCommandStoring {
    static let shared = UserDefaultsActionButtonCommandStore()

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: sending UserDefaults = .standard,
        key: String = "com.mabryventures.VolumeArc.watch.actionButton.pendingCommands"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func enqueue(_ record: WatchActionButtonCommandRecord) async {
        var records = loadRecords()
        records.append(record)
        save(records)
        NotificationCenter.default.post(name: .volumeArcWatchActionButtonCommandQueued, object: nil)
    }

    func drain() async -> [WatchActionButtonCommandRecord] {
        let records = loadRecords()
        defaults.removeObject(forKey: key)
        return records
    }

    private func loadRecords() -> [WatchActionButtonCommandRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([WatchActionButtonCommandRecord].self, from: data)
        else { return [] }
        return records
    }

    private func save(_ records: [WatchActionButtonCommandRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}

actor WatchActionButtonRuntime {
    static let shared = WatchActionButtonRuntime()

    private var commandStore: any WatchActionButtonCommandStoring
    private var telemetrySink: any TelemetrySink

    init(
        commandStore: any WatchActionButtonCommandStoring = UserDefaultsActionButtonCommandStore.shared,
        telemetrySink: any TelemetrySink = UserDefaultsTelemetrySink()
    ) {
        self.commandStore = commandStore
        self.telemetrySink = telemetrySink
    }

    func fire(_ command: WatchActionButtonCommand, actionName: String) async {
        telemetrySink.record(
            TelemetryEvent(
                category: "watch.action_button",
                name: "fired",
                severity: .info,
                message: "Apple Watch Action Button fired.",
                metadata: ["action": actionName]
            )
        )
        await commandStore.enqueue(
            WatchActionButtonCommandRecord(command: command, actionName: actionName)
        )
    }

    #if DEBUG
    func configureForTesting(
        commandStore: any WatchActionButtonCommandStoring,
        telemetrySink: any TelemetrySink
    ) {
        self.commandStore = commandStore
        self.telemetrySink = telemetrySink
    }

    func resetForTesting() {
        commandStore = UserDefaultsActionButtonCommandStore.shared
        telemetrySink = UserDefaultsTelemetrySink()
    }
    #endif
}

enum WatchActionButtonFeedback: Sendable, Equatable {
    case acknowledged
    case failed
    case formSolid
    case formReview
    case formInconclusive
    case resultPending
}

protocol WatchActionButtonHapticPlaying: Sendable {
    func play(_ feedback: WatchActionButtonFeedback) async
}

struct SystemWatchActionButtonHaptics: WatchActionButtonHapticPlaying {
    func play(_ feedback: WatchActionButtonFeedback) async {
        #if canImport(WatchKit)
        let haptics: [WKHapticType] = switch feedback {
        case .acknowledged:
            [.success]
        case .failed:
            [.failure]
        case .formSolid:
            [.success, .success, .success]
        case .formReview:
            [.retry, .retry, .retry, .retry, .retry]
        case .formInconclusive:
            [.failure, .retry]
        case .resultPending:
            [.directionUp, .directionDown]
        }
        for haptic in haptics {
            await MainActor.run {
                WKInterfaceDevice.current().play(haptic)
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        #else
        _ = feedback
        #endif
    }
}

extension Notification.Name {
    static let volumeArcWatchActionButtonCommandQueued = Notification.Name(
        "VolumeArc.WatchActionButtonCommandQueued"
    )
}

enum WatchActionButtonAvailability {
    // shouldShowBindingHint uses isLikelyUltra's "ultra" string heuristic because WatchKit
    // does not expose a stable Ultra capability flag; revisit this if Apple renames future models.
    static var shouldShowBindingHint: Bool {
        #if canImport(WatchKit)
        isLikelyUltra(
            model: WKInterfaceDevice.current().model,
            localizedModel: WKInterfaceDevice.current().localizedModel
        )
        #else
        false
        #endif
    }

    static func isLikelyUltra(model: String, localizedModel: String) -> Bool {
        [model, localizedModel].contains { value in
            value.localizedCaseInsensitiveContains("ultra")
        }
    }
}
