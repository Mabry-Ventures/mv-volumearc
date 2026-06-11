#if canImport(SwiftData)
import XCTest
import SwiftData
import VolumeArcCore

/// End-to-end integration tests that exercise the full chain:
/// dashboard action → repository → aggregate update → widget snapshot.
///
/// Uses an in-memory SwiftData container so tests are hermetic and fast.
/// No mocks for the data layer — the real repositories are under test.
@MainActor
final class VolumeArcDashboardIntegrationTests: XCTestCase {
    private var container: ModelContainer!
    private var workoutRepository: SwiftDataWorkoutRepository!
    private var coachMemoryRepository: SwiftDataCoachMemoryRepository!
    private var userProfileRepository: SwiftDataUserProfileRepository!
    private var trainingPlanRepository: SwiftDataTrainingPlanRepository!

    override func setUp() async throws {
        let schema = Schema(VolumeArcSchemaV5.models)
        let config = ModelConfiguration(
            "IntegrationTest-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(
            for: schema,
            migrationPlan: VolumeArcSchemaMigrationPlan.self,
            configurations: [config]
        )

        workoutRepository = SwiftDataWorkoutRepository(container: container)
        coachMemoryRepository = SwiftDataCoachMemoryRepository(container: container)
        userProfileRepository = SwiftDataUserProfileRepository(container: container)
        trainingPlanRepository = SwiftDataTrainingPlanRepository(container: container)
        PlatformSurfaceDefaultsWriter.clearLiveActivityState()
    }

    override func tearDown() async throws {
        PlatformSurfaceDefaultsWriter.clearLiveActivityState()
        container = nil
        workoutRepository = nil
        coachMemoryRepository = nil
        userProfileRepository = nil
        trainingPlanRepository = nil
    }

    // MARK: - Workout create → append → complete chain

    func testCreateWorkoutProducesExactlyOneActiveRecord() throws {
        _ = try workoutRepository.createWorkout(title: "Strength Day")

        let active = try workoutRepository.activeWorkout()
        XCTAssertNotNil(active, "activeWorkout should return the newly created session")
        XCTAssertEqual(active?.title, "Strength Day")
        XCTAssertNil(active?.completedAt, "New workout should not be marked complete")
    }

    func testAppendSetUpdatesWorkoutAggregates() throws {
        let workout = try workoutRepository.createWorkout(title: "Leg Day")

        let set = WorkoutSetPerformance(
            weight: 225,
            reps: 5,
            rpe: 7.5,
            completedAt: .now
        )
        try workoutRepository.appendSet(
            set,
            forExercise: "back-squat",
            to: workout.identifier
        )

        let updated = try workoutRepository.workout(withIdentifier: workout.identifier)
        XCTAssertEqual(updated?.completedSetCount, 1)
        XCTAssertEqual(updated?.totalVolumeLoad, 225 * 5)
        XCTAssertEqual(updated?.averageRPE ?? 0, 7.5, accuracy: 0.01)
        XCTAssertTrue(updated?.exerciseIDsCSV.contains("back-squat") ?? false)
    }

    func testMultipleSetsAccumulate() throws {
        let workout = try workoutRepository.createWorkout(title: "Chest Day")

        for weight in [135.0, 155.0, 175.0] {
            try workoutRepository.appendSet(
                WorkoutSetPerformance(weight: weight, reps: 8, rpe: 7.0, completedAt: .now),
                forExercise: "bench-press",
                to: workout.identifier
            )
        }

        let updated = try workoutRepository.workout(withIdentifier: workout.identifier)
        XCTAssertEqual(updated?.completedSetCount, 3)
        XCTAssertEqual(updated?.totalVolumeLoad ?? 0, 3720, accuracy: 0.01) // 135*8 + 155*8 + 175*8
    }

    func testCompleteWorkoutClearsActiveState() throws {
        let workout = try workoutRepository.createWorkout(title: "Pull Day")

        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 185, reps: 6, rpe: 8, completedAt: .now),
            forExercise: "barbell-row",
            to: workout.identifier
        )

        try workoutRepository.completeWorkout(identifier: workout.identifier, summary: "Solid session")

        let active = try workoutRepository.activeWorkout()
        XCTAssertNil(active, "No active workout should remain after completion")

        let completed = try workoutRepository.workout(withIdentifier: workout.identifier)
        XCTAssertNotNil(completed?.completedAt, "Completed workout must have a completion timestamp")
        XCTAssertEqual(completed?.summary, "Solid session")
    }

    // MARK: - History projection

    func testHistoryProjectionBuildsFromAppendedSets() throws {
        let workout = try workoutRepository.createWorkout(title: "Session 1")

        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 225, reps: 5, rpe: 7, completedAt: .now),
            forExercise: "back-squat",
            to: workout.identifier
        )
        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 245, reps: 3, rpe: 8, completedAt: .now),
            forExercise: "back-squat",
            to: workout.identifier
        )
        try workoutRepository.completeWorkout(identifier: workout.identifier)

        let history = try workoutRepository.history(forExercise: "back-squat")
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.topWeight, 245)
    }

    // MARK: - Recent sessions projection

    func testRecentSessionsReflectCompletedWorkouts() throws {
        // Create two completed sessions
        let one = try workoutRepository.createWorkout(title: "Session A")
        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 100, reps: 10, rpe: 6, completedAt: .now),
            forExercise: "goblet-squat",
            to: one.identifier
        )
        try workoutRepository.completeWorkout(identifier: one.identifier)

        let two = try workoutRepository.createWorkout(title: "Session B")
        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 135, reps: 8, rpe: 7, completedAt: .now),
            forExercise: "romanian-deadlift",
            to: two.identifier
        )
        try workoutRepository.completeWorkout(identifier: two.identifier)

        let recent = try workoutRepository.recentSessions(limit: 10)
        XCTAssertEqual(recent.count, 2)
        XCTAssertTrue(recent.allSatisfy { $0.completedSetCount == 1 })
    }

    func testRefreshLoadsExternalHealthWorkoutsIntoReadinessHistory() async throws {
        let now = Date.now
        let importer = FixedHealthWorkoutImporter(workouts: [
            ImportedHealthWorkout(
                externalIdentifier: "hk-ride-1",
                sourceName: "Peloton",
                sourceBundleIdentifier: "com.onepeloton.ios",
                title: "Ride from Peloton",
                activityIdentifier: "13",
                startedAt: now.addingTimeInterval(-3_900),
                endedAt: now.addingTimeInterval(-300),
                durationMinutes: 60,
                activeEnergyKilocalories: 510
            ),
            ImportedHealthWorkout(
                externalIdentifier: "hk-strength-1",
                sourceName: "Strong",
                sourceBundleIdentifier: "io.strongapp.Strong",
                title: "Strength training from Strong",
                activityIdentifier: "50",
                startedAt: now.addingTimeInterval(-2 * 86_400),
                endedAt: now.addingTimeInterval(-2 * 86_400 + 3_600),
                durationMinutes: 60,
                activeEnergyKilocalories: 320
            ),
        ])
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry, healthWorkoutImporter: importer)

        await model.refresh()
        await model.refresh()

        XCTAssertEqual(model.recentSessions.count, 2, "External HK workouts should join the local history once")
        XCTAssertTrue(
            model.readiness.factors.contains { $0.name == "Training frequency" && $0.detail.contains("2/") },
            "Readiness should count imported external workouts as recent training"
        )
        let records = try workoutRepository.recentWorkouts(limit: 10)
        XCTAssertTrue(
            records.isEmpty,
            "HealthKit-derived workouts must not be persisted into the CloudKit-backed workout store"
        )

        let importEvents = telemetry.currentEvents.filter { $0.category == "health" && $0.name == "workouts_loaded" }
        XCTAssertFalse(importEvents.isEmpty)
    }

    func testRefreshRecordsHealthWorkoutImportFailureWithoutBlockingDashboard() async {
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(
            telemetrySink: telemetry,
            healthWorkoutImporter: ThrowingHealthWorkoutImporter()
        )

        let refreshed = await model.refresh()

        XCTAssertTrue(refreshed, "Health import failure should not block local dashboard refresh")
        XCTAssertTrue(
            telemetry.currentEvents.contains { $0.category == "health" && $0.name == "workout_import_failed" },
            "Import failures should be visible to diagnostics"
        )
    }

    func testCompleteWorkoutSessionReturnsFreshSnapshotForNewSession() async throws {
        // Use a fictitious exercise + an unusual rep count so the value can't
        // collide with whatever the autopilot recommends for the new session.
        let previousDuration = 42
        let previousVolume: Double = 12_345

        let previous = try workoutRepository.createWorkout(
            title: "Previous Session",
            startedAt: .now.addingTimeInterval(TimeInterval(-(previousDuration * 60)))
        )
        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 12_345, reps: 1, rpe: 9, completedAt: .now.addingTimeInterval(-300)),
            forExercise: "back-squat",
            to: previous.identifier
        )
        try workoutRepository.completeWorkout(identifier: previous.identifier)

        let model = makeDashboardModel()
        await model.refresh()

        await model.startWorkoutSession()
        let expectedTarget = model.autopilot?.nextTarget
        await model.logRecommendedSet()

        let completed = await model.completeWorkoutSession()
        let snapshot = try XCTUnwrap(completed)
        XCTAssertEqual(snapshot.completedSetCount, 1, "The returned snapshot should describe the session that just completed")
        XCTAssertNotEqual(snapshot.totalVolumeLoad, previousVolume, "The snapshot should not reuse the previous session's total volume")
        XCTAssertNotEqual(snapshot.durationMinutes, previousDuration, "The snapshot should not reuse the previous session's duration")

        if let expectedTarget {
            XCTAssertEqual(
                snapshot.totalVolumeLoad,
                expectedTarget.weight * Double(expectedTarget.repRange.lowerBound),
                accuracy: 0.01,
                "The returned snapshot should use the just-logged set metrics"
            )
        }

        let publishedVolume = try XCTUnwrap(model.recentSessions.first?.totalVolumeLoad)
        XCTAssertEqual(
            publishedVolume,
            snapshot.totalVolumeLoad,
            accuracy: 0.01,
            "Refresh should publish the same freshly completed session the method returned"
        )
    }

    func testWorkoutStartAndCompletionPublishLiveActivityJourneyTelemetry() async throws {
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)
        _ = await model.refresh()

        await model.startWorkoutSession()

        let liveState = try XCTUnwrap(
            PlatformSurfaceDefaultsReader.loadLiveActivityState(),
            "Starting a workout should publish the Live Activity state snapshot consumed by ActivityKit."
        )
        XCTAssertEqual(liveState.workoutTitle, model.activeWorkoutTitle)
        XCTAssertFalse(liveState.activeExerciseName.isEmpty)

        let startedEvent = try XCTUnwrap(telemetry.currentEvents.first {
            $0.category == "liveactivity" && $0.name == "started"
        })
        XCTAssertEqual(startedEvent.severity, .info)
        XCTAssertEqual(startedEvent.metadata["workout_title_present"], "true")
        XCTAssertEqual(startedEvent.metadata["exercise_present"], "true")
        XCTAssertNil(startedEvent.metadata["workout"])
        XCTAssertNil(startedEvent.metadata["exercise"])

        _ = await model.completeWorkoutSession()

        XCTAssertNil(
            PlatformSurfaceDefaultsReader.loadLiveActivityState(),
            "Completing the workout should clear the shared Live Activity state so ActivityKit can dismiss the surface."
        )

        let endedEvent = try XCTUnwrap(telemetry.currentEvents.first {
            $0.category == "liveactivity" && $0.name == "ended"
        })
        XCTAssertEqual(endedEvent.severity, .info)
        XCTAssertEqual(endedEvent.metadata["workout_id"], startedEvent.metadata["workout_id"])
    }

    // MARK: - Profile + onboarding

    func testUpsertProfilePersistsValues() throws {
        let defaults = UserProfileDefaults(
            name: "Jane Lifter",
            coachingStyle: .analytical,
            privacyMode: .strict,
            advancementLevel: .advanced,
            availableEquipment: [.barbell, .dumbbell],
            preferredRepRangeLower: 3,
            preferredRepRangeUpper: 6,
            sessionTimeBudgetMinutes: 75,
            weeklyTrainingDays: 5
        )
        try userProfileRepository.upsertProfile(defaults)

        let profile = try userProfileRepository.athleteProfile()
        XCTAssertEqual(profile.name, "Jane Lifter")
        XCTAssertEqual(profile.advancementLevel, .advanced)
        XCTAssertEqual(profile.weeklyTrainingDays, 5)
        XCTAssertEqual(profile.preferredRepRange, 3...6)
    }

    func testMarkOnboardingCompleteFlipsFlag() throws {
        let defaults = UserProfileDefaults(
            name: "Tester",
            coachingStyle: .motivational,
            privacyMode: .standard,
            advancementLevel: .intermediate,
            availableEquipment: [.barbell],
            preferredRepRangeLower: 5,
            preferredRepRangeUpper: 8,
            sessionTimeBudgetMinutes: 60,
            weeklyTrainingDays: 4
        )
        try userProfileRepository.upsertProfile(defaults)

        XCTAssertFalse(try userProfileRepository.isOnboardingComplete())
        try userProfileRepository.markOnboardingComplete()
        XCTAssertTrue(try userProfileRepository.isOnboardingComplete())
    }

    // MARK: - Paywall / subscription wiring (VOL-58)

    /// VOL-58 verification: the dashboard model exposes a non-nil
    /// `subscriptionStore` that `ProfileView` can pass into `PaywallView`.
    /// This is the integration-level stand-in for the XCUITest that was
    /// deferred because SwiftUI Form cells in iOS 26 don't reliably
    /// surface inner `accessibilityIdentifier`s. The XCUITest would have
    /// verified the end-to-end tap → sheet flow; this test verifies the
    /// state binding that makes that flow possible.
    func testDashboardModelExposesSubscriptionStoreForPaywall() {
        let model = makeDashboardModel()
        XCTAssertNotNil(
            model.subscriptionStore,
            "ProfileView's paywall sheet binds to model.subscriptionStore — if this is nil, tapping Upgrade is a no-op"
        )

        // If the compiler accepts this expression, the paywall wiring is
        // type-compatible with the view layer. The integration test
        // documents the contract even though SwiftUI views are hard to
        // instantiate in XCTest without ViewInspector.
        let store = try? XCTUnwrap(model.subscriptionStore)
        XCTAssertNotNil(store, "StoreKit subscription store must be available")
    }

    func testStrictPrivacyModeRedactsCoachContext() async throws {
        let store = CapturedContextStore()
        let provider = CapturingCoachProvider(store: store)
        let model = makeDashboardModel(aiProvider: provider)

        try userProfileRepository.upsertProfile(
            UserProfileDefaults(
                name: "Jane Lifter",
                coachingStyle: .analytical,
                privacyMode: .strict,
                advancementLevel: .advanced,
                availableEquipment: [.barbell, .dumbbell],
                preferredRepRangeLower: 3,
                preferredRepRangeUpper: 6,
                sessionTimeBudgetMinutes: 75,
                weeklyTrainingDays: 5
            )
        )
        try userProfileRepository.markOnboardingComplete()
        try coachMemoryRepository.append(
            content: "Last session Jane reported the bench press felt unusually heavy.",
            theme: "bench"
        )

        let workout = try workoutRepository.createWorkout(
            title: "Bench Day",
            startedAt: .now.addingTimeInterval(-(75 * 60))
        )
        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 185, reps: 4, rpe: 8.5, completedAt: .now.addingTimeInterval(-600)),
            forExercise: "bench-press",
            to: workout.identifier
        )
        try workoutRepository.completeWorkout(identifier: workout.identifier)

        await model.refresh()
        await model.askCoach("How should I approach today's top set?")

        let captured = await store.get()
        let context = try XCTUnwrap(captured)
        XCTAssertTrue(context.contains("Readiness:"), "Strict mode should still preserve useful training context")
        XCTAssertFalse(context.contains("Jane Lifter"), "Strict mode should redact the athlete's name")
        XCTAssertFalse(context.contains("Last 7 days:"), "Strict mode should strip recent history summaries")
        XCTAssertFalse(context.contains("Last session:"), "Strict mode should strip the previous session summary")
        XCTAssertFalse(context.contains("Recent coaching notes"), "Strict mode should strip stored coaching memories")
    }

    // VOL-124: strict mode must redact PII from the free-text QUESTION on
    // the egress path, not just the structured context block. Before the
    // fix, `askCoach` passed the raw prompt straight to the provider, so a
    // user who typed an email/phone into the coach box leaked it to the
    // relay even in strict mode — contradicting the privacy policy.
    func testStrictPrivacyModeRedactsCoachQuestion() async throws {
        let store = CapturedContextStore()
        let provider = CapturingCoachProvider(store: store)
        let model = makeDashboardModel(aiProvider: provider)

        try userProfileRepository.upsertProfile(
            UserProfileDefaults(
                name: "Jane Lifter",
                coachingStyle: .analytical,
                privacyMode: .strict,
                advancementLevel: .advanced,
                availableEquipment: [.barbell],
                preferredRepRangeLower: 3,
                preferredRepRangeUpper: 6,
                sessionTimeBudgetMinutes: 60,
                weeklyTrainingDays: 4
            )
        )
        try userProfileRepository.markOnboardingComplete()

        await model.refresh()
        await model.askCoach("My email is jane@example.com and my phone is 615-555-0142 — should I deload?")

        let capturedPrompt = await store.getPrompt()
        let outbound = try XCTUnwrap(capturedPrompt)
        XCTAssertFalse(outbound.contains("jane@example.com"), "Strict mode must redact the email from the outbound question")
        XCTAssertFalse(outbound.contains("615-555-0142"), "Strict mode must redact the phone number from the outbound question")
        XCTAssertTrue(outbound.contains(PromptPrivacyRedactor.redactionMarker), "Strict mode should leave the redaction marker in place")
        XCTAssertTrue(outbound.lowercased().contains("deload"), "Coaching-relevant text must survive redaction")
    }

    // VOL-124: the default (standard) mode is a no-op for question
    // redaction — personalization is intentional there, and the privacy
    // policy discloses it. This pins that we don't over-redact the default.
    func testStandardPrivacyModePreservesCoachQuestion() async throws {
        let store = CapturedContextStore()
        let provider = CapturingCoachProvider(store: store)
        let model = makeDashboardModel(aiProvider: provider)

        try userProfileRepository.upsertProfile(
            UserProfileDefaults(
                name: "Jane Lifter",
                coachingStyle: .analytical,
                privacyMode: .standard,
                advancementLevel: .advanced,
                availableEquipment: [.barbell],
                preferredRepRangeLower: 3,
                preferredRepRangeUpper: 6,
                sessionTimeBudgetMinutes: 60,
                weeklyTrainingDays: 4
            )
        )
        try userProfileRepository.markOnboardingComplete()

        await model.refresh()
        await model.askCoach("My email is jane@example.com — should I deload?")

        let capturedPrompt = await store.getPrompt()
        let outbound = try XCTUnwrap(capturedPrompt)
        XCTAssertTrue(outbound.contains("jane@example.com"), "Standard mode should not redact the question")
        XCTAssertFalse(outbound.contains(PromptPrivacyRedactor.redactionMarker), "Standard mode should leave no redaction marker")
    }

    func testCoachAskEmitsFirstTokenBeforeCompletionTelemetry() async throws {
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)

        await model.refresh()
        await model.askCoach("Should I push today?")

        let coachEvents = telemetry.currentEvents.filter { $0.category == "coach" }
        let firstTokenIndex = coachEvents.firstIndex { $0.name == "first_token_received" }
        let completeIndex = coachEvents.firstIndex { $0.name == "ask_complete" }

        XCTAssertNotNil(firstTokenIndex, "Coach ask should record first-token telemetry")
        XCTAssertNotNil(completeIndex, "Coach ask should record completion telemetry")
        XCTAssertLessThan(
            try XCTUnwrap(firstTokenIndex),
            try XCTUnwrap(completeIndex),
            "The first-token event must fire before the final completion event"
        )
    }

    func testVoiceCoachPermissionAndSingleTurnPromptEmitJourneyTelemetry() async throws {
        let telemetry = InMemoryTelemetrySink()
        let transport = RecordingVoiceTransport(response: "Hold load and keep two reps in reserve.")
        let model = makeDashboardModel(
            telemetrySink: telemetry,
            voicePermissionStore: MockVoicePermissionStore(),
            voiceCoach: LiveVoiceCoachOrchestrator(transport: transport)
        )

        let sent = await model.askCoachByVoice("How is my squat form?")

        XCTAssertTrue(sent)
        XCTAssertFalse(model.isVoiceTurnActive)
        XCTAssertFalse(model.isCoachStreaming)
        XCTAssertNil(model.voiceNotice)
        XCTAssertEqual(model.voicePermissionStatus.microphone, .authorized)
        XCTAssertEqual(model.voicePermissionStatus.speechRecognition, .authorized)
        XCTAssertEqual(model.coachMessages.map(\.sender), [.user, .coach])
        XCTAssertEqual(model.coachMessages.last?.content, "Hold load and keep two reps in reserve.")

        let calls = await transport.calls
        XCTAssertTrue(
            calls.contains { call in
                if case let .send(context, userText) = call {
                    return context.contains("Readiness") && userText == "How is my squat form?"
                }
                return false
            },
            "Voice turn must route the spoken transcript through the voice transport with grounded context"
        )

        let voiceEvents = telemetry.currentEvents.filter { $0.category == "voice" }
        XCTAssertNotNil(voiceEvents.first { $0.name == "enabled" })
        XCTAssertNotNil(voiceEvents.first { $0.name == "session_started" })
        XCTAssertNotNil(voiceEvents.first { $0.name == "session_completed" })
    }

    // MARK: - Coach memory

    func testCoachMemoryAppendAndProject() throws {
        try coachMemoryRepository.append(
            content: "User mentioned squat felt heavy off the floor",
            theme: "squat"
        )

        let memory = try coachMemoryRepository.coachMemory()
        XCTAssertEqual(memory.entries.count, 1)
        XCTAssertEqual(memory.entries.first?.theme, "squat")
        XCTAssertTrue(memory.entries.first?.summary.contains("squat") ?? false)
    }

    func testManualCoachMemorySaveRefreshesPublishedMemory() async {
        let model = makeDashboardModel()
        let saved = await model.appendCoachMemory(
            content: "Keep deadlift cues focused on wedge and patience.",
            theme: "deadlift"
        )

        XCTAssertTrue(saved)
        XCTAssertEqual(model.coachMemory.entries.count, 1)
        XCTAssertEqual(model.coachMemory.entries.first?.theme, "deadlift")
        XCTAssertTrue(model.coachMemory.entries.first?.summary.contains("wedge") ?? false)
    }

    // MARK: - Training plan

    func testTrainingPlanUpsertAndQuery() throws {
        let plan = [
            WeeklyWorkout(dayOfWeek: 1, title: "Monday Squat"),
            WeeklyWorkout(dayOfWeek: 3, title: "Wednesday Bench"),
            WeeklyWorkout(dayOfWeek: 5, title: "Friday Deadlift"),
        ]
        try trainingPlanRepository.upsertPlan(plan)

        let fetched = try trainingPlanRepository.weeklyWorkouts()
        XCTAssertEqual(fetched.count, 3)
        XCTAssertEqual(fetched.map(\.title), plan.map(\.title))
    }

    func testTrainingPlanNextWorkoutUsesMondayBasedWeekdays() throws {
        let plan = [
            WeeklyWorkout(dayOfWeek: 5, title: "Friday Deadlift"),
            WeeklyWorkout(dayOfWeek: 1, title: "Monday Squat"),
            WeeklyWorkout(dayOfWeek: 3, title: "Wednesday Bench"),
        ]
        try trainingPlanRepository.upsertPlan(plan)

        let monday = try XCTUnwrap(DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 4,
            day: 27
        ).date)
        let saturday = try XCTUnwrap(DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 5,
            day: 2
        ).date)
        let sunday = try XCTUnwrap(DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 5,
            day: 3
        ).date)

        XCTAssertEqual(try trainingPlanRepository.nextWorkout(from: monday)?.title, "Monday Squat")
        XCTAssertEqual(try trainingPlanRepository.nextWorkout(from: saturday)?.title, "Monday Squat")
        XCTAssertEqual(try trainingPlanRepository.nextWorkout(from: sunday)?.title, "Monday Squat")
    }

    func testScheduleCoDesignedWorkoutForTomorrowPersistsPlanAndEmitsTelemetry() async throws {
        try trainingPlanRepository.upsertPlan([
            WeeklyWorkout(dayOfWeek: 1, title: "Monday Squat"),
            WeeklyWorkout(dayOfWeek: 2, title: "Lower Strength"),
            WeeklyWorkout(dayOfWeek: 5, title: "Friday Deadlift"),
        ])
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)
        let monday = try XCTUnwrap(DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 6,
            day: 1
        ).date)

        let scheduled = await model.scheduleCoDesignedWorkoutForTomorrow(
            title: "Lower-body hypertrophy",
            durationMinutes: 52,
            targetRPE: 8,
            exercises: [
                WeeklyWorkoutExercise(
                    name: "Front Squat",
                    sets: 5,
                    reps: 6,
                    weight: 225,
                    targetRPE: 8,
                    restSeconds: 150
                ),
                WeeklyWorkoutExercise(
                    name: "Romanian Deadlift",
                    sets: 3,
                    reps: 10,
                    weight: 185,
                    targetRPE: 7,
                    restSeconds: 120
                ),
            ],
            now: monday,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertTrue(scheduled)
        let workouts = try trainingPlanRepository.weeklyWorkouts()
        XCTAssertEqual(workouts.count, 3)
        let scheduledWorkout = try XCTUnwrap(workouts.first { $0.dayOfWeek == 2 })
        XCTAssertEqual(scheduledWorkout.title, "Lower-body hypertrophy")
        XCTAssertEqual(scheduledWorkout.durationMinutes, 52)
        XCTAssertEqual(scheduledWorkout.targetRPE, 8)
        XCTAssertEqual(scheduledWorkout.exercises.map(\.name), ["Front Squat", "Romanian Deadlift"])
        XCTAssertEqual(scheduledWorkout.exercises.first?.sets, 5)
        XCTAssertEqual(workouts.first(where: { $0.dayOfWeek == 1 })?.title, "Monday Squat")

        let event = try XCTUnwrap(telemetry.currentEvents.first {
            $0.category == "coach" && $0.name == "plan_scheduled"
        })
        XCTAssertEqual(event.metadata["dayOfWeek"], "2")
        XCTAssertEqual(event.metadata["title_present"], "true")
        XCTAssertEqual(event.metadata["title_length_bucket"], "21-80")
        XCTAssertEqual(event.metadata["exerciseCount"], "2")
    }

    func testScheduleWorkoutPlanForTodayPersistsBuilderDraftAndEmitsTelemetry() async throws {
        try trainingPlanRepository.upsertPlan([
            WeeklyWorkout(dayOfWeek: 1, title: "Monday Squat"),
            WeeklyWorkout(dayOfWeek: 5, title: "Friday Deadlift"),
        ])
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)
        let wednesday = try XCTUnwrap(DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026,
            month: 6,
            day: 3
        ).date)
        let plan = WorkoutSessionPlan(
            title: "Builder upper strength",
            durationMinutes: 50,
            targetRPE: 7,
            exercises: [
                WeeklyWorkoutExercise(
                    name: "Bench Press",
                    sets: 4,
                    reps: 5,
                    weight: 185,
                    targetRPE: 7,
                    restSeconds: 150
                ),
                WeeklyWorkoutExercise(
                    name: "Barbell Row",
                    sets: 4,
                    reps: 6,
                    weight: 155,
                    targetRPE: 7,
                    restSeconds: 120
                ),
            ]
        )

        let scheduled = await model.scheduleWorkoutPlan(
            plan,
            on: wednesday,
            source: "workouts_builder",
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertTrue(scheduled)
        let workouts = try trainingPlanRepository.weeklyWorkouts()
        let scheduledWorkout = try XCTUnwrap(workouts.first { $0.dayOfWeek == 3 })
        XCTAssertEqual(scheduledWorkout.title, "Builder upper strength")
        XCTAssertEqual(scheduledWorkout.durationMinutes, 50)
        XCTAssertEqual(scheduledWorkout.targetRPE, 7)
        XCTAssertEqual(scheduledWorkout.exercises.map(\.name), ["Bench Press", "Barbell Row"])

        let event = try XCTUnwrap(telemetry.currentEvents.first {
            $0.category == "coach" && $0.name == "plan_scheduled" && $0.metadata["source"] == "workouts_builder"
        })
        XCTAssertEqual(event.metadata["dayOfWeek"], "3")
        XCTAssertEqual(event.metadata["exerciseCount"], "2")
    }

    func testStartingWorkoutWithPlanCarriesExercisesAndAdvancesThroughSets() async throws {
        let model = makeDashboardModel()
        let plan = WorkoutSessionPlan(
            title: "Coach lower strength",
            durationMinutes: 50,
            targetRPE: 8,
            exercises: [
                WeeklyWorkoutExercise(
                    name: "Back Squat",
                    sets: 2,
                    reps: 5,
                    weight: 225,
                    targetRPE: 8,
                    restSeconds: 150
                ),
                WeeklyWorkoutExercise(
                    name: "Romanian Deadlift",
                    sets: 1,
                    reps: 8,
                    weight: 185,
                    targetRPE: 7,
                    restSeconds: 120
                ),
            ]
        )

        await model.startWorkoutSession(plan: plan)

        XCTAssertTrue(model.isSessionActive)
        XCTAssertEqual(model.activeWorkoutTitle, "Coach lower strength")
        XCTAssertEqual(model.activeSessionExercise?.name, "Back Squat")
        XCTAssertEqual(model.activeSessionExerciseSetCount, 2)

        await model.logRecommendedSet()
        XCTAssertEqual(model.loggedSetCountThisSession, 1)
        XCTAssertEqual(model.loggedSetCountForActiveExercise, 1)
        XCTAssertEqual(model.activeSessionExercise?.name, "Back Squat")

        await model.logRecommendedSet()
        XCTAssertEqual(model.loggedSetCountThisSession, 2)
        XCTAssertEqual(model.loggedSetCountForActiveExercise, 0)
        XCTAssertEqual(model.activeSessionExercise?.name, "Romanian Deadlift")

        await model.logRecommendedSet(weightOverride: 195, repsOverride: 8, rpeOverride: 7)

        let completed = await model.completeWorkoutSession()
        let completedSnapshot = try XCTUnwrap(completed)
        XCTAssertEqual(completedSnapshot.completedSetCount, 3)
        XCTAssertEqual(completedSnapshot.exerciseIDs, ["back-squat", "romanian-deadlift"])
    }

    func testActiveSessionPlanCanReplaceAndSkipCurrentExercise() async throws {
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)
        let plan = WorkoutSessionPlan(
            title: "Busy gym lower",
            exercises: [
                WeeklyWorkoutExercise(
                    name: "Back Squat",
                    sets: 3,
                    reps: 5,
                    weight: 225,
                    targetRPE: 8,
                    restSeconds: 150
                ),
                WeeklyWorkoutExercise(
                    name: "Romanian Deadlift",
                    sets: 2,
                    reps: 8,
                    weight: 185,
                    targetRPE: 7,
                    restSeconds: 120
                ),
            ]
        )

        await model.startWorkoutSession(plan: plan)
        model.replaceActiveSessionExercise(with: WeeklyWorkoutExercise(
            name: "Front Squat",
            sets: 3,
            reps: 5,
            weight: 185,
            targetRPE: 7,
            restSeconds: 150
        ))

        XCTAssertEqual(model.activeSessionExercise?.name, "Front Squat")

        let skip = try XCTUnwrap(model.skipActiveSessionExercise())

        XCTAssertEqual(skip.skippedExercise, "Front Squat")
        XCTAssertEqual(skip.nextExercise, "Romanian Deadlift")
        XCTAssertEqual(model.activeSessionExercise?.name, "Romanian Deadlift")
        XCTAssertEqual(model.activeSessionPlan?.exercises.map(\.name), ["Romanian Deadlift"])
        XCTAssertEqual(model.loggedSetCountThisSession, 0)
        XCTAssertEqual(model.loggedSetCountForActiveExercise, 0)
        XCTAssertTrue(telemetry.currentEvents.contains {
            $0.category == "workout" && $0.name == "exercise_replaced"
        })
        XCTAssertTrue(telemetry.currentEvents.contains {
            $0.category == "workout" && $0.name == "exercise_skipped"
        })
    }

    func testSkippingCurrentExerciseRemovesItWithoutInflatingSetProgress() async throws {
        let activeSessionStateStore = InMemoryActiveWorkoutSessionStateStore()
        let model = makeDashboardModel(activeSessionStateStore: activeSessionStateStore)
        let plan = WorkoutSessionPlan(
            title: "Busy gym upper",
            exercises: [
                WeeklyWorkoutExercise(
                    name: "Bench Press",
                    sets: 3,
                    reps: 5,
                    weight: 185,
                    targetRPE: 8,
                    restSeconds: 150
                ),
                WeeklyWorkoutExercise(
                    name: "Barbell Row",
                    sets: 3,
                    reps: 8,
                    weight: 135,
                    targetRPE: 7,
                    restSeconds: 120
                ),
                WeeklyWorkoutExercise(
                    name: "Overhead Press",
                    sets: 2,
                    reps: 6,
                    weight: 95,
                    targetRPE: 7,
                    restSeconds: 120
                ),
            ]
        )

        await model.startWorkoutSession(plan: plan)
        let workoutID = try XCTUnwrap(model.activeWorkoutID)
        await model.logRecommendedSet()
        model.moveActiveSession(toExerciseAt: 1)
        await model.logRecommendedSet()

        let skip = try XCTUnwrap(model.skipActiveSessionExercise())

        XCTAssertEqual(skip.skippedExercise, "Barbell Row")
        XCTAssertEqual(skip.nextExercise, "Overhead Press")
        XCTAssertEqual(model.loggedSetCountThisSession, 2)
        XCTAssertEqual(model.activeSessionExercise?.name, "Overhead Press")
        XCTAssertEqual(model.activeSessionPlan?.exercises.map(\.name), ["Bench Press", "Overhead Press"])
        XCTAssertEqual(model.loggedSetCountForActiveExercise, 0)
        XCTAssertEqual(
            activeSessionStateStore.load(workoutID: workoutID)?.loggedSetCountsByExerciseIndex,
            [0: 1]
        )
    }

    func testActiveSessionPlanCanDeferAndSelectExercisesForBusyGym() async throws {
        let telemetry = InMemoryTelemetrySink()
        let activeSessionStateStore = InMemoryActiveWorkoutSessionStateStore()
        let model = makeDashboardModel(
            telemetrySink: telemetry,
            activeSessionStateStore: activeSessionStateStore
        )
        let plan = WorkoutSessionPlan(
            title: "Busy gym lower",
            exercises: [
                WeeklyWorkoutExercise(
                    name: "Back Squat",
                    sets: 3,
                    reps: 5,
                    weight: 225,
                    targetRPE: 8,
                    restSeconds: 150
                ),
                WeeklyWorkoutExercise(
                    name: "Romanian Deadlift",
                    sets: 2,
                    reps: 8,
                    weight: 185,
                    targetRPE: 7,
                    restSeconds: 120
                ),
                WeeklyWorkoutExercise(
                    name: "Walking Lunge",
                    sets: 2,
                    reps: 10,
                    weight: 35,
                    targetRPE: 7,
                    restSeconds: 90
                ),
            ]
        )

        await model.startWorkoutSession(plan: plan)
        let workoutID = try XCTUnwrap(model.activeWorkoutID)

        let pivot = try XCTUnwrap(model.deferActiveSessionExercise())

        XCTAssertEqual(pivot.deferredExercise, "Back Squat")
        XCTAssertEqual(pivot.nextExercise, "Romanian Deadlift")
        XCTAssertEqual(model.activeSessionExercise?.name, "Romanian Deadlift")
        XCTAssertEqual(model.activeSessionExerciseIndex, 0)
        XCTAssertEqual(model.activeSessionPlan?.exercises.map(\.name), [
            "Romanian Deadlift",
            "Walking Lunge",
            "Back Squat",
        ])
        XCTAssertEqual(activeSessionStateStore.load(workoutID: workoutID)?.plan.exercises.map(\.name), [
            "Romanian Deadlift",
            "Walking Lunge",
            "Back Squat",
        ])

        model.moveActiveSession(toExerciseAt: 2)

        XCTAssertEqual(model.activeSessionExercise?.name, "Back Squat")
        XCTAssertEqual(model.activeSessionExerciseIndex, 2)
        XCTAssertEqual(model.loggedSetCountForActiveExercise, 0)
        XCTAssertEqual(activeSessionStateStore.load(workoutID: workoutID)?.activeExerciseIndex, 2)
        XCTAssertTrue(telemetry.currentEvents.contains {
            $0.category == "workout" && $0.name == "exercise_deferred"
        })
        XCTAssertTrue(telemetry.currentEvents.contains {
            $0.category == "workout" && $0.name == "exercise_selected"
        })
    }

    func testActiveSessionExerciseSelectionPreservesPerExerciseSetProgress() async throws {
        let activeSessionStateStore = InMemoryActiveWorkoutSessionStateStore()
        let model = makeDashboardModel(activeSessionStateStore: activeSessionStateStore)
        let plan = WorkoutSessionPlan(
            title: "Busy gym upper",
            exercises: [
                WeeklyWorkoutExercise(
                    name: "Bench Press",
                    sets: 3,
                    reps: 5,
                    weight: 185,
                    targetRPE: 8,
                    restSeconds: 150
                ),
                WeeklyWorkoutExercise(
                    name: "Barbell Row",
                    sets: 3,
                    reps: 8,
                    weight: 135,
                    targetRPE: 7,
                    restSeconds: 120
                ),
            ]
        )

        await model.startWorkoutSession(plan: plan)
        let workoutID = try XCTUnwrap(model.activeWorkoutID)

        await model.logRecommendedSet()
        XCTAssertEqual(model.activeSessionExercise?.name, "Bench Press")
        XCTAssertEqual(model.loggedSetCountForActiveExercise, 1)

        model.moveActiveSession(toExerciseAt: 1)
        await model.logRecommendedSet()
        XCTAssertEqual(model.activeSessionExercise?.name, "Barbell Row")
        XCTAssertEqual(model.loggedSetCountForActiveExercise, 1)

        model.moveActiveSession(toExerciseAt: 0)
        XCTAssertEqual(model.activeSessionExercise?.name, "Bench Press")
        XCTAssertEqual(model.loggedSetCountForActiveExercise, 1)

        model.moveActiveSession(toExerciseAt: 1)
        XCTAssertEqual(model.activeSessionExercise?.name, "Barbell Row")
        XCTAssertEqual(model.loggedSetCountForActiveExercise, 1)
        XCTAssertEqual(
            activeSessionStateStore.load(workoutID: workoutID)?.loggedSetCountsByExerciseIndex,
            [0: 1, 1: 1]
        )
    }

    func testRefreshRehydratesActiveSessionPlanAfterCrashSimulation() async throws {
        let activeSessionStateStore = InMemoryActiveWorkoutSessionStateStore()
        let plan = WorkoutSessionPlan(
            title: "Crash-safe lower",
            exercises: [
                WeeklyWorkoutExercise(
                    name: "Back Squat",
                    sets: 2,
                    reps: 5,
                    weight: 225,
                    targetRPE: 8,
                    restSeconds: 150
                ),
                WeeklyWorkoutExercise(
                    name: "Romanian Deadlift",
                    sets: 2,
                    reps: 8,
                    weight: 185,
                    targetRPE: 7,
                    restSeconds: 120
                ),
            ]
        )
        let originalModel = makeDashboardModel(activeSessionStateStore: activeSessionStateStore)

        await originalModel.startWorkoutSession(plan: plan)
        let workoutID = try XCTUnwrap(originalModel.activeWorkoutID)
        await originalModel.logRecommendedSet()
        await originalModel.logRecommendedSet()

        XCTAssertEqual(originalModel.activeSessionExercise?.name, "Romanian Deadlift")
        XCTAssertNotNil(activeSessionStateStore.load(workoutID: workoutID))

        let telemetry = InMemoryTelemetrySink()
        let rehydratedModel = makeDashboardModel(
            telemetrySink: telemetry,
            activeSessionStateStore: activeSessionStateStore
        )
        _ = await rehydratedModel.refresh()

        XCTAssertTrue(rehydratedModel.isSessionActive)
        XCTAssertEqual(rehydratedModel.activeWorkoutID, workoutID)
        XCTAssertEqual(rehydratedModel.activeWorkoutTitle, "Crash-safe lower")
        XCTAssertEqual(rehydratedModel.loggedSetCountThisSession, 2)
        XCTAssertEqual(rehydratedModel.activeSessionExercise?.name, "Romanian Deadlift")
        XCTAssertEqual(rehydratedModel.activeSessionExerciseIndex, 1)
        XCTAssertEqual(rehydratedModel.loggedSetCountForActiveExercise, 0)
        XCTAssertEqual(rehydratedModel.activeSessionPlan?.exercises.map(\.name), [
            "Back Squat",
            "Romanian Deadlift",
        ])
        XCTAssertTrue(telemetry.currentEvents.contains {
            $0.category == "workout" && $0.name == "active_session.recovered"
        })
    }

    func testCompletingWorkoutClearsPersistedActiveSessionPlan() async throws {
        let activeSessionStateStore = InMemoryActiveWorkoutSessionStateStore()
        let model = makeDashboardModel(activeSessionStateStore: activeSessionStateStore)
        let plan = WorkoutSessionPlan(
            title: "Clear on complete",
            exercises: [
                WeeklyWorkoutExercise(
                    name: "Back Squat",
                    sets: 1,
                    reps: 5,
                    weight: 225,
                    targetRPE: 8,
                    restSeconds: 150
                ),
            ]
        )

        await model.startWorkoutSession(plan: plan)
        let workoutID = try XCTUnwrap(model.activeWorkoutID)
        XCTAssertNotNil(activeSessionStateStore.load(workoutID: workoutID))

        await model.logRecommendedSet()
        _ = await model.completeWorkoutSession()

        XCTAssertNil(activeSessionStateStore.load(workoutID: workoutID))
    }

    func testConnectAppleAccountPersistsSessionAndSeedsEmptyProfileName() async throws {
        let accountSessionStore = InMemoryAccountSessionStore()
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(
            telemetrySink: telemetry,
            accountSessionStore: accountSessionStore
        )

        await model.connectAppleAccount(
            userID: "apple-user-1",
            displayName: "Jared Mabry",
            email: "jared@example.com"
        )

        XCTAssertEqual(model.accountSession?.provider, "apple")
        XCTAssertEqual(model.accountSession?.userID, "apple-user-1")
        XCTAssertEqual(model.accountSession?.displayName, "Jared Mabry")
        XCTAssertEqual(accountSessionStore.load()?.userID, "apple-user-1")
        XCTAssertEqual(model.athlete.name, "Jared Mabry")
        XCTAssertTrue(telemetry.currentEvents.contains {
            $0.category == "account" && $0.name == "apple_sign_in_connected"
        })
    }

    // MARK: - VOL-283 — coach safety boundary end to end

    /// A medical red-flag prompt must produce escalation copy WITHOUT
    /// the underlying provider ever being invoked. Production wiring
    /// guarantees this by wrapping every factory chain in
    /// `SafetyFilteredCoachProvider`; this test mirrors that wiring and
    /// pins the boundary across the full dashboard pipeline (privacy
    /// redaction, context build, streaming, message rendering).
    func testAskCoachShortCircuitsMedicalRedFlagBeforeProvider() async throws {
        let spy = CoachProviderInvocationSpy()
        let model = makeDashboardModel(aiProvider: SafetyFilteredCoachProvider(base: spy))

        await model.askCoach("I felt chest pain and got dizzy during squats — should I push through?")

        XCTAssertEqual(model.coachMessages.map(\.sender), [.user, .coach])
        let content = model.coachMessages.last?.content.lowercased() ?? ""
        XCTAssertTrue(content.contains("stop the session"))
        XCTAssertTrue(content.contains("medical care"))
        let invocations = await spy.invocationCount
        XCTAssertEqual(invocations, 0, "A red-flag prompt must never reach a coach provider")
    }

    // MARK: - VOL-284 — prescription clamps end to end

    /// A coach response prescribing an absurd load must be clamped both
    /// at extraction (what the athlete previews) and at the coach-source
    /// scheduling backstop (what persists), with `coach.safety.clamp`
    /// telemetry recording the intervention.
    func testCoachExtractedPlanClampsInsaneLoadBeforePersisting() async throws {
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)

        let preview = model.clampedCoachWorkoutPlan(
            from: "Squat: 3x5 at 855 lb\nBench Press: 3x8 at 600 lbs",
            title: "Coach Workout"
        )
        XCTAssertEqual(preview?.exercises.map(\.weight), [135, 135],
                       "No logged history -> barbell first-exposure cap")

        // Route the RAW extracted numbers at the persistence backstop to
        // prove no caller can bypass the clamp for coach-sourced plans.
        let scheduled = await model.scheduleWorkoutPlan(
            WorkoutSessionPlan(
                title: "Backstop Probe",
                targetRPE: 9,
                exercises: [WeeklyWorkoutExercise(
                    name: "Barbell Back Squat", sets: 3, reps: 5,
                    weight: 855, targetRPE: 9, restSeconds: 120
                )]
            ),
            on: .now,
            source: "coach"
        )
        XCTAssertTrue(scheduled)

        let persisted = try trainingPlanRepository.weeklyWorkouts()
            .first { $0.title == "Backstop Probe" }
        XCTAssertEqual(persisted?.exercises.first?.weight, 135)
        XCTAssertTrue(telemetry.currentEvents.contains {
            $0.category == "coach.safety" && $0.name == "clamp"
        })
    }

    private func makeDashboardModel(
        aiProvider: any AICoachProvider = LocalHeuristicAICoachProvider(),
        recoveryReader: any RecoveryReader = UnavailableRecoveryReader(),
        telemetrySink: any TelemetrySink = InMemoryTelemetrySink(),
        voicePermissionStore: any VoicePermissionStore = UnavailableVoicePermissionStore(),
        voiceCoach: LiveVoiceCoachOrchestrator? = nil,
        healthWorkoutImporter: any HealthWorkoutImporting = UnavailableHealthWorkoutImporter(),
        watchVoiceSettingsStore: any WatchVoiceSettingsStore = UserDefaultsWatchVoiceSettingsStore(),
        watchConnectivityCoordinator: WatchConnectivityCoordinator? = nil,
        activeSessionStateStore: ActiveWorkoutSessionStateStore = InMemoryActiveWorkoutSessionStateStore(),
        accountSessionStore: AccountSessionStore = InMemoryAccountSessionStore()
    ) -> WorkoutDashboardModel {
        WorkoutDashboardModel(
            aiProvider: aiProvider,
            syncEngine: CloudSyncCoordinator(
                transport: UnavailableCloudSyncTransport(reason: "Integration tests do not sync"),
                stateStore: FileSyncStateStore(
                    url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                )
            ),
            repository: workoutRepository,
            coachMemoryRepository: coachMemoryRepository,
            userProfileRepository: userProfileRepository,
            trainingPlanRepository: trainingPlanRepository,
            accountSessionStore: accountSessionStore,
            voicePermissionStore: voicePermissionStore,
            healthStore: UnavailableHealthStore(),
            notificationStore: InMemoryNotificationStore(),
            telemetrySink: telemetrySink,
            surfaceStore: UserDefaultsPlatformSurfaceStateStore(),
            subscriptionStore: StoreKitSubscriptionStore(productIDs: []),
            voiceCoach: voiceCoach ?? LiveVoiceCoachOrchestrator(
                transport: AIRelayVoiceTransport(provider: aiProvider)
            ),
            recoveryReader: recoveryReader,
            healthWorkoutImporter: healthWorkoutImporter,
            watchVoiceSettingsStore: watchVoiceSettingsStore,
            watchConnectivityCoordinator: watchConnectivityCoordinator,
            activeSessionStateStore: activeSessionStateStore
        )
    }

    // MARK: - VOL-200 P5 — Signals telemetry

    /// `recordSignalsViewed()` is wired from `SignalsView.task` to emit
    /// the three journey-catalog events (`signals.readiness.opened`,
    /// `signals.volume.opened`, `signals.frequency.opened`). The unit
    /// test pins the contract without booting the simulator — XCUITest
    /// coverage in `VolumeArcSignalsJourneyTests` exercises the
    /// view-appearance path.
    func testRecordSignalsViewedEmitsThreeCatalogEvents() throws {
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)

        model.recordSignalsViewed()

        let signalsEvents = telemetry.currentEvents.filter { $0.category == "signals" }
        XCTAssertEqual(signalsEvents.count, 3, "recordSignalsViewed should emit exactly three signals events")

        let names = Set(signalsEvents.map(\.name))
        XCTAssertEqual(
            names,
            ["readiness.opened", "volume.opened", "frequency.opened"],
            "Signals telemetry event names should match the journey catalog rows verbatim"
        )
    }

    // MARK: - VOL-256: active-workout crash recovery

    /// VOL-256 contract: a `WorkoutRecord` with `completedAt == nil`
    /// persisted in SwiftData survives crashes. On the next dashboard
    /// refresh (simulated here by constructing a fresh model + calling
    /// `refresh()`), the model rehydrates `isSessionActive`,
    /// `activeWorkoutID`, `activeWorkoutTitle`, and
    /// `loggedSetCountThisSession` from the persisted record. The
    /// Today tab's quick-actions row then surfaces "Continue Session"
    /// via the existing `model.isSessionActive` gate.
    ///
    /// This is the crash-recovery path: the SwiftData persistence
    /// survives, the model construction does not. If a regression
    /// removed the `loadActiveWorkout` query or the
    /// `if let active = snapshot.activeWorkout` branch in
    /// `WorkoutDashboardModel.refresh()`, this test fails.
    func testRefreshRehydratesInProgressWorkoutAfterCrashSimulation() async throws {
        // Stage 1: a previous launch started a workout but never
        // completed it. Insert a `WorkoutRecord` whose `completedAt`
        // is nil directly through the repository — same path the
        // production `startWorkoutSession()` action takes.
        let workout = try workoutRepository.createWorkout(
            title: "Crashed Heavy Lower",
            startedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )
        let workoutID = workout.identifier
        try workoutRepository.appendSet(
            WorkoutSetPerformance(
                weight: 225,
                reps: 5,
                rpe: 7.5,
                completedAt: Date(timeIntervalSince1970: 1_720_000_300)
            ),
            forExercise: "back-squat",
            to: workoutID
        )

        // Stage 2: simulate a crash by constructing a fresh
        // `WorkoutDashboardModel`. The model's in-memory state starts
        // empty — `isSessionActive` defaults to false. SwiftData
        // persistence is durable, so the unfinished record is still
        // on disk.
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)
        XCTAssertFalse(model.isSessionActive, "Fresh model must start with no active session.")

        // Stage 3: refresh — the dashboard refresh loader queries for
        // workouts with `completedAt == nil` and the model rehydrates
        // session state.
        _ = await model.refresh()

        XCTAssertTrue(model.isSessionActive, "Refresh must rehydrate isSessionActive from the persisted in-progress record.")
        XCTAssertEqual(model.activeWorkoutID, workoutID)
        XCTAssertEqual(model.activeWorkoutTitle, "Crashed Heavy Lower")
        XCTAssertEqual(model.loggedSetCountThisSession, 1, "The pre-crash set must still count toward the rehydrated session.")

        // Stage 4: the recovery emits a single telemetry event so
        // crash-recovery rate is observable in production.
        let recoveryEvents = telemetry.currentEvents.filter {
            $0.category == "workout" && $0.name == "active_session.recovered"
        }
        XCTAssertEqual(recoveryEvents.count, 1, "Recovery must emit exactly one telemetry event per restoration transition.")
        XCTAssertEqual(recoveryEvents.first?.metadata["workout_id"], workoutID)
        XCTAssertEqual(recoveryEvents.first?.metadata["completed_sets"], "1")
        XCTAssertEqual(recoveryEvents.first?.severity, .info)
    }

    /// Polling-refresh dedupe: once a session is already active in
    /// the model, subsequent refreshes that re-observe the same
    /// `activeWorkout` must NOT re-fire the `active_session.recovered`
    /// event. Without this guard, the periodic refresh loop would
    /// drown the telemetry stream in spurious "recovered" events.
    func testRefreshDoesNotReemitRecoveryEventWhileSessionAlreadyActive() async throws {
        let workout = try workoutRepository.createWorkout(
            title: "Heavy Lower",
            startedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )
        let workoutID = workout.identifier
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)

        _ = await model.refresh()  // First refresh — recovery event fires.
        _ = await model.refresh()  // Second refresh — already active, must NOT re-fire.
        _ = await model.refresh()  // Third refresh — same.

        let recoveryEvents = telemetry.currentEvents.filter {
            $0.category == "workout" && $0.name == "active_session.recovered"
        }
        XCTAssertEqual(recoveryEvents.count, 1, "Recovery event must dedupe across the polling refresh loop.")
        XCTAssertEqual(model.activeWorkoutID, workoutID)
    }

    func testRecordWorkoutDetailOpenedEmitsCatalogEventWithSessionMetadata() throws {
        let telemetry = InMemoryTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)
        let session = RecentSession(
            date: Date(timeIntervalSince1970: 1_720_000_000),
            durationMinutes: 52,
            exerciseIDs: ["back-squat", "bench-press"],
            totalVolumeLoad: 12_345,
            averageRPE: 7.5,
            completedSetCount: 9
        )

        model.recordWorkoutDetailOpened(session: session)

        let event = try XCTUnwrap(
            telemetry.currentEvents.first { $0.category == "workout" && $0.name == "detail.opened" }
        )
        XCTAssertEqual(event.severity, .info)
        XCTAssertEqual(event.metadata["sets"], "9")
        XCTAssertEqual(event.metadata["durationMinutes"], "52")
        XCTAssertEqual(event.metadata["volumeLoad"], "12345")
    }

    func testHandleWatchVoiceTogglePayloadPersistsMirroredSetting() async throws {
        let settings = DashboardTestWatchVoiceSettingsStore(enabled: true)
        let model = makeDashboardModel(watchVoiceSettingsStore: settings)
        let payload = WatchPayload(
            kind: .voiceCoachToggle,
            workoutID: "voice-toggle",
            body: WatchVoiceCoach.encodeSettingsPayload(isEnabled: false)
        )

        await model.handleWatchPayload(payload)

        let enabled = await settings.isWatchVoiceEnabled()
        XCTAssertFalse(enabled)
    }

    func testHandleWatchFormCheckStartAndStopDriveRemoteCaptureState() async throws {
        let model = makeDashboardModel()
        let request = WatchFormCheckStartPayload(
            sessionID: "form-session",
            exerciseID: FormCheckExercise.squat.rawValue,
            exerciseName: "Back Squat",
            setNumber: 1
        )

        await model.handleWatchPayload(
            WatchPayload(
                kind: .formCheckStart,
                workoutID: "watch",
                body: WatchFormCheckStartPayload.encode(request)
            )
        )

        XCTAssertEqual(model.activeWatchFormCheckRequest, request)
        XCTAssertNil(model.watchFormCheckStopToken)

        await model.handleWatchPayload(
            WatchPayload(
                kind: .formCheckStop,
                workoutID: "watch",
                body: WatchFormCheckStopPayload.encode(WatchFormCheckStopPayload(sessionID: request.sessionID))
            )
        )

        XCTAssertNotNil(model.watchFormCheckStopToken)
    }

    func testCompleteWatchFormCheckSendsResultPayloadToWatch() async throws {
        let transport = RecordingDashboardWatchTransport(reachable: true)
        let coordinator = WatchConnectivityCoordinator(
            transport: transport,
            payloadStore: DashboardInMemoryPendingPayloadStore()
        )
        let model = makeDashboardModel(watchConnectivityCoordinator: coordinator)
        let request = WatchFormCheckStartPayload(
            sessionID: "form-session",
            exerciseID: FormCheckExercise.squat.rawValue,
            exerciseName: "Back Squat",
            setNumber: 1
        )
        let analysis = FormCheckAnalysis(
            exercise: .squat,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 18,
            frameCount: 120,
            poseFrameCount: 120,
            averageConfidence: 0.92,
            reps: [],
            maxLateralDrift: 0.02,
            flags: [],
            verdict: .solid,
            hapticCode: .solid,
            cueText: "Clean reps."
        )

        await model.handleWatchPayload(
            WatchPayload(
                kind: .formCheckStart,
                workoutID: "watch",
                body: WatchFormCheckStartPayload.encode(request)
            )
        )
        await model.completeWatchFormCheck(analysis, sessionID: "form-session")

        XCTAssertNil(model.activeWatchFormCheckRequest)
        XCTAssertNil(model.watchFormCheckStopToken)
        let sent = await transport.sent
        let payload = try XCTUnwrap(sent.first { $0.kind == .formCheckResult })
        let result = try XCTUnwrap(WatchFormCheckResultPayload.decode(from: payload.body))
        XCTAssertEqual(result.sessionID, "form-session")
        XCTAssertEqual(result.verdict, .solid)
        XCTAssertEqual(result.cueText, "Clean reps.")
    }

    func testWatchConnectivityDropQueuesPayloadAndSurfacesNotice() async throws {
        let telemetry = InMemoryTelemetrySink()
        let transport = RecordingDashboardWatchTransport(reachable: false)
        let coordinator = WatchConnectivityCoordinator(
            transport: transport,
            payloadStore: DashboardInMemoryPendingPayloadStore(),
            telemetrySink: telemetry
        )
        let model = makeDashboardModel(
            telemetrySink: telemetry,
            watchConnectivityCoordinator: coordinator
        )
        let request = WatchFormCheckStartPayload(
            sessionID: "form-queued",
            exerciseID: FormCheckExercise.squat.rawValue,
            exerciseName: "Back Squat",
            setNumber: 1
        )
        let analysis = FormCheckAnalysis(
            exercise: .squat,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 18,
            frameCount: 120,
            poseFrameCount: 120,
            averageConfidence: 0.92,
            reps: [],
            maxLateralDrift: 0.02,
            flags: [],
            verdict: .solid,
            hapticCode: .solid,
            cueText: "Clean reps."
        )

        await model.handleWatchPayload(
            WatchPayload(
                kind: .formCheckStart,
                workoutID: "watch",
                body: WatchFormCheckStartPayload.encode(request)
            )
        )
        await model.completeWatchFormCheck(analysis, sessionID: request.sessionID)

        let pending = await coordinator.pendingPayloadCount()
        XCTAssertEqual(pending, 1)
        XCTAssertEqual(model.watchConnectivityNotice?.kind, .queued)
        XCTAssertEqual(model.watchConnectivityNotice?.severity, .warning)
        XCTAssertEqual(model.watchConnectivityNotice?.title, "Watch update queued")
        XCTAssertTrue(model.watchConnectivityNotice?.message.contains("1 update") == true)
        XCTAssertTrue(telemetry.currentEvents.contains {
            $0.category == "watch" && $0.name == "payload.queued"
        })
        XCTAssertTrue(telemetry.currentEvents.contains {
            $0.category == "watch.form_check" && $0.name == "result_sent_queued"
        })
    }

    func testWatchConnectivityReconnectReplaysQueuedPayloadAndUpdatesNotice() async throws {
        let telemetry = InMemoryTelemetrySink()
        let transport = RecordingDashboardWatchTransport(reachable: false)
        let coordinator = WatchConnectivityCoordinator(
            transport: transport,
            payloadStore: DashboardInMemoryPendingPayloadStore(),
            telemetrySink: telemetry
        )
        let model = makeDashboardModel(
            telemetrySink: telemetry,
            watchConnectivityCoordinator: coordinator
        )
        let request = WatchFormCheckStartPayload(
            sessionID: "form-replayed",
            exerciseID: FormCheckExercise.squat.rawValue,
            exerciseName: "Back Squat",
            setNumber: 1
        )
        let analysis = FormCheckAnalysis(
            exercise: .squat,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 18,
            frameCount: 120,
            poseFrameCount: 120,
            averageConfidence: 0.92,
            reps: [],
            maxLateralDrift: 0.02,
            flags: [],
            verdict: .solid,
            hapticCode: .solid,
            cueText: "Clean reps."
        )

        await model.handleWatchPayload(
            WatchPayload(
                kind: .formCheckStart,
                workoutID: "watch",
                body: WatchFormCheckStartPayload.encode(request)
            )
        )
        await model.completeWatchFormCheck(analysis, sessionID: request.sessionID)
        await transport.setReachable(true)
        await model.flushWatchConnectivityPendingPayloads()

        let pending = await coordinator.pendingPayloadCount()
        let sent = await transport.sent
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.kind, .formCheckResult)
        XCTAssertEqual(model.watchConnectivityNotice?.kind, .replayed)
        XCTAssertEqual(model.watchConnectivityNotice?.severity, .info)
        XCTAssertEqual(model.watchConnectivityNotice?.title, "Watch back in sync")
        XCTAssertTrue(model.watchConnectivityNotice?.message.contains("1 queued update") == true)
        XCTAssertTrue(telemetry.currentEvents.contains {
            $0.category == "watch" && $0.name == "payload.replayed"
        })
    }

    func testDismissWatchFormCheckSendsStoppedPayloadToWatch() async throws {
        let transport = RecordingDashboardWatchTransport(reachable: true)
        let coordinator = WatchConnectivityCoordinator(
            transport: transport,
            payloadStore: DashboardInMemoryPendingPayloadStore()
        )
        let model = makeDashboardModel(watchConnectivityCoordinator: coordinator)
        let request = WatchFormCheckStartPayload(
            sessionID: "form-dismissed",
            exerciseID: FormCheckExercise.squat.rawValue,
            exerciseName: "Back Squat",
            setNumber: 1
        )

        await model.handleWatchPayload(
            WatchPayload(
                kind: .formCheckStart,
                workoutID: "watch",
                body: WatchFormCheckStartPayload.encode(request)
            )
        )
        await model.dismissWatchFormCheckRequest(sessionID: request.sessionID)

        XCTAssertNil(model.activeWatchFormCheckRequest)
        XCTAssertNil(model.watchFormCheckStopToken)
        let sent = await transport.sent
        let payload = try XCTUnwrap(sent.first { $0.kind == .formCheckStopped })
        let stopped = try XCTUnwrap(WatchFormCheckStoppedPayload.decode(from: payload.body))
        XCTAssertEqual(stopped.sessionID, request.sessionID)
        XCTAssertEqual(stopped.reason, .userDismissed)
    }

    func testRejectWatchFormCheckSendsUnavailableStoppedPayloadToWatch() async throws {
        let transport = RecordingDashboardWatchTransport(reachable: true)
        let coordinator = WatchConnectivityCoordinator(
            transport: transport,
            payloadStore: DashboardInMemoryPendingPayloadStore()
        )
        let model = makeDashboardModel(watchConnectivityCoordinator: coordinator)
        let request = WatchFormCheckStartPayload(
            sessionID: "form-unavailable",
            exerciseID: "unsupported-lift",
            exerciseName: "Unsupported Lift",
            setNumber: 1
        )

        await model.handleWatchPayload(
            WatchPayload(
                kind: .formCheckStart,
                workoutID: "watch",
                body: WatchFormCheckStartPayload.encode(request)
            )
        )
        await model.rejectWatchFormCheckRequest(
            sessionID: request.sessionID,
            message: "This lift is not supported for camera form check yet."
        )

        XCTAssertNil(model.activeWatchFormCheckRequest)
        XCTAssertNil(model.watchFormCheckStopToken)
        let sent = await transport.sent
        let payload = try XCTUnwrap(sent.first { $0.kind == .formCheckStopped })
        let stopped = try XCTUnwrap(WatchFormCheckStoppedPayload.decode(from: payload.body))
        XCTAssertEqual(stopped.sessionID, request.sessionID)
        XCTAssertEqual(stopped.reason, .unavailable)
    }

    // MARK: - VOL-181 recovery wiring

    func testCoachContextIncludesInjectedRecoverySnapshot() async throws {
        let captured = CapturedContextStore()
        let provider = CapturingCoachProvider(store: captured)
        let recovery = RecoveryContext(
            hrvMean7Day: 58,
            hrvBaseline28Day: 54,
            hrvDeltaPercent: 7.4,
            sleep7DayTotalHours: 53,
            sleepDailyTargetHours: 8.0,
            sleepDebtHours: -3.0,
            strengthLoad7DayKJ: 2_100,
            strengthLoad7DayMinutes: 210
        )
        let model = makeDashboardModel(
            aiProvider: provider,
            recoveryReader: FixedRecoveryReader(value: recovery)
        )

        // Seed minimal training data so the prompt block has the
        // training-context section to anchor recovery against.
        let workout = try workoutRepository.createWorkout(
            title: "Squat Day",
            startedAt: .now.addingTimeInterval(-(45 * 60))
        )
        try workoutRepository.appendSet(
            WorkoutSetPerformance(weight: 235, reps: 5, rpe: 7.5, completedAt: .now.addingTimeInterval(-600)),
            forExercise: "back-squat",
            to: workout.identifier
        )
        try workoutRepository.completeWorkout(identifier: workout.identifier)

        await model.refresh()
        await model.askCoach("How am I looking?")

        let capturedValue = await captured.get()
        let context = try XCTUnwrap(capturedValue)
        XCTAssertTrue(
            context.contains("## Recovery (Apple Health)"),
            "Coach prompt should include the recovery section when reader provides data; got:\n\(context)"
        )
        XCTAssertTrue(
            context.contains("HRV: 58ms 7-day vs 54ms baseline"),
            "Coach prompt should surface the HRV triple from the recovery reader"
        )
        XCTAssertTrue(
            context.contains("behind target") || context.contains("significant deficit"),
            "Coach prompt should classify the -3h sleep debt descriptor"
        )
        XCTAssertTrue(
            context.contains("Training load (7d strength): 2100kJ across 210min"),
            "Coach prompt should surface the strength-load summary"
        )
    }

    func testCoachContextOmitsRecoverySectionWhenReaderEmpty() async throws {
        let captured = CapturedContextStore()
        let provider = CapturingCoachProvider(store: captured)
        let model = makeDashboardModel(
            aiProvider: provider,
            recoveryReader: UnavailableRecoveryReader()
        )

        await model.refresh()
        await model.askCoach("How am I doing?")

        let capturedValue = await captured.get()
        let context = try XCTUnwrap(capturedValue)
        XCTAssertFalse(
            context.contains("Recovery (Apple Health)"),
            "Coach prompt should omit the recovery section when reader returns empty context"
        )
    }
}

/// VOL-181: deterministic fake reader for unit + integration tests.
/// Lets a test pin a specific `RecoveryContext` and assert the model's
/// coach-prompt build path threads it through correctly.
private struct FixedRecoveryReader: RecoveryReader {
    let value: RecoveryContext

    func currentRecovery(now: Date) async -> RecoveryContext {
        value
    }
}

private struct FixedHealthWorkoutImporter: HealthWorkoutImporting {
    let workouts: [ImportedHealthWorkout]

    func completedWorkouts(since startDate: Date, now: Date) async throws -> [ImportedHealthWorkout] {
        workouts.filter { $0.startedAt >= startDate && $0.endedAt <= now }
    }
}

private struct ThrowingHealthWorkoutImporter: HealthWorkoutImporting {
    func completedWorkouts(since startDate: Date, now: Date) async throws -> [ImportedHealthWorkout] {
        throw DashboardHealthImportTestError.simulatedFailure
    }
}

private enum DashboardHealthImportTestError: Error {
    case simulatedFailure
}

private actor CapturedContextStore {
    private var context: String?
    private var prompt: String?
    func set(_ value: String) { context = value }
    func get() -> String? { context }
    // VOL-124: also capture the outbound free-text prompt so tests can
    // assert strict-mode question redaction on the relay egress path.
    func setPrompt(_ value: String) { prompt = value }
    func getPrompt() -> String? { prompt }
}

private struct CapturingCoachProvider: AICoachProvider, Sendable {
    let store: CapturedContextStore

    func coachResponse(for prompt: String, context: String) async throws -> String {
        await store.set(context)
        await store.setPrompt(prompt)
        return "Captured"
    }
}

private actor DashboardTestWatchVoiceSettingsStore: WatchVoiceSettingsStore {
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

private actor DashboardInMemoryPendingPayloadStore: WatchPendingPayloadStore {
    private var payloads: [WatchPayload] = []

    func enqueue(_ payload: WatchPayload) async {
        payloads.append(payload)
    }

    func enqueueFront(_ payload: WatchPayload) async {
        payloads.insert(payload, at: 0)
    }

    func dequeueAll() async -> [WatchPayload] {
        defer { payloads.removeAll() }
        return payloads
    }

    func count() async -> Int {
        payloads.count
    }
}

private actor RecordingDashboardWatchTransport: WatchSessionTransport {
    private(set) var sent: [WatchPayload] = []
    private var reachable: Bool

    init(reachable: Bool) {
        self.reachable = reachable
    }

    func activate() async {}

    func isReachable() async -> Bool {
        reachable
    }

    func setReachable(_ reachable: Bool) {
        self.reachable = reachable
    }

    func send(_ payload: WatchPayload) async throws {
        guard reachable else { throw WatchTransportError.notReachable }
        sent.append(payload)
    }
}

private actor CoachProviderInvocationSpy: AICoachProvider {
    private(set) var invocationCount = 0

    func coachResponse(for prompt: String, context: String) async throws -> String {
        invocationCount += 1
        // Unsafe sentinel — if the safety boundary ever leaks, the message
        // assertions fail loudly instead of passing on safe-looking copy.
        return "Push through and go heavy."
    }
}
#endif
