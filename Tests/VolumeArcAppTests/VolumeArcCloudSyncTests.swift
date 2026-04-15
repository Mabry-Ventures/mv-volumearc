#if canImport(SwiftData)
import XCTest
import SwiftData
import VolumeArcCore

@MainActor
final class VolumeArcCloudSyncTests: XCTestCase {
    private var container: ModelContainer!
    private var outboundQueue: SwiftDataOutboundSyncQueue!
    private var workoutRepository: SwiftDataWorkoutRepository!
    private var coachMemoryRepository: SwiftDataCoachMemoryRepository!
    private var userProfileRepository: SwiftDataUserProfileRepository!
    private var trainingPlanRepository: SwiftDataTrainingPlanRepository!

    override func setUp() async throws {
        container = try Self.makeContainer(named: "CloudSyncTest-\(UUID().uuidString)")
        outboundQueue = SwiftDataOutboundSyncQueue(container: container)
        workoutRepository = SwiftDataWorkoutRepository(container: container, outboundQueue: outboundQueue)
        coachMemoryRepository = SwiftDataCoachMemoryRepository(container: container, outboundQueue: outboundQueue)
        userProfileRepository = SwiftDataUserProfileRepository(container: container, outboundQueue: outboundQueue)
        trainingPlanRepository = SwiftDataTrainingPlanRepository(container: container, outboundQueue: outboundQueue)
    }

    override func tearDown() async throws {
        container = nil
        outboundQueue = nil
        workoutRepository = nil
        coachMemoryRepository = nil
        userProfileRepository = nil
        trainingPlanRepository = nil
    }

    func testLocalWorkoutWriteProducesOutboundPayload() throws {
        let startedAt = Date(timeIntervalSince1970: 1_720_000_000)
        let workout = try workoutRepository.createWorkout(title: "Strength Day", startedAt: startedAt)

        let pending = try outboundQueue.pendingRecords()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].recordType, CloudSyncRecord.Kind.workout.rawValue)
        XCTAssertEqual(pending[0].operation, CloudSyncRecord.Operation.upsert.rawValue)
        XCTAssertEqual(pending[0].recordIdentifier, workout.identifier)

        let payload = try XCTUnwrap(SyncPayloadCodec.decodeWorkoutPayload(from: pending[0].payloadJSON))
        XCTAssertEqual(payload.title, workout.title)
        XCTAssertEqual(payload.startedAt, workout.startedAt)
        XCTAssertNil(payload.completedAt)
        XCTAssertEqual(payload.durationMinutes, workout.durationMinutes)
        XCTAssertEqual(payload.exerciseIDsCSV, workout.exerciseIDsCSV)
        XCTAssertEqual(payload.setsJSON, workout.setsJSON)
        XCTAssertEqual(payload.totalVolumeLoad, workout.totalVolumeLoad, accuracy: 0.001)
        XCTAssertEqual(payload.averageRPE, workout.averageRPE, accuracy: 0.001)
        XCTAssertEqual(payload.completedSetCount, workout.completedSetCount)
        XCTAssertEqual(payload.summary, workout.summary)
    }

    func testAppendSetProducesOutboundPayloadWithFullWorkoutState() throws {
        let workout = try workoutRepository.createWorkout(title: "Leg Day", startedAt: Date(timeIntervalSince1970: 1_720_000_100))
        let set = WorkoutSetPerformance(
            weight: 225,
            reps: 5,
            rpe: 7.5,
            completedAt: Date(timeIntervalSince1970: 1_720_000_160)
        )

        try workoutRepository.appendSet(set, forExercise: "back-squat", to: workout.identifier)

        let pending = try outboundQueue.pendingRecords()
        XCTAssertEqual(pending.count, 2)

        let payload = try XCTUnwrap(
            pending
                .compactMap { SyncPayloadCodec.decodeWorkoutPayload(from: $0.payloadJSON) }
                .first(where: { $0.completedSetCount == 1 && abs($0.totalVolumeLoad - 1125) < 0.001 })
        )
        let loggedSets = try XCTUnwrap(Self.decodeLoggedSets(from: payload.setsJSON))
        XCTAssertEqual(loggedSets.count, 1)
        XCTAssertEqual(loggedSets[0].exerciseID, "back-squat")
        XCTAssertEqual(loggedSets[0].set, set)
        XCTAssertEqual(payload.totalVolumeLoad, 1125, accuracy: 0.001)
        XCTAssertEqual(payload.completedSetCount, 1)
        XCTAssertEqual(payload.averageRPE, 7.5, accuracy: 0.001)
        XCTAssertEqual(payload.exerciseIDsCSV, "back-squat")
    }

    func testCompleteWorkoutProducesOutboundPayloadWithCompletedAt() throws {
        let workout = try workoutRepository.createWorkout(title: "Pull Day", startedAt: Date(timeIntervalSince1970: 1_720_000_200))
        try workoutRepository.appendSet(
            WorkoutSetPerformance(
                weight: 185,
                reps: 6,
                rpe: 8,
                completedAt: Date(timeIntervalSince1970: 1_720_000_260)
            ),
            forExercise: "barbell-row",
            to: workout.identifier
        )

        try workoutRepository.completeWorkout(identifier: workout.identifier, summary: "Solid session")

        let pending = try outboundQueue.pendingRecords()
        XCTAssertEqual(pending.count, 3)

        let payload = try XCTUnwrap(
            pending
                .compactMap { SyncPayloadCodec.decodeWorkoutPayload(from: $0.payloadJSON) }
                .first(where: { $0.completedAt != nil && $0.summary == "Solid session" })
        )
        XCTAssertNotNil(payload.completedAt)
        XCTAssertEqual(payload.summary, "Solid session")
        XCTAssertGreaterThan(payload.durationMinutes, 0)
    }

    func testRoundTripWorkoutPayloadEqualsOriginal() async throws {
        let sourceContainer = try Self.makeContainer(named: "RoundTripSource-\(UUID().uuidString)")
        let sourceContext = ModelContext(sourceContainer)
        let startedAt = Date(timeIntervalSince1970: 1_720_000_300)
        let completedAt = startedAt.addingTimeInterval(2_400)
        let updatedAt = startedAt.addingTimeInterval(2_460)
        let original = WorkoutRecord(
            identifier: "roundtrip-workout",
            title: "Round Trip",
            startedAt: startedAt,
            completedAt: completedAt,
            durationMinutes: 40,
            exerciseIDsCSV: "back-squat,bench-press",
            setsJSON: Self.makeLoggedSetsJSON([
                LoggedSetFixture(
                    exerciseID: "back-squat",
                    set: WorkoutSetPerformance(weight: 225, reps: 5, rpe: 8, completedAt: startedAt.addingTimeInterval(300))
                ),
                LoggedSetFixture(
                    exerciseID: "bench-press",
                    set: WorkoutSetPerformance(weight: 185, reps: 6, rpe: 8.5, completedAt: startedAt.addingTimeInterval(900))
                ),
            ]),
            totalVolumeLoad: 2_235,
            averageRPE: 8.25,
            completedSetCount: 2,
            summary: "Strong finish",
            updatedAt: updatedAt
        )
        sourceContext.insert(original)
        try sourceContext.save()

        let outboundRecord = try XCTUnwrap(SyncPayloadCodec.makeRecord(for: original))

        let destinationContainer = try Self.makeContainer(named: "RoundTripDestination-\(UUID().uuidString)")
        let applier = makeApplier(container: destinationContainer)
        try await applier.apply(result: CloudSyncPullResult(changedRecords: [outboundRecord], deletedRecordIDs: [], nextCursor: nil))

        let destinationRepository = SwiftDataWorkoutRepository(container: destinationContainer)
        let restored = try XCTUnwrap(destinationRepository.workout(withIdentifier: original.identifier))
        assertWorkout(restored, equals: original)
    }

    func testServerWinsConflictResolutionByTimestamp() async throws {
        let localWorkout = try workoutRepository.createWorkout(
            title: "Local Workout",
            startedAt: Date(timeIntervalSince1970: 1_720_000_400),
            updatedAt: Date(timeIntervalSince1970: 1_720_000_500)
        )
        try Self.updateWorkout(
            identifier: localWorkout.identifier,
            in: container,
            title: "Local Workout",
            summary: "Local summary",
            totalVolumeLoad: 500,
            averageRPE: 7.0,
            completedSetCount: 1,
            updatedAt: Date(timeIntervalSince1970: 1_720_000_500)
        )

        let inbound = WorkoutRecord(
            identifier: localWorkout.identifier,
            title: "Server Workout",
            startedAt: Date(timeIntervalSince1970: 1_720_000_400),
            completedAt: Date(timeIntervalSince1970: 1_720_000_800),
            durationMinutes: 30,
            exerciseIDsCSV: "deadlift",
            setsJSON: Self.makeLoggedSetsJSON([
                LoggedSetFixture(
                    exerciseID: "deadlift",
                    set: WorkoutSetPerformance(weight: 315, reps: 3, rpe: 9, completedAt: Date(timeIntervalSince1970: 1_720_000_760))
                ),
            ]),
            totalVolumeLoad: 945,
            averageRPE: 9,
            completedSetCount: 1,
            summary: "Server summary",
            updatedAt: Date(timeIntervalSince1970: 1_720_000_900)
        )
        let record = try XCTUnwrap(SyncPayloadCodec.makeRecord(for: inbound))

        let telemetry = InMemoryTelemetrySink()
        let applier = makeApplier(container: container, telemetrySink: telemetry)
        try await applier.apply(result: CloudSyncPullResult(changedRecords: [record], deletedRecordIDs: [], nextCursor: nil))

        let updated = try XCTUnwrap(workoutRepository.workout(withIdentifier: localWorkout.identifier))
        assertWorkout(updated, equals: inbound)
        XCTAssertFalse(telemetry.currentEvents.contains { $0.name == "sync_conflict_local_wins" })
    }

    func testClientWinsConflictResolutionWhenLocalIsNewer() async throws {
        let identifier = "client-wins-workout"
        let localUpdatedAt = Date(timeIntervalSince1970: 1_720_001_000)
        let inboundUpdatedAt = Date(timeIntervalSince1970: 1_720_000_900)

        let localWorkout = WorkoutRecord(
            identifier: identifier,
            title: "Local Wins",
            startedAt: Date(timeIntervalSince1970: 1_720_000_700),
            completedAt: Date(timeIntervalSince1970: 1_720_001_020),
            durationMinutes: 35,
            exerciseIDsCSV: "bench-press",
            setsJSON: Self.makeLoggedSetsJSON([
                LoggedSetFixture(
                    exerciseID: "bench-press",
                    set: WorkoutSetPerformance(weight: 205, reps: 5, rpe: 8, completedAt: Date(timeIntervalSince1970: 1_720_000_900))
                ),
            ]),
            totalVolumeLoad: 1_025,
            averageRPE: 8,
            completedSetCount: 1,
            summary: "Newest local",
            updatedAt: localUpdatedAt
        )
        let context = ModelContext(container)
        context.insert(localWorkout)
        try context.save()

        let inbound = WorkoutRecord(
            identifier: identifier,
            title: "Older Server",
            startedAt: Date(timeIntervalSince1970: 1_720_000_700),
            completedAt: Date(timeIntervalSince1970: 1_720_000_980),
            durationMinutes: 25,
            exerciseIDsCSV: "bench-press",
            setsJSON: Self.makeLoggedSetsJSON([
                LoggedSetFixture(
                    exerciseID: "bench-press",
                    set: WorkoutSetPerformance(weight: 185, reps: 5, rpe: 7, completedAt: Date(timeIntervalSince1970: 1_720_000_840))
                ),
            ]),
            totalVolumeLoad: 925,
            averageRPE: 7,
            completedSetCount: 1,
            summary: "Older server",
            updatedAt: inboundUpdatedAt
        )
        let record = try XCTUnwrap(SyncPayloadCodec.makeRecord(for: inbound))

        let telemetry = InMemoryTelemetrySink()
        let applier = makeApplier(container: container, telemetrySink: telemetry)
        try await applier.apply(result: CloudSyncPullResult(changedRecords: [record], deletedRecordIDs: [], nextCursor: nil))

        let fetched = try XCTUnwrap(workoutRepository.workout(withIdentifier: identifier))
        assertWorkout(fetched, equals: localWorkout)
        XCTAssertTrue(telemetry.currentEvents.contains { $0.name == "sync_conflict_local_wins" })
    }

    func testProfileUpsertProducesOutboundPayload() throws {
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

        let pending = try outboundQueue.pendingRecords()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].recordType, CloudSyncRecord.Kind.userProfile.rawValue)
        XCTAssertEqual(pending[0].recordIdentifier, CloudSyncRecord.Kind.userProfile.defaultIdentifier)

        let payload = try XCTUnwrap(SyncPayloadCodec.decodeUserProfilePayload(from: pending[0].payloadJSON))
        XCTAssertEqual(payload.name, defaults.name)
        XCTAssertEqual(payload.coachingStyle, defaults.coachingStyle.rawValue)
        XCTAssertEqual(payload.privacyMode, defaults.privacyMode.rawValue)
        XCTAssertEqual(payload.advancementLevel, defaults.advancementLevel.rawValue)
        XCTAssertEqual(payload.availableEquipmentCSV, "barbell,dumbbell")
        XCTAssertEqual(payload.preferredRepRangeLower, defaults.preferredRepRangeLower)
        XCTAssertEqual(payload.preferredRepRangeUpper, defaults.preferredRepRangeUpper)
        XCTAssertEqual(payload.sessionTimeBudgetMinutes, defaults.sessionTimeBudgetMinutes)
        XCTAssertEqual(payload.weeklyTrainingDays, defaults.weeklyTrainingDays)
        XCTAssertFalse(payload.onboardingCompleted)
    }

    func testTrainingPlanUpsertProducesOutboundPayload() throws {
        let workouts = [
            WeeklyWorkout(dayOfWeek: 1, title: "Monday Squat"),
            WeeklyWorkout(dayOfWeek: 3, title: "Wednesday Bench"),
        ]

        try trainingPlanRepository.upsertPlan(workouts)

        let pending = try outboundQueue.pendingRecords()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].recordType, CloudSyncRecord.Kind.trainingPlan.rawValue)
        XCTAssertEqual(pending[0].recordIdentifier, CloudSyncRecord.Kind.trainingPlan.defaultIdentifier)

        let payload = try XCTUnwrap(SyncPayloadCodec.decodeTrainingPlanPayload(from: pending[0].payloadJSON))
        let decoded = try XCTUnwrap(SyncPayloadCodec.decode([WeeklyWorkout].self, from: payload.workoutsJSON))
        XCTAssertEqual(decoded.map(\.dayOfWeek), workouts.map(\.dayOfWeek))
        XCTAssertEqual(decoded.map(\.title), workouts.map(\.title))
    }

    func testCoachMemoryAppendProducesOutboundPayload() throws {
        try coachMemoryRepository.append(content: "Back squat moved well.", theme: "squat")

        let pending = try outboundQueue.pendingRecords()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].recordType, CloudSyncRecord.Kind.coachMemory.rawValue)
        XCTAssertFalse(pending[0].recordIdentifier.isEmpty)

        let payload = try XCTUnwrap(SyncPayloadCodec.decodeCoachMemoryPayload(from: pending[0].payloadJSON))
        XCTAssertEqual(payload.content, "Back squat moved well.")
        XCTAssertEqual(payload.theme, "squat")
    }

    func testPushDrainsQueueAndDeletesRowsOnSuccess() async throws {
        _ = try workoutRepository.createWorkout(title: "Push Queue", startedAt: Date(timeIntervalSince1970: 1_720_001_100))
        try userProfileRepository.upsertProfile(
            UserProfileDefaults(
                name: "Queue User",
                coachingStyle: .motivational,
                privacyMode: .standard,
                advancementLevel: .intermediate,
                availableEquipment: [.barbell],
                preferredRepRangeLower: 5,
                preferredRepRangeUpper: 8,
                sessionTimeBudgetMinutes: 60,
                weeklyTrainingDays: 4
            )
        )
        try coachMemoryRepository.append(content: "Queue memory", theme: "queue")

        let transport = RecordingCloudSyncTransport()
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue
        )

        let pushedCount = try await coordinator.push()
        XCTAssertEqual(pushedCount, 3)
        XCTAssertTrue(try outboundQueue.pendingRecords().isEmpty)
        let pushedRecords = await transport.pushedRecords
        XCTAssertEqual(pushedRecords.count, 3)
    }

    func testPushRetainsQueueOnTransportFailure() async throws {
        _ = try workoutRepository.createWorkout(title: "Retain Queue", startedAt: Date(timeIntervalSince1970: 1_720_001_200))
        try coachMemoryRepository.append(content: "Should stay queued", theme: "failure")

        let transport = RecordingCloudSyncTransport(shouldThrow: true)
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await coordinator.push()
        }

        XCTAssertEqual(try outboundQueue.pendingRecords().count, 2)
        let pushedRecords = await transport.pushedRecords
        XCTAssertTrue(pushedRecords.isEmpty)
    }

    // MARK: - VOL-67 fixup: pull-before-push + stale-queue invalidation

    /// Codex P1: `syncCycle()` must pull remote changes before pushing
    /// queued writes, so the applier's `shouldApply` timestamp check has
    /// a chance to run against the pre-push remote state.
    func testSyncCyclePullsBeforePushing() async throws {
        _ = try workoutRepository.createWorkout(title: "Ordering Probe", startedAt: Date(timeIntervalSince1970: 1_720_010_000))

        let transport = RecordingCloudSyncTransport()
        let applier = makeApplier(container: container, outboundQueue: outboundQueue)
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            payloadApplier: applier,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue
        )

        _ = try await coordinator.syncCycle()

        let pullOrder = await transport.pullCallOrder
        let pushOrder = await transport.pushCallOrder
        XCTAssertEqual(pullOrder.count, 1, "Expected exactly one pull in a single sync cycle")
        XCTAssertEqual(pushOrder.count, 1, "Expected exactly one push in a single sync cycle")
        XCTAssertLessThan(pullOrder[0], pushOrder[0], "Pull must happen strictly before push")
    }

    /// Codex P1 scenario: device A has a stale queued upsert and device B
    /// has already written a newer version of the same workout to the
    /// server. When A runs `syncCycle()`, it must (1) pull B's newer
    /// version and update local state, (2) invalidate A's stale queued
    /// entry, (3) push nothing (the only queued row was stale).
    func testSyncCycleInvalidatesStaleQueuedUpsertWhenPullBringsNewerVersion() async throws {
        // 1) Local (stale) write at T0, queued.
        let workoutID = "shared-workout"
        let t0 = Date(timeIntervalSince1970: 1_720_020_000)
        let staleWorkout = WorkoutRecord(
            identifier: workoutID,
            title: "Stale Local",
            startedAt: t0,
            totalVolumeLoad: 100,
            averageRPE: 7,
            completedSetCount: 1,
            summary: "stale",
            updatedAt: t0
        )
        let context = ModelContext(container)
        context.insert(staleWorkout)
        try context.save()
        try outboundQueue.enqueue(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: workoutID,
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: SyncPayloadCodec.encodeWorkoutPayload(from: staleWorkout) ?? "",
            queuedAt: t0
        )
        XCTAssertEqual(try outboundQueue.pendingRecords().count, 1)

        // 2) Server (device B) has a newer version at T1.
        let t1 = t0.addingTimeInterval(60)
        let serverWorkout = WorkoutRecord(
            identifier: workoutID,
            title: "Remote Winner",
            startedAt: t0,
            durationMinutes: 45,
            totalVolumeLoad: 2_000,
            averageRPE: 8.5,
            completedSetCount: 10,
            summary: "remote",
            updatedAt: t1
        )
        let serverRecord = try XCTUnwrap(SyncPayloadCodec.makeRecord(for: serverWorkout))
        let transport = RecordingCloudSyncTransport(pullResult: {
            CloudSyncPullResult(changedRecords: [serverRecord], deletedRecordIDs: [], nextCursor: nil)
        })

        // 3) Run syncCycle. Pull-first must apply server's T1 AND drop A's T0 queue entry.
        let applier = makeApplier(container: container, outboundQueue: outboundQueue)
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            payloadApplier: applier,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue
        )
        _ = try await coordinator.syncCycle()

        // 4) Local workout is now at T1 with remote's fields.
        let restored = try XCTUnwrap(workoutRepository.workout(withIdentifier: workoutID))
        XCTAssertEqual(restored.title, "Remote Winner")
        XCTAssertEqual(restored.updatedAt.timeIntervalSince1970, t1.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(restored.totalVolumeLoad, 2_000, accuracy: 0.001)

        // 5) Queue is empty — the stale T0 entry was invalidated.
        XCTAssertTrue(try outboundQueue.pendingRecords().isEmpty)

        // 6) Push was called but nothing was actually sent (queue was empty by then).
        let pushed = await transport.pushedRecords
        XCTAssertTrue(pushed.isEmpty, "Stale queued write must not reach the transport")
    }

    /// Codex P1 (follow-up): when the user deletes a workout, the
    /// outbound queue entry's `queuedAt` must reflect the deletion
    /// wall-clock time, NOT the record's prior `updatedAt`. If we used
    /// the old value, a newer inbound pull between the record's last
    /// update and the delete would cause the applier's
    /// `invalidateEntries(olderThan:)` to drop the queued delete,
    /// silently losing the user's delete intent.
    func testDeleteWorkoutEnqueuesWithActualDeletionTimestamp() throws {
        let t0 = Date(timeIntervalSince1970: 1_720_050_000)
        let workout = try workoutRepository.createWorkout(title: "To Delete", startedAt: t0, updatedAt: t0)
        XCTAssertEqual(workout.updatedAt.timeIntervalSince1970, t0.timeIntervalSince1970, accuracy: 0.01)

        // Clear the create upsert so we're only looking at the delete.
        let createEntries = try outboundQueue.pendingRecords()
        try outboundQueue.delete(ids: createEntries.map(\.id))
        XCTAssertTrue(try outboundQueue.pendingRecords().isEmpty)

        let beforeDelete = Date()
        try workoutRepository.deleteWorkout(identifier: workout.identifier)
        let afterDelete = Date()

        let deleteEntries = try outboundQueue.pendingRecords()
        XCTAssertEqual(deleteEntries.count, 1)
        let deleteEntry = try XCTUnwrap(deleteEntries.first)
        XCTAssertEqual(deleteEntry.operation, CloudSyncRecord.Operation.delete.rawValue)
        XCTAssertEqual(deleteEntry.recordIdentifier, workout.identifier)
        // queuedAt must be the actual delete instant (≥ beforeDelete, ≤ afterDelete),
        // NOT the record's stale `updatedAt` which was set at create time.
        XCTAssertGreaterThanOrEqual(deleteEntry.queuedAt.timeIntervalSince1970,
                                     beforeDelete.timeIntervalSince1970 - 0.001,
                                     "Queued delete timestamp must be >= delete wall-clock")
        XCTAssertLessThanOrEqual(deleteEntry.queuedAt.timeIntervalSince1970,
                                  afterDelete.timeIntervalSince1970 + 0.001,
                                  "Queued delete timestamp must be <= delete wall-clock")
        XCTAssertGreaterThan(deleteEntry.queuedAt.timeIntervalSince1970,
                             t0.timeIntervalSince1970,
                             "Queued delete timestamp must be strictly newer than the record's original updatedAt")
    }

    /// Codex P1 (follow-up): the `CloudSyncRecord` built from a queued
    /// delete must use the delete's `queuedAt` as its `modifiedAt`,
    /// not the payload's embedded `updatedAt` (which was snapshotted
    /// pre-delete). Otherwise the pushed tombstone carries a stale
    /// timestamp and server-side LWW can silently overwrite it.
    func testPushedDeleteRecordUsesDeletionTimestampAsModifiedAt() async throws {
        // 1) Create, then delete, a workout. The queued entry's queuedAt
        //    is the delete time; the payload's embedded updatedAt is the
        //    pre-delete create time.
        let createdAt = Date(timeIntervalSince1970: 1_720_060_000)
        let workout = try workoutRepository.createWorkout(title: "Delete Me", startedAt: createdAt, updatedAt: createdAt)
        XCTAssertEqual(workout.updatedAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 0.01)

        let beforeDelete = Date()
        try workoutRepository.deleteWorkout(identifier: workout.identifier)
        let afterDelete = Date()

        // 2) Push via coordinator so we see what modifiedAt the transport
        //    actually receives on the outbound CloudSyncRecord.
        let transport = RecordingCloudSyncTransport()
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue
        )
        _ = try await coordinator.push()

        // 3) Locate the delete record among the pushed batch and check
        //    that its modifiedAt matches the delete wall-clock, not the
        //    stale createdAt embedded in the payload.
        let pushed = await transport.pushedRecords
        let deleteRecord = try XCTUnwrap(pushed.first(where: {
            $0.kind == .workout && $0.operation == .delete && $0.identifier == workout.identifier
        }))
        XCTAssertGreaterThanOrEqual(deleteRecord.modifiedAt.timeIntervalSince1970,
                                     beforeDelete.timeIntervalSince1970 - 0.001)
        XCTAssertLessThanOrEqual(deleteRecord.modifiedAt.timeIntervalSince1970,
                                  afterDelete.timeIntervalSince1970 + 0.001)
        XCTAssertGreaterThan(deleteRecord.modifiedAt.timeIntervalSince1970,
                             createdAt.timeIntervalSince1970,
                             "Delete tombstone modifiedAt must be the delete wall-clock, not the record's pre-delete updatedAt")
    }

    /// Codex P1 scenario: device A has a stale queued upsert for a
    /// workout that device B has already deleted on the server. When A
    /// runs `syncCycle()`, it must (1) apply the remote delete locally,
    /// (2) unconditionally clear A's queued upsert so it can't
    /// resurrect the record on the next push.
    func testSyncCycleInvalidatesQueuedUpsertWhenPullDeliversDeletion() async throws {
        // 1) Local stale upsert is queued.
        let workoutID = "doomed-workout"
        let t0 = Date(timeIntervalSince1970: 1_720_030_000)
        let doomed = try workoutRepository.createWorkout(title: "Doomed", startedAt: t0)
        XCTAssertEqual(try outboundQueue.pendingRecords().count, 1)

        // 2) Server has a delete record for the same identifier.
        let deleteRecord = CloudSyncRecord(
            kind: .workout,
            identifier: doomed.identifier,
            operation: .delete,
            payloadJSON: "",
            modifiedAt: t0.addingTimeInterval(120)
        )
        let transport = RecordingCloudSyncTransport(pullResult: {
            CloudSyncPullResult(changedRecords: [deleteRecord], deletedRecordIDs: [], nextCursor: nil)
        })

        // 3) Run syncCycle.
        let applier = makeApplier(container: container, outboundQueue: outboundQueue)
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            payloadApplier: applier,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue
        )
        _ = try await coordinator.syncCycle()

        // 4) Local workout is gone AND the queue is empty — no resurrection path.
        XCTAssertNil(try workoutRepository.workout(withIdentifier: workoutID))
        XCTAssertTrue(try outboundQueue.pendingRecords().isEmpty)

        // 5) Nothing was pushed to the transport.
        let pushed = await transport.pushedRecords
        XCTAssertTrue(pushed.isEmpty, "Queued upsert must not reach the transport after an inbound delete")
    }

    // MARK: - VOL-67 Codex P1 #3: coalesce drained rows before push

    /// Multiple mutations of the same workout must collapse to a
    /// single pushed record. Without this, CloudKit receives
    /// duplicate `CKRecord`s with the same `CKRecord.ID` in one
    /// `CKModifyRecordsOperation`, which may be rejected or applied
    /// in undefined order.
    func testPushCoalescesMultipleUpsertsForSameRecord() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_720_070_000)
        let workout = try workoutRepository.createWorkout(title: "Coalesce Me", startedAt: startedAt)

        // Three successive sets → three upserts queued for the same workout.
        for (index, weight) in [225.0, 230.0, 235.0].enumerated() {
            try workoutRepository.appendSet(
                WorkoutSetPerformance(
                    weight: weight,
                    reps: 5,
                    rpe: 7.5,
                    completedAt: startedAt.addingTimeInterval(Double(index * 60 + 60))
                ),
                forExercise: "back-squat",
                to: workout.identifier
            )
        }

        let pendingBefore = try outboundQueue.pendingRecords()
            .filter { $0.recordType == CloudSyncRecord.Kind.workout.rawValue && $0.recordIdentifier == workout.identifier }
        XCTAssertEqual(pendingBefore.count, 4, "Expected 4 queued workout upserts (1 create + 3 appendSet)")

        let transport = RecordingCloudSyncTransport()
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue
        )

        let pushedCount = try await coordinator.push()
        XCTAssertEqual(pushedCount, 1, "Four upserts for the same workout must coalesce to one pushed record")

        let pushed = await transport.pushedRecords
        let workoutRecords = pushed.filter { $0.kind == .workout && $0.identifier == workout.identifier }
        XCTAssertEqual(workoutRecords.count, 1, "Transport must receive exactly one CKRecord per workout identifier")

        // The pushed record must reflect the final state (235 lb set, 3 sets total).
        let pushedPayload = try XCTUnwrap(SyncPayloadCodec.decodeWorkoutPayload(from: workoutRecords[0].payloadJSON))
        XCTAssertEqual(pushedPayload.completedSetCount, 3)
        XCTAssertEqual(pushedPayload.totalVolumeLoad, 225.0 * 5 + 230.0 * 5 + 235.0 * 5, accuracy: 0.001)

        // Every drained row (including superseded ones) is cleared from the queue.
        XCTAssertTrue(try outboundQueue.pendingRecords().filter {
            $0.recordType == CloudSyncRecord.Kind.workout.rawValue && $0.recordIdentifier == workout.identifier
        }.isEmpty)
    }

    /// An upsert followed by a delete for the same record should
    /// collapse to the delete. Otherwise CloudKit would receive both
    /// an upsert and a delete for the same `CKRecord.ID` in one
    /// batch, with undefined ordering.
    func testPushCoalescesUpsertFollowedByDeleteToDelete() async throws {
        let workout = try workoutRepository.createWorkout(title: "Create Then Delete", startedAt: Date(timeIntervalSince1970: 1_720_080_000))
        try workoutRepository.deleteWorkout(identifier: workout.identifier)

        // Queue now has: create upsert + delete, both for the same workout.
        let pendingBefore = try outboundQueue.pendingRecords().filter {
            $0.recordType == CloudSyncRecord.Kind.workout.rawValue && $0.recordIdentifier == workout.identifier
        }
        XCTAssertEqual(pendingBefore.count, 2)

        let transport = RecordingCloudSyncTransport()
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue
        )

        _ = try await coordinator.push()

        let pushed = await transport.pushedRecords
        let forThisWorkout = pushed.filter { $0.kind == .workout && $0.identifier == workout.identifier }
        XCTAssertEqual(forThisWorkout.count, 1, "Upsert+delete must coalesce to one pushed record")
        XCTAssertEqual(forThisWorkout[0].operation, .delete, "Coalesced result must be the delete")
        XCTAssertTrue(try outboundQueue.pendingRecords().isEmpty)
    }

    // MARK: - VOL-67 Codex P2: legacy record type aliases

    /// Codex P2 (fixup #6): `shouldApply` treats equal timestamps as
    /// inbound-wins (strict `>` for the reject branch), but
    /// `invalidateEntries` was keeping rows where `queuedAt >= olderThan`.
    /// On tied timestamps the applier would apply the inbound record
    /// while the same-timestamp queue row survived, then the next push
    /// would resend the stale payload and overwrite the freshly-applied
    /// state. Fix: strict `>` so ties drop the queue row, matching the
    /// applier.
    func testInvalidateEntriesDropsRowsOnExactTimestampTies() throws {
        let tiedTimestamp = Date(timeIntervalSince1970: 1_720_090_000)
        try outboundQueue.enqueue(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: "tied-workout",
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: "{}",
            queuedAt: tiedTimestamp
        )
        XCTAssertEqual(try outboundQueue.pendingRecords().count, 1)

        // Invalidate with the EXACT same timestamp — the row should be
        // dropped (inbound wins ties, matching shouldApply semantics).
        try outboundQueue.invalidateEntries(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: "tied-workout",
            olderThan: tiedTimestamp
        )
        XCTAssertTrue(try outboundQueue.pendingRecords().isEmpty,
                      "Queue row with queuedAt == olderThan must be invalidated (inbound wins ties)")
    }

    /// Complement: a row strictly NEWER than the inbound timestamp
    /// should NOT be invalidated (local is newer, the push is still
    /// meaningful and should survive).
    func testInvalidateEntriesKeepsRowsStrictlyNewerThanOlderThan() throws {
        let older = Date(timeIntervalSince1970: 1_720_090_000)
        let newer = older.addingTimeInterval(1)
        try outboundQueue.enqueue(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: "newer-workout",
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: "{}",
            queuedAt: newer
        )

        try outboundQueue.invalidateEntries(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: "newer-workout",
            olderThan: older
        )
        XCTAssertEqual(try outboundQueue.pendingRecords().count, 1,
                       "Queue row with queuedAt > olderThan must NOT be invalidated")
    }

    // MARK: - VOL-67 Codex P2 #6: synthesize legacy field-based payloads

    /// Pre-VOL-67 CKRecords may have stored each payload field as an
    /// individual CKRecord key (e.g., `title`, `startedAt`, `updatedAt`)
    /// instead of a single `payloadJSON` blob. The applier requires a
    /// canonical `payloadJSON`, so the transport synthesizes one via
    /// `SyncPayloadCodec.synthesizeLegacyPayloadJSON(kind:fields:)`
    /// when `payloadJSON` is missing. Without this, pre-rename
    /// records would silently decode-fail while the sync cursor
    /// advanced, losing the cloud data.
    func testSynthesizeLegacyPayloadForWorkoutFields() throws {
        let startedAt = Date(timeIntervalSince1970: 1_720_100_000)
        let updatedAt = startedAt.addingTimeInterval(1_800)
        let fields: [String: Any] = [
            "title": "Legacy Workout",
            "startedAt": startedAt,
            "completedAt": startedAt.addingTimeInterval(1_800),
            "durationMinutes": 30,
            "exerciseIDsCSV": "back-squat,bench-press",
            "setsJSON": "[]",
            "totalVolumeLoad": 2_250.0,
            "averageRPE": 7.5,
            "completedSetCount": 5,
            "summary": "From a pre-VOL-67 record",
            "updatedAt": updatedAt,
        ]

        let json = try XCTUnwrap(
            SyncPayloadCodec.synthesizeLegacyPayloadJSON(kind: .workout, fields: fields),
            "Legacy field-based workout record must synthesize a canonical payloadJSON"
        )

        let decoded = try XCTUnwrap(SyncPayloadCodec.decodeWorkoutPayload(from: json))
        XCTAssertEqual(decoded.title, "Legacy Workout")
        XCTAssertEqual(decoded.startedAt.timeIntervalSince1970, startedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.durationMinutes, 30)
        XCTAssertEqual(decoded.totalVolumeLoad, 2_250.0, accuracy: 0.001)
        XCTAssertEqual(decoded.completedSetCount, 5)
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970, updatedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testSynthesizeLegacyPayloadForUserProfileFields() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_720_110_000)
        let fields: [String: Any] = [
            "name": "Legacy Athlete",
            "coachingStyle": "methodical",
            "privacyMode": "strict",
            "advancementLevel": "advanced",
            "availableEquipmentCSV": "barbell,dumbbell",
            "preferredRepRangeLower": 6,
            "preferredRepRangeUpper": 10,
            "sessionTimeBudgetMinutes": 75,
            "weeklyTrainingDays": 5,
            "onboardingCompleted": true,
            "updatedAt": updatedAt,
        ]

        let json = try XCTUnwrap(
            SyncPayloadCodec.synthesizeLegacyPayloadJSON(kind: .userProfile, fields: fields)
        )
        let decoded = try XCTUnwrap(SyncPayloadCodec.decodeUserProfilePayload(from: json))
        XCTAssertEqual(decoded.name, "Legacy Athlete")
        XCTAssertEqual(decoded.advancementLevel, "advanced")
        XCTAssertEqual(decoded.preferredRepRangeLower, 6)
        XCTAssertEqual(decoded.preferredRepRangeUpper, 10)
        XCTAssertTrue(decoded.onboardingCompleted)
    }

    func testSynthesizeLegacyPayloadReturnsNilWhenRequiredFieldsMissing() {
        // Missing `title` (required) → nil.
        let fields: [String: Any] = [
            "startedAt": Date(timeIntervalSince1970: 1_720_120_000),
            "updatedAt": Date(timeIntervalSince1970: 1_720_120_000),
        ]
        XCTAssertNil(SyncPayloadCodec.synthesizeLegacyPayloadJSON(kind: .workout, fields: fields))
    }

    /// Date fields can come in as `TimeInterval` (double) from some
    /// legacy encodings — the synthesis helper accepts both `Date`
    /// and numeric forms.
    func testSynthesizeLegacyPayloadAcceptsNumericDateEncoding() throws {
        let startedAtSeconds: TimeInterval = 1_720_130_000
        let fields: [String: Any] = [
            "title": "Numeric Dates",
            "startedAt": startedAtSeconds,
            "updatedAt": NSNumber(value: startedAtSeconds + 600),
            "setsJSON": "[]",
        ]

        let json = try XCTUnwrap(
            SyncPayloadCodec.synthesizeLegacyPayloadJSON(kind: .workout, fields: fields)
        )
        let decoded = try XCTUnwrap(SyncPayloadCodec.decodeWorkoutPayload(from: json))
        XCTAssertEqual(decoded.startedAt.timeIntervalSince1970, startedAtSeconds, accuracy: 0.001)
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970, startedAtSeconds + 600, accuracy: 0.001)
    }

    /// Codex P2 (fixup #5): the queue's `invalidateEntries` must
    /// collapse legacy long-form row recordTypes (`userProfile`,
    /// `trainingPlan`, `coachMemory`) and current short-form call
    /// sites (`profile`, `plan`, `memory`) to the same `Kind` for
    /// matching. Otherwise a pre-rename queue row on an upgraded
    /// client never gets invalidated when a newer pull lands, and
    /// the next push resends the stale payload over the server.
    func testInvalidateEntriesMatchesLegacyLongFormRecordType() throws {
        // Simulate a pre-rename queue row: stored with recordType
        // "userProfile" (the legacy long form) that this version's
        // rawValue-based lookup would miss.
        let oldPayload = "{}"
        try outboundQueue.enqueue(
            recordType: "userProfile",
            recordIdentifier: CloudSyncRecord.Kind.userProfile.defaultIdentifier,
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: oldPayload,
            queuedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )
        XCTAssertEqual(try outboundQueue.pendingRecords().count, 1)

        // Applier call site always uses the current short-form
        // `kind.rawValue` ("profile"). Invalidating with that should
        // STILL match the legacy long-form row.
        try outboundQueue.invalidateEntries(
            recordType: CloudSyncRecord.Kind.userProfile.rawValue, // "profile"
            recordIdentifier: CloudSyncRecord.Kind.userProfile.defaultIdentifier,
            olderThan: Date() // future → matches any older row
        )

        XCTAssertTrue(try outboundQueue.pendingRecords().isEmpty,
                      "Legacy long-form queue row must be invalidated by a short-form invalidation call")
    }

    /// CloudKit records written by a prior version of this code may
    /// carry the pre-rename long-form record types (`userProfile`,
    /// `trainingPlan`, `coachMemory`). `Kind.parse(_:)` must accept
    /// both forms so existing remote data doesn't silently vanish
    /// on decode.
    func testKindParseAcceptsLegacyLongFormNames() {
        XCTAssertEqual(CloudSyncRecord.Kind.parse("workout"), .workout)
        XCTAssertEqual(CloudSyncRecord.Kind.parse("profile"), .userProfile)
        XCTAssertEqual(CloudSyncRecord.Kind.parse("plan"), .trainingPlan)
        XCTAssertEqual(CloudSyncRecord.Kind.parse("memory"), .coachMemory)

        // Legacy long-form names from earlier (unshipped) schemas.
        XCTAssertEqual(CloudSyncRecord.Kind.parse("userProfile"), .userProfile)
        XCTAssertEqual(CloudSyncRecord.Kind.parse("trainingPlan"), .trainingPlan)
        XCTAssertEqual(CloudSyncRecord.Kind.parse("coachMemory"), .coachMemory)

        // Unknown raw strings return nil.
        XCTAssertNil(CloudSyncRecord.Kind.parse("bogus"))
        XCTAssertNil(CloudSyncRecord.Kind.parse(""))
    }

    // MARK: - Helpers

    private func makeApplier(
        container: ModelContainer,
        telemetrySink: (any TelemetrySink)? = nil,
        outboundQueue: (any OutboundSyncQueue)? = nil
    ) -> DefaultSyncPayloadApplier {
        DefaultSyncPayloadApplier(
            workoutRepository: SwiftDataWorkoutRepository(container: container, outboundQueue: outboundQueue),
            coachMemoryRepository: SwiftDataCoachMemoryRepository(container: container, outboundQueue: outboundQueue),
            userProfileRepository: SwiftDataUserProfileRepository(container: container, outboundQueue: outboundQueue),
            trainingPlanRepository: SwiftDataTrainingPlanRepository(container: container, outboundQueue: outboundQueue),
            telemetrySink: telemetrySink,
            outboundQueue: outboundQueue
        )
    }

    private func assertWorkout(_ lhs: WorkoutRecord, equals rhs: WorkoutRecord, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.identifier, rhs.identifier, file: file, line: line)
        XCTAssertEqual(lhs.title, rhs.title, file: file, line: line)
        XCTAssertEqual(lhs.startedAt.timeIntervalSince1970, rhs.startedAt.timeIntervalSince1970, accuracy: 0.001, file: file, line: line)
        switch (lhs.completedAt, rhs.completedAt) {
        case let (.some(lhsCompletedAt), .some(rhsCompletedAt)):
            XCTAssertEqual(lhsCompletedAt.timeIntervalSince1970, rhsCompletedAt.timeIntervalSince1970, accuracy: 0.001, file: file, line: line)
        case (.none, .none):
            break
        default:
            XCTFail("Completed timestamps did not match", file: file, line: line)
        }
        XCTAssertEqual(lhs.durationMinutes, rhs.durationMinutes, file: file, line: line)
        XCTAssertEqual(lhs.exerciseIDsCSV, rhs.exerciseIDsCSV, file: file, line: line)
        XCTAssertEqual(lhs.setsJSON, rhs.setsJSON, file: file, line: line)
        XCTAssertEqual(lhs.totalVolumeLoad, rhs.totalVolumeLoad, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(lhs.averageRPE, rhs.averageRPE, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(lhs.completedSetCount, rhs.completedSetCount, file: file, line: line)
        XCTAssertEqual(lhs.summary, rhs.summary, file: file, line: line)
        XCTAssertEqual(lhs.updatedAt.timeIntervalSince1970, rhs.updatedAt.timeIntervalSince1970, accuracy: 0.001, file: file, line: line)
    }

    private static func updateWorkout(
        identifier: String,
        in container: ModelContainer,
        title: String,
        summary: String,
        totalVolumeLoad: Double,
        averageRPE: Double,
        completedSetCount: Int,
        updatedAt: Date
    ) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.identifier == identifier
            }
        )
        descriptor.fetchLimit = 1
        guard let workout = try context.fetch(descriptor).first else {
            XCTFail("Expected workout \(identifier) to exist before mutation")
            return
        }

        workout.title = title
        workout.summary = summary
        workout.totalVolumeLoad = totalVolumeLoad
        workout.averageRPE = averageRPE
        workout.completedSetCount = completedSetCount
        workout.updatedAt = updatedAt
        try context.save()
    }

    private static func decodeLoggedSets(from json: String) -> [LoggedSetFixture]? {
        // `SwiftDataWorkoutRepository.appendSet` writes `setsJSON` with a
        // plain JSONEncoder (default `.deferredToDate` strategy → seconds
        // since reference date), not with `SyncPayloadCodec`. Match that
        // strategy here so round-trip tests decode the same bytes the
        // repo produced.
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([LoggedSetFixture].self, from: data)
    }

    private static func makeLoggedSetsJSON(_ sets: [LoggedSetFixture]) -> String {
        // Same rationale as `decodeLoggedSets` — produce bytes the repo
        // can read back with its own default JSONDecoder.
        guard let data = try? JSONEncoder().encode(sets),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func makeContainer(named name: String) throws -> ModelContainer {
        let schema = Schema(VolumeArcSchemaV4.models)
        let config = ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: VolumeArcSchemaMigrationPlan.self,
            configurations: [config]
        )
    }
}

private struct LoggedSetFixture: Codable, Equatable {
    let exerciseID: String
    let set: WorkoutSetPerformance
}

private actor RecordingTransportRecorder {
    private(set) var pushedRecords: [CloudSyncRecord] = []
    private(set) var pushCallOrder: [Int] = []
    private(set) var pullCallOrder: [Int] = []
    private var stepCounter = 0

    func append(_ records: [CloudSyncRecord]) {
        pushedRecords.append(contentsOf: records)
        stepCounter += 1
        pushCallOrder.append(stepCounter)
    }

    func recordPull() {
        stepCounter += 1
        pullCallOrder.append(stepCounter)
    }
}

private final class RecordingCloudSyncTransport: CloudSyncTransport, @unchecked Sendable {
    private let recorder = RecordingTransportRecorder()
    private let shouldThrow: Bool
    private let pullResultProvider: @Sendable () -> CloudSyncPullResult

    init(
        shouldThrow: Bool = false,
        pullResult: @Sendable @escaping () -> CloudSyncPullResult = {
            CloudSyncPullResult(changedRecords: [], deletedRecordIDs: [], nextCursor: nil)
        }
    ) {
        self.shouldThrow = shouldThrow
        self.pullResultProvider = pullResult
    }

    var isAvailable: Bool { true }

    func pushRecords(_ records: [CloudSyncRecord]) async throws {
        if shouldThrow {
            throw RecordingTransportError.pushFailed
        }
        await recorder.append(records)
    }

    func pullChanges(since cursor: String?) async throws -> CloudSyncPullResult {
        await recorder.recordPull()
        return pullResultProvider()
    }

    var pushedRecords: [CloudSyncRecord] {
        get async {
            await recorder.pushedRecords
        }
    }

    var pushCallOrder: [Int] {
        get async {
            await recorder.pushCallOrder
        }
    }

    var pullCallOrder: [Int] {
        get async {
            await recorder.pullCallOrder
        }
    }
}

private enum RecordingTransportError: Error {
    case pushFailed
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @Sendable @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected async expression to throw", file: file, line: line)
    } catch {
        // Expected path.
    }
}
#endif
