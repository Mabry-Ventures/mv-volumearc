import Foundation
import XCTest
@testable import VolumeArcCore
#if canImport(HealthKit) && canImport(WorkoutKit)
import HealthKit
import WorkoutKit
#endif

@MainActor
final class WatchWorkoutModelHealthKitTests: XCTestCase {
    func test_startSessionStartsNativeHealthSessionAndUsesSameWorkoutIDForPhonePayload() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let model = makeModel(transport: transport, healthStore: healthStore)

        await model.startSession()

        let calls = await healthStore.calls
        let startCall = try XCTUnwrap(calls.firstStart)
        XCTAssertEqual(startCall.activityType, .strengthTraining)
        XCTAssertTrue(startCall.workoutID.hasPrefix("watch-"))

        let sentPayloads = await transport.sent
        let startPayload = try XCTUnwrap(sentPayloads.first)
        XCTAssertEqual(startPayload.kind, .startSession)
        XCTAssertEqual(startPayload.workoutID, startCall.workoutID)
        XCTAssertTrue(model.sessionActive)
    }

    func test_startSessionContinuesWithoutNativeCaptureWhenHealthAuthorizationIsDenied() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        await healthStore.setAuthorized(false)
        let model = makeModel(transport: transport, healthStore: healthStore)

        await model.startSession()

        let calls = await healthStore.calls
        XCTAssertTrue(calls.contains(.requestAuthorization))
        XCTAssertNil(calls.firstStart)

        let sentPayloads = await transport.sent
        XCTAssertEqual(sentPayloads.first?.kind, .startSession)
        XCTAssertTrue(model.sessionActive)
        XCTAssertEqual(model.statusMessage, "Live session started. Health capture unavailable.")
    }

    func test_liveWorkoutMetricsUpdateVisibleHeartRateForActiveWorkoutOnly() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let model = makeModel(transport: transport, healthStore: healthStore)

        await model.startSession()
        let calls = await healthStore.calls
        let workoutID = try XCTUnwrap(calls.firstStart?.workoutID)
        await healthStore.waitForSubscriber()

        await healthStore.emit(
            LiveWorkoutMetrics(
                workoutID: "other-workout",
                heartRateBPM: 99,
                activeEnergyKilocalories: 3,
                elapsedTime: 12,
                capturedAt: Date(timeIntervalSinceReferenceDate: 100)
            )
        )
        try await waitUntil { model.liveMetricEventCount == 1 }
        XCTAssertNil(model.currentHeartRateBPM)

        await healthStore.emit(
            LiveWorkoutMetrics(
                workoutID: workoutID,
                heartRateBPM: 123,
                activeEnergyKilocalories: 8,
                elapsedTime: 42,
                capturedAt: Date(timeIntervalSinceReferenceDate: 120)
            )
        )

        try await waitUntil { model.currentHeartRateBPM == 123 }
    }

    func test_watchVitalsInsightUsesLiveHeartRateWhenAvailable() {
        let model = makeModel(
            transport: RecordingWatchTransport(reachable: true),
            healthStore: FakeLiveHealthStore()
        )
        XCTAssertFalse(model.watchVitalsInsight.isEmpty)

        model.updateHeartRate(beatsPerMinute: 118)

        XCTAssertEqual(model.watchVitalsInsight, "Live HR 118 bpm")
    }

    func test_loadPersistedStateResumesLiveMetricsForActiveWorkout() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let stateStore = InMemoryWatchSessionStateStore()
        let workoutID = "watch-restored"
        await stateStore.save(
            WatchSessionSnapshot(
                workoutID: workoutID,
                selectedAction: .hold,
                restEndsAt: Date(timeIntervalSinceReferenceDate: 300),
                coachPrompt: "Fallback?",
                sessionActive: true,
                statusMessage: "Restored"
            )
        )
        let model = makeModel(transport: transport, stateStore: stateStore, healthStore: healthStore)

        await model.loadPersistedState()
        await healthStore.waitForSubscriber()
        await healthStore.emit(
            LiveWorkoutMetrics(
                workoutID: workoutID,
                heartRateBPM: 111,
                activeEnergyKilocalories: 4,
                elapsedTime: 18,
                capturedAt: Date(timeIntervalSinceReferenceDate: 320)
            )
        )

        try await waitUntil { model.currentHeartRateBPM == 111 }
    }

    func test_loadPersistedStateDoesNotObserveMetricsForInactiveWorkout() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let stateStore = InMemoryWatchSessionStateStore()
        await stateStore.save(
            WatchSessionSnapshot(
                workoutID: "watch-inactive",
                selectedAction: .hold,
                restEndsAt: Date(timeIntervalSinceReferenceDate: 400),
                coachPrompt: "Fallback?",
                sessionActive: false,
                statusMessage: "Restored"
            )
        )
        let model = makeModel(transport: transport, stateStore: stateStore, healthStore: healthStore)

        await model.loadPersistedState()

        let hasSubscriber = await healthStore.hasSubscriber
        XCTAssertFalse(hasSubscriber)
    }

    func test_completeWorkoutFinishesNativeHealthSessionAndLinksSummaryPayload() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let model = makeModel(transport: transport, healthStore: healthStore)

        await model.startSession()
        let startCalls = await healthStore.calls
        let workoutID = try XCTUnwrap(startCalls.firstStart?.workoutID)
        await healthStore.waitForSubscriber()
        await healthStore.emit(
            LiveWorkoutMetrics(
                workoutID: workoutID,
                heartRateBPM: 117,
                activeEnergyKilocalories: 6,
                elapsedTime: 30,
                capturedAt: Date(timeIntervalSinceReferenceDate: 200)
            )
        )
        try await waitUntil { model.currentHeartRateBPM == 117 }

        await model.completeWorkout()

        let calls = await healthStore.calls
        XCTAssertTrue(calls.contains(.end))
        XCTAssertFalse(model.sessionActive)
        XCTAssertNil(model.currentHeartRateBPM)

        let sentPayloads = await transport.sent
        let completedPayload = try XCTUnwrap(sentPayloads.last { $0.kind == .completedWorkout })
        XCTAssertEqual(completedPayload.workoutID, workoutID)

        let summary = try XCTUnwrap(SyncPayloadCodec.decode(WatchWorkoutSyncPayload.self, from: completedPayload.body))
        XCTAssertEqual(summary.workoutID, workoutID)
    }

    func test_watchVoiceCoachEmitsWorkoutEventTTSStrings() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let voicePlayback = FakeWatchVoicePlayback()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            voicePlayback: voicePlayback
        )

        let nextSet = WatchVoiceCoach.utterance(
            for: .nextSet(exerciseName: model.autopilot.nextExerciseName, target: model.autopilot.nextTarget)
        )
        let setComplete = WatchVoiceCoach.utterance(for: .setComplete(restSeconds: 90))
        let restRemaining = WatchVoiceCoach.utterance(for: .restRemaining(seconds: 30))
        let coachCue = WatchVoiceCoach.utterance(for: .coachCue(model.autopilot.bestCue))

        await model.startSession()
        await model.resetRestTimer()
        await model.announceRestRemaining(seconds: 30)
        await model.requestCoachCue()

        let spoken = await voicePlayback.spoken
        XCTAssertTrue(spoken.contains(nextSet))
        XCTAssertTrue(spoken.contains(setComplete))
        XCTAssertTrue(spoken.contains(restRemaining))
        XCTAssertTrue(spoken.contains(coachCue))
        XCTAssertTrue(spoken.allSatisfy { $0.delivery == .textToSpeech })

        let prewarmCount = await voicePlayback.prewarmCount
        XCTAssertEqual(prewarmCount, 1)
    }

    func test_watchVoiceCoachSettingDisablesSpeechAndPersists() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let voicePlayback = FakeWatchVoicePlayback()
        let settings = InMemoryWatchVoiceSettingsStore(enabled: true)
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            voicePlayback: voicePlayback,
            voiceSettingsStore: settings
        )

        await model.setWatchVoiceEnabled(false)
        await model.startSession()
        await model.resetRestTimer()

        let spoken = await voicePlayback.spoken
        XCTAssertTrue(spoken.isEmpty)
        let enabled = await settings.isWatchVoiceEnabled()
        XCTAssertFalse(enabled)
        let stopCount = await voicePlayback.stopCount
        XCTAssertEqual(stopCount, 1)
        let voicePayloads = await transport.sent.filter { $0.kind == .voiceCoachToggle }
        XCTAssertEqual(voicePayloads.count, 1)
        XCTAssertEqual(WatchVoiceCoach.decodeSettingsPayload(from: voicePayloads[0].body)?.isEnabled, false)
        let prewarmCount = await voicePlayback.prewarmCount
        XCTAssertEqual(prewarmCount, 0)
    }

    func test_watchVoiceCoachAppliesMirroredPhoneToggleWithoutEchoingPayload() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let voicePlayback = FakeWatchVoicePlayback()
        let settings = InMemoryWatchVoiceSettingsStore(enabled: true)
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            voicePlayback: voicePlayback,
            voiceSettingsStore: settings
        )
        let payload = WatchPayload(
            kind: .voiceCoachToggle,
            workoutID: "phone-toggle",
            body: WatchVoiceCoach.encodeSettingsPayload(isEnabled: false)
        )

        await model.applyWatchPayload(payload)

        let enabled = await settings.isWatchVoiceEnabled()
        XCTAssertFalse(enabled)
        let stopCount = await voicePlayback.stopCount
        XCTAssertEqual(stopCount, 1)
        let sentPayloads = await transport.sent
        XCTAssertTrue(sentPayloads.isEmpty)
    }

    func test_watchVoiceCoachSuppressesAutomaticSpeechDuringAODExceptRestTimerAlert() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let voicePlayback = FakeWatchVoicePlayback()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            voicePlayback: voicePlayback
        )

        model.setLuminanceReduced(true)
        await model.startSession()
        await model.requestCoachCue()
        await model.resetRestTimer()
        await model.announceRestRemaining(seconds: 30)
        let suppressed = await voicePlayback.spoken
        XCTAssertTrue(suppressed.isEmpty)

        await model.announceRestTimerAlert(seconds: 30)
        let spoken = await voicePlayback.spoken
        XCTAssertEqual(spoken, [WatchVoiceUtterance(text: "30 seconds remaining")])
    }

    func test_scheduleRecommendedWorkoutRequestsAuthorizationAndSchedulesStructuralPrescription() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let scheduler = FakeWorkoutKitScheduler()
        await scheduler.setAuthorizationState(.notDetermined, requestResult: .authorized)
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            workoutKitScheduler: scheduler,
            workoutID: "watch-workoutkit"
        )
        let scheduledAt = Date(timeIntervalSinceReferenceDate: 700)

        await model.scheduleRecommendedWorkoutInAppleWorkouts(at: scheduledAt)

        let didRequestAuthorization = await scheduler.didRequestAuthorization
        XCTAssertTrue(didRequestAuthorization)

        let scheduled = await scheduler.scheduled
        let call = try XCTUnwrap(scheduled.first)
        XCTAssertEqual(call.prescription.workoutID, "watch-workoutkit")
        XCTAssertEqual(call.prescription.exerciseID, VolumeArcExerciseCatalog.backSquat.id)
        XCTAssertEqual(call.prescription.exerciseName, VolumeArcExerciseCatalog.backSquat.name)
        XCTAssertEqual(call.prescription.activityType, .strengthTraining)
        XCTAssertEqual(call.prescription.target.repRange, 5...8)
        XCTAssertEqual(call.prescription.setCount, WorkoutKitPrescription.defaultSetCount)
        XCTAssertEqual(call.prescription.restDuration, WorkoutKitPrescription.defaultRestDuration)
        XCTAssertEqual(
            call.date.minute,
            Calendar.current.component(.minute, from: scheduledAt.addingTimeInterval(60))
        )
        XCTAssertEqual(model.statusMessage, "Added Back Squat to Apple Workouts.")

        let exportedScope = WorkoutKitPrescription.dataScope.joined(separator: " ").lowercased()
        XCTAssertFalse(exportedScope.contains("coach"))
        XCTAssertFalse(exportedScope.contains("athlete"))
        XCTAssertFalse(exportedScope.contains("profile"))
        XCTAssertFalse(exportedScope.contains("readiness"))
    }

    func test_scheduleRecommendedWorkoutDoesNotScheduleWhenWorkoutKitAuthorizationIsDenied() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let scheduler = FakeWorkoutKitScheduler()
        await scheduler.setAuthorizationState(.denied, requestResult: .denied)
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            workoutKitScheduler: scheduler
        )

        await model.scheduleRecommendedWorkoutInAppleWorkouts()

        let scheduled = await scheduler.scheduled
        XCTAssertTrue(scheduled.isEmpty)
        XCTAssertEqual(model.statusMessage, "Apple Workouts permission not granted.")
    }

    func test_startWorkoutKitHandoffLinksAppleWorkoutsStartToVolumeArcSession() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let model = makeModel(transport: transport, healthStore: healthStore)

        await model.startWorkoutKitHandoff(workoutID: "workoutkit-started")

        let calls = await healthStore.calls
        let startCall = try XCTUnwrap(calls.firstStart)
        XCTAssertEqual(startCall.workoutID, "workoutkit-started")
        XCTAssertEqual(startCall.activityType, .strengthTraining)
        XCTAssertTrue(model.sessionActive)

        let sentPayloads = await transport.sent
        let startPayload = try XCTUnwrap(sentPayloads.first)
        XCTAssertEqual(startPayload.kind, .startSession)
        XCTAssertEqual(startPayload.workoutID, "workoutkit-started")
        XCTAssertEqual(startPayload.body, "workoutkit:Back Squat")
    }

    func test_actionButtonStartCommandStartsSessionAndConfirmsOnWrist() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let voicePlayback = FakeWatchVoicePlayback()
        let actionStore = InMemoryWatchActionButtonCommandStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            voicePlayback: voicePlayback,
            actionButtonCommandStore: actionStore,
            actionButtonHaptics: haptics
        )
        await actionStore.enqueue(
            WatchActionButtonCommandRecord(
                command: .startActiveWorkout,
                actionName: VolumeArcActionButtonActionName.startActiveWorkout
            )
        )

        await model.processPendingActionButtonCommands()

        let sentPayloads = await transport.sent
        let playedHaptics = await haptics.played
        let spoken = await voicePlayback.spoken
        XCTAssertTrue(model.sessionActive)
        XCTAssertEqual(model.statusMessage, "Action Button started VolumeArc workout.")
        XCTAssertEqual(sentPayloads.first?.kind, .startSession)
        XCTAssertEqual(playedHaptics, [.acknowledged])
        XCTAssertTrue(spoken.contains(WatchVoiceUtterance(text: "Workout started.")))
    }

    func test_actionButtonLogNextSetRequiresActiveWorkout() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let voicePlayback = FakeWatchVoicePlayback()
        let actionStore = InMemoryWatchActionButtonCommandStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            voicePlayback: voicePlayback,
            actionButtonCommandStore: actionStore,
            actionButtonHaptics: haptics
        )
        await actionStore.enqueue(
            WatchActionButtonCommandRecord(
                command: .logNextSet,
                actionName: VolumeArcActionButtonActionName.logNextSet
            )
        )

        await model.processPendingActionButtonCommands()

        let sentPayloads = await transport.sent
        let playedHaptics = await haptics.played
        let spoken = await voicePlayback.spoken
        XCTAssertFalse(model.sessionActive)
        XCTAssertEqual(model.statusMessage, "No active workout.")
        XCTAssertTrue(sentPayloads.isEmpty)
        XCTAssertEqual(playedHaptics, [.failed])
        XCTAssertEqual(spoken, [WatchVoiceUtterance(text: "No active workout.")])
    }

    func test_actionButtonLogNextSetDuringSessionSyncsDecisionAndRestTimer() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let voicePlayback = FakeWatchVoicePlayback()
        let actionStore = InMemoryWatchActionButtonCommandStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            voicePlayback: voicePlayback,
            actionButtonCommandStore: actionStore,
            actionButtonHaptics: haptics
        )
        await model.startSession()
        await actionStore.enqueue(
            WatchActionButtonCommandRecord(
                command: .logNextSet,
                actionName: VolumeArcActionButtonActionName.logNextSet
            )
        )

        await model.processPendingActionButtonCommands()

        let sentPayloads = await transport.sent
        let playedHaptics = await haptics.played
        let spoken = await voicePlayback.spoken
        let sentKinds = sentPayloads.map(\.kind)
        XCTAssertTrue(model.sessionActive)
        XCTAssertEqual(model.statusMessage, "Set logged from Action Button.")
        XCTAssertTrue(sentKinds.contains(.liveState))
        XCTAssertTrue(sentKinds.contains(.restTimer))
        XCTAssertEqual(playedHaptics, [.acknowledged])
        XCTAssertTrue(spoken.contains(WatchVoiceUtterance(text: "Set logged.")))
    }

    #if canImport(HealthKit) && canImport(WorkoutKit)
    func test_workoutKitPlanFactoryBuildsCustomStrengthWorkoutFromPrescription() throws {
        let target = WorkoutTarget(weight: 95, unit: "lb", repRange: 5...8, targetRPE: 7.5)
        let prescription = WorkoutKitPrescription(
            workoutID: "watch-fixed-plan",
            exerciseID: VolumeArcExerciseCatalog.backSquat.id,
            exerciseName: VolumeArcExerciseCatalog.backSquat.name,
            activityType: .strengthTraining,
            target: target,
            setCount: 4,
            restDuration: 120
        )

        let plan = VolumeArcWorkoutKitPlanFactory.workoutPlan(for: prescription)
        XCTAssertEqual(plan.id, WorkoutKitPrescription.stablePlanID(for: "watch-fixed-plan"))

        guard case let .custom(workout) = plan.workout else {
            return XCTFail("Expected a custom WorkoutKit workout")
        }

        XCTAssertEqual(workout.activity, HKWorkoutActivityType.traditionalStrengthTraining)
        XCTAssertEqual(workout.location, .indoor)
        XCTAssertEqual(workout.displayName, "VolumeArc Back Squat")
        XCTAssertEqual(workout.blocks.count, 1)

        let block = try XCTUnwrap(workout.blocks.first)
        XCTAssertEqual(block.iterations, 4)
        XCTAssertEqual(block.steps.count, 2)
        XCTAssertEqual(block.steps[0].purpose, .work)
        XCTAssertEqual(block.steps[0].step.displayName, "Back Squat 95lb x 5-8")
        XCTAssertEqual(block.steps[0].step.goal, .open)
        XCTAssertEqual(block.steps[1].purpose, .recovery)
        XCTAssertEqual(block.steps[1].step.displayName, "Rest 120 seconds")

        guard case let .time(restDuration, restUnit) = block.steps[1].step.goal else {
            return XCTFail("Expected the recovery step to carry a time goal")
        }
        XCTAssertEqual(restDuration, 120)
        XCTAssertEqual(restUnit, .seconds)
    }
    #endif

    private func makeModel(
        transport: RecordingWatchTransport,
        stateStore: InMemoryWatchSessionStateStore = InMemoryWatchSessionStateStore(),
        healthStore: FakeLiveHealthStore,
        workoutKitScheduler: WorkoutKitScheduling = UnavailableWorkoutKitScheduler(),
        voicePlayback: WatchVoicePlayback = UnavailableWatchVoicePlayback(),
        voiceSettingsStore: WatchVoiceSettingsStore = InMemoryWatchVoiceSettingsStore(enabled: true),
        actionButtonCommandStore: any WatchActionButtonCommandStoring = InMemoryWatchActionButtonCommandStore(),
        actionButtonHaptics: any WatchActionButtonHapticPlaying = RecordingWatchActionButtonHaptics(),
        workoutID: String = "watch-seeded"
    ) -> WatchWorkoutModel {
        WatchWorkoutModel(
            coordinator: WatchConnectivityCoordinator(
                transport: transport,
                payloadStore: InMemoryPendingPayloadStore()
            ),
            stateStore: stateStore,
            healthStore: healthStore,
            workoutKitScheduler: workoutKitScheduler,
            voicePlayback: voicePlayback,
            voiceSettingsStore: voiceSettingsStore,
            actionButtonCommandStore: actionButtonCommandStore,
            actionButtonHaptics: actionButtonHaptics,
            workoutID: workoutID
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

private extension [FakeLiveHealthStore.Call] {
    var firstStart: (activityType: WorkoutActivityType, workoutID: String)? {
        for call in self {
            if case let .start(activityType, workoutID) = call {
                return (activityType, workoutID)
            }
        }
        return nil
    }
}

private actor FakeLiveHealthStore: HealthStore {
    enum Call: Equatable {
        case requestAuthorization
        case start(WorkoutActivityType, String)
        case end
    }

    private var continuation: AsyncStream<LiveWorkoutMetrics>.Continuation?
    private(set) var calls: [Call] = []
    var authorized = true

    var isAuthorized: Bool {
        get async { authorized }
    }

    var hasSubscriber: Bool {
        continuation != nil
    }

    func requestAuthorization() async throws -> HealthAuthorizationResult {
        calls.append(.requestAuthorization)
        return HealthAuthorizationResult(canShareWorkouts: authorized, requestedReadIdentifiers: [])
    }

    func startWorkoutSession(activityType: WorkoutActivityType) async throws {
        try await startWorkoutSession(activityType: activityType, workoutID: "legacy-workout")
    }

    func startWorkoutSession(activityType: WorkoutActivityType, workoutID: String) async throws {
        calls.append(.start(activityType, workoutID))
    }

    func endWorkoutSession() async throws {
        calls.append(.end)
        let continuation = continuation
        self.continuation = nil
        continuation?.finish()
    }

    func liveWorkoutMetrics() async -> AsyncStream<LiveWorkoutMetrics> {
        AsyncStream { continuation in
            Task { self.setContinuation(continuation) }
        }
    }

    func emit(_ metrics: LiveWorkoutMetrics) {
        continuation?.yield(metrics)
    }

    func waitForSubscriber() async {
        for _ in 0..<50 {
            if continuation != nil { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func setAuthorized(_ authorized: Bool) {
        self.authorized = authorized
    }

    private func setContinuation(_ continuation: AsyncStream<LiveWorkoutMetrics>.Continuation) {
        self.continuation = continuation
    }
}

private struct WorkoutKitScheduleCall: Sendable {
    let prescription: WorkoutKitPrescription
    let date: DateComponents
}

private actor FakeWorkoutKitScheduler: WorkoutKitScheduling {
    private(set) var didRequestAuthorization = false
    private(set) var scheduled: [WorkoutKitScheduleCall] = []
    private var state: WorkoutKitScheduleAuthorization = .authorized
    private var requestResult: WorkoutKitScheduleAuthorization = .authorized

    func setAuthorizationState(
        _ state: WorkoutKitScheduleAuthorization,
        requestResult: WorkoutKitScheduleAuthorization
    ) {
        self.state = state
        self.requestResult = requestResult
    }

    func authorizationState() async -> WorkoutKitScheduleAuthorization {
        state
    }

    func requestAuthorization() async -> WorkoutKitScheduleAuthorization {
        didRequestAuthorization = true
        state = requestResult
        return requestResult
    }

    func schedule(_ prescription: WorkoutKitPrescription, at date: DateComponents) async throws {
        scheduled.append(WorkoutKitScheduleCall(prescription: prescription, date: date))
    }
}

private actor FakeWatchVoicePlayback: WatchVoicePlayback {
    private(set) var prewarmCount = 0
    private(set) var spoken: [WatchVoiceUtterance] = []
    private(set) var stopCount = 0

    func prewarm() async {
        prewarmCount += 1
    }

    func speak(_ utterance: WatchVoiceUtterance) async throws {
        spoken.append(utterance)
    }

    func stop() async {
        stopCount += 1
    }
}

private actor InMemoryWatchVoiceSettingsStore: WatchVoiceSettingsStore {
    private var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func isWatchVoiceEnabled() async -> Bool {
        enabled
    }

    func setWatchVoiceEnabled(_ enabled: Bool) async {
        self.enabled = enabled
    }
}

private actor InMemoryWatchActionButtonCommandStore: WatchActionButtonCommandStoring {
    private var records: [WatchActionButtonCommandRecord] = []

    func enqueue(_ record: WatchActionButtonCommandRecord) async {
        records.append(record)
    }

    func drain() async -> [WatchActionButtonCommandRecord] {
        defer { records.removeAll() }
        return records
    }
}

private actor RecordingWatchActionButtonHaptics: WatchActionButtonHapticPlaying {
    private(set) var played: [WatchActionButtonFeedback] = []

    func play(_ feedback: WatchActionButtonFeedback) async {
        played.append(feedback)
    }
}

private actor InMemoryPendingPayloadStore: WatchPendingPayloadStore {
    private var payloads: [WatchPayload] = []

    func enqueue(_ payload: WatchPayload) async {
        payloads.append(payload)
    }

    func dequeueAll() async -> [WatchPayload] {
        defer { payloads.removeAll() }
        return payloads
    }

    func count() async -> Int {
        payloads.count
    }
}

private actor InMemoryWatchSessionStateStore: WatchSessionStateStore {
    private var snapshot: WatchSessionSnapshot?

    func load() async -> WatchSessionSnapshot? {
        snapshot
    }

    func save(_ snapshot: WatchSessionSnapshot) async {
        self.snapshot = snapshot
    }

    func clear() async {
        snapshot = nil
    }
}

private actor RecordingWatchTransport: WatchSessionTransport {
    private(set) var sent: [WatchPayload] = []
    private let reachable: Bool

    init(reachable: Bool) {
        self.reachable = reachable
    }

    func activate() async {}

    func isReachable() async -> Bool {
        reachable
    }

    func send(_ payload: WatchPayload) async throws {
        sent.append(payload)
    }
}
