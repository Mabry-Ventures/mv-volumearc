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

        // VOL-67 Copilot (fixup #25): the V3→V4 singleton clamp is
        // now CONDITIONAL. It only fires for records whose fields
        // match `VolumeArcProductDefaults` exactly. This V1 fixture
        // uses a customized workoutsJSON (`[{"dayOfWeek":1,"title":
        // "Migration Upper"}]`), so the heuristic recognizes it as
        // a real user edit and preserves the V1→V2 backfill's
        // `Date()` value rather than clamping to `.distantPast`.
        // Fixup #17's Codex concern (seeded defaults beating older
        // authoritative cloud data) is separately covered by
        // `testV3ToV4MigrationClampsSeededDefaultSingletonRecords`.
        XCTAssertLessThan(
            abs(migratedPlans[0].updatedAt.timeIntervalSinceNow),
            600,
            "Customized V1 training plan's updatedAt should retain the V1→V2 backfill Date() value (close to now) — the conditional clamp preserves user edits"
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

    /// VOL-67 Codex P1 (fixup #8, re-scoped in fixup #13): after V3→V4
    /// migration AND a post-bootstrap `OutboundQueueBackfill` run,
    /// every pre-existing record must have a queue row. Otherwise
    /// users who upgrade with local history and make no further edits
    /// would never have anything to push, and their pre-upgrade data
    /// would never reach CloudKit. This test runs the backfill
    /// explicitly to validate the helper end-to-end against a migrated
    /// store.
    @MainActor
    func testV3ToV4MigrationBackfillsOutboundQueueForExistingRecords() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("VolumeArcMigrationQueueBackfill.sqlite")
        let fixtureDate = Date(timeIntervalSince1970: 1_715_100_000)
        try writeV3FixtureStoreWithAllEntities(at: storeURL, startedAt: fixtureDate)

        let migratedContainer = try makeDiskBackedCurrentContainer(at: storeURL)
        try OutboundQueueBackfill.performIfNeeded(
            container: migratedContainer,
            userDefaults: makeEphemeralUserDefaults(),
            flagKey: "test-\(UUID().uuidString)"
        )
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

    /// VOL-67 Codex P1 fixup #13 + fixup #26: the V3→V4 migration
    /// backfill clamps singleton queue rows + payload `updatedAt` to
    /// `.distantPast` only when the record matches the seeded-default
    /// field heuristic (same gate as the record-level clamp in fixup
    /// #25). This test validates the clamp branch: uses a V3 fixture
    /// with fields matching `VolumeArcProductDefaults` exactly.
    ///
    /// The complementary preserve-branch test
    /// (`testV3ToV4MigrationPreservesCustomizedSingletonBackfillTimestamps`)
    /// covers the user-edit path where backfill payloads retain their
    /// real `updatedAt` so genuine edits can propagate cross-device.
    @MainActor
    func testV3ToV4MigrationClampsSeededDefaultSingletonBackfillTimestamps() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("VolumeArcMigrationBackfillClampSeededDefaults.sqlite")
        let fixtureDate = Date(timeIntervalSince1970: 1_715_300_000)
        try writeV3FixtureStoreWithSeededDefaults(at: storeURL, startedAt: fixtureDate)

        let migratedContainer = try makeDiskBackedCurrentContainer(at: storeURL)
        try OutboundQueueBackfill.performIfNeeded(
            container: migratedContainer,
            userDefaults: makeEphemeralUserDefaults(),
            flagKey: "test-\(UUID().uuidString)"
        )
        let migratedContext = ModelContext(migratedContainer)

        let queuedRows = try migratedContext.fetch(FetchDescriptor<OutboundSyncQueueRecord>())
        let queuedByKind = Dictionary(grouping: queuedRows, by: { $0.recordType })

        // Singleton: profile queue row and embedded payload must both be distantPast
        let profileRow = try XCTUnwrap((queuedByKind[CloudSyncRecord.Kind.userProfile.rawValue] ?? []).first)
        XCTAssertEqual(
            profileRow.queuedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            accuracy: 1.0,
            "Seeded-default profile queue row's queuedAt should be clamped to distantPast"
        )
        let profilePayload = try XCTUnwrap(SyncPayloadCodec.decodeUserProfilePayload(from: profileRow.payloadJSON))
        XCTAssertEqual(
            profilePayload.updatedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            accuracy: 1.0,
            "Seeded-default profile payload's embedded updatedAt should be clamped to distantPast"
        )

        // Singleton: plan queue row and embedded payload must both be distantPast
        let planRow = try XCTUnwrap((queuedByKind[CloudSyncRecord.Kind.trainingPlan.rawValue] ?? []).first)
        XCTAssertEqual(
            planRow.queuedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            accuracy: 1.0,
            "Seeded-default plan queue row's queuedAt should be clamped to distantPast"
        )
        let planPayload = try XCTUnwrap(SyncPayloadCodec.decodeTrainingPlanPayload(from: planRow.payloadJSON))
        XCTAssertEqual(
            planPayload.updatedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            accuracy: 1.0,
            "Seeded-default plan payload's embedded updatedAt should be clamped to distantPast"
        )

        // Per-record kinds always keep real timestamps regardless of heuristic.
        let workoutRow = try XCTUnwrap((queuedByKind[CloudSyncRecord.Kind.workout.rawValue] ?? []).first)
        XCTAssertGreaterThan(
            workoutRow.queuedAt.timeIntervalSince1970,
            0,
            "Workout queue row's queuedAt should be a real timestamp, not distantPast"
        )
        let workoutPayload = try XCTUnwrap(SyncPayloadCodec.decodeWorkoutPayload(from: workoutRow.payloadJSON))
        XCTAssertGreaterThan(
            workoutPayload.updatedAt.timeIntervalSince1970,
            0,
            "Workout payload's embedded updatedAt should be a real timestamp"
        )

        let memoryRow = try XCTUnwrap((queuedByKind[CloudSyncRecord.Kind.coachMemory.rawValue] ?? []).first)
        XCTAssertGreaterThan(
            memoryRow.queuedAt.timeIntervalSince1970,
            0,
            "Memory queue row's queuedAt should be a real timestamp, not distantPast"
        )
    }

    /// VOL-67 Codex P1 fixup #26: complement to the backfill clamp
    /// test — verifies the PRESERVATION branch. For customized
    /// singletons, the backfill must queue the record with its REAL
    /// `updatedAt` (both the queue row and the embedded payload),
    /// NOT `.distantPast`. Unconditionally clamping would make
    /// pushed edits look artificially old and any other device
    /// would reject them, silently losing the user's pre-upgrade
    /// customizations.
    @MainActor
    func testV3ToV4MigrationPreservesCustomizedSingletonBackfillTimestamps() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("VolumeArcMigrationBackfillPreserveCustomized.sqlite")
        let fixtureDate = Date(timeIntervalSince1970: 1_715_300_000)
        // Customized fixture — name and workoutsJSON differ from defaults.
        try writeV3FixtureStoreWithAllEntities(at: storeURL, startedAt: fixtureDate)

        let migratedContainer = try makeDiskBackedCurrentContainer(at: storeURL)
        try OutboundQueueBackfill.performIfNeeded(
            container: migratedContainer,
            userDefaults: makeEphemeralUserDefaults(),
            flagKey: "test-\(UUID().uuidString)"
        )
        let migratedContext = ModelContext(migratedContainer)

        let queuedRows = try migratedContext.fetch(FetchDescriptor<OutboundSyncQueueRecord>())
        let queuedByKind = Dictionary(grouping: queuedRows, by: { $0.recordType })

        // Profile: backfill queue row + embedded payload must NOT be distantPast.
        // Customized records keep their REAL updatedAt so cross-device LWW works.
        let profileRow = try XCTUnwrap((queuedByKind[CloudSyncRecord.Kind.userProfile.rawValue] ?? []).first)
        XCTAssertNotEqual(
            profileRow.queuedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            "Customized profile queue row's queuedAt must NOT be clamped"
        )
        XCTAssertGreaterThan(profileRow.queuedAt.timeIntervalSince1970, 0)

        let profilePayload = try XCTUnwrap(SyncPayloadCodec.decodeUserProfilePayload(from: profileRow.payloadJSON))
        XCTAssertNotEqual(
            profilePayload.updatedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            "Customized profile payload's embedded updatedAt must NOT be clamped"
        )
        XCTAssertGreaterThan(profilePayload.updatedAt.timeIntervalSince1970, 0)

        // Plan: same — customized workoutsJSON means preserve timestamps.
        let planRow = try XCTUnwrap((queuedByKind[CloudSyncRecord.Kind.trainingPlan.rawValue] ?? []).first)
        XCTAssertNotEqual(
            planRow.queuedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            "Customized plan queue row's queuedAt must NOT be clamped"
        )
        XCTAssertGreaterThan(planRow.queuedAt.timeIntervalSince1970, 0)

        let planPayload = try XCTUnwrap(SyncPayloadCodec.decodeTrainingPlanPayload(from: planRow.payloadJSON))
        XCTAssertNotEqual(
            planPayload.updatedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            "Customized plan payload's embedded updatedAt must NOT be clamped"
        )
        XCTAssertGreaterThan(planPayload.updatedAt.timeIntervalSince1970, 0)
    }

    /// VOL-67 Codex P1 fixup #17 + Copilot fixup #25: the V3→V4
    /// migration clamps migrated singleton records' `updatedAt` to
    /// `.distantPast` ONLY when every field matches the current
    /// `VolumeArcProductDefaults`. Seeded untouched defaults lose
    /// conflict resolution against older-but-authoritative cloud
    /// data (addressing fixup #17's Codex P1 concern), but
    /// user-customized records keep their real timestamps so
    /// genuine local edits aren't erased on upgrade (addressing
    /// fixup #25's Copilot concern).
    ///
    /// This test validates the clamp branch: uses a V3 fixture whose
    /// profile and plan exactly match the current seeded defaults,
    /// then asserts the migration clamps both to `.distantPast`.
    /// Per-record kinds (workouts, memories) are unaffected.
    @MainActor
    func testV3ToV4MigrationClampsSeededDefaultSingletonRecords() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("VolumeArcMigrationSeededDefaultClamp.sqlite")
        let fixtureDate = Date(timeIntervalSince1970: 1_715_350_000)
        try writeV3FixtureStoreWithSeededDefaults(at: storeURL, startedAt: fixtureDate)

        let migratedContainer = try makeDiskBackedCurrentContainer(at: storeURL)
        let migratedContext = ModelContext(migratedContainer)

        // Profile record: every field matches defaults, so it's an
        // untouched seed — clamp should fire.
        let profile = try XCTUnwrap(migratedContext.fetch(FetchDescriptor<UserProfileRecord>()).first)
        XCTAssertEqual(
            profile.updatedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            accuracy: 1.0,
            "Seeded-default UserProfileRecord.updatedAt must be clamped to distantPast"
        )

        // Plan record: workoutsJSON matches the encoded default
        // weekly schedule, so it's an untouched seed — clamp fires.
        let plan = try XCTUnwrap(migratedContext.fetch(FetchDescriptor<TrainingPlanRecord>()).first)
        XCTAssertEqual(
            plan.updatedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            accuracy: 1.0,
            "Seeded-default TrainingPlanRecord.updatedAt must be clamped to distantPast"
        )

        // Per-record kinds keep real timestamps regardless of clamp
        // heuristic.
        let workout = try XCTUnwrap(migratedContext.fetch(FetchDescriptor<WorkoutRecord>()).first)
        XCTAssertGreaterThan(
            workout.updatedAt.timeIntervalSince1970,
            0,
            "Migrated WorkoutRecord.updatedAt should be a real timestamp (per-record kinds reflect real user actions)"
        )
        XCTAssertNotEqual(
            workout.updatedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            "Migrated WorkoutRecord.updatedAt should NOT be clamped to distantPast"
        )

        let memory = try XCTUnwrap(migratedContext.fetch(FetchDescriptor<CoachMemoryRecord>()).first)
        XCTAssertGreaterThan(
            memory.createdAt.timeIntervalSince1970,
            0,
            "Migrated CoachMemoryRecord.createdAt should be a real timestamp"
        )
    }

    /// VOL-67 Copilot fixup #25: complement to the clamp test —
    /// verifies the PRESERVATION branch. When the V3 fixture's
    /// profile or plan has any field diverging from
    /// `VolumeArcProductDefaults`, the field-match heuristic
    /// recognizes real user edits and leaves the migrated
    /// `updatedAt` alone. Without this branch, fixup #17's
    /// unconditional clamp would discard genuine user edits on
    /// upgrade and let any inbound server state overwrite local
    /// customizations.
    @MainActor
    func testV3ToV4MigrationPreservesCustomizedSingletonRecordUpdatedAt() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("VolumeArcMigrationCustomizedPreserve.sqlite")
        let fixtureDate = Date(timeIntervalSince1970: 1_715_350_000)
        // The "AllEntities" fixture seeds profile with name="V3 Athlete"
        // (differs from default "") and plan with workoutsJSON="[]"
        // (differs from the encoded default weekly schedule), so both
        // are "customized" per the heuristic.
        try writeV3FixtureStoreWithAllEntities(at: storeURL, startedAt: fixtureDate)

        let migratedContainer = try makeDiskBackedCurrentContainer(at: storeURL)
        let migratedContext = ModelContext(migratedContainer)

        // Customized profile: migrated updatedAt must NOT be distantPast.
        // It should retain a real timestamp (either the V1→V2 backfill
        // or the fixture's original value, depending on migration path).
        let profile = try XCTUnwrap(migratedContext.fetch(FetchDescriptor<UserProfileRecord>()).first)
        XCTAssertNotEqual(
            profile.updatedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            "Customized UserProfileRecord (name != default) must NOT be clamped — preserves real user-edit timestamps"
        )
        XCTAssertGreaterThan(
            profile.updatedAt.timeIntervalSince1970,
            0,
            "Customized UserProfileRecord.updatedAt should be a real timestamp post-migration"
        )

        // Customized plan (workoutsJSON != encoded defaults): same.
        let plan = try XCTUnwrap(migratedContext.fetch(FetchDescriptor<TrainingPlanRecord>()).first)
        XCTAssertNotEqual(
            plan.updatedAt.timeIntervalSince1970,
            Date.distantPast.timeIntervalSince1970,
            "Customized TrainingPlanRecord (workoutsJSON != default) must NOT be clamped"
        )
        XCTAssertGreaterThan(
            plan.updatedAt.timeIntervalSince1970,
            0,
            "Customized TrainingPlanRecord.updatedAt should be a real timestamp post-migration"
        )
    }

    /// VOL-67 Codex P2 (fixup #17): the deterministic legacy memory
    /// identifier must be collision-resistant to delimiter confusion.
    /// The original newline-delimited format could produce the same
    /// canonical string for different field pairs — e.g.,
    /// `(content: "", theme: "foo\nbar")` and
    /// `(content: "\nfoo", theme: "bar")` both serialized to
    /// `"<millis>\n\nfoo\nbar"`, producing the same identifier for
    /// logically distinct memories. The fix uses length-prefixed
    /// canonical form so different inputs always hash to different IDs.
    ///
    /// This test re-opens the V4 migration twice with two different
    /// CoachMemoryRecord fixtures that would collide under the old
    /// format, and verifies the migrated identifiers differ.
    func testDeterministicLegacyMemoryIdentifierResistsDelimiterCollisions() throws {
        let fixtureDate = Date(timeIntervalSince1970: 1_715_600_000)
        let tempRoot = FileManager.default.temporaryDirectory

        func migrateAndReturnMemoryIdentifier(
            storeName: String,
            content: String,
            theme: String
        ) throws -> String {
            let directory = tempRoot.appendingPathComponent("\(storeName)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let storeURL = directory.appendingPathComponent("\(storeName).sqlite")
            try writeV3FixtureStoreWithCustomMemory(
                at: storeURL,
                memoryCreatedAt: fixtureDate,
                memoryContent: content,
                memoryTheme: theme
            )

            let migrated = try makeDiskBackedCurrentContainer(at: storeURL)
            let context = ModelContext(migrated)
            let memory = try XCTUnwrap(context.fetch(FetchDescriptor<CoachMemoryRecord>()).first)
            return memory.identifier
        }

        // Pair A: collision-prone inputs that the old newline-delimited
        // format would have hashed to the same string.
        let idA1 = try migrateAndReturnMemoryIdentifier(
            storeName: "A1",
            content: "",
            theme: "foo\nbar"
        )
        let idA2 = try migrateAndReturnMemoryIdentifier(
            storeName: "A2",
            content: "\nfoo",
            theme: "bar"
        )
        XCTAssertNotEqual(
            idA1,
            idA2,
            "Memories with different (content, theme) pairs must hash to different IDs even when the old newline-delimited encoding would have collided"
        )

        // Pair B: another delimiter-collision case — content ends in
        // newline vs theme starts with content continuation.
        let idB1 = try migrateAndReturnMemoryIdentifier(
            storeName: "B1",
            content: "hello",
            theme: "world"
        )
        let idB2 = try migrateAndReturnMemoryIdentifier(
            storeName: "B2",
            content: "hello\nworld",
            theme: ""
        )
        XCTAssertNotEqual(
            idB1,
            idB2,
            "Memories with the same total delimiter-joined bytes but different field boundaries must hash differently"
        )

        // VOL-67 Codex P2 (fixup #20): pin the exact identifier for a
        // fixed (createdAt, content, theme) triple. This catches any
        // regression in the canonical-string format — including the
        // locale-sensitive timestamp formatting issue Codex flagged in
        // fixup #20 (dropping the `Locale(identifier: "en_US_POSIX")`
        // argument to `String(format:)` would change the decimal
        // separator on non-US locales and produce a different hash).
        //
        // The value below was captured against the fixup #20 code path
        // and must stay stable. Any change to `deterministicLegacyMemoryIdentifier`
        // — delimiter order, precision, byte counting, locale
        // handling — will break this test and require an intentional
        // update (and a cross-device migration plan, because any such
        // change is a breaking hash format).
        let pinnedIdentifier = try migrateAndReturnMemoryIdentifier(
            storeName: "Pinned",
            content: "canonical test",
            theme: "migration"
        )
        XCTAssertEqual(
            pinnedIdentifier,
            "legacy-925b5338d35a27a978a3643c77c8faf934e96ff44b5ab567e63d261f36ec4fd9",
            "Fixed-input identifier must stay stable across code changes. If this assertion fails and you INTENDED to change the hash format, update the expected value AND document a cross-device migration plan (old clients will never match new clients on the same logical memory after any hash change)."
        )
    }

    /// VOL-67 Copilot (fixup #13): production creates a ModelContainer
    /// with TWO configurations — a primary store for the syncable
    /// records and a SEPARATE store for `OutboundSyncQueueRecord`. Prior
    /// migration tests used a single-configuration container, so they
    /// couldn't validate that the V3→V4 backfill actually routes queue
    /// inserts to the separate queue store. This test mirrors
    /// production: migrates a V3 store with a multi-config V4
    /// container, runs the post-bootstrap `OutboundQueueBackfill`
    /// helper (which is where the backfill lives now, outside the
    /// migration stage), then opens a queue-only container pointing
    /// at the queue URL to confirm the rows landed there specifically.
    @MainActor
    func testV3ToV4MigrationBackfillsOutboundQueueWithSeparateQueueStore() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let primaryURL = temporaryDirectory.appendingPathComponent("VolumeArc.sqlite")
        let queueURL = temporaryDirectory.appendingPathComponent("VolumeArcOutboundQueue.sqlite")
        let fixtureDate = Date(timeIntervalSince1970: 1_715_400_000)
        try writeV3FixtureStoreWithAllEntities(at: primaryURL, startedAt: fixtureDate)

        // Build a V4 container with two configurations pointing at the
        // two separate store URLs. This mirrors
        // `VolumeArcPersistenceController.makeContainer` exactly, minus
        // CloudKit mirroring (which can't run in tests).
        let syncableSchema = Schema([
            UserProfileRecord.self,
            TrainingPlanRecord.self,
            WorkoutRecord.self,
            CoachMemoryRecord.self,
        ])
        let queueSchema = Schema([OutboundSyncQueueRecord.self])
        let combinedSchema = Schema(VolumeArcSchemaV4.models)

        let primaryConfig = ModelConfiguration(
            "VolumeArc",
            schema: syncableSchema,
            url: primaryURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let queueConfig = ModelConfiguration(
            "VolumeArc-OutboundQueue",
            schema: queueSchema,
            url: queueURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        let multiConfigContainer = try ModelContainer(
            for: combinedSchema,
            migrationPlan: VolumeArcSchemaMigrationPlan.self,
            configurations: [primaryConfig, queueConfig]
        )

        // Post-bootstrap backfill: this is what production runs right
        // after `makeContainer` inside `VolumeArcPersistenceController.init`.
        try OutboundQueueBackfill.performIfNeeded(
            container: multiConfigContainer,
            userDefaults: makeEphemeralUserDefaults(),
            flagKey: "test-\(UUID().uuidString)"
        )

        // Verify the records migrated into the primary store.
        let primaryContext = ModelContext(multiConfigContainer)
        let workouts = try primaryContext.fetch(FetchDescriptor<WorkoutRecord>())
        let profiles = try primaryContext.fetch(FetchDescriptor<UserProfileRecord>())
        let plans = try primaryContext.fetch(FetchDescriptor<TrainingPlanRecord>())
        let memories = try primaryContext.fetch(FetchDescriptor<CoachMemoryRecord>())
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(memories.count, 1)

        // Open a separate queue-only container pointing at the queue
        // URL. If the migration backfill wasn't routed to this store,
        // this container will be empty — the original bug we're
        // preventing.
        let queueOnlyContainer = try ModelContainer(
            for: queueSchema,
            configurations: [
                ModelConfiguration(
                    "VolumeArc-OutboundQueue",
                    schema: queueSchema,
                    url: queueURL,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            ]
        )
        let queueContext = ModelContext(queueOnlyContainer)
        let queuedRows = try queueContext.fetch(FetchDescriptor<OutboundSyncQueueRecord>())

        // Four records → four queue rows (workout, profile, plan, memory).
        XCTAssertEqual(queuedRows.count, 4, "Expected 4 outbound queue rows after V3→V4 migration")

        let queuedByKind = Dictionary(grouping: queuedRows, by: { $0.recordType })
        XCTAssertEqual(queuedByKind[CloudSyncRecord.Kind.workout.rawValue]?.count, 1)
        XCTAssertEqual(queuedByKind[CloudSyncRecord.Kind.userProfile.rawValue]?.count, 1)
        XCTAssertEqual(queuedByKind[CloudSyncRecord.Kind.trainingPlan.rawValue]?.count, 1)
        XCTAssertEqual(queuedByKind[CloudSyncRecord.Kind.coachMemory.rawValue]?.count, 1)
    }

    /// VOL-67 Copilot (fixup #15): `OutboundQueueBackfill.performIfNeeded`
    /// builds its dedupe key from `(recordType, recordIdentifier)` of
    /// existing queue rows and compares against a key computed the same
    /// way for each candidate migrating record. Before this fix, both
    /// sides used raw strings — so a legacy long-form row in the queue
    /// (`recordType="userProfile"`, `recordIdentifier="userProfile"`)
    /// wouldn't match the canonical short-form key the backfill built
    /// (`("profile", "profile")`), and the backfill would insert a
    /// duplicate canonical row for the same logical singleton.
    ///
    /// Fix: normalize both existing and newly-computed keys via
    /// `CloudSyncRecord.Kind.parse(_:)` + `canonicalQueueIdentifier(from:)`.
    ///
    /// Setup: migrate a V3 store, then manually insert a LEGACY-form
    /// profile queue row before running the backfill. Expected: the
    /// backfill sees the legacy row as already-queued for the profile
    /// kind and skips it — the final queue has exactly one profile row,
    /// not two.
    @MainActor
    func testBackfillCanonicalizesLegacyQueueKeysForDedupe() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("VolumeArcBackfillDedupe.sqlite")
        let fixtureDate = Date(timeIntervalSince1970: 1_715_500_000)
        try writeV3FixtureStoreWithAllEntities(at: storeURL, startedAt: fixtureDate)

        let migratedContainer = try makeDiskBackedCurrentContainer(at: storeURL)
        let seedContext = ModelContext(migratedContainer)

        // Seed the queue with a LEGACY-form singleton row BEFORE
        // running the backfill. `recordType="userProfile"` uses the
        // long-form alias (not canonical `"profile"`), and the
        // `recordIdentifier="userProfile"` matches the long-form
        // identifier shape that pre-canonicalization code produced.
        //
        // VOL-67 Codex P2 (fixup #31): the fixture's payloadJSON must
        // be a VALID envelope that decodes for the kind, otherwise
        // the backfill's new validity filter treats the row as
        // malformed and enqueues a fresh canonical row on top of it
        // (correct behavior for malformed legacy rows, wrong for this
        // test which is specifically validating canonical dedupe of a
        // legitimate-but-legacy-shape row). Use the repository's
        // migrated profile to generate a real valid payload.
        let migratedProfileForPayload = try XCTUnwrap(
            seedContext.fetch(FetchDescriptor<UserProfileRecord>()).first
        )
        let validLegacyPayload = try XCTUnwrap(
            SyncPayloadCodec.encodeUserProfilePayload(from: migratedProfileForPayload)
        )
        seedContext.insert(OutboundSyncQueueRecord(
            recordType: "userProfile",
            recordIdentifier: "userProfile",
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: validLegacyPayload,
            queuedAt: Date(timeIntervalSince1970: 1_715_500_100)
        ))
        try seedContext.save()

        // Sanity: exactly one profile-shaped row is in the queue
        // BEFORE the backfill runs.
        let preBackfillRows = try seedContext.fetch(FetchDescriptor<OutboundSyncQueueRecord>())
        XCTAssertEqual(preBackfillRows.count, 1)

        try OutboundQueueBackfill.performIfNeeded(
            container: migratedContainer,
            userDefaults: makeEphemeralUserDefaults(),
            flagKey: "test-\(UUID().uuidString)"
        )

        // The backfill should have:
        //   - Seen the legacy "userProfile" row and recognized it as
        //     the same logical profile singleton, so NOT added a
        //     duplicate canonical "profile" row.
        //   - Still added the rows for workout, plan, memory (which
        //     had no pre-existing queue rows).
        let postContext = ModelContext(migratedContainer)
        let queuedRows = try postContext.fetch(FetchDescriptor<OutboundSyncQueueRecord>())

        // Profile: exactly ONE row, and it's the legacy one we seeded
        // (backfill recognized it and skipped).
        let profileRows = queuedRows.filter { row in
            CloudSyncRecord.Kind.parse(row.recordType) == .userProfile
        }
        XCTAssertEqual(
            profileRows.count,
            1,
            "Backfill must not duplicate a canonical profile row when a legacy profile row already exists"
        )
        XCTAssertEqual(
            profileRows.first?.recordType,
            "userProfile",
            "The remaining profile row should be the legacy one we seeded — backfill should NOT have replaced it"
        )

        // The other kinds should have been backfilled normally.
        XCTAssertEqual(
            queuedRows.filter { CloudSyncRecord.Kind.parse($0.recordType) == .workout }.count,
            1
        )
        XCTAssertEqual(
            queuedRows.filter { CloudSyncRecord.Kind.parse($0.recordType) == .trainingPlan }.count,
            1
        )
        XCTAssertEqual(
            queuedRows.filter { CloudSyncRecord.Kind.parse($0.recordType) == .coachMemory }.count,
            1
        )
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

    /// Write a V3 fixture store containing a single `CoachMemoryRecord`
    /// with caller-specified `content`/`theme`. Used by the
    /// deterministic-ID collision-resistance tests (fixup #17) to
    /// materialize memories with delimiter-ambiguous field values that
    /// the old newline-joined hash would have collided on.
    private func writeV3FixtureStoreWithCustomMemory(
        at storeURL: URL,
        memoryCreatedAt: Date,
        memoryContent: String,
        memoryTheme: String
    ) throws {
        let schema = Schema(VolumeArcSchemaV3.models)
        let config = ModelConfiguration(
            "MigrationFixtureCustomMemoryV3",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        try autoreleasepool {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            context.insert(
                VolumeArcSchemaV3.CoachMemoryRecord(
                    content: memoryContent,
                    theme: memoryTheme,
                    createdAt: memoryCreatedAt
                )
            )

            try context.save()
        }
    }

    /// VOL-67 Copilot (fixup #25): write a V3 fixture whose profile
    /// and plan EXACTLY match `VolumeArcProductDefaults` so that the
    /// V3→V4 migration's field-match heuristic recognizes them as
    /// seeded defaults and clamps their `updatedAt` to `.distantPast`.
    /// Used by the clamp-behavior test to verify the "untouched
    /// defaults lose conflict resolution against real cloud data"
    /// path still works after the heuristic was added.
    private func writeV3FixtureStoreWithSeededDefaults(at storeURL: URL, startedAt: Date) throws {
        let schema = Schema(VolumeArcSchemaV3.models)
        let config = ModelConfiguration(
            "MigrationFixtureSeededDefaultsV3",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        try autoreleasepool {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            // Match VolumeArcProductDefaults.userProfile exactly.
            let defaults = VolumeArcProductDefaults.userProfile
            let defaultEquipmentCSV = defaults.availableEquipment
                .map(\.rawValue)
                .sorted()
                .joined(separator: ",")
            context.insert(VolumeArcSchemaV3.UserProfileRecord(
                name: defaults.name,
                coachingStyle: defaults.coachingStyle.rawValue,
                privacyMode: defaults.privacyMode.rawValue,
                advancementLevel: defaults.advancementLevel.rawValue,
                availableEquipmentCSV: defaultEquipmentCSV,
                preferredRepRangeLower: defaults.preferredRepRangeLower,
                preferredRepRangeUpper: defaults.preferredRepRangeUpper,
                sessionTimeBudgetMinutes: defaults.sessionTimeBudgetMinutes,
                weeklyTrainingDays: defaults.weeklyTrainingDays
                // onboardingCompleted defaults to false — matching the seed
            ))

            // Match the encoded default weekly schedule exactly.
            let defaultPlanJSON = SyncPayloadCodec.encode(VolumeArcProductDefaults.weeklySchedule) ?? "[]"
            context.insert(VolumeArcSchemaV3.TrainingPlanRecord(
                workoutsJSON: defaultPlanJSON,
                updatedAt: startedAt
            ))

            // Workout + memory still use real user-action timestamps —
            // per-record kinds never get clamped regardless of the
            // heuristic.
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

    /// A throwaway `UserDefaults` suite so tests don't touch the user's
    /// `.standard` defaults or collide across runs. Each test gets a
    /// fresh suite bound to a random name; the suite is never
    /// registered or persisted, so its contents vanish when the test
    /// process ends.
    private func makeEphemeralUserDefaults() -> UserDefaults {
        let suiteName = "VolumeArcTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        // Reset anything the suite may have been initialized with.
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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
