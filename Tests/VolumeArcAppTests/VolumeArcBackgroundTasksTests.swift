#if canImport(SwiftData)
import XCTest
import SwiftData
import VolumeArcCore

/// VOL-110: unit coverage for the BGTask app-refresh observability path
/// and the widget snapshot publishing path.
///
/// Why this is a unit test (not an XCUITest):
/// - `BGAppRefreshTask` cannot be constructed in user code — only the
///   system allocates one. The standard private SPI to simulate it
///   (`_simulateLaunchForTaskWithIdentifier:`) requires LLDB, which
///   XCUITest cannot drive in CI.
/// - The app-side handler in `VolumeArcBackgroundTasks.handleAppRefresh`
///   delegates to `WorkoutDashboardModel.performBackgroundRefresh()`,
///   which IS testable. We exercise the model method directly with a
///   capturing telemetry sink, asserting the same observability contract
///   the BGTask handler depends on.
/// - The widget snapshot publishing path likewise routes through
///   `WorkoutDashboardModel.refresh()` → `PlatformSurfaceDefaultsWriter`,
///   which is unit-testable end-to-end against a temporary
///   UserDefaults suite.
@MainActor
final class VolumeArcBackgroundTasksTests: XCTestCase {
    private var container: ModelContainer!
    private var workoutRepository: SwiftDataWorkoutRepository!
    private var coachMemoryRepository: SwiftDataCoachMemoryRepository!
    private var userProfileRepository: SwiftDataUserProfileRepository!
    private var trainingPlanRepository: SwiftDataTrainingPlanRepository!

    override func setUp() async throws {
        let schema = Schema(VolumeArcSchemaV4.models)
        let config = ModelConfiguration(
            "BackgroundTasksTest-\(UUID().uuidString)",
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

    // MARK: - VOL-110 BGTask refresh telemetry

    /// VOL-110 contract: when the BGTask handler calls
    /// `performBackgroundRefresh`, the telemetry sink records both
    /// `background.refresh_started` and `background.refresh_completed`
    /// events bracketing the actual refresh work.
    ///
    /// Operations folks rely on these events to verify the BGTask is
    /// actually waking the app (vs the OS coalescing it away). A
    /// regression where one of the events stops firing would silently
    /// erase that observability — this test catches it.
    func testPerformBackgroundRefreshRecordsBracketingTelemetry() async throws {
        let telemetry = CapturingTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)

        let success = await model.performBackgroundRefresh()
        XCTAssertTrue(success, "Background refresh should complete successfully on a healthy model")

        let backgroundEvents = telemetry.events.filter { $0.category == "background" }
        XCTAssertEqual(
            backgroundEvents.map(\.name),
            ["refresh_started", "refresh_completed"],
            "BGTask path should record exactly the two bracketing events in order"
        )

        // Both events should be `.info` severity — operations watches
        // these as routine signals, not warnings or errors.
        XCTAssertTrue(
            backgroundEvents.allSatisfy { $0.severity == .info },
            "Bracketing background events should be info severity"
        )
    }

    /// Repeated calls preserve event ordering. If a future refactor adds
    /// reentrancy that interleaves events from concurrent calls, this
    /// test surfaces the regression — the recorded names should still
    /// match the call pattern.
    func testRepeatedBackgroundRefreshRecordsTelemetryPerCall() async throws {
        let telemetry = CapturingTelemetrySink()
        let model = makeDashboardModel(telemetrySink: telemetry)

        await model.performBackgroundRefresh()
        await model.performBackgroundRefresh()
        await model.performBackgroundRefresh()

        let backgroundEvents = telemetry.events.filter { $0.category == "background" }
        XCTAssertEqual(
            backgroundEvents.map(\.name),
            [
                "refresh_started", "refresh_completed",
                "refresh_started", "refresh_completed",
                "refresh_started", "refresh_completed",
            ],
            "3 BGTask invocations should record 6 events in started/completed pairs"
        )
    }

    // MARK: - VOL-110 widget snapshot round-trip

    /// VOL-110 contract: the widget snapshot writer + reader round-trip
    /// preserves every payload field. The dashboard model publishes a
    /// snapshot during `refresh()` for the widget extension to read; if
    /// the encoder or storage key drifts, the widget renders stale data
    /// silently. This test pins the contract on a temporary UserDefaults
    /// suite so we don't depend on the real app group entitlement at
    /// test time.
    func testWidgetSnapshotRoundTripPreservesAllFields() throws {
        // Use a per-test UserDefaults suite so the test is hermetic and
        // doesn't pollute the real app-group store. The suite is
        // released when the test process exits.
        let suiteName = "com.mabryventures.VolumeArc.tests.widget.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults suite for widget snapshot test")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let original = WidgetSummarySnapshot(
            nextWorkoutTitle: "Monday Squat",
            readinessScore: "82",
            primaryLiftForecast: "Back squat 245x5",
            nextActionTitle: "Start session",
            syncSummary: "Synced 2 minutes ago",
            streakDays: 7,
            coachPrompt: "Brace before unrack.",
            updatedAt: Date(timeIntervalSince1970: 1_745_000_000)
        )

        // VOL-110: use the testable overload that takes an injected
        // `UserDefaults` so the round-trip is hermetic — no app-group
        // entitlement required.
        PlatformSurfaceDefaultsWriter.saveWidgetSnapshot(original, to: defaults)

        let decoded = PlatformSurfaceDefaultsReader.loadWidgetSnapshot(from: defaults)
        XCTAssertNotNil(decoded, "Widget snapshot should be decodable after a round-trip write")

        XCTAssertEqual(decoded?.nextWorkoutTitle, original.nextWorkoutTitle)
        XCTAssertEqual(decoded?.readinessScore, original.readinessScore)
        XCTAssertEqual(decoded?.primaryLiftForecast, original.primaryLiftForecast)
        XCTAssertEqual(decoded?.nextActionTitle, original.nextActionTitle)
        XCTAssertEqual(decoded?.syncSummary, original.syncSummary)
        XCTAssertEqual(decoded?.streakDays, original.streakDays)
        XCTAssertEqual(decoded?.coachPrompt, original.coachPrompt)
        XCTAssertEqual(decoded?.updatedAt, original.updatedAt)
    }

    /// Reading a snapshot from an empty store returns nil (vs throwing).
    /// Pins the "first launch — no snapshot yet" contract.
    func testWidgetSnapshotLoadReturnsNilWhenStoreIsEmpty() throws {
        let suiteName = "com.mabryventures.VolumeArc.tests.widget.empty.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(PlatformSurfaceDefaultsReader.loadWidgetSnapshot(from: defaults))
    }

    // MARK: - Helpers

    /// Construct a fully-wired `WorkoutDashboardModel` with the in-memory
    /// SwiftData container + a caller-provided telemetry sink. Mirrors
    /// the integration-test helper in `VolumeArcDashboardIntegrationTests`
    /// but takes the sink as a parameter so the BGTask test can pass a
    /// `CapturingTelemetrySink` and read events back.
    private func makeDashboardModel(
        telemetrySink: TelemetrySink,
        aiProvider: any AICoachProvider = LocalHeuristicAICoachProvider()
    ) -> WorkoutDashboardModel {
        WorkoutDashboardModel(
            aiProvider: aiProvider,
            syncEngine: CloudSyncCoordinator(
                transport: UnavailableCloudSyncTransport(reason: "BG tests do not sync"),
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
            telemetrySink: telemetrySink,
            surfaceStore: UserDefaultsPlatformSurfaceStateStore(),
            subscriptionStore: StoreKitSubscriptionStore(productIDs: []),
            voiceCoach: LiveVoiceCoachOrchestrator(
                transport: OpenAIRelayVoiceTransport(provider: aiProvider)
            )
        )
    }
}
#endif
