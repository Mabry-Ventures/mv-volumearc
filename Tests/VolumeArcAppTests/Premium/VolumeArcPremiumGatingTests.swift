import XCTest
import VolumeArcCore

// VOL-91: Premium entitlement gating integration tests.
//
// The runtime factory decides two things based on the caller's premium
// state:
//   1. Coach tier — `.pro` for premium users, `.flashLite` for free.
//      (Routed to the relay via `X-Coach-Tier:`.)
//   2. Live voice transport — `AIRelayVoiceTransport` installed only
//      when premium AND the `.voiceCoaching` flag is on; otherwise
//      `UnavailableVoiceTransport` so every `speak(...)` call throws
//      `AIRuntimeIntegrationError.relayUnavailable`.
//
// The factory's concrete provider type is opaque (`AICoachProvider`),
// so tests verify the decision via the one-shot telemetry signal on
// `premium.entitlement.gated` (category) / `coach_tier` | `live_voice`
// (name). Metadata carries the resolved `premium` bool verbatim —
// that's the same value the factory uses to pick the tier / install
// the transport. For voice specifically we also probe
// `LiveVoiceCoachOrchestrator.speak` and confirm the expected error is
// thrown when the Unavailable transport is installed.
//
// To isolate these tests from process-wide state, each test:
//   - installs a relay URL via `VolumeArcSecureStore` so
//     `VolumeArcAIConfiguration.relayConfiguration` returns non-nil
//     (otherwise the factory collapses to the local heuristic chain
//     and the relay-transport installation branch is unreachable)
//   - uses a fresh `PremiumGateTelemetry` per test (one-shot dedupe
//     is scoped to the instance, so tests can't bleed into each other)
//   - constructs the factory from `@MainActor` to match the
//     production call site in `VolumeArcApp.init`
@MainActor
final class VolumeArcPremiumGatingTests: XCTestCase {

    // MARK: - Setup / teardown

    private static let relayURLString = "https://relay.volumearc.app/"
    private static let relaySecretsKey = "ai.relay.baseURL"
    private var previousRelayValue: String?

    override func setUp() async throws {
        try await super.setUp()
        let store = VolumeArcSecureStore()
        previousRelayValue = try? store.load(Self.relaySecretsKey)
        try store.save(Self.relayURLString, for: Self.relaySecretsKey)
    }

    override func tearDown() async throws {
        // Restore the previous relay URL if one existed. We don't attempt
        // to delete when `previousRelayValue == nil` because
        // `VolumeArcSecureStore` exposes no `delete` API — every test in
        // this suite overwrites the key in `setUp` anyway, so a stray
        // URL cannot bleed across test cases in this class.
        if let previousRelayValue {
            let store = VolumeArcSecureStore()
            try? store.save(previousRelayValue, for: Self.relaySecretsKey)
        }
        previousRelayValue = nil
        try await super.tearDown()
    }

    // MARK: - Coach tier gating

    func testCoachProviderUsesProTierWhenPremium() throws {
        let telemetry = CapturingTelemetrySink()
        let premiumGate = PremiumGateTelemetry(telemetry: telemetry)
        let subscriptionStore = MockSubscriptionStore(isPremium: true)

        _ = VolumeArcAIRuntimeFactory.makeCoachProvider(
            flagGate: nil,
            subscriptionStore: subscriptionStore,
            premiumGate: premiumGate
        )

        let events = telemetry.events(category: "premium.entitlement.gated")
            .filter { $0.name == "coach_tier" }
        XCTAssertEqual(events.count, 1, "coach_tier gate should emit exactly once")
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.severity, .info)
        XCTAssertEqual(event.metadata["premium"], "true",
            "Premium users must take the pro-tier branch")
    }

    func testCoachProviderUsesFlashLiteWhenFree() throws {
        let telemetry = CapturingTelemetrySink()
        let premiumGate = PremiumGateTelemetry(telemetry: telemetry)
        let subscriptionStore = MockSubscriptionStore(isPremium: false)

        _ = VolumeArcAIRuntimeFactory.makeCoachProvider(
            flagGate: nil,
            subscriptionStore: subscriptionStore,
            premiumGate: premiumGate
        )

        let events = telemetry.events(category: "premium.entitlement.gated")
            .filter { $0.name == "coach_tier" }
        XCTAssertEqual(events.count, 1, "coach_tier gate should emit exactly once")
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.severity, .info)
        XCTAssertEqual(event.metadata["premium"], "false",
            "Free users must fall back to flash-lite")
    }

    func testCoachProviderUsesFlashLiteWhenSubscriptionStoreNil() throws {
        // Legacy call sites (pre-VOL-91 tests) pass `nil` for the store.
        // The factory must default to free tier without crashing.
        let telemetry = CapturingTelemetrySink()
        let premiumGate = PremiumGateTelemetry(telemetry: telemetry)

        _ = VolumeArcAIRuntimeFactory.makeCoachProvider(
            flagGate: nil,
            subscriptionStore: nil,
            premiumGate: premiumGate
        )

        let events = telemetry.events(category: "premium.entitlement.gated")
            .filter { $0.name == "coach_tier" }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.metadata["premium"], "false",
            "Nil subscription store must be treated as free, not premium")
    }

    // MARK: - Voice coach gating

    func testVoiceCoachUnavailableWhenNotPremium() async throws {
        let telemetry = CapturingTelemetrySink()
        let flags = AlwaysEnabledFlagProvider()
        let flagGate = FlagGateTelemetry(flags: flags, telemetry: telemetry)
        let premiumGate = PremiumGateTelemetry(telemetry: telemetry)
        let subscriptionStore = MockSubscriptionStore(isPremium: false)

        let coach = VolumeArcAIRuntimeFactory.makeVoiceCoach(
            flagGate: flagGate,
            subscriptionStore: subscriptionStore,
            premiumGate: premiumGate
        )

        // Speak must throw because the factory installed
        // UnavailableVoiceTransport (free user → no live voice).
        do {
            _ = try await coach.speak(prompt: "Hi", context: "")
            XCTFail("Free users must not reach the relay voice transport")
        } catch let error as AIRuntimeIntegrationError {
            guard case .relayUnavailable = error else {
                XCTFail("Expected relayUnavailable, got \(error)")
                return
            }
        }

        // Gate telemetry confirms the factory recorded the free-tier decision.
        let liveVoice = telemetry.events(category: "premium.entitlement.gated")
            .filter { $0.name == "live_voice" }
        XCTAssertEqual(liveVoice.count, 1)
        XCTAssertEqual(liveVoice.first?.metadata["premium"], "false")
    }

    func testVoiceCoachInstalledWhenPremiumAndFlagOn() async throws {
        let telemetry = CapturingTelemetrySink()
        let flags = AlwaysEnabledFlagProvider()
        let flagGate = FlagGateTelemetry(flags: flags, telemetry: telemetry)
        let premiumGate = PremiumGateTelemetry(telemetry: telemetry)
        let subscriptionStore = MockSubscriptionStore(isPremium: true)

        _ = VolumeArcAIRuntimeFactory.makeVoiceCoach(
            flagGate: flagGate,
            subscriptionStore: subscriptionStore,
            premiumGate: premiumGate
        )

        // Voice gate emission + flag gate emission both confirm the
        // factory reached the "install relay transport" branch. Actually
        // dispatching `speak` would exercise the network, which is out
        // of scope for a unit test — the telemetry contract is the
        // observable signal of the decision.
        let liveVoice = telemetry.events(category: "premium.entitlement.gated")
            .filter { $0.name == "live_voice" }
        XCTAssertEqual(liveVoice.count, 1)
        XCTAssertEqual(liveVoice.first?.metadata["premium"], "true",
            "Premium + voice flag on must record premium=true")

        let voiceFlag = telemetry.events(category: "feature.flag.applied")
            .filter { $0.name == FeatureFlag.voiceCoaching.rawValue }
        XCTAssertEqual(voiceFlag.count, 1)
        XCTAssertEqual(voiceFlag.first?.metadata["enabled"], "true",
            "voiceCoaching flag gate must record enabled=true")
    }

    func testVoiceCoachUnavailableWhenPremiumButFlagOff() async throws {
        let telemetry = CapturingTelemetrySink()
        let flags = StubFeatureFlagProvider(defaults: [.voiceCoaching: false])
        let flagGate = FlagGateTelemetry(flags: flags, telemetry: telemetry)
        let premiumGate = PremiumGateTelemetry(telemetry: telemetry)
        let subscriptionStore = MockSubscriptionStore(isPremium: true)

        let coach = VolumeArcAIRuntimeFactory.makeVoiceCoach(
            flagGate: flagGate,
            subscriptionStore: subscriptionStore,
            premiumGate: premiumGate
        )

        // Flag is off even though the user is premium — transport
        // stays on the Unavailable stub and every call throws.
        do {
            _ = try await coach.speak(prompt: "Hi", context: "")
            XCTFail("Flag off must gate even premium users")
        } catch let error as AIRuntimeIntegrationError {
            guard case .relayUnavailable = error else {
                XCTFail("Expected relayUnavailable, got \(error)")
                return
            }
        }

        // Gates record premium=true / voice_coaching=false — the flag
        // was the load-bearing signal, not the entitlement.
        let liveVoice = telemetry.events(category: "premium.entitlement.gated")
            .filter { $0.name == "live_voice" }
        XCTAssertEqual(liveVoice.first?.metadata["premium"], "true")

        let voiceFlag = telemetry.events(category: "feature.flag.applied")
            .filter { $0.name == FeatureFlag.voiceCoaching.rawValue }
        XCTAssertEqual(voiceFlag.first?.metadata["enabled"], "false")
    }

    // MARK: - One-shot telemetry contract

    func testCoachTierTelemetryFiresOncePerLaunch() {
        let telemetry = CapturingTelemetrySink()
        let premiumGate = PremiumGateTelemetry(telemetry: telemetry)
        let subscriptionStore = MockSubscriptionStore(isPremium: true)

        // Simulate the launch sequence from `VolumeArcApp.init` — the
        // app constructs the coach provider and then the voice coach,
        // both threaded through the same `premiumGate`. The internal
        // voice → coach re-entry must NOT re-emit the coach_tier event.
        _ = VolumeArcAIRuntimeFactory.makeCoachProvider(
            flagGate: nil,
            subscriptionStore: subscriptionStore,
            premiumGate: premiumGate
        )
        _ = VolumeArcAIRuntimeFactory.makeVoiceCoach(
            flagGate: nil,
            subscriptionStore: subscriptionStore,
            premiumGate: premiumGate
        )
        // A third call to makeCoachProvider (e.g., a secondary surface
        // that rebuilds the coach) also must not re-emit.
        _ = VolumeArcAIRuntimeFactory.makeCoachProvider(
            flagGate: nil,
            subscriptionStore: subscriptionStore,
            premiumGate: premiumGate
        )

        let coachTierEvents = telemetry.events(category: "premium.entitlement.gated")
            .filter { $0.name == "coach_tier" }
        XCTAssertEqual(coachTierEvents.count, 1,
            "coach_tier must emit exactly once per launch even across multiple factory invocations")

        let liveVoiceEvents = telemetry.events(category: "premium.entitlement.gated")
            .filter { $0.name == "live_voice" }
        XCTAssertEqual(liveVoiceEvents.count, 1,
            "live_voice must emit exactly once per launch")
    }

    func testPremiumGateResetForTestingAllowsRepeatEmission() {
        let telemetry = CapturingTelemetrySink()
        let premiumGate = PremiumGateTelemetry(telemetry: telemetry)

        premiumGate.recordIfFirst("coach_tier", isPremium: true)
        premiumGate.recordIfFirst("coach_tier", isPremium: true)
        XCTAssertEqual(telemetry.events.count, 1, "Second invocation must be deduped")

        premiumGate.resetForTesting()
        premiumGate.recordIfFirst("coach_tier", isPremium: false)
        XCTAssertEqual(telemetry.events.count, 2, "Reset must allow a fresh emission")
    }
}

// MARK: - Test doubles

/// Minimal in-memory premium-entitlement provider that lets tests
/// supply either state without pulling in StoreKit.
@MainActor
private final class MockSubscriptionStore: PremiumEntitlementProviding {
    var isPremium: Bool

    init(isPremium: Bool) {
        self.isPremium = isPremium
    }
}

/// Flag provider that returns `true` for every flag — the voice gating
/// tests want the `.voiceCoaching` flag on so the premium gate becomes
/// the load-bearing signal.
private final class AlwaysEnabledFlagProvider: FeatureFlagProvider, @unchecked Sendable {
    func isEnabled(_ flag: FeatureFlag) -> Bool { true }
    func setOverride(_ flag: FeatureFlag, enabled: Bool) {}
    func clearOverride(_ flag: FeatureFlag) {}
    func clearAllOverrides() {}
}

/// Flag provider with configurable per-flag state. Mirrors the pattern
/// `FeatureFlagProviderTests` uses so tests that need to flip a single
/// flag without touching UserDefaults share the same contract.
private final class StubFeatureFlagProvider: FeatureFlagProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [FeatureFlag: Bool]

    init(defaults: [FeatureFlag: Bool] = [:]) {
        var merged: [FeatureFlag: Bool] = [:]
        for flag in FeatureFlag.allCases {
            merged[flag] = defaults[flag] ?? true
        }
        self.values = merged
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return values[flag] ?? true
    }

    func setOverride(_ flag: FeatureFlag, enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        values[flag] = enabled
    }

    func clearOverride(_ flag: FeatureFlag) {
        lock.lock()
        defer { lock.unlock() }
        values[flag] = nil
    }

    func clearAllOverrides() {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
    }
}
