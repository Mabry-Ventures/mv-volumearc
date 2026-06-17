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
    /// VOL-67 Copilot (fixup #19): delete tombstones must NOT carry
    /// the full serialized record body. `CloudSyncCoordinator.makeCloudSyncRecord`
    /// uses `queuedAt` as the authoritative delete timestamp and
    /// ignores `payloadJSON` for `.delete` operations, and
    /// `DefaultSyncPayloadApplier` doesn't decode the payload on
    /// deletions either — so serializing the full body just retained
    /// deleted user content in the outbound queue and CloudKit
    /// tombstone for no functional benefit. Fix: stage an empty
    /// `payloadJSON` on delete.
    func testDeleteWorkoutTombstoneHasEmptyPayload() throws {
        let workout = try workoutRepository.createWorkout(
            title: "With Content To Not Retain",
            startedAt: Date(timeIntervalSince1970: 1_720_055_000)
        )

        // Clear the create upsert so only the delete remains.
        let createEntries = try outboundQueue.pendingRecords()
        try outboundQueue.delete(ids: createEntries.map(\.id))

        try workoutRepository.deleteWorkout(identifier: workout.identifier)

        let tombstones = try outboundQueue.pendingRecords()
            .filter { $0.operation == CloudSyncRecord.Operation.delete.rawValue }
        XCTAssertEqual(tombstones.count, 1, "Exactly one delete tombstone expected")
        XCTAssertEqual(
            tombstones.first?.payloadJSON,
            "",
            "Delete tombstones must have empty payloadJSON — the sync pipeline ignores it and persisting the body retains deleted user content"
        )
    }

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

    // MARK: - VOL-67 Codex P1 (fixup #35): push behavior when pull fails

    /// Codex P1 (fixup #35 + follow-up): when `pullChanges` throws,
    /// `syncCycle` must NOT drain the outbound queue — the queued
    /// entries haven't been reconciled against the server and could
    /// clobber newer remote state that we couldn't see due to the
    /// pull failure. The queue stays intact until the next successful
    /// pull reconciles it. However, caller-provided `additionalRecords`
    /// (known-fresh from the current user action) ARE still pushed so
    /// immediate writes aren't stranded.
    func testSyncCyclePreservesQueueWhenPullFails() async throws {
        // 1) Queue a local workout mutation (historical, un-reconciled).
        _ = try workoutRepository.createWorkout(
            title: "Historical Queued Write",
            startedAt: Date(timeIntervalSince1970: 1_720_040_000)
        )
        XCTAssertEqual(try outboundQueue.pendingRecords().count, 1)

        // 2) Transport configured to THROW on pull.
        let transport = RecordingCloudSyncTransport(shouldThrowOnPull: true)
        let telemetry = InMemoryTelemetrySink()
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue,
            telemetrySink: telemetry
        )

        // 3) syncCycle must NOT throw — pull failure is absorbed.
        let count = try await coordinator.syncCycle()

        // 4) Queue should NOT have been drained — push used limit: 0
        //    because pull failed and entries aren't reconciled.
        XCTAssertEqual(
            try outboundQueue.pendingRecords().count,
            1,
            "Queue must be preserved when pull fails — stale entries could clobber newer server state"
        )

        // 5) Nothing reached the transport (no additionalRecords + no drain).
        let pushed = await transport.pushedRecords
        XCTAssertTrue(pushed.isEmpty, "No records should be pushed when pull fails and no additionalRecords provided")
        XCTAssertEqual(count, 0)

        // 6) Pull failure was logged to telemetry.
        XCTAssertTrue(
            telemetry.currentEvents.contains { $0.name == "pull_failed" },
            "Expected pull_failed telemetry event"
        )
    }

    /// Complement: caller-provided `additionalRecords` (known-fresh)
    /// ARE still pushed even when pull fails. This ensures immediate
    /// user actions reach CloudKit without being stranded by an
    /// inbound-sync failure.
    func testSyncCyclePushesAdditionalRecordsEvenWhenPullFails() async throws {
        let transport = RecordingCloudSyncTransport(shouldThrowOnPull: true)
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue,
            telemetrySink: InMemoryTelemetrySink()
        )

        // Push a caller-provided record (known-fresh).
        let freshRecord = CloudSyncRecord(
            kind: .workout,
            identifier: "fresh-direct-push",
            operation: .upsert,
            payloadJSON: "{}",
            modifiedAt: .now
        )
        let count = try await coordinator.syncCycle(pushing: [freshRecord])

        // The fresh record reached the transport despite pull failure.
        let pushed = await transport.pushedRecords
        XCTAssertEqual(pushed.count, 1, "additionalRecords must push even when pull fails")
        XCTAssertEqual(pushed.first?.identifier, "fresh-direct-push")
        XCTAssertEqual(count, 1)
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

    /// VOL-67 Codex P2 (fixup #10): queue rows that differ only in
    /// recordType alias form (legacy `userProfile` vs. canonical
    /// `profile`) or in identifier alias form must collapse to a
    /// single coalesced push. Otherwise the server gets two writes
    /// for the same logical singleton record with undefined ordering.
    func testPushCoalescesLegacyAndCanonicalAliasesForSameSingleton() async throws {
        let baseTimestamp = Date(timeIntervalSince1970: 1_720_150_000)

        // Enqueue TWO rows for the same logical profile: one with the
        // legacy long-form recordType/identifier, one with the
        // canonical short form. The canonical one is newer.
        let legacyPayload = try XCTUnwrap(SyncPayloadCodec.synthesizeLegacyPayloadJSON(
            kind: .userProfile,
            fields: [
                "name": "Legacy Queued",
                "coachingStyle": "motivational",
                "privacyMode": "standard",
                "advancementLevel": "intermediate",
                "availableEquipmentCSV": "barbell",
                "preferredRepRangeLower": 5,
                "preferredRepRangeUpper": 8,
                "sessionTimeBudgetMinutes": 60,
                "weeklyTrainingDays": 4,
                "onboardingCompleted": true,
                "updatedAt": baseTimestamp,
            ]
        ))
        try outboundQueue.enqueue(
            recordType: "userProfile", // legacy long-form
            recordIdentifier: "userProfile", // legacy long-form identifier
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: legacyPayload,
            queuedAt: baseTimestamp
        )

        let newerTimestamp = baseTimestamp.addingTimeInterval(60)
        let canonicalPayload = try XCTUnwrap(SyncPayloadCodec.synthesizeLegacyPayloadJSON(
            kind: .userProfile,
            fields: [
                "name": "Canonical Newer",
                "coachingStyle": "motivational",
                "privacyMode": "standard",
                "advancementLevel": "intermediate",
                "availableEquipmentCSV": "barbell",
                "preferredRepRangeLower": 5,
                "preferredRepRangeUpper": 8,
                "sessionTimeBudgetMinutes": 60,
                "weeklyTrainingDays": 4,
                "onboardingCompleted": true,
                "updatedAt": newerTimestamp,
            ]
        ))
        try outboundQueue.enqueue(
            recordType: CloudSyncRecord.Kind.userProfile.rawValue, // "profile"
            recordIdentifier: CloudSyncRecord.Kind.userProfile.defaultIdentifier, // "profile"
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: canonicalPayload,
            queuedAt: newerTimestamp
        )

        XCTAssertEqual(try outboundQueue.pendingRecords().count, 2)

        let transport = RecordingCloudSyncTransport()
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue
        )

        let pushedCount = try await coordinator.push()
        XCTAssertEqual(pushedCount, 1, "Two alias-form rows for the same logical profile must coalesce to one")

        let pushed = await transport.pushedRecords
        XCTAssertEqual(pushed.count, 1)

        // The coalesced record must be the newer canonical one.
        let pushedRecord = try XCTUnwrap(pushed.first)
        XCTAssertEqual(pushedRecord.kind, .userProfile)
        XCTAssertEqual(pushedRecord.identifier, "profile", "Coalesced outbound must use canonical singleton identifier")
        let decodedPayload = try XCTUnwrap(SyncPayloadCodec.decodeUserProfilePayload(from: pushedRecord.payloadJSON))
        XCTAssertEqual(decodedPayload.name, "Canonical Newer", "Newer queuedAt must win the coalesce")

        XCTAssertTrue(try outboundQueue.pendingRecords().isEmpty)
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

    // MARK: - VOL-67 Codex P1 (fixup #18): tombstone wins over inbound resurrection

    /// Codex P1 (fixup #18): when `syncCycle` pulls before pushing, a
    /// workout that was just deleted locally can still have a queued
    /// delete tombstone while the local `WorkoutRecord` is gone. Without
    /// the tombstone-check, any inbound upsert is inserted unconditionally,
    /// so an older server version can resurrect a record the user just
    /// deleted — the subsequent push sends the tombstone to CloudKit but
    /// doesn't remove the reinserted local row, leaving local state
    /// incorrect until a later pull.
    ///
    /// This test reproduces the race: queue a newer delete, apply an
    /// older inbound upsert, verify the local workout is NOT resurrected
    /// and the tombstone is still pending for the next push.
    func testApplierSuppressesInboundUpsertWhenNewerDeleteTombstonePending() async throws {
        // Step 1: seed a workout locally and let the repository queue
        // its upsert. The repository's createWorkout helper handles
        // the outbound enqueue atomically.
        _ = try workoutRepository.createWorkout(
            title: "Pending Delete",
            startedAt: Date(timeIntervalSince1970: 1_720_300_000)
        )

        // Step 2: replace the auto-generated identifier so we can
        // reference it by name in the rest of the test. We fetch the
        // workout, grab the true identifier, and use that throughout.
        let context = ModelContext(container)
        let seededWorkout = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WorkoutRecord>()).first
        )
        let realIdentifier = seededWorkout.identifier

        // Step 3: delete the local workout. The repository removes the
        // WorkoutRecord from the store AND enqueues a delete tombstone
        // atomically (staged into the same context save).
        try workoutRepository.deleteWorkout(identifier: realIdentifier)

        // Sanity: the local workout is gone and the outbound queue
        // holds the delete tombstone.
        let remainingWorkouts = try context.fetch(FetchDescriptor<WorkoutRecord>())
        XCTAssertTrue(
            remainingWorkouts.isEmpty,
            "Local workout should be gone after repository.deleteWorkout"
        )

        let pendingBeforePull = try outboundQueue.pendingRecords()
            .filter { $0.recordIdentifier == realIdentifier && $0.operation == CloudSyncRecord.Operation.delete.rawValue }
        XCTAssertEqual(
            pendingBeforePull.count,
            1,
            "Exactly one delete tombstone should be pending"
        )
        let tombstoneTimestamp = try XCTUnwrap(pendingBeforePull.first?.queuedAt)

        // Step 4: construct an inbound upsert for the same workout
        // with an `updatedAt` STRICTLY OLDER than the tombstone's
        // queuedAt. This is the server-knows-a-stale-version case
        // Codex described.
        let inboundTimestamp = tombstoneTimestamp.addingTimeInterval(-60)
        let inboundPayload = WorkoutRecord(
            identifier: realIdentifier,
            title: "Server Version (Older)",
            startedAt: inboundTimestamp,
            updatedAt: inboundTimestamp
        )
        let inboundRecord = try XCTUnwrap(
            SyncPayloadCodec.makeRecord(for: inboundPayload, operation: .upsert)
        )

        // Step 5: apply the pull result through the applier.
        let telemetry = InMemoryTelemetrySink()
        let applier = makeApplier(
            container: container,
            telemetrySink: telemetry,
            outboundQueue: outboundQueue
        )
        try await applier.apply(result: CloudSyncPullResult(
            changedRecords: [inboundRecord],
            deletedRecordIDs: [],
            nextCursor: nil
        ))

        // Step 6: verify the workout was NOT resurrected.
        let refreshedContext = ModelContext(container)
        let refreshedWorkouts = try refreshedContext.fetch(FetchDescriptor<WorkoutRecord>())
        XCTAssertTrue(
            refreshedWorkouts.isEmpty,
            "Local workout must NOT be resurrected — a newer delete tombstone is pending"
        )

        // Step 7: verify the delete tombstone is still in the queue
        // (ready to push).
        let remainingTombstones = try outboundQueue.pendingRecords()
            .filter { $0.recordIdentifier == realIdentifier && $0.operation == CloudSyncRecord.Operation.delete.rawValue }
        XCTAssertEqual(
            remainingTombstones.count,
            1,
            "Delete tombstone must still be pending for the next push cycle"
        )

        // Step 8: verify telemetry was emitted for the suppressed insert.
        XCTAssertTrue(
            telemetry.currentEvents.contains { $0.name == "inbound_upsert_suppressed_by_tombstone" },
            "Expected inbound_upsert_suppressed_by_tombstone telemetry event"
        )
    }

    /// Complement: when the inbound is STRICTLY NEWER than the
    /// tombstone, normal last-write-wins takes over and the record
    /// IS resurrected (the server's mutation is newer than the
    /// user's delete intent). Strict `>` matches the applier's
    /// existing `shouldApply` tie-breaking: inbound wins ties.
    func testApplierResurrectsInboundUpsertWhenTombstoneIsOlder() async throws {
        // Seed, capture identifier, delete — same as the previous test.
        _ = try workoutRepository.createWorkout(
            title: "Will Be Resurrected",
            startedAt: Date(timeIntervalSince1970: 1_720_310_000)
        )
        let context = ModelContext(container)
        let seeded = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutRecord>()).first)
        let realIdentifier = seeded.identifier
        try workoutRepository.deleteWorkout(identifier: realIdentifier)

        let pendingDeletes = try outboundQueue.pendingRecords()
            .filter { $0.recordIdentifier == realIdentifier && $0.operation == CloudSyncRecord.Operation.delete.rawValue }
        let tombstoneTimestamp = try XCTUnwrap(pendingDeletes.first?.queuedAt)

        // Inbound is STRICTLY NEWER than the tombstone.
        let inboundTimestamp = tombstoneTimestamp.addingTimeInterval(60)
        let inboundPayload = WorkoutRecord(
            identifier: realIdentifier,
            title: "Server Version (Newer)",
            startedAt: inboundTimestamp,
            updatedAt: inboundTimestamp
        )
        let inboundRecord = try XCTUnwrap(
            SyncPayloadCodec.makeRecord(for: inboundPayload, operation: .upsert)
        )

        let applier = makeApplier(container: container, outboundQueue: outboundQueue)
        try await applier.apply(result: CloudSyncPullResult(
            changedRecords: [inboundRecord],
            deletedRecordIDs: [],
            nextCursor: nil
        ))

        // The record SHOULD be resurrected — newer upsert beats older
        // delete under last-write-wins.
        let refreshedContext = ModelContext(container)
        let refreshed = try refreshedContext.fetch(FetchDescriptor<WorkoutRecord>())
        XCTAssertEqual(refreshed.count, 1, "Newer inbound upsert must resurrect the record")
        XCTAssertEqual(refreshed.first?.title, "Server Version (Newer)")
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

    /// VOL-67 Codex P2 (fixup #12): pre-VOL-67 CloudKit records stored
    /// the available-equipment CSV under the field key `"equipment"`,
    /// not the canonical `"availableEquipmentCSV"`. On an upgrade pull
    /// we have to read both so the user's real equipment list isn't
    /// dropped to empty and then pushed back to cloud.
    func testSynthesizeLegacyPayloadReadsLegacyEquipmentKey() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_720_110_001)
        let fields: [String: Any] = [
            "name": "Pre-VOL-67 Athlete",
            // Intentionally omit availableEquipmentCSV and provide the
            // legacy `equipment` key instead, matching what an older
            // applier would have written to CloudKit.
            "equipment": "barbell,kettlebell,bodyweight",
            "updatedAt": updatedAt,
        ]

        let json = try XCTUnwrap(
            SyncPayloadCodec.synthesizeLegacyPayloadJSON(kind: .userProfile, fields: fields)
        )
        let decoded = try XCTUnwrap(SyncPayloadCodec.decodeUserProfilePayload(from: json))
        XCTAssertEqual(decoded.availableEquipmentCSV, "barbell,kettlebell,bodyweight")
    }

    /// When both keys are present, the canonical one wins — an
    /// intermediate upgrade (record written twice, once by old code and
    /// once by new) shouldn't resurrect the stale `equipment` value.
    func testSynthesizeLegacyPayloadPrefersCanonicalEquipmentKey() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_720_110_002)
        let fields: [String: Any] = [
            "name": "Dual-Key Athlete",
            "availableEquipmentCSV": "dumbbell,machine",
            "equipment": "barbell", // stale leftover
            "updatedAt": updatedAt,
        ]

        let json = try XCTUnwrap(
            SyncPayloadCodec.synthesizeLegacyPayloadJSON(kind: .userProfile, fields: fields)
        )
        let decoded = try XCTUnwrap(SyncPayloadCodec.decodeUserProfilePayload(from: json))
        XCTAssertEqual(decoded.availableEquipmentCSV, "dumbbell,machine")
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

    /// VOL-67 Codex P2 (fixup #32): `synthesizeLegacyPayloadJSON`
    /// must accept string timestamps from legacy CKRecord fields.
    /// The pre-`payloadJSON` transport on early builds stored some
    /// field values as `NSString` (via plist/JSON intermediates), so
    /// a legacy workout record with `startedAt: "1720140000"` or
    /// `updatedAt: "2024-07-04T12:00:00Z"` must synthesize
    /// successfully. Before this fix, string timestamps were rejected
    /// by `readDate`, synthesis returned nil, and the pull path
    /// (fixup #21/#30) then cleared `nextCursor` — trapping the
    /// device in an infinite re-fetch loop without ever applying
    /// those records.
    func testSynthesizeLegacyPayloadAcceptsStringTimestamps() throws {
        // Numeric string (epoch seconds) — most common legacy form.
        let numericStringSeconds: TimeInterval = 1_720_140_000
        let numericFields: [String: Any] = [
            "title": "Numeric String Dates",
            "startedAt": "\(numericStringSeconds)",
            "updatedAt": "\(numericStringSeconds + 1_200)",
            "setsJSON": "[]",
        ]
        let numericJSON = try XCTUnwrap(
            SyncPayloadCodec.synthesizeLegacyPayloadJSON(kind: .workout, fields: numericFields),
            "Synthesis must succeed with string epoch timestamps"
        )
        let numericDecoded = try XCTUnwrap(SyncPayloadCodec.decodeWorkoutPayload(from: numericJSON))
        XCTAssertEqual(
            numericDecoded.startedAt.timeIntervalSince1970,
            numericStringSeconds,
            accuracy: 0.001
        )
        XCTAssertEqual(
            numericDecoded.updatedAt.timeIntervalSince1970,
            numericStringSeconds + 1_200,
            accuracy: 0.001
        )

        // ISO 8601 strings (with and without fractional seconds).
        let iso8601Fields: [String: Any] = [
            "title": "ISO 8601 Dates",
            "startedAt": "2024-07-04T12:00:00.000Z",
            "updatedAt": "2024-07-04T12:30:00Z",
            "setsJSON": "[]",
        ]
        let iso8601JSON = try XCTUnwrap(
            SyncPayloadCodec.synthesizeLegacyPayloadJSON(kind: .workout, fields: iso8601Fields),
            "Synthesis must succeed with ISO 8601 string timestamps (both fractional and non-fractional variants)"
        )
        let iso8601Decoded = try XCTUnwrap(SyncPayloadCodec.decodeWorkoutPayload(from: iso8601JSON))
        // 2024-07-04T12:00:00Z = 1720094400
        XCTAssertEqual(
            iso8601Decoded.startedAt.timeIntervalSince1970,
            1_720_094_400,
            accuracy: 1.0
        )
        XCTAssertEqual(
            iso8601Decoded.updatedAt.timeIntervalSince1970,
            1_720_094_400 + 1_800,
            accuracy: 1.0
        )
    }

    // MARK: - VOL-67 Codex P2 (fixup #7): canonicalize singleton IDs

    /// Singleton kinds (`userProfile`, `trainingPlan`) always enqueue
    /// under the canonical `defaultIdentifier` ("profile" / "plan").
    /// But a legacy CK inbound record may carry `recordName = "userProfile"`
    /// instead of `"profile"`. When the applier processed that record
    /// it used to pass `record.identifier` directly into
    /// `invalidateEntries`, which never matched the canonically-queued
    /// row. The test here exercises that exact path: queue a canonical
    /// profile row, then simulate a legacy-form inbound apply by
    /// calling `canonicalQueueIdentifier(from: "userProfile")` and
    /// verifying it resolves to `"profile"` so invalidation matches.
    func testCanonicalQueueIdentifierNormalizesSingletonLegacyForms() {
        let profile = CloudSyncRecord.Kind.userProfile
        let plan = CloudSyncRecord.Kind.trainingPlan
        let workout = CloudSyncRecord.Kind.workout
        let memory = CloudSyncRecord.Kind.coachMemory

        // Singletons: any input collapses to defaultIdentifier.
        XCTAssertEqual(profile.canonicalQueueIdentifier(from: "userProfile"), "profile")
        XCTAssertEqual(profile.canonicalQueueIdentifier(from: "profile"), "profile")
        XCTAssertEqual(profile.canonicalQueueIdentifier(from: "random-uuid"), "profile")
        XCTAssertEqual(plan.canonicalQueueIdentifier(from: "trainingPlan"), "plan")
        XCTAssertEqual(plan.canonicalQueueIdentifier(from: "plan"), "plan")

        // Non-singletons: pass through.
        let workoutID = UUID().uuidString
        XCTAssertEqual(workout.canonicalQueueIdentifier(from: workoutID), workoutID)
        let memoryID = UUID().uuidString
        XCTAssertEqual(memory.canonicalQueueIdentifier(from: memoryID), memoryID)

        XCTAssertTrue(profile.isSingleton)
        XCTAssertTrue(plan.isSingleton)
        XCTAssertFalse(workout.isSingleton)
        XCTAssertFalse(memory.isSingleton)
    }

    /// End-to-end: queue a canonical profile row ("profile"), apply a
    /// simulated inbound record with a legacy recordIdentifier
    /// ("userProfile"), verify the queued row is invalidated via the
    /// applier's `invalidateEntries` path.
    func testApplierInvalidatesCanonicalProfileRowFromLegacyInboundIdentifier() async throws {
        let baselineTimestamp = Date(timeIntervalSince1970: 1_720_140_000)

        // Queue a canonical profile upsert. Payload JSON is constructed
        // via the legacy-field synthesis helper so we get a correctly
        // envelope-wrapped payload the applier can decode.
        let queuedJSON = try XCTUnwrap(SyncPayloadCodec.synthesizeLegacyPayloadJSON(
            kind: .userProfile,
            fields: [
                "name": "Queued Stale",
                "coachingStyle": "motivational",
                "privacyMode": "standard",
                "advancementLevel": "intermediate",
                "availableEquipmentCSV": "barbell",
                "preferredRepRangeLower": 5,
                "preferredRepRangeUpper": 8,
                "sessionTimeBudgetMinutes": 60,
                "weeklyTrainingDays": 4,
                "onboardingCompleted": true,
                "updatedAt": baselineTimestamp,
            ]
        ))
        try outboundQueue.enqueue(
            recordType: CloudSyncRecord.Kind.userProfile.rawValue, // "profile"
            recordIdentifier: CloudSyncRecord.Kind.userProfile.defaultIdentifier, // "profile"
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: queuedJSON,
            queuedAt: baselineTimestamp
        )
        XCTAssertEqual(try outboundQueue.pendingRecords().count, 1)

        // Build an inbound record with the LEGACY identifier form
        // ("userProfile" instead of canonical "profile") but a newer
        // timestamp, as if it came from a pre-rename peer device.
        let newerTimestamp = baselineTimestamp.addingTimeInterval(300)
        let inboundJSON = try XCTUnwrap(SyncPayloadCodec.synthesizeLegacyPayloadJSON(
            kind: .userProfile,
            fields: [
                "name": "Winner",
                "coachingStyle": "motivational",
                "privacyMode": "standard",
                "advancementLevel": "intermediate",
                "availableEquipmentCSV": "barbell",
                "preferredRepRangeLower": 5,
                "preferredRepRangeUpper": 8,
                "sessionTimeBudgetMinutes": 60,
                "weeklyTrainingDays": 4,
                "onboardingCompleted": true,
                "updatedAt": newerTimestamp,
            ]
        ))
        let legacyInbound = CloudSyncRecord(
            kind: .userProfile,
            identifier: "userProfile", // legacy long-form
            operation: .upsert,
            payloadJSON: inboundJSON,
            modifiedAt: newerTimestamp
        )

        // Apply it — the applier must:
        // 1. Update the local profile store to the winner state
        // 2. Invalidate the queued "profile" row even though the
        //    inbound identifier was "userProfile"
        let applier = makeApplier(container: container, outboundQueue: outboundQueue)
        try await applier.apply(result: CloudSyncPullResult(
            changedRecords: [legacyInbound],
            deletedRecordIDs: [],
            nextCursor: nil
        ))

        // Queue should now be empty — the stale canonical row was
        // invalidated via the legacy inbound identifier.
        XCTAssertTrue(try outboundQueue.pendingRecords().isEmpty,
                      "Canonical profile queue row must be invalidated when a legacy 'userProfile' record is applied")
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

    // MARK: - VOL-67 Codex P1/P2 (fixup #14): quarantine siblings + unparseable upserts

    /// Codex P1 (fixup #14): when the newest row for a coalesce key
    /// fails to parse and gets quarantined, OLDER valid rows for the
    /// same key must stay in the queue. Before this fix, the post-push
    /// cleanup deleted EVERY drained row for the batch — including the
    /// older valid siblings for a quarantined key — so a single
    /// corrupted latest row would silently wipe the last known good
    /// state for that key.
    ///
    /// Setup: two rows for workout-X (older valid, newer unparseable
    /// operation) + one row for workout-Y (valid, different key).
    /// Expected after push: workout-Y pushed, workout-X's unparseable
    /// row deleted, workout-X's older valid row STAYS in queue.
    func testPushPreservesOlderSiblingWhenNewestSiblingQuarantined() async throws {
        // Create a throwaway workout just to synthesize a valid
        // envelope-wrapped payloadJSON for the "older valid" row.
        let validOlder = WorkoutRecord(
            identifier: "workout-X",
            title: "Older Valid State",
            startedAt: Date(timeIntervalSince1970: 1_720_100_000),
            updatedAt: Date(timeIntervalSince1970: 1_720_100_000)
        )
        let validPayloadJSON = try XCTUnwrap(SyncPayloadCodec.encodeWorkoutPayload(from: validOlder))

        let validOther = WorkoutRecord(
            identifier: "workout-Y",
            title: "Unrelated Valid",
            startedAt: Date(timeIntervalSince1970: 1_720_100_500),
            updatedAt: Date(timeIntervalSince1970: 1_720_100_500)
        )
        let validOtherPayloadJSON = try XCTUnwrap(SyncPayloadCodec.encodeWorkoutPayload(from: validOther))

        // Row 1: older valid row for workout-X (enqueuedAt = 1_720_100_000).
        try outboundQueue.enqueue(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: "workout-X",
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: validPayloadJSON,
            queuedAt: Date(timeIntervalSince1970: 1_720_100_000)
        )

        // Row 2: newer row for SAME workout-X with a bogus operation
        // string — `Operation(rawValue: "bogus")` returns nil so
        // makeCloudSyncRecord throws and the row gets quarantined.
        // This exercises fixup #11 F5 (quarantine-on-parse-failure)
        // and fixup #14 finding #1 (preserve sibling).
        try outboundQueue.enqueue(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: "workout-X",
            operation: "bogus",
            payloadJSON: validPayloadJSON,
            queuedAt: Date(timeIntervalSince1970: 1_720_100_100)
        )

        // Row 3: valid unrelated row for workout-Y (different key).
        try outboundQueue.enqueue(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: "workout-Y",
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: validOtherPayloadJSON,
            queuedAt: Date(timeIntervalSince1970: 1_720_100_500)
        )

        XCTAssertEqual(try outboundQueue.pendingRecords().count, 3)

        let telemetry = InMemoryTelemetrySink()
        let transport = RecordingCloudSyncTransport()
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue,
            telemetrySink: telemetry
        )

        let pushedCount = try await coordinator.push()

        // Only workout-Y actually reached the transport.
        XCTAssertEqual(pushedCount, 1, "Only the valid unrelated row should be pushed")
        let pushed = await transport.pushedRecords
        XCTAssertEqual(pushed.count, 1)
        XCTAssertEqual(pushed[0].identifier, "workout-Y")

        // Quarantine telemetry was emitted for the bogus-operation row.
        XCTAssertTrue(
            telemetry.currentEvents.contains { $0.name == "outbound_row_quarantined" },
            "Expected outbound_row_quarantined telemetry for the bogus-operation row"
        )

        // Queue state after push:
        //   - workout-X's OLDER valid row (row 1) must STAY (fallback for quarantined key)
        //   - workout-X's unparseable newer row (row 2) must be DELETED
        //   - workout-Y (row 3) must be DELETED (pushed successfully)
        let remaining = try outboundQueue.pendingRecords()
        let remainingForX = remaining.filter { $0.recordIdentifier == "workout-X" }
        XCTAssertEqual(remainingForX.count, 1,
                       "Exactly one workout-X row should remain (the older valid sibling)")
        XCTAssertEqual(remainingForX.first?.operation, CloudSyncRecord.Operation.upsert.rawValue,
                       "Remaining workout-X row must be the valid-operation sibling, not the bogus one")
        XCTAssertEqual(remainingForX.first?.queuedAt, Date(timeIntervalSince1970: 1_720_100_000),
                       "Remaining workout-X row must be the OLDER one")

        XCTAssertTrue(
            remaining.filter { $0.recordIdentifier == "workout-Y" }.isEmpty,
            "workout-Y should be deleted after successful push"
        )
    }

    /// Codex P2 (fixup #14): `makeCloudSyncRecord` must throw when an
    /// upsert's `payloadJSON` can't be decoded — before this fix it
    /// fell back to `change.queuedAt` and sent the malformed payload
    /// to the transport, where downstream appliers would silently drop
    /// it while the cursor advanced (cross-device data loss).
    ///
    /// Setup: single queue row with valid JSON that is NOT a valid
    /// envelope — `SyncPayloadCodec.modifiedAt` returns nil, so the
    /// pre-transport decode must reject it and route to quarantine.
    func testPushQuarantinesUpsertWithUnparseablePayloadBeforeTransport() async throws {
        // "{}" is valid JSON but does not contain the
        // `{ "workout": { ... } }` envelope, so `decodeWorkoutPayload`
        // returns nil and `SyncPayloadCodec.modifiedAt` returns nil.
        // Pre-fixup-#14, the push code fell back to `queuedAt` and sent
        // this record anyway. Post-fixup-#14, it must throw → quarantine.
        try outboundQueue.enqueue(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: "workout-unparseable",
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: "{}",
            queuedAt: Date(timeIntervalSince1970: 1_720_200_000)
        )
        XCTAssertEqual(try outboundQueue.pendingRecords().count, 1)

        let telemetry = InMemoryTelemetrySink()
        let transport = RecordingCloudSyncTransport()
        let coordinator = CloudSyncCoordinator(
            transport: transport,
            stateStore: FileSyncStateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            outboundQueue: outboundQueue,
            telemetrySink: telemetry
        )

        let pushedCount = try await coordinator.push()

        // Nothing reached the transport.
        XCTAssertEqual(pushedCount, 0, "Unparseable upsert must NOT be sent to the transport")
        let pushed = await transport.pushedRecords
        XCTAssertTrue(pushed.isEmpty, "Transport must not receive records with undecodable payloadJSON")

        // Quarantine telemetry was emitted.
        let quarantineEvent = telemetry.currentEvents.first { $0.name == "outbound_row_quarantined" }
        XCTAssertNotNil(quarantineEvent,
                        "Expected outbound_row_quarantined telemetry for the unparseable upsert")

        // The row has been deleted from the queue so it can't re-poison
        // subsequent pushes.
        XCTAssertTrue(
            try outboundQueue.pendingRecords().isEmpty,
            "Quarantined unparseable row must be deleted from the queue"
        )
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

    // VOL-87: test helper that mirrors the `WorkoutRecord` field set; a
    // parameter struct would just rewrap the same call sites without
    // improving readability, so accept the 8 parameters and disable the
    // lint at the declaration.
    // swiftlint:disable:next function_parameter_count
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
        let schema = Schema(VolumeArcSchemaLatest.models)
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
    private let shouldThrowOnPull: Bool
    private let pullResultProvider: @Sendable () -> CloudSyncPullResult

    init(
        shouldThrow: Bool = false,
        shouldThrowOnPull: Bool = false,
        pullResult: @Sendable @escaping () -> CloudSyncPullResult = {
            CloudSyncPullResult(changedRecords: [], deletedRecordIDs: [], nextCursor: nil)
        }
    ) {
        self.shouldThrow = shouldThrow
        self.shouldThrowOnPull = shouldThrowOnPull
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
        if shouldThrowOnPull {
            throw RecordingTransportError.pullFailed
        }
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
    case pullFailed
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
