// VOL-255: active `MXMetricManagerSubscriber` that routes Apple's
// MetricKit payloads into the VolumeArc telemetry fanout.
//
// The Sentry SDK already opts in to its own MetricKit forwarding
// via `enableMetricKit = true` (see VolumeArcSentryConfiguration), but
// that path is opaque — payloads land in Sentry's UI but never reach
// `UserDefaultsTelemetrySink`, `OSLogTelemetrySink`, or the in-app
// diagnostics overlay. This subscriber gives us a second copy on the
// VolumeArc-internal side so:
//
//   * Battery / thermal / hang reports can be correlated with feature
//     events in the same telemetry stream.
//   * The `os_log` mirror (`OSLogTelemetrySink`) makes payloads visible
//     in Console.app for offline debug sessions.
//   * Test surfaces (the `VolumeArcTelemetryDebugProbe` + journey
//     XCUITests) can observe metric events alongside the rest of the
//     telemetry stream.
//
// The subscriber is platform-gated on `canImport(MetricKit)` (iOS 13+,
// macOS 12+). The watch app has no MetricKit access today; a separate
// watchOS subscriber lands in a follow-on ticket once Apple's
// watchOS-side MetricKit story is broader than `MXAppLaunchDiagnostic`.

#if canImport(MetricKit)
import Foundation
import MetricKit
import VolumeArcCore

/// Tiny abstraction over `MXMetricManager` so the subscriber can be
/// unit-tested without a live MetricKit context. The shared real
/// implementation forwards directly to `MXMetricManager.shared`.
public protocol VolumeArcMetricManaging: AnyObject, Sendable {
    func add(_ subscriber: MXMetricManagerSubscriber)
    func remove(_ subscriber: MXMetricManagerSubscriber)
}

public final class SystemMetricManager: VolumeArcMetricManaging, @unchecked Sendable {
    public init() {}

    public func add(_ subscriber: MXMetricManagerSubscriber) {
        MXMetricManager.shared.add(subscriber)
    }

    public func remove(_ subscriber: MXMetricManagerSubscriber) {
        MXMetricManager.shared.remove(subscriber)
    }
}

/// VOL-255. Routes MetricKit metric payloads (CPU, GPU, animation,
/// scroll hitches, app launch, app responsiveness, hang count, disk I/O,
/// memory) and diagnostic payloads (crashes, hangs, disk-writes, app
/// launches, CPU exceptions) into the VolumeArc telemetry sink.
///
/// Two ingestion surfaces from MetricKit's protocol:
///
///   * `didReceive metricPayloads:`: daily metric rollups Apple sends
///     once per 24h on charge / idle. Includes p95 / p50 / cdf
///     histograms. We record one telemetry event per non-empty payload
///     dimension so downstream consumers can group by category.
///
///   * `didReceive diagnosticPayloads:`: per-incident diagnostic
///     records (a crash, a hang). Recorded at `.error` severity so
///     they pop in `UserDefaultsTelemetrySink`'s persistent log and
///     reach Sentry through the existing fanout.
///
/// Past payloads (`didReceive metricPayloads:` fires on first
/// subscription with any previously-stored payloads) are recorded once
/// at startup; new ones land as Apple posts them.
///
/// Not `@MainActor`-isolated: MetricKit's protocol contract dispatches
/// callbacks from an arbitrary background thread, and the
/// `TelemetrySink` protocol is already `Sendable` so it's safe to
/// `record(_:)` from any actor. Avoiding the MainActor hop also keeps
/// the diagnostic-payload path off the main thread on app launch,
/// when MetricKit delivers any backlogged crash/hang reports.
public final class VolumeArcMetricKitSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let telemetrySink: any TelemetrySink
    private let metricManager: any VolumeArcMetricManaging

    public init(
        telemetrySink: any TelemetrySink,
        metricManager: any VolumeArcMetricManaging = SystemMetricManager()
    ) {
        self.telemetrySink = telemetrySink
        self.metricManager = metricManager
        super.init()
    }

    /// Wire the subscriber into MetricKit's shared manager. Call once at
    /// app launch after the telemetry sink is constructed. Idempotent —
    /// calling twice is harmless because `MXMetricManager.add(_:)` only
    /// holds a strong reference for the lifetime of the subscriber object.
    public func register() {
        metricManager.add(self)
    }

    /// For symmetry / tests. Production never unregisters (the
    /// subscriber's lifetime matches the app process).
    public func unregister() {
        metricManager.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber

    /// VOL-255: surface every payload as a single
    /// `metrickit.metric_payload.received` event, with the payload's
    /// begin/end timestamps + a synopsis of which dimensions Apple
    /// included. Recording the full per-metric distribution would be
    /// more useful but also wastes telemetry bytes on histograms most
    /// consumers won't query; the synopsis is enough to spot "battery
    /// payload arrived and we should pull it up in Sentry's UI."
    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let snapshot = Self.snapshot(for: payload)
            telemetrySink.record(TelemetryEvent(
                category: "metrickit",
                name: "metric_payload.received",
                severity: .info,
                message: "MetricKit metric payload covering \(snapshot.coveredDimensions.count) dimension(s)",
                metadata: snapshot.metadata
            ))
        }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let snapshot = Self.snapshot(for: payload)
            telemetrySink.record(TelemetryEvent(
                category: "metrickit",
                name: "diagnostic_payload.received",
                severity: .error,
                message: "MetricKit diagnostic payload (\(snapshot.diagnosticKinds.joined(separator: ", ")))",
                metadata: snapshot.metadata
            ))
        }
    }

    // MARK: - Snapshot helpers (pure, unit-testable)

    /// Per-payload synopsis pulled out as a pure function so the
    /// metadata mapping is testable without instantiating
    /// `MXMetricPayload` (which has no public initializer).
    struct PayloadSnapshot: Sendable {
        let coveredDimensions: [String]
        let metadata: [String: String]
    }

    struct DiagnosticSnapshot: Sendable {
        let diagnosticKinds: [String]
        let metadata: [String: String]
    }

    static func snapshot(for payload: MXMetricPayload) -> PayloadSnapshot {
        var dims: [String] = []
        if payload.cpuMetrics != nil { dims.append("cpu") }
        if payload.gpuMetrics != nil { dims.append("gpu") }
        if payload.cellularConditionMetrics != nil { dims.append("cellular") }
        if payload.applicationTimeMetrics != nil { dims.append("application_time") }
        if payload.locationActivityMetrics != nil { dims.append("location") }
        if payload.networkTransferMetrics != nil { dims.append("network") }
        if payload.applicationLaunchMetrics != nil { dims.append("launch") }
        if payload.applicationResponsivenessMetrics != nil { dims.append("responsiveness") }
        if payload.diskIOMetrics != nil { dims.append("disk_io") }
        if payload.memoryMetrics != nil { dims.append("memory") }
        if payload.displayMetrics != nil { dims.append("display") }
        if payload.animationMetrics != nil { dims.append("animation") }
        if payload.applicationExitMetrics != nil { dims.append("application_exit") }
        if payload.signpostMetrics != nil { dims.append("signpost") }

        let metadata: [String: String] = [
            "begin": ISO8601DateFormatter().string(from: payload.timeStampBegin),
            "end": ISO8601DateFormatter().string(from: payload.timeStampEnd),
            "dimensions": dims.joined(separator: ","),
            "dimensionCount": String(dims.count)
        ]
        return PayloadSnapshot(coveredDimensions: dims, metadata: metadata)
    }

    static func snapshot(for payload: MXDiagnosticPayload) -> DiagnosticSnapshot {
        var kinds: [String] = []
        if let crashes = payload.crashDiagnostics, crashes.isEmpty == false { kinds.append("crash:\(crashes.count)") }
        if let hangs = payload.hangDiagnostics, hangs.isEmpty == false { kinds.append("hang:\(hangs.count)") }
        if let cpu = payload.cpuExceptionDiagnostics, cpu.isEmpty == false { kinds.append("cpu_exception:\(cpu.count)") }
        if let disk = payload.diskWriteExceptionDiagnostics, disk.isEmpty == false { kinds.append("disk_write_exception:\(disk.count)") }
        if let launch = payload.appLaunchDiagnostics, launch.isEmpty == false { kinds.append("app_launch:\(launch.count)") }

        let metadata: [String: String] = [
            "begin": ISO8601DateFormatter().string(from: payload.timeStampBegin),
            "end": ISO8601DateFormatter().string(from: payload.timeStampEnd),
            "kinds": kinds.joined(separator: ","),
            "kindCount": String(kinds.count)
        ]
        return DiagnosticSnapshot(diagnosticKinds: kinds, metadata: metadata)
    }
}
#endif
