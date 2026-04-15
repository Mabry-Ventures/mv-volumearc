#if canImport(SwiftData)
import XCTest
import SwiftData
import VolumeArcCore

final class VolumeArcMigrationTests: XCTestCase {

    // MARK: - Schema V1 model registration

    func testSchemaV1ContainsAllExpectedModels() {
        let models = VolumeArcSchemaV1.models
        let modelNames = models.map { String(describing: $0) }

        XCTAssertTrue(modelNames.contains(where: { $0.contains("UserProfileRecord") }),
                      "Schema V1 should include UserProfileRecord")
        XCTAssertTrue(modelNames.contains(where: { $0.contains("TrainingPlanRecord") }),
                      "Schema V1 should include TrainingPlanRecord")
        XCTAssertTrue(modelNames.contains(where: { $0.contains("WorkoutRecord") }),
                      "Schema V1 should include WorkoutRecord")
        XCTAssertTrue(modelNames.contains(where: { $0.contains("CoachMemoryRecord") }),
                      "Schema V1 should include CoachMemoryRecord")
    }

    func testSchemaV1HasCorrectVersion() {
        XCTAssertEqual(VolumeArcSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
    }

    func testSchemaV2HasCorrectVersion() {
        XCTAssertEqual(VolumeArcSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
    }

    func testSchemaV3HasCorrectVersion() {
        XCTAssertEqual(VolumeArcSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
    }

    func testSchemaV4HasCorrectVersion() {
        XCTAssertEqual(VolumeArcSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
    }

    // MARK: - Migration plan structure

    func testMigrationPlanIncludesV1Schema() {
        let schemas = VolumeArcSchemaMigrationPlan.schemas
        XCTAssertFalse(schemas.isEmpty, "Migration plan should include at least one schema")
        XCTAssertTrue(schemas.contains(where: { $0 == VolumeArcSchemaV1.self }),
                      "Migration plan should include VolumeArcSchemaV1")
        XCTAssertTrue(schemas.contains(where: { $0 == VolumeArcSchemaV2.self }),
                      "Migration plan should include VolumeArcSchemaV2")
        XCTAssertTrue(schemas.contains(where: { $0 == VolumeArcSchemaV3.self }),
                      "Migration plan should include VolumeArcSchemaV3")
        XCTAssertTrue(schemas.contains(where: { $0 == VolumeArcSchemaV4.self }),
                      "Migration plan should include VolumeArcSchemaV4")
    }

    func testMigrationPlanContainsV1ToV2Stage() {
        XCTAssertEqual(VolumeArcSchemaMigrationPlan.schemas.count, 4,
                       "Migration plan should define the V1 bridge plus the V2, V3, and V4 schemas")
        XCTAssertEqual(VolumeArcSchemaMigrationPlan.stages.count, 3,
                       "Migration plan should contain the V1 to V2 bridge plus the V2 to V3 and V3 to V4 stages")
    }

    // MARK: - In-memory container creation

    func testInMemoryContainerCreatesSuccessfully() throws {
        let schema = Schema(VolumeArcSchemaV4.models)
        let config = ModelConfiguration(
            "MigrationTest",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        let container = try ModelContainer(
            for: schema,
            migrationPlan: VolumeArcSchemaMigrationPlan.self,
            configurations: [config]
        )

        XCTAssertNotNil(container)
    }

    func testV1StoreMigratesToCurrentSchemaWithoutDataLoss() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("VolumeArcMigration.sqlite")
        let fixtureDate = Date(timeIntervalSince1970: 1_710_000_000)

        try writeV1FixtureStore(at: storeURL, fixtureDate: fixtureDate)
        Thread.sleep(forTimeInterval: 1.0)

        let migratedContainer = try makeDiskBackedCurrentContainer(at: storeURL)
        let migratedContext = ModelContext(migratedContainer)

        let migratedProfiles = try migratedContext.fetch(FetchDescriptor<UserProfileRecord>())
        let migratedPlans = try migratedContext.fetch(FetchDescriptor<TrainingPlanRecord>())
        let migratedWorkouts = try migratedContext.fetch(FetchDescriptor<WorkoutRecord>())
        let migratedCoachMemories = try migratedContext.fetch(FetchDescriptor<CoachMemoryRecord>())

        XCTAssertEqual(migratedProfiles.count, 1)
        XCTAssertEqual(migratedPlans.count, 1)
        XCTAssertEqual(migratedWorkouts.count, 1)
        XCTAssertEqual(migratedCoachMemories.count, 1)

        XCTAssertEqual(migratedProfiles.first?.name, "Migrating Athlete")
        XCTAssertEqual(migratedPlans.first?.workoutsJSON, "[{\"dayOfWeek\":1,\"title\":\"Migration Upper\"}]")
        XCTAssertEqual(migratedWorkouts.first?.identifier, "legacy-workout")
        XCTAssertEqual(migratedCoachMemories.first?.content, "Legacy coaching note")

        XCTAssertLessThan(
            abs(migratedPlans[0].updatedAt.timeIntervalSinceNow),
            600,
            "Migrated V1 training plans should backfill updatedAt with a sensible default"
        )
    }

    func testV3StoreMigratesToV4BackfillingWorkoutUpdatedAtAndCoachMemoryIdentifier() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("VolumeArcMigrationV3.sqlite")
        let fixtureDate = Date(timeIntervalSince1970: 1_715_000_000)
        let completedAt = fixtureDate.addingTimeInterval(2_700)

        try writeV3FixtureStore(at: storeURL, startedAt: fixtureDate, completedAt: completedAt)

        let migratedContainer = try makeDiskBackedCurrentContainer(at: storeURL)
        let migratedContext = ModelContext(migratedContainer)

        let migratedWorkout = try XCTUnwrap(
            migratedContext.fetch(FetchDescriptor<WorkoutRecord>()).first
        )
        XCTAssertEqual(
            migratedWorkout.updatedAt.timeIntervalSince1970,
            completedAt.timeIntervalSince1970,
            accuracy: 0.001,
            "V3 workouts should backfill updatedAt from completedAt when available"
        )

        let migratedMemory = try XCTUnwrap(
            migratedContext.fetch(FetchDescriptor<CoachMemoryRecord>()).first
        )
        XCTAssertFalse(
            migratedMemory.identifier.isEmpty,
            "V3 coach memories should receive a generated identifier during V4 migration"
        )
    }

    /// VOL-67 Codex P1 (fixup #8): the V3→V4 migration must backfill
    /// the outbound sync queue with an upsert for every pre-existing
    /// record. Otherwise users who upgrade with local history and
    /// make no further edits would never have anything to push, and
    /// their pre-upgrade data would never reach CloudKit.
    func testV3ToV4MigrationBackfillsOutboundQueueForExistingRecords() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("VolumeArcMigrationQueueBackfill.sqlite")
        let fixtureDate = Date(timeIntervalSince1970: 1_715_100_000)
        try writeV3FixtureStoreWithAllEntities(at: storeURL, startedAt: fixtureDate)

        let migratedContainer = try makeDiskBackedCurrentContainer(at: storeURL)
        let migratedContext = ModelContext(migratedContainer)

        let queuedRows = try migratedContext.fetch(FetchDescriptor<OutboundSyncQueueRecord>())
        let queuedByKind = Dictionary(grouping: queuedRows, by: { $0.recordType })

        // One workout queued under "workout"
        let workoutRows = queuedByKind[CloudSyncRecord.Kind.workout.rawValue] ?? []
        XCTAssertEqual(workoutRows.count, 1, "Expected one workout upsert queued after V3→V4 migration")
        XCTAssertEqual(workoutRows.first?.operation, CloudSyncRecord.Operation.upsert.rawValue)
        XCTAssertEqual(workoutRows.first?.recordIdentifier, "v3-workout")

        // One profile queued under the canonical "profile" identifier
        let profileRows = queuedByKind[CloudSyncRecord.Kind.userProfile.rawValue] ?? []
        XCTAssertEqual(profileRows.count, 1, "Expected one profile upsert queued after V3→V4 migration")
        XCTAssertEqual(profileRows.first?.recordIdentifier, CloudSyncRecord.Kind.userProfile.defaultIdentifier)

        // One plan queued under the canonical "plan" identifier
        let planRows = queuedByKind[CloudSyncRecord.Kind.trainingPlan.rawValue] ?? []
        XCTAssertEqual(planRows.count, 1, "Expected one training plan upsert queued after V3→V4 migration")
        XCTAssertEqual(planRows.first?.recordIdentifier, CloudSyncRecord.Kind.trainingPlan.defaultIdentifier)

        // One memory queued with the deterministic identifier that
        // was also assigned to the migrated CoachMemoryRecord.
        let memoryRows = queuedByKind[CloudSyncRecord.Kind.coachMemory.rawValue] ?? []
        XCTAssertEqual(memoryRows.count, 1, "Expected one coach memory upsert queued after V3→V4 migration")
        let migratedMemory = try XCTUnwrap(migratedContext.fetch(FetchDescriptor<CoachMemoryRecord>()).first)
        XCTAssertEqual(memoryRows.first?.recordIdentifier, migratedMemory.identifier)
    }

    /// VOL-67 Codex P2 (fixup #8): the memory identifier assigned by
    /// V3→V4 migration must be deterministic — every device migrating
    /// the same `(createdAt, content, theme)` triple must produce the
    /// same identifier, so delete tombstones and queue invalidation
    /// can target the same logical record across devices. Runs two
    /// independent migrations with identical fixtures and asserts the
    /// identifiers match.
    func testV3ToV4MigrationProducesDeterministicMemoryIdentifiers() throws {
        let fixtureDate = Date(timeIntervalSince1970: 1_715_200_000)
        let tempRoot = FileManager.default.temporaryDirectory

        func migrateAndReturnMemoryIdentifier(storeName: String) throws -> String {
            let directory = tempRoot.appendingPathComponent("\(storeName)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let storeURL = directory.appendingPathComponent("\(storeName).sqlite")
            try writeV3FixtureStore(at: storeURL, startedAt: fixtureDate, completedAt: fixtureDate)

            let migrated = try makeDiskBackedCurrentContainer(at: storeURL)
            let context = ModelContext(migrated)
            let memory = try XCTUnwrap(context.fetch(FetchDescriptor<CoachMemoryRecord>()).first)
            return memory.identifier
        }

        let identifierA = try migrateAndReturnMemoryIdentifier(storeName: "DeviceA")
        let identifierB = try migrateAndReturnMemoryIdentifier(storeName: "DeviceB")

        XCTAssertEqual(
            identifierA,
            identifierB,
            "Two independent migrations of identical legacy memories must produce the same identifier"
        )
        XCTAssertTrue(
            identifierA.hasPrefix("legacy-"),
            "Deterministic legacy identifiers are prefixed for observability"
        )
        // SHA256 hex digest is 64 characters; the prefix adds 7.
        XCTAssertEqual(identifierA.count, "legacy-".count + 64)
    }

    func testCanInsertAndFetchUserProfileRecord() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let profile = UserProfileRecord(
            name: "Test Athlete",
            coachingStyle: "motivational",
            privacyMode: "standard",
            advancementLevel: "intermediate",
            availableEquipmentCSV: "barbell,dumbbell",
            preferredRepRangeLower: 5,
            preferredRepRangeUpper: 8,
            sessionTimeBudgetMinutes: 60,
            weeklyTrainingDays: 4
        )
        context.insert(profile)
        try context.save()

        var descriptor = FetchDescriptor<UserProfileRecord>()
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Test Athlete")
        XCTAssertEqual(fetched.first?.weeklyTrainingDays, 4)
    }

    func testCanInsertAndFetchTrainingPlanRecord() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let plan = TrainingPlanRecord(workoutsJSON: "[{\"dayOfWeek\":1,\"title\":\"Upper\"}]")
        context.insert(plan)
        try context.save()

        var descriptor = FetchDescriptor<TrainingPlanRecord>()
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertTrue(fetched.first?.workoutsJSON.contains("Upper") ?? false)
    }

    // MARK: - Helpers

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(VolumeArcSchemaV4.models)
        let config = ModelConfiguration(
            "MigrationTest-\(UUID().uuidString)",
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

    private func writeV1FixtureStore(at storeURL: URL, fixtureDate: Date) throws {
        let schema = Schema(VolumeArcSchemaV1.models)
        let config = ModelConfiguration(
            "MigrationFixture",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        try autoreleasepool {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            context.insert(
                VolumeArcSchemaV1.UserProfileRecord(
                    name: "Migrating Athlete",
                    coachingStyle: "analytical",
                    privacyMode: "standard",
                    advancementLevel: "intermediate",
                    availableEquipmentCSV: "barbell,dumbbell",
                    preferredRepRangeLower: 4,
                    preferredRepRangeUpper: 8,
                    sessionTimeBudgetMinutes: 55,
                    weeklyTrainingDays: 4,
                    onboardingCompleted: true,
                    updatedAt: fixtureDate
                )
            )
            context.insert(
                VolumeArcSchemaV1.TrainingPlanRecord(
                    workoutsJSON: "[{\"dayOfWeek\":1,\"title\":\"Migration Upper\"}]"
                )
            )
            context.insert(
                VolumeArcSchemaV1.WorkoutRecord(
                    identifier: "legacy-workout",
                    title: "Legacy Session",
                    startedAt: fixtureDate,
                    completedAt: fixtureDate.addingTimeInterval(1800),
                    durationMinutes: 30,
                    exerciseIDsCSV: "bench-press",
                    setsJSON: "[{\"exerciseID\":\"bench-press\",\"weight\":185,\"reps\":5}]",
                    totalVolumeLoad: 925,
                    averageRPE: 8,
                    completedSetCount: 1,
                    summary: "Legacy summary"
                )
            )
            context.insert(
                VolumeArcSchemaV1.CoachMemoryRecord(
                    content: "Legacy coaching note",
                    theme: "bench",
                    createdAt: fixtureDate
                )
            )
            try context.save()
        }
    }

    /// Write a V3 fixture store populated with one of each entity:
    /// workout, profile, plan, memory. Used by the queue-backfill
    /// migration test.
    private func writeV3FixtureStoreWithAllEntities(at storeURL: URL, startedAt: Date) throws {
        let schema = Schema(VolumeArcSchemaV3.models)
        let config = ModelConfiguration(
            "MigrationFixtureAllEntitiesV3",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        try autoreleasepool {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            context.insert(VolumeArcSchemaV3.WorkoutRecord(
                identifier: "v3-workout",
                title: "V3 Workout",
                startedAt: startedAt,
                completedAt: startedAt.addingTimeInterval(1_800),
                durationMinutes: 30,
                exerciseIDsCSV: "back-squat",
                setsJSON: "[]",
                totalVolumeLoad: 1_000,
                averageRPE: 7,
                completedSetCount: 5,
                summary: "V3 summary"
            ))
            context.insert(VolumeArcSchemaV3.UserProfileRecord(
                name: "V3 Athlete",
                coachingStyle: "motivational",
                privacyMode: "standard",
                advancementLevel: "intermediate",
                availableEquipmentCSV: "barbell",
                preferredRepRangeLower: 5,
                preferredRepRangeUpper: 8,
                sessionTimeBudgetMinutes: 60,
                weeklyTrainingDays: 4
            ))
            context.insert(VolumeArcSchemaV3.TrainingPlanRecord(
                workoutsJSON: "[]",
                updatedAt: startedAt
            ))
            context.insert(VolumeArcSchemaV3.CoachMemoryRecord(
                content: "V3 memory",
                theme: "squat",
                createdAt: startedAt
            ))

            try context.save()
        }
    }

    private func writeV3FixtureStore(at storeURL: URL, startedAt: Date, completedAt: Date) throws {
        let schema = Schema(VolumeArcSchemaV3.models)
        let config = ModelConfiguration(
            "MigrationFixtureV3",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        try autoreleasepool {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            context.insert(
                VolumeArcSchemaV3.WorkoutRecord(
                    identifier: "v3-workout",
                    title: "V3 Session",
                    startedAt: startedAt,
                    completedAt: completedAt,
                    durationMinutes: 45,
                    exerciseIDsCSV: "back-squat",
                    setsJSON: "[{\"exerciseID\":\"back-squat\",\"weight\":225,\"reps\":5}]",
                    totalVolumeLoad: 1_125,
                    averageRPE: 8.0,
                    completedSetCount: 1,
                    summary: "Legacy V3 summary"
                )
            )
            context.insert(
                VolumeArcSchemaV3.CoachMemoryRecord(
                    content: "Legacy V3 memory",
                    theme: "squat",
                    createdAt: startedAt
                )
            )

            try context.save()
        }
    }

    private func makeDiskBackedCurrentContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(VolumeArcSchemaV4.models)
        let config = ModelConfiguration(
            "MigrationFixture",
            schema: schema,
            url: storeURL,
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
#endif
