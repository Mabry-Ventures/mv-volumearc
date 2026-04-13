import XCTest
import VolumeArcCore

final class VolumeArcAppConfigurationTests: XCTestCase {
    func testShortcutsCatalogContainsExpectedCoreIntents() {
        XCTAssertEqual(VolumeArcShortcuts.appShortcuts.count, 6)
        XCTAssertTrue(StartNextWorkoutIntent.openAppWhenRun)
        XCTAssertTrue(AskCoachIntent.openAppWhenRun)
        XCTAssertTrue(OpenSignalsIntent.openAppWhenRun)
        XCTAssertTrue(StartWorkoutSessionIntent.openAppWhenRun)
        XCTAssertTrue(LogRecommendedSetIntent.openAppWhenRun)
        XCTAssertTrue(SyncVolumeArcIntent.openAppWhenRun)
    }

    func testPremiumCatalogContainsExpectedPlans() {
        XCTAssertEqual(
            Set(VolumeArcPremiumCatalog.subscriptionProductIDs),
            [
                "com.mabryventures.VolumeArc.premium.monthly",
                "com.mabryventures.VolumeArc.premium.yearly",
            ]
        )
    }

    func testCloudKitSyncZoneMatchesShippingContract() {
        XCTAssertEqual(VolumeArcCloudConfiguration.syncZoneName, "VolumeArcSyncZone")
    }

    func testWidgetControllerReloadTimelinesIsSafeWithoutWidgetRuntime() {
        let controller = VolumeArcWidgetController()
        controller.reloadTimelines()
    }

    func testLiveActivityControllerNoOpsSafelyWithoutActiveSessions() async {
        let controller = VolumeArcLiveActivityController()
        await controller.startOrUpdate(
            from: LiveActivityState(
                workoutTitle: "Strength Day",
                activeExerciseName: "Back Squat",
                targetSummary: "225 x 5",
                restSecondsRemaining: 90
            )
        )
        await controller.end()
    }

    func testCoachIntentPerformPathsDoNotThrow() async throws {
        _ = try await AskCoachIntent(prompt: "That felt heavy. Should I hold?").perform()
        _ = try await StartWorkoutSessionIntent().perform()
        _ = try await LogRecommendedSetIntent().perform()
        _ = try await SyncVolumeArcIntent().perform()
    }

    func testSecureStoreRoundTripsAndUpdatesValues() throws {
        let store = VolumeArcSecureStore()
        let key = "tests.\(UUID().uuidString)"

        try store.save("initial", for: key)
        XCTAssertEqual(try store.load(key), "initial")

        try store.save("updated", for: key)
        XCTAssertEqual(try store.load(key), "updated")
    }
}
