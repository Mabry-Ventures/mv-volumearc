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

    // VOL-80 / VOL-181: Regression guard. Phone read set covers the
    // App Store-justified read types: Workouts (training history),
    // HRV-SDNN + Sleep Analysis (recovery analysis surfaced via the
    // VOL-181 `HealthKitRecoveryReader`). Expanding this set without
    // a consumer (and a matching usage-description string in
    // `scripts/generate_xcode_project.rb`) fails App Store review
    // and is a least-privilege regression. If you add a type,
    // update this assertion AND the usage-description string in
    // the same PR.
    //
    // VOL-227 fix: original assertion was `["HKWorkoutTypeIdentifier"]`
    // only — pre-dated the VOL-181 recovery work that legitimately
    // added HRV + Sleep to the phone scope alongside their usage
    // descriptions. The test had been failing silently in CI because
    // unit-test exit-code semantics let UI tests still attempt to
    // run (see VOL-227 for the broader investigation).
    func testPhoneHealthKitReadScopeStaysWorkoutsOnly() {
        XCTAssertEqual(
            HealthKitAuthorizationScope.phoneReadIdentifiers,
            [
                "HKWorkoutTypeIdentifier",
                "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
                "HKCategoryTypeIdentifierSleepAnalysis",
            ]
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
