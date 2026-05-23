// swiftlint:disable file_length
import SwiftUI
import VolumeArcCore

private struct WatchLiveStatePayload: Codable, Sendable {
    let action: String
    let exercise: String
    let targetWeight: Int
    let targetUnit: String
    let targetRepLower: Int
}

private enum WatchHealthCaptureError: Error {
    case authorizationDenied
}

@MainActor
// swiftlint:disable:next type_body_length
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
    @Published private(set) var isWatchVoiceEnabled = true
    @Published private(set) var statusMessage = String(localized: "Watch coach standing by.", comment: "Watch default status")
    #if DEBUG
    @Published private(set) var liveMetricEventCount = 0
    #endif

    private let coordinator: WatchConnectivityCoordinator
    private let stateStore: WatchSessionStateStore
    private let healthStore: HealthStore
    private let workoutKitScheduler: WorkoutKitScheduling
    private let voicePlayback: WatchVoicePlayback
    private let voiceSettingsStore: WatchVoiceSettingsStore
    private var activeWorkoutID: String
    private var isLuminanceReduced = false
    private var liveMetricsTask: Task<Void, Never>?

    init(
        coordinator: WatchConnectivityCoordinator,
        stateStore: WatchSessionStateStore,
        healthStore: HealthStore = UnavailableHealthStore(),
        workoutKitScheduler: WorkoutKitScheduling = UnavailableWorkoutKitScheduler(),
        voicePlayback: WatchVoicePlayback = UnavailableWatchVoicePlayback(),
        voiceSettingsStore: WatchVoiceSettingsStore = UserDefaultsWatchVoiceSettingsStore(),
        workoutID: String = WatchWorkoutModel.makeWorkoutID()
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
        self.healthStore = healthStore
        self.workoutKitScheduler = workoutKitScheduler
        self.voicePlayback = voicePlayback
        self.voiceSettingsStore = voiceSettingsStore
        self.activeWorkoutID = workoutID
    }

    static func live() -> WatchWorkoutModel {
        WatchWorkoutModel(
            coordinator: WatchConnectivityCoordinator(
                transport: Self.makeTransport(),
                payloadStore: Self.makePendingPayloadStore()
            ),
            stateStore: Self.makeStateStore(),
            healthStore: Self.makeHealthStore(),
            workoutKitScheduler: Self.makeWorkoutKitScheduler(),
            voicePlayback: Self.makeVoicePlayback(),
            voiceSettingsStore: UserDefaultsWatchVoiceSettingsStore()
        )
    }

    func loadPersistedState() async {
        isWatchVoiceEnabled = await voiceSettingsStore.isWatchVoiceEnabled()
        if isWatchVoiceEnabled {
            await voicePlayback.prewarm()
        }
        if let snapshot = await stateStore.load() {
            activeWorkoutID = snapshot.workoutID
            selectedAction = snapshot.selectedAction
            restEndsAt = snapshot.restEndsAt
            coachPrompt = snapshot.coachPrompt
            sessionActive = snapshot.sessionActive
            statusMessage = snapshot.statusMessage
        }
        await refreshConnectivity()
        if sessionActive {
            observeLiveWorkoutMetrics()
        }
    }

    func setLuminanceReduced(_ reduced: Bool) {
        isLuminanceReduced = reduced
    }

    func setWatchVoiceEnabled(_ enabled: Bool) async {
        await applyWatchVoiceEnabled(enabled, syncToPeer: true)
    }

    func applyWatchPayload(_ payload: WatchPayload) async {
        guard payload.kind == .voiceCoachToggle,
              let settings = WatchVoiceCoach.decodeSettingsPayload(from: payload.body)
        else { return }
        await applyWatchVoiceEnabled(settings.isEnabled, syncToPeer: false)
    }

    private func applyWatchVoiceEnabled(_ enabled: Bool, syncToPeer: Bool) async {
        isWatchVoiceEnabled = enabled
        await voiceSettingsStore.setWatchVoiceEnabled(enabled)
        guard isWatchVoiceEnabled == enabled else { return }
        if enabled {
            await voicePlayback.prewarm()
            guard isWatchVoiceEnabled == enabled else { return }
            statusMessage = String(localized: "Watch voice coach enabled.", comment: "Watch voice coach enabled status")
        } else {
            await voicePlayback.stop()
            guard isWatchVoiceEnabled == enabled else { return }
            statusMessage = String(localized: "Watch voice coach muted.", comment: "Watch voice coach disabled status")
        }
        if syncToPeer {
            await syncWatchVoiceSetting(enabled)
            guard isWatchVoiceEnabled == enabled else { return }
        }
        await persistState()
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
            workoutID: activeWorkoutID,
            body: "reset:90"
        )

        do {
            try await coordinator.send(payload)
            statusMessage = String(localized: "Rest timer synced.", comment: "Watch rest timer sync status")
        } catch {
            statusMessage = String(localized: "Rest timer updated locally. Phone sync will retry.", comment: "Watch rest timer offline status")
        }
        await speakVoiceEvent(.setComplete(restSeconds: 90))
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await persistState()
    }

    func announceRestRemaining(seconds: Int) async {
        if sessionActive { await speakVoiceEvent(.restRemaining(seconds: seconds)) }
    }

    func announceRestTimerAlert(seconds: Int) async {
        if sessionActive { await speakVoiceEvent(.restRemaining(seconds: seconds), allowDuringLuminanceReduced: true) }
    }

    func updateHeartRate(beatsPerMinute bpm: Int?) {
        currentHeartRateBPM = bpm
    }

    var watchVitalsInsight: String {
        if let currentHeartRateBPM {
            return String(
                localized: "Live HR \(currentHeartRateBPM) bpm",
                comment: "Watch Vitals insight when live heart rate is available"
            )
        }

        if readiness.score >= 80 {
            return String(
                localized: "Green light for planned load",
                comment: "Watch Vitals insight for high readiness"
            )
        } else if readiness.score >= 65 {
            return String(
                localized: "Steady effort, listen for fatigue",
                comment: "Watch Vitals insight for moderate readiness"
            )
        } else {
            return String(
                localized: "Keep today conservative",
                comment: "Watch Vitals insight for low readiness"
            )
        }
    }

    func choose(_ action: WorkoutAction) async {
        await ensureSessionStarted()
        selectedAction = action
        let payload = WatchPayload(
            kind: .liveState,
            workoutID: activeWorkoutID,
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
        activeWorkoutID = Self.makeWorkoutID()
        let healthCaptureStarted = await startNativeWorkoutCapture(workoutID: activeWorkoutID)
        let payload = WatchPayload(
            kind: .startSession,
            workoutID: activeWorkoutID,
            body: autopilot.nextExerciseName
        )

        do {
            try await coordinator.send(payload)
            sessionActive = true
            statusMessage = healthCaptureStarted
                ? String(localized: "Live session started on watch.", comment: "Watch session start status")
                : String(
                    localized: "Live session started. Health capture unavailable.",
                    comment: "Watch session start status when native HealthKit capture is unavailable"
                )
        } catch {
            statusMessage = healthCaptureStarted
                ? String(
                    localized: "Watch session started locally. Phone sync will retry.",
                    comment: "Watch session start offline"
                )
                : String(
                    localized: "Watch session started locally. Health capture unavailable; phone sync will retry.",
                    comment: "Watch session start offline when native HealthKit capture is unavailable"
                )
            sessionActive = true
        }
        if isWatchVoiceEnabled {
            await voicePlayback.prewarm()
        }
        await speakVoiceEvent(.nextSet(exerciseName: autopilot.nextExerciseName, target: autopilot.nextTarget))
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await persistState()
    }

    func startWorkoutKitHandoff(workoutID: String) async {
        guard sessionActive == false else { return }
        activeWorkoutID = workoutID
        let healthCaptureStarted = await startNativeWorkoutCapture(workoutID: activeWorkoutID)
        let payload = WatchPayload(
            kind: .startSession,
            workoutID: activeWorkoutID,
            body: "workoutkit:\(autopilot.nextExerciseName)"
        )

        do {
            try await coordinator.send(payload)
            statusMessage = healthCaptureStarted
                ? String(localized: "Apple Workouts session linked to VolumeArc.", comment: "WorkoutKit handoff start status")
                : String(
                    localized: "Apple Workouts session linked. Health capture unavailable.",
                    comment: "WorkoutKit handoff start status when native HealthKit capture is unavailable"
                )
        } catch {
            statusMessage = healthCaptureStarted
                ? String(
                    localized: "Apple Workouts session linked locally. Phone sync will retry.",
                    comment: "WorkoutKit handoff offline start status"
                )
                : String(
                    localized: "Apple Workouts session linked locally. Health capture unavailable; phone sync will retry.",
                    comment: "WorkoutKit handoff offline start status when native HealthKit capture is unavailable"
                )
        }

        sessionActive = true
        if isWatchVoiceEnabled {
            await voicePlayback.prewarm()
        }
        await speakVoiceEvent(.nextSet(exerciseName: autopilot.nextExerciseName, target: autopilot.nextTarget))
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await persistState()
    }

    func scheduleRecommendedWorkoutInAppleWorkouts(at date: Date = .now) async {
        let prescription = workoutKitPrescription(workoutID: activeWorkoutID)
        let state = await workoutKitScheduler.authorizationState()
        let authorizedState = state == .notDetermined
            ? await workoutKitScheduler.requestAuthorization()
            : state

        guard authorizedState == .authorized else {
            statusMessage = authorizedState == .unavailable
                ? String(
                    localized: "Apple Workouts scheduling is unavailable on this watch.",
                    comment: "WorkoutKit unavailable scheduling status"
                )
                : String(
                    localized: "Apple Workouts permission not granted.",
                    comment: "WorkoutKit authorization denied scheduling status"
                )
            await persistState()
            return
        }

        do {
            try await workoutKitScheduler.schedule(
                prescription,
                at: Self.scheduleDateComponents(from: date)
            )
            statusMessage = String(
                localized: "Added \(prescription.exerciseName) to Apple Workouts.",
                comment: "WorkoutKit successful schedule status"
            )
        } catch {
            statusMessage = String(
                localized: "Could not add this workout to Apple Workouts.",
                comment: "WorkoutKit failed schedule status"
            )
        }
        await persistState()
    }

    func endSession() async {
        guard sessionActive else { return }
        let payload = WatchPayload(
            kind: .endSession,
            workoutID: activeWorkoutID,
            body: "completed"
        )

        do {
            try await coordinator.send(payload)
            statusMessage = String(localized: "Live session ended.", comment: "Watch session end status")
        } catch {
            statusMessage = String(localized: "Watch ended the session. Phone sync will retry.", comment: "Watch session end offline")
        }
        await stopNativeWorkoutCapture()
        await voicePlayback.stop()
        sessionActive = false
        activeWorkoutID = Self.makeWorkoutID()
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await stateStore.clear()
    }

    func requestCoachCue() async {
        await ensureSessionStarted()
        let payload = WatchPayload(
            kind: .coachCue,
            workoutID: activeWorkoutID,
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
        await speakVoiceEvent(.coachCue(autopilot.bestCue))
        pendingSyncCount = await coordinator.pendingPayloadCount()
        await persistState()
    }

    func completeWorkout() async {
        await ensureSessionStarted()
        let completedAt = Date.now
        let workoutID = activeWorkoutID
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
                workoutID: workoutID,
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
            workoutID: workoutID,
            createdAt: completedAt,
            body: payloadBody
        )

        do {
            try await coordinator.send(payload)
            statusMessage = String(localized: "Workout summary sent to iPhone.", comment: "Workout complete status")
        } catch {
            statusMessage = String(localized: "Workout summary queued for the phone.", comment: "Workout complete offline status")
        }
        await stopNativeWorkoutCapture()
        await voicePlayback.stop()
        sessionActive = false
        activeWorkoutID = Self.makeWorkoutID()
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

    private static func makeHealthStore() -> HealthStore {
        #if canImport(HealthKit)
        HealthKitRuntimeStore()
        #else
        UnavailableHealthStore()
        #endif
    }

    private static func makeWorkoutKitScheduler() -> WorkoutKitScheduling {
        #if canImport(WorkoutKit)
        if #available(iOS 17.0, watchOS 10.0, *) {
            return SystemWorkoutKitScheduler()
        }
        #endif
        return UnavailableWorkoutKitScheduler()
    }

    private static func makeVoicePlayback() -> WatchVoicePlayback {
        #if canImport(AVFoundation)
        return AVFoundationWatchVoicePlayback()
        #else
        return UnavailableWatchVoicePlayback()
        #endif
    }

    private static func makeWorkoutID() -> String {
        "watch-\(UUID().uuidString)"
    }

    private static func scheduleDateComponents(from date: Date) -> DateComponents {
        Calendar.current.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: date.addingTimeInterval(60)
        )
    }

    private func workoutKitPrescription(workoutID: String) -> WorkoutKitPrescription {
        WorkoutKitPrescription(
            autopilot: autopilot,
            workoutID: workoutID
        )
    }

    private func startNativeWorkoutCapture(workoutID: String) async -> Bool {
        do {
            if await healthStore.isAuthorized == false {
                let result = try await healthStore.requestAuthorization()
                guard result.canShareWorkouts else { throw WatchHealthCaptureError.authorizationDenied }
            }
            let authorized = await healthStore.isAuthorized
            guard authorized else { throw WatchHealthCaptureError.authorizationDenied }
            try await healthStore.startWorkoutSession(activityType: .strengthTraining, workoutID: workoutID)
            observeLiveWorkoutMetrics()
            return true
        } catch {
            return false
        }
    }

    private func stopNativeWorkoutCapture() async {
        liveMetricsTask?.cancel()
        liveMetricsTask = nil
        do {
            try await healthStore.endWorkoutSession()
        } catch {
            statusMessage = String(
                localized: "Workout ended, but Apple Health save failed.",
                comment: "Watch HealthKit workout finish failure status"
            )
        }
        currentHeartRateBPM = nil
    }

    private func observeLiveWorkoutMetrics() {
        liveMetricsTask?.cancel()
        liveMetricsTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.healthStore.liveWorkoutMetrics()
            for await metrics in stream {
                #if DEBUG
                self.liveMetricEventCount += 1
                #endif
                guard metrics.workoutID == self.activeWorkoutID else { continue }
                if let heartRateBPM = metrics.heartRateBPM {
                    self.currentHeartRateBPM = heartRateBPM
                }
            }
        }
    }

    private func speakVoiceEvent(_ event: WatchVoiceEvent, allowDuringLuminanceReduced: Bool = false) async {
        guard isWatchVoiceEnabled else { return }
        guard isLuminanceReduced == false || allowDuringLuminanceReduced else { return }
        let utterance = WatchVoiceCoach.utterance(for: event)
        do {
            try await voicePlayback.speak(utterance)
        } catch {
            statusMessage = String(
                localized: "Watch voice coach unavailable.",
                comment: "Watch voice coach playback failure status"
            )
        }
    }

    private func syncWatchVoiceSetting(_ enabled: Bool) async {
        let payload = WatchPayload(
            kind: .voiceCoachToggle,
            workoutID: activeWorkoutID,
            body: WatchVoiceCoach.encodeSettingsPayload(isEnabled: enabled)
        )
        try? await coordinator.send(payload)
        pendingSyncCount = await coordinator.pendingPayloadCount()
    }

    private func persistState() async {
        await stateStore.save(
            WatchSessionSnapshot(
                workoutID: activeWorkoutID,
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

private struct WatchRestThirtySecondObserver: View {
    let endsAt: Date
    let onThirtySecondsRemaining: () -> Void
    @State private var didAnnounceThirtySeconds = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(Int(endsAt.timeIntervalSince(context.date)), 0)

            Color.clear
                .onChange(of: remaining) { oldValue, newValue in
                    if newValue > 30 {
                        didAnnounceThirtySeconds = false
                    }
                    if oldValue > 30, newValue <= 30, newValue > 0, didAnnounceThirtySeconds == false {
                        didAnnounceThirtySeconds = true
                        onThirtySecondsRemaining()
                    }
                }
                .onChange(of: endsAt) { _, _ in
                    didAnnounceThirtySeconds = false
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

                    Button(String(localized: "Add to Workouts", comment: "Watch WorkoutKit schedule button")) {
                        Task {
                            await model.scheduleRecommendedWorkoutInAppleWorkouts()
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(
                        String(
                            localized: "Add recommended workout to Apple Workouts",
                            comment: "Watch WorkoutKit schedule button accessibility label"
                        )
                    )
                    .accessibilityHint(
                        String(
                            localized: "Schedules the current VolumeArc prescription in Apple's Workouts app",
                            comment: "Watch WorkoutKit schedule button accessibility hint"
                        )
                    )

                    if let heartRate = model.currentHeartRateBPM {
                        Text(
                            String(
                                localized: "Live HR \(heartRate) bpm",
                                comment: "Watch live heart-rate label; placeholder is beats per minute"
                            )
                        )
                        .font(VA.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(VA.Colors.textSecondary)
                        .accessibilityLabel(
                            String(
                                localized: "Live heart rate",
                                comment: "Watch live heart-rate accessibility label"
                            )
                        )
                        .accessibilityValue(
                            String(
                                localized: "^[\(heartRate) beat](inflect: true) per minute",
                                comment: "Watch live heart-rate accessibility value"
                            )
                        )
                    }

                    Divider()

                    WatchRestTimerDisplay(
                        endsAt: model.restEndsAt,
                        onReset: {
                            Task { await model.resetRestTimer() }
                        }
                    )
                }

                    Divider()

                    Text(String(localized: "Settings", comment: "Watch settings section header"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)

                    Toggle(
                        String(localized: "Voice Coach on Watch", comment: "Watch voice coach toggle label"),
                        isOn: Binding(
                            get: { model.isWatchVoiceEnabled },
                            set: { enabled in
                                Task {
                                    await model.setWatchVoiceEnabled(enabled)
                                }
                            }
                        )
                    )
                    .accessibilityIdentifier("watch.voiceCoach.toggle")
                    .accessibilityHint(
                        String(
                            localized: "Turns spoken set cues and rest alerts on this Apple Watch on or off",
                            comment: "Watch voice coach toggle accessibility hint"
                        )
                    )

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

                    watchVitalsChip

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
        .overlay {
            WatchRestThirtySecondObserver(
                endsAt: model.restEndsAt,
                onThirtySecondsRemaining: {
                    Task { await model.announceRestTimerAlert(seconds: 30) }
                }
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .transaction { transaction in
            if isLuminanceReduced {
                transaction.animation = nil
            }
        }
        .task {
            model.setLuminanceReduced(isLuminanceReduced)
            await model.loadPersistedState()
        }
        .onChange(of: isLuminanceReduced) { _, newValue in
            model.setLuminanceReduced(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchConnectivityNotifications.payloadDidArrive)) { notification in
            guard let payload = notification.userInfo?[WatchConnectivityNotifications.payloadUserInfoKey] as? WatchPayload else {
                return
            }
            Task {
                await model.applyWatchPayload(payload)
            }
        }
    }

    private var watchVitalsChip: some View {
        HStack(spacing: VA.Space.sm) {
            Image(systemName: "applewatch")
                .font(VA.Typography.headline)
                .foregroundStyle(VA.Colors.secondary)

            VStack(alignment: .leading, spacing: VA.Space.xxs) {
                Text(String(localized: "Vitals say", comment: "Watch Vitals chip label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                Text(model.watchVitalsInsight)
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(VA.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous)
                .fill(VA.Colors.secondary.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous)
                .strokeBorder(VA.Colors.secondary.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watch.vitalsSayChip")
        .accessibilityLabel(
            String(
                localized: "Vitals say \(model.watchVitalsInsight)",
                comment: "Watch Vitals chip accessibility label"
            )
        )
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
// swiftlint:enable file_length
