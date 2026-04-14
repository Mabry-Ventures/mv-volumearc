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
    @Published var coachPrompt = "Rack is taken. Best fallback?"
    @Published private(set) var sessionActive = false
    @Published private(set) var pendingSyncCount = 0
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
                : "Connected again. Replayed \(pendingSyncCount) queued updates.")
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
            statusMessage = "Decision saved on watch. We’ll sync it to phone when available."
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
            statusMessage = String(localized: "Coach prompt queued on watch until phone reconnects.", comment: "Coach cue offline status")
        }
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await persistState()
    }

    func completeWorkout() async {
        await ensureSessionStarted()
        let completedAt = Date.now
        let payloadBody = SyncPayloadCodec.encode(
            WatchWorkoutSyncPayload(
                workoutID: "active-strength-session",
                receivedAt: completedAt,
                title: "Watch Strength Session",
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
                summary: "\(autopilot.nextExerciseName) wrapped with \(selectedAction.rawValue) recommendation."
            )
        ) ?? "\(autopilot.nextExerciseName) wrapped with \(selectedAction.rawValue) recommendation."
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

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Rest", comment: "Watch rest timer header"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(remaining == 0 ? String(localized: "Go time", comment: "Watch rest complete label") : "\(remaining)s")
                    .font(.title2.bold())
                    .foregroundStyle(remaining == 0 ? Color.green : Color.primary)
                    .accessibilityLabel(remaining == 0 ? "Go time, rest complete" : "Rest timer")
                    .accessibilityValue(remaining == 0 ? "Rest complete" : "\(remaining) seconds remaining")
                Button(remaining == 0 ? "Restart Rest" : "Reset to 90s", action: onReset)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
    }
}

struct WatchWorkoutView: View {
    @StateObject private var model: WatchWorkoutModel

    init(model: WatchWorkoutModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Now", comment: "Watch current exercise header"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(model.autopilot.nextExerciseName)
                    .font(.title3.bold())
                    .accessibilityLabel("Exercise: \(model.autopilot.nextExerciseName)")

                Text("\(Int(model.autopilot.nextTarget.weight))\(model.autopilot.nextTarget.unit) x \(model.autopilot.nextTarget.repRange.lowerBound)-\(model.autopilot.nextTarget.repRange.upperBound)")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .accessibilityValue("\(Int(model.autopilot.nextTarget.weight)) pounds, \(model.autopilot.nextTarget.repRange.lowerBound) to \(model.autopilot.nextTarget.repRange.upperBound) reps")

                Text(model.autopilot.bestCue)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(model.sessionActive ? String(localized: "Session Live", comment: "Watch active session label") : String(localized: "Session Ready", comment: "Watch ready session label"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button(model.sessionActive ? String(localized: "End Session", comment: "Watch end session button") : String(localized: "Start Session", comment: "Watch start session button")) {
                        Task {
                            if model.sessionActive {
                                await model.endSession()
                            } else {
                                await model.startSession()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(model.sessionActive ? "End workout session" : "Start workout session")

                    Divider()

                    WatchRestTimerDisplay(endsAt: model.restEndsAt) {
                        Task { await model.resetRestTimer() }
                    }
                }

                    Divider()

                    Text(String(localized: "Decision", comment: "Watch decision header"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        actionButton(title: "Up", icon: "arrow.up", action: .increase)
                        actionButton(title: "Hold", icon: "equal", action: .hold)
                        actionButton(title: "Down", icon: "arrow.down", action: .decrease)
                    }

                    Text(model.decisionSummary(for: model.selectedAction))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Divider()

                    Text("Readiness \(model.readiness.score)")
                        .font(.headline)
                        .accessibilityLabel("Readiness score \(model.readiness.score)")
                    Text(model.readiness.brief)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Fallback: \(VolumeArcExerciseCatalog.frontSquat.name)")
                        .font(.footnote.weight(.semibold))
                    Text("If the rack is taken, keep the squat stimulus with front squats and trim one accessory.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Divider()

                    Text(model.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if model.pendingSyncCount > 0 {
                        Text("\(model.pendingSyncCount) updates waiting for phone sync")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Pending sync updates")
                    }

                    Divider()

                    Text(String(localized: "Coach cue", comment: "Watch coach section header"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Ask for a fallback or load check", comment: "Watch coach prompt placeholder"), text: $model.coachPrompt)
                    Button(String(localized: "Send Cue Request", comment: "Watch send coach cue button")) {
                        Task {
                            await model.requestCoachCue()
                        }
                    }
                    .buttonStyle(.bordered)

                Button(String(localized: "Complete on Watch", comment: "Watch complete workout button")) {
                    Task {
                        await model.completeWorkout()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Complete workout on Watch")
                .accessibilityHint("Finishes the session and queues the summary for phone sync")
            }
            .padding()
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
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(model.selectedAction == action ? .orange : .gray)
        .accessibilityLabel(accessibilityLabelForAction(action))
        .accessibilityHint(accessibilityHintForAction(action))
    }

    private func accessibilityLabelForAction(_ action: WorkoutAction) -> String {
        switch action {
        case .increase: return "Increase weight"
        case .hold: return "Hold weight"
        case .decrease: return "Decrease weight"
        default: return action.rawValue
        }
    }

    private func accessibilityHintForAction(_ action: WorkoutAction) -> String {
        switch action {
        case .increase: return "Move up the load for the next set"
        case .hold: return "Keep the same load for the next set"
        case .decrease: return "Reduce the load for the next set"
        default: return ""
        }
    }
}
