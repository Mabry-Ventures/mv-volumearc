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
    }

    func testMigrationPlanContainsV1ToV2Stage() {
        XCTAssertEqual(VolumeArcSchemaMigrationPlan.schemas.count, 3,
                       "Migration plan should define the V1 bridge, V2 backfill, and V3 current schemas")
        XCTAssertEqual(VolumeArcSchemaMigrationPlan.stages.count, 2,
                       "Migration plan should contain the V1 to V2 bridge and the V2 to V3 tightening stage")
    }

    // MARK: - In-memory container creation

    func testInMemoryContainerCreatesSuccessfully() throws {
        let schema = Schema(VolumeArcSchemaV3.models)
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
        let schema = Schema(VolumeArcSchemaV3.models)
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

    private func makeDiskBackedCurrentContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(VolumeArcSchemaV3.models)
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
