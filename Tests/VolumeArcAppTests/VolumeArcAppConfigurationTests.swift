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

    // VOL-80: Regression guard. Phone read set is workouts-only. Expanding
    // this set without a consumer (and an updated usage-description string in
    // `scripts/generate_xcode_project.rb`) fails App Store review and is a
    // least-privilege regression. If you add a type, update this assertion
    // AND the usage-description string in the same PR.
    func testPhoneHealthKitReadScopeStaysWorkoutsOnly() {
        XCTAssertEqual(
            HealthKitAuthorizationScope.phoneReadIdentifiers,
            ["HKWorkoutTypeIdentifier"]
        )
    }

    // VOL-80: Watch read set covers everything `HKLiveWorkoutDataSource` needs
    // to populate the saved workout with an HR chart and calorie total.
    func testWatchHealthKitReadScopeCoversLiveWorkoutQuantities() {
        XCTAssertEqual(
            HealthKitAuthorizationScope.watchReadIdentifiers,
            [
                "HKWorkoutTypeIdentifier",
                "HKQuantityTypeIdentifierHeartRate",
                "HKQuantityTypeIdentifierActiveEnergyBurned"
            ]
        )
    }

    func testHealthKitWriteScopeStaysWorkoutsOnly() {
        XCTAssertEqual(
            HealthKitAuthorizationScope.sharedWriteIdentifiers,
            ["HKWorkoutTypeIdentifier"]
        )
    }
}
