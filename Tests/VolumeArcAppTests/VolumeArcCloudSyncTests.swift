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

    private func makeApplier(
        container: ModelContainer,
        telemetrySink: (any TelemetrySink)? = nil
    ) -> DefaultSyncPayloadApplier {
        DefaultSyncPayloadApplier(
            workoutRepository: SwiftDataWorkoutRepository(container: container),
            coachMemoryRepository: SwiftDataCoachMemoryRepository(container: container),
            userProfileRepository: SwiftDataUserProfileRepository(container: container),
            trainingPlanRepository: SwiftDataTrainingPlanRepository(container: container),
            telemetrySink: telemetrySink
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

    func append(_ records: [CloudSyncRecord]) {
        pushedRecords.append(contentsOf: records)
    }
}

private final class RecordingCloudSyncTransport: CloudSyncTransport, @unchecked Sendable {
    private let recorder = RecordingTransportRecorder()
    private let shouldThrow: Bool

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    var isAvailable: Bool { true }

    func pushRecords(_ records: [CloudSyncRecord]) async throws {
        if shouldThrow {
            throw RecordingTransportError.pushFailed
        }
        await recorder.append(records)
    }

    func pullChanges(since cursor: String?) async throws -> CloudSyncPullResult {
        CloudSyncPullResult(changedRecords: [], deletedRecordIDs: [], nextCursor: cursor)
    }

    var pushedRecords: [CloudSyncRecord] {
        get async {
            await recorder.pushedRecords
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
