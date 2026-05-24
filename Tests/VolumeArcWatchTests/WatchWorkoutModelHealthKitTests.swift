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

    func test_startSessionDonatesActionButtonLogNextSetIntent() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let donor = RecordingActionDonor()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            actionButtonNextActionDonor: donor
        )

        await model.startSession()

        let donationCount = await donor.logNextSetDonationCount
        XCTAssertEqual(donationCount, 1)
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

    func test_doubleTapSettingPersistsAndControlsPrimaryAction() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let settings = InMemoryWatchDoubleTapSettingsStore(enabled: true)
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            doubleTapSettingsStore: settings
        )

        XCTAssertTrue(model.isDoubleTapEnabled)
        XCTAssertFalse(model.canUseDoubleTapPrimaryAction)

        await model.startSession()
        XCTAssertTrue(model.canUseDoubleTapPrimaryAction)

        await model.setDoubleTapEnabled(false)

        let persisted = await settings.isDoubleTapEnabled()
        XCTAssertFalse(persisted)
        XCTAssertFalse(model.isDoubleTapEnabled)
        XCTAssertFalse(model.canUseDoubleTapPrimaryAction)
        XCTAssertEqual(model.statusMessage, "Double Tap set logging disabled.")
    }

    func test_doubleTapLogNextSetDuringSessionSyncsDecisionRestTimerHapticVoiceAndTelemetry() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let voicePlayback = FakeWatchVoicePlayback()
        let haptics = RecordingWatchActionButtonHaptics()
        let telemetry = InMemoryTelemetrySink()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            voicePlayback: voicePlayback,
            doubleTapTelemetrySink: telemetry,
            actionButtonHaptics: haptics
        )

        await model.startSession()
        await model.handleDoubleTapLogNextSet()

        let sentPayloads = await transport.sent
        let playedHaptics = await haptics.played
        let spoken = await voicePlayback.spoken
        let sentKinds = sentPayloads.map(\.kind)
        let doubleTapEvent = try XCTUnwrap(
            telemetry.currentEvents.first { $0.category == "watch.double_tap" && $0.name == "set_logged" }
        )
        XCTAssertTrue(model.sessionActive)
        XCTAssertEqual(model.statusMessage, "Set logged from Double Tap.")
        XCTAssertTrue(sentKinds.contains(.liveState))
        XCTAssertTrue(sentKinds.contains(.restTimer))
        XCTAssertEqual(playedHaptics, [.acknowledged])
        XCTAssertTrue(spoken.contains(WatchVoiceUtterance(text: "Logged. Rest 90 seconds.")))
        XCTAssertEqual(doubleTapEvent.metadata["selectedAction"], WorkoutAction.hold.rawValue)
    }

    func test_doubleTapDisabledDoesNotRecordTelemetryButManualButtonStillLogsSet() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let telemetry = InMemoryTelemetrySink()
        let settings = InMemoryWatchDoubleTapSettingsStore(enabled: false)
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            doubleTapSettingsStore: settings,
            doubleTapTelemetrySink: telemetry,
            actionButtonHaptics: haptics
        )

        await model.loadPersistedState()
        await model.handleDoubleTapLogNextSet()

        var sentPayloads = await transport.sent
        var playedHaptics = await haptics.played
        XCTAssertFalse(model.isDoubleTapEnabled)
        XCTAssertTrue(sentPayloads.isEmpty)
        XCTAssertTrue(playedHaptics.isEmpty)
        XCTAssertTrue(telemetry.currentEvents.isEmpty)

        await model.startSession()
        await model.logSetManually()

        sentPayloads = await transport.sent
        playedHaptics = await haptics.played
        let sentKinds = sentPayloads.map(\.kind)
        XCTAssertEqual(model.statusMessage, "Set logged on Watch.")
        XCTAssertTrue(sentKinds.contains(.liveState))
        XCTAssertTrue(sentKinds.contains(.restTimer))
        XCTAssertEqual(playedHaptics, [.acknowledged])
        XCTAssertTrue(telemetry.currentEvents.isEmpty)
    }

    func test_doubleTapLogNextSetRequiresActiveWorkout() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let telemetry = InMemoryTelemetrySink()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            doubleTapTelemetrySink: telemetry,
            actionButtonHaptics: haptics
        )

        await model.handleDoubleTapLogNextSet()

        let sentPayloads = await transport.sent
        let playedHaptics = await haptics.played
        XCTAssertEqual(model.statusMessage, "Start a session to log a set.")
        XCTAssertTrue(sentPayloads.isEmpty)
        XCTAssertTrue(playedHaptics.isEmpty)
        XCTAssertTrue(telemetry.currentEvents.isEmpty)
    }

    func test_formCheckStartAndStopSendWatchConnectivityPayloads() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            actionButtonHaptics: haptics
        )

        await model.startSession()
        await model.startFormCheckCapture()
        await model.stopFormCheckCapture()

        let sentPayloads = await transport.sent
        let startPayload = try XCTUnwrap(sentPayloads.last { $0.kind == .formCheckStart })
        let stopPayload = try XCTUnwrap(sentPayloads.last { $0.kind == .formCheckStop })
        let start = try XCTUnwrap(WatchFormCheckStartPayload.decode(from: startPayload.body))
        let stop = try XCTUnwrap(WatchFormCheckStopPayload.decode(from: stopPayload.body))
        XCTAssertEqual(start.exercise, .squat)
        XCTAssertEqual(start.exerciseName, "Back Squat")
        XCTAssertEqual(stop.sessionID, start.sessionID)
        XCTAssertEqual(model.activeFormCheckSessionID, start.sessionID)
        XCTAssertTrue(model.isFormCheckAnalyzing)
        XCTAssertEqual(model.statusMessage, "Analyzing form on iPhone.")
        let playedHaptics = await haptics.played
        XCTAssertEqual(playedHaptics, [.acknowledged])
    }

    func test_formCheckResultAppliesHapticsVoiceAndSummary() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let voicePlayback = FakeWatchVoicePlayback()
        let haptics = RecordingWatchActionButtonHaptics()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            voicePlayback: voicePlayback,
            actionButtonHaptics: haptics
        )

        await model.startSession()
        await model.startFormCheckCapture()
        let sessionID = try XCTUnwrap(model.activeFormCheckSessionID)
        let result = WatchFormCheckResultPayload(
            sessionID: sessionID,
            exercise: .squat,
            verdict: .solid,
            cueText: "Clean reps.",
            hapticCode: .solid,
            repCount: 3,
            duration: 16
        )

        await model.applyWatchPayload(
            WatchPayload(
                kind: .formCheckResult,
                workoutID: "watch-seeded",
                body: WatchFormCheckResultPayload.encode(result)
            )
        )

        XCTAssertNil(model.activeFormCheckSessionID)
        XCTAssertFalse(model.isFormCheckAnalyzing)
        XCTAssertEqual(model.formCheckResultSummary, "Form solid")
        XCTAssertEqual(model.statusMessage, "Form solid")
        let playedHaptics = await haptics.played
        let spoken = await voicePlayback.spoken
        XCTAssertTrue(playedHaptics.contains(.formSolid))
        XCTAssertTrue(spoken.contains(WatchVoiceUtterance(text: "Clean reps.")))
    }

    func test_formCheckStoppedPayloadClearsStateAndPlaysStopHaptic() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            actionButtonHaptics: haptics
        )

        await model.startSession()
        await model.startFormCheckCapture()
        let sessionID = try XCTUnwrap(model.activeFormCheckSessionID)
        await model.applyWatchPayload(
            WatchPayload(
                kind: .formCheckStopped,
                workoutID: "watch-seeded",
                body: WatchFormCheckStoppedPayload.encode(
                    WatchFormCheckStoppedPayload(
                        sessionID: sessionID,
                        reason: .unavailable,
                        message: "This lift is not supported for camera form check yet."
                    )
                )
            )
        )

        XCTAssertNil(model.activeFormCheckSessionID)
        XCTAssertFalse(model.isFormCheckAnalyzing)
        XCTAssertNil(model.formCheckResultSummary)
        XCTAssertEqual(model.statusMessage, "This lift is not supported for camera form check yet.")
        XCTAssertEqual(model.pendingSyncCount, 0)
        let playedHaptics = await haptics.played
        XCTAssertTrue(playedHaptics.contains(.failed))
    }

    func test_cancelFormCheckAnalyzingClearsProgressAndSession() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            actionButtonHaptics: haptics
        )

        await model.startSession()
        await model.startFormCheckCapture()
        await model.stopFormCheckCapture()
        XCTAssertTrue(model.isFormCheckAnalyzing)

        await model.cancelFormCheckAnalyzing()

        XCTAssertNil(model.activeFormCheckSessionID)
        XCTAssertFalse(model.isFormCheckAnalyzing)
        XCTAssertNil(model.formCheckResultSummary)
        XCTAssertEqual(model.statusMessage, "Form check canceled.")
        let playedHaptics = await haptics.played
        XCTAssertTrue(playedHaptics.contains(.failed))
    }

    func test_formCheckAnalyzeTimeoutClearsProgressAndSession() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            actionButtonHaptics: haptics,
            formCheckAnalyzeTimeoutNanoseconds: 10_000_000
        )

        await model.startSession()
        await model.startFormCheckCapture()
        await model.stopFormCheckCapture()

        try await waitUntil {
            model.activeFormCheckSessionID == nil && model.isFormCheckAnalyzing == false
        }
        XCTAssertNil(model.formCheckResultSummary)
        XCTAssertEqual(model.statusMessage, "Form check timed out. Try again.")
        let playedHaptics = await haptics.played
        XCTAssertTrue(playedHaptics.contains(.failed))
    }

    func test_formCheckStartUsesNextLoggedSetNumber() async throws {
        let transport = RecordingWatchTransport(reachable: true)
        let healthStore = FakeLiveHealthStore()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore
        )

        await model.startSession()
        await model.logSetManually()
        await model.startFormCheckCapture()

        let sentPayloads = await transport.sent
        let startPayload = try XCTUnwrap(sentPayloads.last { $0.kind == .formCheckStart })
        let start = try XCTUnwrap(WatchFormCheckStartPayload.decode(from: startPayload.body))
        XCTAssertEqual(start.setNumber, 2)
    }

    func test_formCheckQueuedStopShowsPendingHaptic() async throws {
        let transport = RecordingWatchTransport(reachable: false)
        let healthStore = FakeLiveHealthStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            actionButtonHaptics: haptics
        )

        await model.startSession()
        await model.startFormCheckCapture()
        await model.stopFormCheckCapture()

        XCTAssertEqual(model.statusMessage, "Stop queued. Result pending.")
        XCTAssertTrue(model.pendingSyncCount > 0)
        let playedHaptics = await haptics.played
        XCTAssertTrue(playedHaptics.contains(.resultPending))
    }

    func test_formCheckReliableTransferStillShowsQueuedWhenPeerIsUnreachable() async throws {
        let transport = RecordingWatchTransport(reachable: false, throwsWhenUnreachable: false)
        let healthStore = FakeLiveHealthStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            actionButtonHaptics: haptics
        )

        await model.startSession()
        await model.startFormCheckCapture()
        XCTAssertEqual(model.statusMessage, "Capture request queued until iPhone reconnects.")

        await model.stopFormCheckCapture()
        XCTAssertEqual(model.statusMessage, "Stop queued. Result pending.")
        XCTAssertEqual(model.pendingSyncCount, 0)

        let sentPayloads = await transport.sent
        XCTAssertNotNil(sentPayloads.first { $0.kind == .formCheckStart })
        XCTAssertNotNil(sentPayloads.first { $0.kind == .formCheckStop })
        let playedHaptics = await haptics.played
        XCTAssertGreaterThanOrEqual(playedHaptics.filter { $0 == .resultPending }.count, 2)
    }

    func test_formCheckQueuedRequestPlaysPendingHapticAfterReconnectFlush() async throws {
        let transport = RecordingWatchTransport(reachable: false)
        let healthStore = FakeLiveHealthStore()
        let haptics = RecordingWatchActionButtonHaptics()
        let model = makeModel(
            transport: transport,
            healthStore: healthStore,
            actionButtonHaptics: haptics
        )

        await model.startFormCheckCapture()
        XCTAssertNotNil(model.activeFormCheckSessionID)
        XCTAssertTrue(model.pendingSyncCount > 0)

        await transport.setReachable(true)
        await model.refreshConnectivity()

        XCTAssertEqual(model.pendingSyncCount, 0)
        XCTAssertTrue(model.statusMessage.contains("Replayed"))
        let playedHaptics = await haptics.played
        XCTAssertGreaterThanOrEqual(playedHaptics.filter { $0 == .resultPending }.count, 2)
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
        doubleTapSettingsStore: any WatchDoubleTapSettingsStore = InMemoryWatchDoubleTapSettingsStore(enabled: true),
        doubleTapTelemetrySink: any TelemetrySink = InMemoryTelemetrySink(),
        actionButtonCommandStore: any WatchActionButtonCommandStoring = InMemoryWatchActionButtonCommandStore(),
        actionButtonHaptics: any WatchActionButtonHapticPlaying = RecordingWatchActionButtonHaptics(),
        actionButtonNextActionDonor: any WatchActionButtonNextActionDonating = RecordingActionDonor(),
        formCheckAnalyzeTimeoutNanoseconds: UInt64 = 45_000_000_000,
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
            doubleTapSettingsStore: doubleTapSettingsStore,
            doubleTapTelemetrySink: doubleTapTelemetrySink,
            actionButtonCommandStore: actionButtonCommandStore,
            actionButtonHaptics: actionButtonHaptics,
            actionButtonNextActionDonor: actionButtonNextActionDonor,
            formCheckAnalyzeTimeoutNanoseconds: formCheckAnalyzeTimeoutNanoseconds,
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

private actor InMemoryWatchDoubleTapSettingsStore: WatchDoubleTapSettingsStore {
    private var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func isDoubleTapEnabled() async -> Bool {
        enabled
    }

    func setDoubleTapEnabled(_ enabled: Bool) async {
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

private actor RecordingActionDonor: WatchActionButtonNextActionDonating {
    private(set) var logNextSetDonationCount = 0

    func donateLogNextSet() async {
        logNextSetDonationCount += 1
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
    private var reachable: Bool
    private let throwsWhenUnreachable: Bool

    init(reachable: Bool, throwsWhenUnreachable: Bool = true) {
        self.reachable = reachable
        self.throwsWhenUnreachable = throwsWhenUnreachable
    }

    func setReachable(_ reachable: Bool) {
        self.reachable = reachable
    }

    func activate() async {}

    func isReachable() async -> Bool {
        reachable
    }

    func send(_ payload: WatchPayload) async throws {
        if reachable == false, throwsWhenUnreachable {
            throw WatchTransportError.notReachable
        }
        sent.append(payload)
    }
}
