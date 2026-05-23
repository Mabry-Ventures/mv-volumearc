import SwiftUI
import VolumeArcCore

private struct WatchLiveStatePayload: Codable, Sendable {
    let action: String
    let exercise: String
    let targetWeight: Int
    let targetUnit: String
    let targetRepLower: Int
}

@MainActor
final class WatchWorkoutModel: ObservableObject {
    @Published private(set) var autopilot: WorkoutAutopilotState
    @Published private(set) var readiness: ReadinessAssessment
    @Published var selectedAction: WorkoutAction = .hold
    @Published var restEndsAt = Date.now.addingTimeInterval(90)
    @Published var coachPrompt = String(
        localized: "Rack is taken. Best fallback?",
        comment: "Default prompt seeded in the watch coach cue field"
    )
    @Published private(set) var sessionActive = false
    @Published private(set) var pendingSyncCount = 0
    @Published private(set) var currentHeartRateBPM: Int?
    @Published private(set) var statusMessage = String(localized: "Watch coach standing by.", comment: "Watch default status")

    private let coordinator: WatchConnectivityCoordinator
    private let stateStore: WatchSessionStateStore

    init(
        coordinator: WatchConnectivityCoordinator,
        stateStore: WatchSessionStateStore
    ) {
        let engine = ProgressionEngine()
        let starterSessions = VolumeArcProductDefaults.starterRecentSessions
        let athlete = VolumeArcProductDefaults.athleteProfile
        let primaryExercise = VolumeArcExerciseCatalog.backSquat
        let primaryHistory = VolumeArcProductDefaults.emptyHistory(for: primaryExercise)
        let readiness = engine.evaluateReadiness(
            from: starterSessions,
            athlete: athlete
        )
        self.readiness = readiness
        self.autopilot = engine.buildAutopilotState(
            for: primaryHistory,
            athlete: athlete,
            goal: VolumeArcProductDefaults.strengthGoal,
            recentSessions: starterSessions,
            memory: VolumeArcProductDefaults.coachMemory
        )
        self.coordinator = coordinator
        self.stateStore = stateStore
    }

    static func live() -> WatchWorkoutModel {
        WatchWorkoutModel(
            coordinator: WatchConnectivityCoordinator(
                transport: Self.makeTransport(),
                payloadStore: Self.makePendingPayloadStore()
            ),
            stateStore: Self.makeStateStore()
        )
    }

    func loadPersistedState() async {
        if let snapshot = await stateStore.load() {
            selectedAction = snapshot.selectedAction
            restEndsAt = snapshot.restEndsAt
            coachPrompt = snapshot.coachPrompt
            sessionActive = snapshot.sessionActive
            statusMessage = snapshot.statusMessage
        }
        await refreshConnectivity()
    }

    func refreshConnectivity() async {
        let reachable = await coordinator.isReachable()
        if reachable {
            try? await coordinator.flushPendingIfReachable()
        }
        pendingSyncCount = await coordinator.pendingPayloadCount()
        statusMessage = reachable
            ? (pendingSyncCount == 0
                ? String(localized: "Connected to iPhone for live coaching.", comment: "Watch connected status")
                : String(
                    localized: "Connected again. Replayed ^[\(pendingSyncCount) queued update](inflect: true).",
                    comment: """
                        Watch reconnect status showing how many queued \
                        updates were replayed. Uses automatic grammar \
                        inflection for singular/plural agreement.
                        """
                ))
            : String(localized: "Phone unavailable. We’ll queue key updates.", comment: "Watch disconnected status")
        await persistState()
    }

    func resetRestTimer() async {
        await ensureSessionStarted()
        restEndsAt = Date.now.addingTimeInterval(90)
        let payload = WatchPayload(
            kind: .restTimer,
            workoutID: "active-strength-session",
            body: "reset:90"
        )

        do {
            try await coordinator.send(payload)
            statusMessage = String(localized: "Rest timer synced.", comment: "Watch rest timer sync status")
        } catch {
            statusMessage = String(localized: "Rest timer updated locally. Phone sync will retry.", comment: "Watch rest timer offline status")
        }
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await persistState()
    }

    func updateHeartRate(beatsPerMinute bpm: Int?) {
        currentHeartRateBPM = bpm
    }

    func choose(_ action: WorkoutAction) async {
        await ensureSessionStarted()
        selectedAction = action
        let payload = WatchPayload(
            kind: .liveState,
            workoutID: "active-strength-session",
            body: SyncPayloadCodec.encode(
                WatchLiveStatePayload(
                    action: action.rawValue,
                    exercise: autopilot.nextExerciseName,
                    targetWeight: Int(autopilot.nextTarget.weight),
                    targetUnit: autopilot.nextTarget.unit,
                    targetRepLower: autopilot.nextTarget.repRange.lowerBound
                )
            ) ?? action.rawValue
        )

        do {
            try await coordinator.send(payload)
            statusMessage = decisionSummary(for: action)
        } catch {
            statusMessage = String(
                localized: "Decision saved on watch. We’ll sync it to phone when available.",
                comment: "Watch decision offline status"
            )
        }
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await persistState()
    }

    func startSession() async {
        guard sessionActive == false else { return }
        let payload = WatchPayload(
            kind: .startSession,
            workoutID: "active-strength-session",
            body: autopilot.nextExerciseName
        )

        do {
            try await coordinator.send(payload)
            sessionActive = true
            statusMessage = String(localized: "Live session started on watch.", comment: "Watch session start status")
        } catch {
            statusMessage = String(localized: "Watch session started locally. Phone sync will retry.", comment: "Watch session start offline")
            sessionActive = true
        }
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await persistState()
    }

    func endSession() async {
        guard sessionActive else { return }
        let payload = WatchPayload(
            kind: .endSession,
            workoutID: "active-strength-session",
            body: "completed"
        )

        do {
            try await coordinator.send(payload)
            statusMessage = String(localized: "Live session ended.", comment: "Watch session end status")
        } catch {
            statusMessage = String(localized: "Watch ended the session. Phone sync will retry.", comment: "Watch session end offline")
        }
        sessionActive = false
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await stateStore.clear()
    }

    func requestCoachCue() async {
        await ensureSessionStarted()
        let payload = WatchPayload(
            kind: .coachCue,
            workoutID: "active-strength-session",
            body: coachPrompt
        )

        do {
            try await coordinator.send(payload)
            statusMessage = String(localized: "Coach prompt sent to iPhone.", comment: "Coach cue sent status")
        } catch {
            statusMessage = String(
                localized: "Coach prompt queued on watch until phone reconnects.",
                comment: "Coach cue offline status"
            )
        }
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await persistState()
    }

    func completeWorkout() async {
        await ensureSessionStarted()
        let completedAt = Date.now
        let summaryLine = String(
            localized: "\(autopilot.nextExerciseName) wrapped with \(selectedAction.rawValue) recommendation.",
            comment: """
                Watch-originated session summary; first placeholder is the \
                exercise name, second is the recommended action \
                (increase/hold/decrease)
                """
        )
        let payloadBody = SyncPayloadCodec.encode(
            WatchWorkoutSyncPayload(
                workoutID: "active-strength-session",
                receivedAt: completedAt,
                title: String(
                    localized: "Watch Strength Session",
                    comment: "Watch-originated session title that surfaces in iPhone session history"
                ),
                exerciseID: VolumeArcExerciseCatalog.backSquat.id,
                exerciseName: autopilot.nextExerciseName,
                set: WorkoutSetPerformance(
                    weight: autopilot.nextTarget.weight,
                    reps: autopilot.nextTarget.repRange.lowerBound,
                    rpe: autopilot.nextTarget.targetRPE,
                    completedAt: completedAt
                ),
                recommendedAction: selectedAction,
                durationMinutes: 32,
                completionRate: 1,
                summary: summaryLine
            )
        ) ?? summaryLine
        let payload = WatchPayload(
            kind: .completedWorkout,
            workoutID: "active-strength-session",
            createdAt: completedAt,
            body: payloadBody
        )

        do {
            try await coordinator.send(payload)
            statusMessage = String(localized: "Workout summary sent to iPhone.", comment: "Workout complete status")
        } catch {
            statusMessage = String(localized: "Workout summary queued for the phone.", comment: "Workout complete offline status")
        }
        sessionActive = false
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await stateStore.clear()
    }

    func decisionSummary(for action: WorkoutAction) -> String {
        switch action {
        case .increase:
            return String(localized: "Move up only if the last rep stays clean.", comment: "Increase weight coaching cue")
        case .hold:
            return String(localized: "Hold the load and own the next set.", comment: "Hold weight coaching cue")
        case .decrease:
            return String(localized: "Trim the jump and keep technique sharp.", comment: "Decrease weight coaching cue")
        default:
            return autopilot.recommendationReason
        }
    }

    private func ensureSessionStarted() async {
        guard sessionActive == false else { return }
        await startSession()
    }

    private static func makeTransport() -> WatchSessionTransport {
        #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
        WatchConnectivitySessionTransport()
        #else
        UnavailableWatchSessionTransport()
        #endif
    }

    private static func makeStateStore() -> WatchSessionStateStore {
        UserDefaultsWatchSessionStateStore()
    }

    private static func makePendingPayloadStore() -> WatchPendingPayloadStore {
        UserDefaultsWatchPendingPayloadStore()
    }

    private func persistState() async {
        await stateStore.save(
            WatchSessionSnapshot(
                selectedAction: selectedAction,
                restEndsAt: restEndsAt,
                coachPrompt: coachPrompt,
                sessionActive: sessionActive,
                statusMessage: statusMessage
            )
        )
    }
}

/// Isolated rest timer display — the only view that re-renders every second.
/// Keeping this out of the parent avoids redrawing the whole ScrollView at 1Hz.
private struct WatchRestTimerDisplay: View {
    let endsAt: Date
    let onReset: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(Int(endsAt.timeIntervalSince(context.date)), 0)

            VStack(alignment: .leading, spacing: VA.Space.sm) {
                Text(String(localized: "Rest", comment: "Watch rest timer header"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                Text(
                    remaining == 0
                        ? String(localized: "Go time", comment: "Watch rest complete label")
                        : String(
                            localized: "\(remaining)s",
                            comment: "Watch rest timer countdown value; the placeholder is the number of seconds remaining"
                        )
                )
                    .font(VA.Typography.display)
                    .foregroundStyle(remaining == 0 ? VA.Colors.success : VA.Colors.textPrimary)
                    .accessibilityLabel(
                        remaining == 0
                            ? String(
                                localized: "Go time, rest complete",
                                comment: "Watch rest timer accessibility label when rest just finished"
                            )
                            : String(
                                localized: "Rest timer",
                                comment: "Watch rest timer accessibility label while counting down"
                            )
                    )
                    .accessibilityValue(
                        remaining == 0
                            ? String(
                                localized: "Rest complete",
                                comment: "Watch rest timer accessibility value when rest just finished"
                            )
                            : String(
                                localized: "^[\(remaining) second](inflect: true) remaining",
                                comment: """
                                    Watch rest timer accessibility value; the \
                                    placeholder is the seconds remaining. Uses \
                                    automatic grammar inflection for \
                                    singular/plural agreement.
                                    """
                            )
                    )
                Button(
                    remaining == 0
                        ? String(localized: "Restart Rest", comment: "Watch rest timer restart button label")
                        : String(localized: "Reset to 90s", comment: "Watch rest timer reset button label"),
                    action: onReset
                )
                    .buttonStyle(.borderedProminent)
                    .tint(VA.Colors.primary)
                    .accessibilityHint(
                        String(
                            localized: "Resets the rest timer back to 90 seconds",
                            comment: "Watch rest timer reset button hint"
                        )
                    )
            }
        }
    }
}

struct WatchWorkoutView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @StateObject private var model: WatchWorkoutModel

    init(model: WatchWorkoutModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Group {
            if isLuminanceReduced {
                WatchAlwaysOnWorkoutView(
                    autopilot: model.autopilot,
                    restEndsAt: model.restEndsAt,
                    heartRateBPM: model.currentHeartRateBPM
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: VA.Space.lg) {
                        Text(String(localized: "Now", comment: "Watch current exercise header"))
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textSecondary)

                Text(model.autopilot.nextExerciseName)
                    .font(VA.Typography.title)
                    .accessibilityLabel(
                        String(
                            localized: "Exercise: \(model.autopilot.nextExerciseName)",
                            comment: "Watch current exercise accessibility label; placeholder is the exercise name"
                        )
                    )

                let nextTarget = model.autopilot.nextTarget
                let weight = Int(nextTarget.weight)
                let repLower = nextTarget.repRange.lowerBound
                let repUpper = nextTarget.repRange.upperBound
                Text(
                    String(
                        localized: "\(weight)\(nextTarget.unit) x \(repLower)-\(repUpper)",
                        comment: """
                            Watch next target weight and rep range (e.g., \
                            225lb x 5-8). Placeholders: weight, unit, lower \
                            rep, upper rep
                            """
                    )
                )
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.primary)
                    .accessibilityValue(
                        String(
                            localized: "\(weight) pounds, \(repLower) to \(repUpper) reps",
                            comment: """
                                Watch next target accessibility value; \
                                placeholders: weight in pounds, lower rep \
                                count, upper rep count
                                """
                        )
                    )

                Text(model.autopilot.bestCue)
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)

                VStack(alignment: .leading, spacing: VA.Space.sm) {
                    Text(
                        model.sessionActive
                            ? String(localized: "Session Live", comment: "Watch active session label")
                            : String(localized: "Session Ready", comment: "Watch ready session label")
                    )
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                    Button(
                        model.sessionActive
                            ? String(localized: "End Session", comment: "Watch end session button")
                            : String(localized: "Start Session", comment: "Watch start session button")
                    ) {
                        Task {
                            if model.sessionActive {
                                await model.endSession()
                            } else {
                                await model.startSession()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(
                        model.sessionActive
                            ? String(
                                localized: "End workout session",
                                comment: "Watch end session button accessibility label"
                            )
                            : String(
                                localized: "Start workout session",
                                comment: "Watch start session button accessibility label"
                            )
                    )
                    .accessibilityHint(
                        model.sessionActive
                            ? String(
                                localized: "Ends the live watch workout and syncs the summary",
                                comment: "Watch end session button accessibility hint"
                            )
                            : String(
                                localized: "Begins a live watch workout and notifies the phone",
                                comment: "Watch start session button accessibility hint"
                            )
                    )

                    Divider()

                    WatchRestTimerDisplay(endsAt: model.restEndsAt) {
                        Task { await model.resetRestTimer() }
                    }
                }

                    Divider()

                    Text(String(localized: "Decision", comment: "Watch decision header"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)

                    HStack(spacing: VA.Space.md) {
                        actionButton(
                            title: String(
                                localized: "Up",
                                comment: "Watch decision button — increase weight"
                            ),
                            icon: "arrow.up",
                            action: .increase
                        )
                        actionButton(
                            title: String(
                                localized: "Hold",
                                comment: "Watch decision button — hold weight"
                            ),
                            icon: "equal",
                            action: .hold
                        )
                        actionButton(
                            title: String(
                                localized: "Down",
                                comment: "Watch decision button — decrease weight"
                            ),
                            icon: "arrow.down",
                            action: .decrease
                        )
                    }

                    Text(model.decisionSummary(for: model.selectedAction))
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textSecondary)

                    Divider()

                    Text(
                        String(
                            localized: "Readiness \(model.readiness.score)",
                            comment: "Watch readiness score label; placeholder is the numeric score"
                        )
                    )
                        .font(VA.Typography.headline)
                        .accessibilityLabel(
                            String(
                                localized: "Readiness score \(model.readiness.score)",
                                comment: "Watch readiness accessibility label; placeholder is the numeric score"
                            )
                        )
                    Text(model.readiness.brief)
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textSecondary)

                    Text(
                        String(
                            localized: "Fallback: \(VolumeArcExerciseCatalog.frontSquat.name)",
                            comment: "Watch fallback exercise suggestion; placeholder is the fallback lift name"
                        )
                    )
                        .font(VA.Typography.footnote)
                    Text(
                        String(
                            localized: "If the rack is taken, keep the squat stimulus with front squats and trim one accessory.",
                            comment: "Watch fallback exercise rationale when the squat rack is unavailable"
                        )
                    )
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textSecondary)

                    Divider()

                    Text(model.statusMessage)
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textSecondary)

                    if model.pendingSyncCount > 0 {
                        Text(
                            String(
                                localized: "^[\(model.pendingSyncCount) update](inflect: true) waiting for phone sync",
                                comment: """
                                    Watch pending-sync indicator; placeholder \
                                    is the count of queued updates. Uses \
                                    automatic grammar inflection for \
                                    singular/plural agreement.
                                    """
                            )
                        )
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.primary)
                            .accessibilityLabel(
                                String(
                                    localized: "Pending sync updates",
                                    comment: "Watch pending sync indicator accessibility label"
                                )
                            )
                    }

                    Divider()

                    Text(String(localized: "Coach cue", comment: "Watch coach section header"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                    TextField(
                        String(
                            localized: "Ask for a fallback or load check",
                            comment: "Watch coach prompt placeholder"
                        ),
                        text: $model.coachPrompt
                    )
                    Button(String(localized: "Send Cue Request", comment: "Watch send coach cue button")) {
                        Task {
                            await model.requestCoachCue()
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(
                        String(
                            localized: "Sends your coach prompt to the phone",
                            comment: "Watch coach cue send button accessibility hint"
                        )
                    )

                Button(String(localized: "Complete on Watch", comment: "Watch complete workout button")) {
                    Task {
                        await model.completeWorkout()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(
                    String(
                        localized: "Complete workout on Watch",
                        comment: "Watch complete workout button accessibility label"
                    )
                )
                .accessibilityHint(
                    String(
                        localized: "Finishes the session and queues the summary for phone sync",
                        comment: "Watch complete workout button accessibility hint"
                    )
                )
                    }
                    .padding(VA.Space.xl)
                }
            }
        }
        .transaction { transaction in
            if isLuminanceReduced {
                transaction.animation = nil
            }
        }
        .task {
            await model.loadPersistedState()
        }
    }

    private func actionButton(title: String, icon: String, action: WorkoutAction) -> some View {
        Button {
            Task {
                await model.choose(action)
            }
        } label: {
            VStack(spacing: VA.Space.xs) {
                Image(systemName: icon)
                Text(title)
                    .font(VA.Typography.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(model.selectedAction == action ? VA.Colors.primary : VA.Colors.neutral)
        .accessibilityLabel(accessibilityLabelForAction(action))
        .accessibilityHint(accessibilityHintForAction(action))
    }

    private func accessibilityLabelForAction(_ action: WorkoutAction) -> String {
        switch action {
        case .increase:
            return String(localized: "Increase weight", comment: "Watch up button accessibility label")
        case .hold:
            return String(localized: "Hold weight", comment: "Watch hold button accessibility label")
        case .decrease:
            return String(localized: "Decrease weight", comment: "Watch down button accessibility label")
        default:
            return action.rawValue
        }
    }

    private func accessibilityHintForAction(_ action: WorkoutAction) -> String {
        switch action {
        case .increase:
            return String(
                localized: "Move up the load for the next set",
                comment: "Watch up button accessibility hint"
            )
        case .hold:
            return String(
                localized: "Keep the same load for the next set",
                comment: "Watch hold button accessibility hint"
            )
        case .decrease:
            return String(
                localized: "Reduce the load for the next set",
                comment: "Watch down button accessibility hint"
            )
        default:
            return ""
        }
    }
}
