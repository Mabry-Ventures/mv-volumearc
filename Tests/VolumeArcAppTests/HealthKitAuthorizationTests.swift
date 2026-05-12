// VOL-136 Phase 1: exercise `WorkoutDashboardModel.requestHealthKitAuthorization()`
// across every branch using the existing HealthStore test doubles
// (`MockHealthStore`, `DenyingHealthStore`, `RecordingHealthStore`)
// from `TestSupport/Mocks.swift`. The doubles already existed
// (`MocksUsageSmokeTests.swift` proves they compile) but no real
// scenario test exercised them — VOL-136 closes that gap.
//
// The four paths under test:
//   1. `shouldSurfacePermissionPrompts == false` → silent short-
//      circuit, records `health.auth_skipped`, returns false.
//   2. `requestAuthorization` returns true and `isAuthorized` is
//      true → returns true, records `health.auth_requested`.
//   3. `requestAuthorization` returns false (user denied) → returns
//      false, records `health.auth_requested`.
//   4. `requestAuthorization` throws → returns false, records
//      `health.auth_failed`.
//
// Each test:
//   - constructs a minimal `WorkoutDashboardModel` via the same
//     helper the dashboard integration suite uses;
//   - exercises the auth path;
//   - asserts the return value, the `isHealthAuthorized` state, and
//     the recorded telemetry event(s).
//
// Why we exercise the public model instead of the protocol directly:
//   The audit's risk is a real-device regression where the
//   *integration* (model + store + telemetry + flag gate) breaks,
//   not a typo in any single conformer. Testing the integration
//   point catches what's actually risky.

#if canImport(SwiftData)
import XCTest
import SwiftData
@testable import VolumeArcCore

@MainActor
final class HealthKitAuthorizationTests: XCTestCase {
    private var container: ModelContainer!
    private var workoutRepository: SwiftDataWorkoutRepository!
    private var coachMemoryRepository: SwiftDataCoachMemoryRepository!
    private var userProfileRepository: SwiftDataUserProfileRepository!
    private var trainingPlanRepository: SwiftDataTrainingPlanRepository!
    private var savedDeterministicMode: Bool!
    private var savedSimulatePermissionPrompts: Bool!

    override func setUp() async throws {
        let schema = Schema(VolumeArcSchemaV4.models)
        let config = ModelConfiguration(
            "HealthKitAuthTests-\(UUID().uuidString)",
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

        // Snapshot the global runtime flags so we can restore them in
        // tearDown. Other tests in the suite expect production
        // defaults; we mutate them locally to drive the
        // shouldSurfacePermissionPrompts branches without polluting
        // shared state.
        savedDeterministicMode = VolumeArcRuntimeFlags.isDeterministicMode
        savedSimulatePermissionPrompts = VolumeArcRuntimeFlags.simulatePermissionPrompts
    }

    override func tearDown() async throws {
        VolumeArcRuntimeFlags.isDeterministicMode = savedDeterministicMode
        VolumeArcRuntimeFlags.simulatePermissionPrompts = savedSimulatePermissionPrompts
    }

    // MARK: - Branch 1: prompt-suppressed short-circuit

    /// Under `isDeterministicMode && !simulatePermissionPrompts`, the
    /// model must short-circuit without touching the store, leave
    /// `isHealthAuthorized` matching the store's reported state, and
    /// record `health.auth_skipped`.
    func testReturnsFalseAndSkipsTelemetryWhenPromptsAreSuppressed() async {
        VolumeArcRuntimeFlags.isDeterministicMode = true
        VolumeArcRuntimeFlags.simulatePermissionPrompts = false

        let telemetry = InMemoryTelemetrySink()
        let store = RecordingHealthStore()
        store.authorized = false

        let model = makeModel(healthStore: store, telemetrySink: telemetry)

        let granted = await model.requestHealthKitAuthorization()

        XCTAssertFalse(granted, "Skipped prompt should return false")
        XCTAssertFalse(model.isHealthAuthorized, "Skipped prompt should mirror the store's unauthorized state")
        XCTAssertEqual(
            store.calls,
            [],
            "The store must not be called when prompts are suppressed"
        )
        XCTAssertTrue(
            telemetry.currentEvents.contains { $0.category == "health" && $0.name == "auth_skipped" },
            "Skipped path must record `health.auth_skipped`"
        )
    }

    // MARK: - Branch 2: granted

    func testReturnsTrueAndRecordsRequestedWhenStoreGrants() async {
        VolumeArcRuntimeFlags.isDeterministicMode = false  // production-like path

        let telemetry = InMemoryTelemetrySink()
        let store = RecordingHealthStore()
        store.authorized = true

        let model = makeModel(healthStore: store, telemetrySink: telemetry)

        let granted = await model.requestHealthKitAuthorization()

        XCTAssertTrue(granted, "Granted path should return true")
        XCTAssertTrue(model.isHealthAuthorized, "Granted path should set isHealthAuthorized")
        XCTAssertEqual(
            store.calls,
            [.requestAuthorization],
            "Granted path must request authorization exactly once"
        )
        XCTAssertTrue(
            telemetry.currentEvents.contains { $0.category == "health" && $0.name == "auth_requested" },
            "Granted path must record `health.auth_requested`"
        )
    }

    // MARK: - Branch 3: denied (user tapped "Don't Allow")

    func testReturnsFalseWhenStoreDeniesButDoesNotThrow() async {
        VolumeArcRuntimeFlags.isDeterministicMode = false

        let telemetry = InMemoryTelemetrySink()
        let store = RecordingHealthStore()
        store.authorized = false

        let model = makeModel(healthStore: store, telemetrySink: telemetry)

        let granted = await model.requestHealthKitAuthorization()

        XCTAssertFalse(granted, "Denied path should return false")
        XCTAssertFalse(model.isHealthAuthorized, "Denied path should leave isHealthAuthorized false")
        XCTAssertTrue(
            telemetry.currentEvents.contains { $0.category == "health" && $0.name == "auth_requested" },
            "Denied path must still record `health.auth_requested` (the request happened, the answer was no)"
        )
        XCTAssertFalse(
            telemetry.currentEvents.contains { $0.category == "health" && $0.name == "auth_failed" },
            "Denied path must NOT record `health.auth_failed` — that's reserved for errors"
        )
    }

    // MARK: - Branch 4: errored

    func testReturnsFalseAndRecordsFailureWhenStoreThrows() async {
        VolumeArcRuntimeFlags.isDeterministicMode = false

        let telemetry = InMemoryTelemetrySink()
        let store = DenyingHealthStore(
            authorizationError: MockError("simulated underlying HealthKit error")
        )

        let model = makeModel(healthStore: store, telemetrySink: telemetry)

        let granted = await model.requestHealthKitAuthorization()

        XCTAssertFalse(granted, "Errored path should return false")
        XCTAssertFalse(model.isHealthAuthorized, "Errored path should leave isHealthAuthorized false")
        XCTAssertTrue(
            telemetry.currentEvents.contains { $0.category == "health" && $0.name == "auth_failed" },
            "Errored path must record `health.auth_failed`"
        )
        XCTAssertFalse(
            telemetry.currentEvents.contains { $0.category == "health" && $0.name == "auth_requested" },
            "Errored path must NOT record `health.auth_requested` — the request didn't complete"
        )
    }

    // MARK: - Helpers

    private func makeModel(
        healthStore: HealthStore,
        telemetrySink: TelemetrySink
    ) -> WorkoutDashboardModel {
        WorkoutDashboardModel(
            aiProvider: LocalHeuristicAICoachProvider(),
            syncEngine: CloudSyncCoordinator(
                transport: UnavailableCloudSyncTransport(reason: "HealthKit tests do not sync"),
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
            healthStore: healthStore,
            notificationStore: InMemoryNotificationStore(),
            telemetrySink: telemetrySink,
            surfaceStore: UserDefaultsPlatformSurfaceStateStore(),
            subscriptionStore: StoreKitSubscriptionStore(productIDs: []),
            voiceCoach: LiveVoiceCoachOrchestrator(
                transport: AIRelayVoiceTransport(provider: LocalHeuristicAICoachProvider())
            )
        )
    }
}
#endif
