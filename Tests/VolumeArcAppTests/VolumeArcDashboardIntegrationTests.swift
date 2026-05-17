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
        let schema = Schema(VolumeArcSchemaV4.models)
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
    }

    override func tearDown() async throws {
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

    private func makeDashboardModel(
        aiProvider: any AICoachProvider = LocalHeuristicAICoachProvider(),
        recoveryReader: any RecoveryReader = UnavailableRecoveryReader()
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
            accountSessionStore: UserDefaultsAccountSessionStore(),
            voicePermissionStore: UnavailableVoicePermissionStore(),
            healthStore: UnavailableHealthStore(),
            notificationStore: InMemoryNotificationStore(),
            telemetrySink: InMemoryTelemetrySink(),
            surfaceStore: UserDefaultsPlatformSurfaceStateStore(),
            subscriptionStore: StoreKitSubscriptionStore(productIDs: []),
            voiceCoach: LiveVoiceCoachOrchestrator(
                transport: AIRelayVoiceTransport(provider: aiProvider)
            ),
            recoveryReader: recoveryReader
        )
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

private actor CapturedContextStore {
    private var context: String?
    func set(_ value: String) { context = value }
    func get() -> String? { context }
}

private struct CapturingCoachProvider: AICoachProvider, Sendable {
    let store: CapturedContextStore

    func coachResponse(for prompt: String, context: String) async throws -> String {
        await store.set(context)
        return "Captured"
    }
}
#endif
