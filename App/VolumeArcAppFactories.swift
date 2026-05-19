import SwiftUI
#if canImport(SwiftData)
import SwiftData
#endif
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(Network)
import Network
#endif
import VolumeArcCore
import VolumeArcUI

// VOL-113: factories that VolumeArcApp.init() calls during launch live
// here in an extension so the @main shell stays under the SwiftLint
// file_length warning. Pre-split these were `private static` on the
// struct; moving to a separate file required relaxing visibility to
// `internal` (the default) so they cross the file boundary. They're
// still on the same module-private struct, so no API surface change.
extension VolumeArcApp {
    static func makeHealthStore() -> HealthStore {
        // VOL-168 Phase 1: wrap the real (or unavailable) store with
        // `ChaosHealthStore` when a matching `-CHAOS_HEALTH_*` launch
        // argument is set. The accessors on `ChaosController` are
        // hard-coded to `false` in Release builds (`#if DEBUG`
        // gate inside each property), so this branch can never wrap
        // the store in shipping binaries — even if launchArguments
        // somehow contained a `-CHAOS_*` token.
        let underlying: HealthStore = {
            #if canImport(HealthKit)
            return HealthKitRuntimeStore()
            #else
            return UnavailableHealthStore()
            #endif
        }()

        #if DEBUG
        if ChaosController.injectHealthAuthDenied {
            return ChaosHealthStore(
                wrapping: underlying,
                nextFailure: .authorizationDenied
            )
        }
        #endif

        return underlying
    }

    /// VOL-181 Phase 1B: HealthKit-backed recovery reader. Returns
    /// `HealthKitRecoveryReader` on iOS (which uses `HKHealthStore`
    /// to derive HRV trend, sleep debt, and weekly strength load) and
    /// `UnavailableRecoveryReader` everywhere else (macOS previews,
    /// SwiftUI canvas, test hosts). The dashboard's `refresh()` calls
    /// `currentRecovery()` and caches the result for the coach prompt
    /// + Today-tab chip.
    static func makeRecoveryReader(telemetrySink: (any TelemetrySink)? = nil) -> RecoveryReader {
        #if canImport(HealthKit)
        // VOL-203: pass the telemetry sink so the reader emits
        // `healthkit.recovery_query_failed` / `recovery_query_empty` /
        // `recovery_unavailable` / `recovery_partial` events instead of
        // silently swallowing every error. Backward-compatible —
        // existing callers that don't pass the sink keep the
        // no-telemetry shape; the dashboard wires it in `init`.
        return HealthKitRecoveryReader(telemetrySink: telemetrySink)
        #else
        return UnavailableRecoveryReader()
        #endif
    }

    static func makeVoicePermissionStore() -> VoicePermissionStore {
        #if canImport(AVFoundation) && canImport(Speech)
        VolumeArcVoicePermissionStore()
        #else
        UnavailableVoicePermissionStore()
        #endif
    }

    static func makeAccountSessionStore() -> AccountSessionStore {
        UserDefaultsAccountSessionStore()
    }

    #if canImport(Network)
    static let reachabilityMonitor = NetworkReachabilityMonitor()

    static func startNetworkReachabilityMonitor() {
        reachabilityMonitor.start { path in
            // Post a notification so observers can react to connectivity changes.
            NotificationCenter.default.post(
                name: .volumeArcReachabilityChanged,
                object: nil,
                userInfo: ["isReachable": path.status == .satisfied]
            )
        }
    }
    #endif

    static func makeSyncTransport() -> CloudSyncTransport {
        // VOL-55: containerIdentifier is now a compile-time constant, so
        // this always has a valid value. We keep the emptiness check for
        // future flexibility in case the constant ever needs to be read
        // from a different source.
        let containerIdentifier = VolumeArcCloudConfiguration.containerIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard containerIdentifier.isEmpty == false else {
            return UnavailableCloudSyncTransport(
                reason: VolumeArcCloudConfiguration.startupWarning
                    ?? "Cloud sync is unavailable on this build."
            )
        }

        // VOL-59 fixup: `CKContainer(identifier:)` traps the process
        // (SIGTRAP / brk 1) if the caller's effective entitlements don't
        // grant access to the requested container. On simulator Debug
        // builds with `CODE_SIGNING_ALLOWED = NO`, the binary is ad-hoc
        // signed without any entitlements, so the CloudKit attach path
        // crashes the app on launch during `VolumeArcApp.init()`. Gate
        // the transport on the runtime entitlement check so the app
        // degrades to `UnavailableCloudSyncTransport` in unsigned /
        // unentitled builds instead of crashing. This also covers the
        // XCTest-hosted app process where the xctest runner inherits
        // no entitlements.
        guard VolumeArcCloudConfiguration.hasCloudKitEntitlement else {
            return UnavailableCloudSyncTransport(
                reason: "Cloud sync is unavailable because this build does not carry a CloudKit entitlement."
            )
        }

        return CloudKitSyncTransport(
            containerIdentifier: containerIdentifier,
            zoneName: VolumeArcCloudConfiguration.syncZoneName
        )
    }

    #if canImport(SwiftData)
    static func startupSignals(
        persistenceStatus: VolumeArcPersistenceController.BootstrapStatus,
        telemetrySink: TelemetrySink
    ) -> [OperationalSignalSummary] {
        var signals: [OperationalSignalSummary] = []

        if persistenceStatus.isDegraded {
            signals.append(
                OperationalSignalSummary(
                    id: "persistence-bootstrap",
                    title: "Storage",
                    message: persistenceStatus.message,
                    severity: persistenceStatus.severity
                )
            )
        }

        if let relayWarning = VolumeArcAIConfiguration.startupWarning(recordingTo: telemetrySink) {
            signals.append(
                OperationalSignalSummary(
                    id: "ai-relay",
                    title: "AI Relay",
                    message: relayWarning,
                    severity: .warning
                )
            )
        }

        if let cloudWarning = VolumeArcCloudConfiguration.startupWarning {
            signals.append(
                OperationalSignalSummary(
                    id: "cloudkit-config",
                    title: "Cloud Sync",
                    message: cloudWarning,
                    severity: .warning
                )
            )
        }

        #if canImport(Sentry)
        if let sentryWarning = VolumeArcSentryConfiguration.startupWarning {
            signals.append(
                OperationalSignalSummary(
                    id: "sentry-config",
                    title: "Crash Reporting",
                    message: sentryWarning,
                    severity: .warning
                )
            )
        }
        #endif
        return signals
    }
    #else
    static func startupSignals(telemetrySink: TelemetrySink) -> [OperationalSignalSummary] {
        var signals: [OperationalSignalSummary] = []

        if let relayWarning = VolumeArcAIConfiguration.startupWarning(recordingTo: telemetrySink) {
            signals.append(
                OperationalSignalSummary(
                    id: "ai-relay",
                    title: "AI Relay",
                    message: relayWarning,
                    severity: .warning
                )
            )
        }

        if let cloudWarning = VolumeArcCloudConfiguration.startupWarning {
            signals.append(
                OperationalSignalSummary(
                    id: "cloudkit-config",
                    title: "Cloud Sync",
                    message: cloudWarning,
                    severity: .warning
                )
            )
        }

        #if canImport(Sentry)
        if let sentryWarning = VolumeArcSentryConfiguration.startupWarning {
            signals.append(
                OperationalSignalSummary(
                    id: "sentry-config",
                    title: "Crash Reporting",
                    message: sentryWarning,
                    severity: .warning
                )
            )
        }
        #endif
        return signals
    }
    #endif

    static func combinedStartupNotice(from signals: [OperationalSignalSummary]) -> String? {
        guard signals.isEmpty == false else { return nil }
        return signals.map(\.message).joined(separator: " ")
    }

    static func highestSeverity(in signals: [OperationalSignalSummary]) -> TelemetrySeverity? {
        signals
            .map(\.severity)
            .max(by: { severityRank($0) < severityRank($1) })
    }

    static func severityRank(_ severity: TelemetrySeverity) -> Int {
        switch severity {
        case .info:
            return 0
        case .warning:
            return 1
        case .error:
            return 2
        }
    }

    static func syncStateStoreURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return applicationSupport
            .appendingPathComponent("VolumeArc", isDirectory: true)
            .appendingPathComponent("sync-state.json", isDirectory: false)
    }

    static func makeNotificationStore() -> NotificationStore {
        #if canImport(UserNotifications)
        UserNotificationCenterStore()
        #else
        InMemoryNotificationStore()
        #endif
    }

    static func makeTelemetrySink(initialEvents: [TelemetryEvent] = []) -> TelemetrySink {
        if VolumeArcRuntimeFlags.isDeterministicMode {
            // VOL-230 fix: the `VolumeArcTelemetryDebugProbe` listens on
            // `.volumeArcTelemetryDidRecord` notifications to expose
            // events through the `debug.telemetry.events` accessibility
            // overlay XCUITests poll. Without `postsNotificationOnRecord:
            // true`, the sink swallows events for the probe, so journey
            // tests time out waiting for events the production code has
            // already emitted. Discovered after VOL-227 unblocked UI
            // test execution: 8+ journey XCUITests failed with
            // "(<category>/<name>) within Xs; not found in probe
            // buffer" because the sink wasn't posting at all.
            return InMemoryTelemetrySink(
                events: initialEvents,
                postsNotificationOnRecord: true
            )
        }

        let persistent = UserDefaultsTelemetrySink()
        var sinks: [TelemetrySink] = []
        if initialEvents.isEmpty == false {
            sinks.append(InMemoryTelemetrySink(events: initialEvents))
        }
        sinks.append(persistent)
        #if canImport(OSLog)
        sinks.append(OSLogTelemetrySink())
        #endif
        #if canImport(Sentry)
        if VolumeArcSentryConfiguration.isConfigured {
            sinks.append(SentryTelemetrySink())
        }
        #endif
        return sinks.count == 1 ? persistent : FanoutTelemetrySink(sinks: sinks)
    }

    /// VOL-112: post a simulated `WatchPayload` notification on launch if
    /// `-PostFakeWatchPayload <kind>` was passed AND we're in
    /// deterministic mode. Used by `VolumeArcWatchSimulationJourneyTests`
    /// to exercise the dashboard's watch-arrival path without spinning
    /// up a paired watchOS+iOS simulator session.
    ///
    /// The deterministic-mode gate is intentional — even if a production
    /// build accidentally received the launch arg, this helper would
    /// silently no-op rather than fabricate a watch event. Pairs with
    /// the `WatchPayloadKind` enum: `restTimer`, `liveState`,
    /// `startSession`, `endSession`, `coachCue`, `completedWorkout`. An
    /// unrecognized kind is silently ignored (returns without posting)
    /// rather than crashing — the test owns choosing a valid kind.
    static func postSimulatedWatchPayloadIfRequested() {
        guard VolumeArcRuntimeFlags.isDeterministicMode,
              let kindRaw = VolumeArcLaunchArguments.postFakeWatchPayloadKind,
              let kind = WatchPayloadKind(rawValue: kindRaw) else {
            return
        }
        let payload = WatchPayload(
            kind: kind,
            workoutID: "test.simulated.\(UUID().uuidString)",
            body: "Simulated payload from -PostFakeWatchPayload"
        )
        NotificationCenter.default.post(
            name: WatchConnectivityNotifications.payloadDidArrive,
            object: nil,
            userInfo: [WatchConnectivityNotifications.payloadUserInfoKey: payload]
        )
    }
}
