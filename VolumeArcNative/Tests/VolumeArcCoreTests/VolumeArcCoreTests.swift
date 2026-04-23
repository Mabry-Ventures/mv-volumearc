import Testing
@testable import VolumeArcCore
#if canImport(HealthKit)
import HealthKit
#endif

@Test func progressionEngineEvaluatesReadiness() {
    let engine = ProgressionEngine()
    let readiness = engine.evaluateReadiness(from: [], athlete: AthleteProfile(name: "Test"))
    #expect(readiness.score > 0)
}

@Test func deepLinkRoundTrips() {
    let destinations: [VolumeArcDeepLink.Destination] = [
        .today,
        .nextWorkout,
        .coach(prompt: "Should I go heavier?"),
        .signals,
        .action(.startWorkoutSession),
        .action(.logRecommendedSet),
        .action(.syncNow),
    ]

    for destination in destinations {
        let url = VolumeArcDeepLink.url(for: destination)
        let parsed = VolumeArcDeepLink.destination(for: url)
        #expect(parsed != nil, "Failed to parse URL: \(url)")
    }
}

@Test func syncPayloadCodecEncodesValidJSON() {
    struct Sample: Codable { let value: Int }
    let result = SyncPayloadCodec.encode(Sample(value: 42))
    #expect(result != nil)
    #expect(result?.contains("42") == true)
}

<<<<<<< HEAD
// VOL-80: Regression test. The phone read set must stay small — only workouts.
// Adding heart rate, active energy, sleep, HRV, etc. on the phone requires a
// consumer for that data AND an updated `NSHealthShareUsageDescription` string
// in `scripts/generate_xcode_project.rb` that names the new category.
@Test func phoneHealthKitReadScopeIsWorkoutsOnly() {
    #expect(HealthKitAuthorizationScope.phoneReadIdentifiers == ["HKWorkoutTypeIdentifier"])
}

// VOL-80: Regression test. Watch adds heart rate + active energy so the live
// workout session can save an HR chart and calorie total into Apple Health.
// If you remove either, `HKLiveWorkoutDataSource` will silently drop the
// matching channel from the saved workout.
@Test func watchHealthKitReadScopeCoversLiveWorkoutQuantities() {
    #expect(HealthKitAuthorizationScope.watchReadIdentifiers == [
        "HKWorkoutTypeIdentifier",
        "HKQuantityTypeIdentifierHeartRate",
        "HKQuantityTypeIdentifierActiveEnergyBurned"
    ])
}

@Test func healthKitWriteScopeIsWorkoutsOnly() {
    #expect(HealthKitAuthorizationScope.sharedWriteIdentifiers == ["HKWorkoutTypeIdentifier"])
}

#if canImport(HealthKit)
// VOL-80: Cross-check the runtime HKObjectType set matches the string
// identifiers declared in `HealthKitAuthorizationScope`. Guards against the
// two declarations drifting (e.g. someone adds a read type to the runtime
// request and forgets to update the scope manifest the tests/usage-desc rely on).
@Test func runtimeReadSetMatchesAuthorizationScope() {
    let phoneIdentifiers = Set(HealthKitRuntimeStore.phoneReadTypes().map(\.identifier))
    #expect(phoneIdentifiers == HealthKitAuthorizationScope.phoneReadIdentifiers)

    let watchIdentifiers = Set(HealthKitRuntimeStore.watchReadTypes().map(\.identifier))
    #expect(watchIdentifiers == HealthKitAuthorizationScope.watchReadIdentifiers)
}
#endif
=======
@Test func legalLinksAreHTTPS() {
    // VOL-71: both legal URLs must parse and use https. App Store review
    // will reject legal links that fall back to http or are malformed, even
    // if the destination pages themselves aren't live yet.
    #expect(LegalLinks.termsOfService.scheme == "https")
    #expect(LegalLinks.termsOfService.host == "volumearc.app")
    #expect(LegalLinks.termsOfService.path == "/terms")

    #expect(LegalLinks.privacyPolicy.scheme == "https")
    #expect(LegalLinks.privacyPolicy.host == "volumearc.app")
    #expect(LegalLinks.privacyPolicy.path == "/privacy")
}
>>>>>>> origin/main
