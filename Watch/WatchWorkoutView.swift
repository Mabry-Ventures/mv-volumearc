import SwiftUI
import VolumeArcCore

@MainActor
final class WatchWorkoutModel: ObservableObject {
    @Published private(set) var autopilot: WorkoutAutopilotState
    @Published private(set) var readiness: ReadinessAssessment
    @Published var selectedAction: WorkoutAction = .hold
    @Published var restEndsAt = Date.now.addingTimeInterval(90)
    @Published var coachPrompt = "Rack is taken. Best fallback?"
    @Published private(set) var sessionActive = false
    @Published private(set) var pendingSyncCount = 0
    @Published private(set) var statusMessage = "Watch coach standing by."

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
                ? "Connected to iPhone for live coaching."
                : "Connected again. Replayed \(pendingSyncCount) queued updates.")
            : "Phone unavailable. We’ll queue key updates."
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
            statusMessage = "Rest timer synced."
        } catch {
            statusMessage = "Rest timer updated locally. Phone sync will retry."
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
            body: [
                "action=\(action.rawValue)",
                "exercise=\(autopilot.nextExerciseName)",
                "target=\(Int(autopilot.nextTarget.weight))\(autopilot.nextTarget.unit)x\(autopilot.nextTarget.repRange.lowerBound)"
            ].joined(separator: "|")
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
            statusMessage = "Live session started on watch."
        } catch {
            statusMessage = "Watch session started locally. Phone sync will retry."
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
            statusMessage = "Live session ended."
        } catch {
            statusMessage = "Watch ended the session. Phone sync will retry."
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
            statusMessage = "Coach prompt sent to iPhone."
        } catch {
            statusMessage = "Coach prompt queued on watch until phone reconnects."
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
            statusMessage = "Workout summary sent to iPhone."
        } catch {
            statusMessage = "Workout summary queued for the phone."
        }
        sessionActive = false
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await stateStore.clear()
    }

    func decisionSummary(for action: WorkoutAction) -> String {
        switch action {
        case .increase:
            return "Move up only if the last rep stays clean."
        case .hold:
            return "Hold the load and own the next set."
        case .decrease:
            return "Trim the jump and keep technique sharp."
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

struct WatchWorkoutView: View {
    @StateObject private var model: WatchWorkoutModel

    init(model: WatchWorkoutModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remainingRest = max(Int(model.restEndsAt.timeIntervalSince(context.date)), 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Now")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(model.autopilot.nextExerciseName)
                        .font(.title3.bold())

                    Text("\(Int(model.autopilot.nextTarget.weight))\(model.autopilot.nextTarget.unit) x \(model.autopilot.nextTarget.repRange.lowerBound)-\(model.autopilot.nextTarget.repRange.upperBound)")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Text(model.autopilot.bestCue)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.sessionActive ? "Session Live" : "Session Ready")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Button(model.sessionActive ? "End Session" : "Start Session") {
                            Task {
                                if model.sessionActive {
                                    await model.endSession()
                                } else {
                                    await model.startSession()
                                }
                            }
                        }
                        .buttonStyle(.bordered)

                        Divider()

                        Text("Rest")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(remainingRest == 0 ? "Go time" : "\(remainingRest)s")
                            .font(.title2.bold())
                        Button(remainingRest == 0 ? "Restart Rest" : "Reset to 90s") {
                            Task {
                                await model.resetRestTimer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }

                    Divider()

                    Text("Decision")
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
                    }

                    Divider()

                    Text("Coach cue")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Ask for a fallback or load check", text: $model.coachPrompt)
                    Button("Send Cue Request") {
                        Task {
                            await model.requestCoachCue()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Complete on Watch") {
                        Task {
                            await model.completeWorkout()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
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
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(model.selectedAction == action ? .orange : .gray)
    }
}
