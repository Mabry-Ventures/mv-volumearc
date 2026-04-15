import Testing
@testable import VolumeArcCore

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
