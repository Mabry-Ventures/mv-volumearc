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

    // MARK: - Migration plan structure

    func testMigrationPlanIncludesV1Schema() {
        let schemas = VolumeArcSchemaMigrationPlan.schemas
        XCTAssertFalse(schemas.isEmpty, "Migration plan should include at least one schema")
        XCTAssertTrue(schemas.contains(where: { $0 == VolumeArcSchemaV1.self }),
                      "Migration plan should include VolumeArcSchemaV1")
    }

    func testMigrationPlanStagesAreEmpty() {
        // With only V1, there should be no migration stages yet.
        // When V2 is added, this test should be updated to verify the stage.
        XCTAssertTrue(VolumeArcSchemaMigrationPlan.stages.isEmpty,
                      "Migration plan should have no stages with only V1 schema")
    }

    // MARK: - In-memory container creation

    func testInMemoryContainerCreatesSuccessfully() throws {
        let schema = Schema(VolumeArcSchemaV1.models)
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
        let schema = Schema(VolumeArcSchemaV1.models)
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
}
#endif
