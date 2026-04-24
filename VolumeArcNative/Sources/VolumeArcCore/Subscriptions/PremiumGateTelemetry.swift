import Foundation

// VOL-91: one-shot premium-entitlement gate telemetry. Mirrors the
// `FlagGateTelemetry` contract from VOL-61 — the runtime factory checks
// a premium entitlement once per feature per launch and emits a single
// `.info` event describing which tier/transport was installed so
// dashboards can observe the entitlement distribution without seeing
// an event on every relay call.
//
// Contract:
// - category: `premium.entitlement.gated`
// - name: the identifier passed by the factory (`coach_tier` | `live_voice`)
// - severity: `.info`
// - metadata: `{"premium": "true" | "false"}`
//
// Dedupe is keyed on the feature name string rather than an enum so new
// gated features can be added by the factory without churning this type.
// Thread safety via `NSLock` shielded `Set<String>`, matching
// `FlagGateTelemetry`'s pattern so the guarantee survives callers that
// may invoke `recordIfFirst(...)` from arbitrary isolation contexts.
public final class PremiumGateTelemetry: @unchecked Sendable {
    private let telemetry: (any TelemetrySink)?
    private let lock = NSLock()
    private var recorded: Set<String> = []

    public init(telemetry: (any TelemetrySink)? = nil) {
        self.telemetry = telemetry
    }

    /// Record the premium gate for `feature` exactly once per launch.
    ///
    /// - Parameters:
    ///   - feature: stable identifier for the gated feature (e.g.
    ///     `coach_tier`, `live_voice`). Becomes the `name` of the
    ///     emitted telemetry event.
    ///   - isPremium: the resolved entitlement state the factory acted
    ///     on. Stored verbatim in the event's `premium` metadata so
    ///     dashboards can split by tier without re-querying.
    public func recordIfFirst(_ feature: String, isPremium: Bool) {
        let shouldEmit: Bool = {
            lock.lock()
            defer { lock.unlock() }
            return recorded.insert(feature).inserted
        }()
        guard shouldEmit else { return }

        telemetry?.record(TelemetryEvent(
            category: "premium.entitlement.gated",
            name: feature,
            severity: .info,
            message: "Premium gate \(feature) resolved to isPremium=\(isPremium) at first invocation.",
            metadata: [
                "premium": isPremium ? "true" : "false",
            ]
        ))
    }

    /// Reset the recorded set. Primarily useful for tests that want to
    /// verify the first-call emission twice in the same process.
    public func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        recorded.removeAll()
    }
}
