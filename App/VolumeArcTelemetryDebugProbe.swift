// VOL-149: test-only bridge between the deterministic-mode telemetry
// sink and a SwiftUI accessibility overlay. The overlay's label is a
// JSON-encoded snapshot of the most recent telemetry events; XCUITests
// poll it via the `debug.telemetry.events` accessibility identifier to
// assert that specific (category, name) events fired during a user
// journey.
//
// Why an in-app observable instead of cross-process UserDefaults:
//
//   The XCUITest target runs in a separate process from the host app.
//   `UserDefaultsTelemetrySink` persists events to the app's
//   `~/Library/Preferences/com.mabryventures.VolumeArc.plist`; the
//   test runner can't read that file at test time. Routing events
//   through the accessibility tree keeps everything inside the
//   XCUITest contract that already works for `debug.watch.last-payload-kind`
//   (see VOL-112 / VolumeArcWatchSimulationJourneyTests).
//
// Production gate: the probe is only constructed when
// `VolumeArcRuntimeFlags.isDeterministicMode` is true. In release
// builds the constructor still compiles but the observer is never
// installed, so there's zero overhead in shipping binaries.

import Foundation
import VolumeArcCore

@MainActor
final class VolumeArcTelemetryDebugProbe: ObservableObject {
    /// Compact JSON encoding of the most recent N events. Format:
    ///   `[{"c":"workout","n":"started","s":"info","t":"2026-…"}, …]`
    /// Test helpers parse this label and assert on `(c, n)` pairs.
    @Published private(set) var recentEventsJSON: String = "[]"

    /// Number of events retained for the probe. Bounded so the
    /// accessibility-label payload stays small even on long journeys
    /// — XCUITest tree reads are cheap but a multi-KB label string
    /// would still be wasted bandwidth on every poll.
    private let maxEvents: Int

    // Swift 6 strict concurrency: `NSObjectProtocol` is non-Sendable,
    // and `deinit` is implicitly nonisolated — accessing a MainActor-
    // isolated property of a non-Sendable type from deinit is a
    // diagnostic error. `nonisolated(unsafe)` is the right escape
    // hatch: this property is written exactly once (in `init`, on
    // the MainActor) and read exactly once (in `deinit`, after the
    // last reference goes away). No race is possible.
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    private var buffer: [CompactEvent] = []

    init(maxEvents: Int = 50) {
        self.maxEvents = maxEvents

        guard VolumeArcRuntimeFlags.isDeterministicMode else {
            // Production guard: the observer is never installed in
            // release builds, so no listener overhead and the JSON
            // stays the empty placeholder forever.
            return
        }

        // Swift 6 strict concurrency: the closure passed to
        // `addObserver(forName:object:queue:using:)` is `@Sendable`
        // and not MainActor-isolated by type, even though it runs on
        // `.main`. We need an explicit entry into MainActor isolation
        // to call `self.append`.
        //
        // VOL-175: the original implementation bounced through
        // `Task { @MainActor in ... }`. Under simulator load (e.g.,
        // when the test bundle includes the chaos journey class
        // alongside the standard journey suites), that Task hop's
        // scheduling deprioritized the append past the test's 10s
        // poll window, dropping events that fired during the poll.
        // `MainActor.assumeIsolated` runs synchronously on the
        // current thread — and because `queue: .main` above already
        // guarantees we're on the main thread, the assumption is
        // safe. No scheduling hop; the event appends the moment the
        // notification fires.
        observer = NotificationCenter.default.addObserver(
            forName: .volumeArcTelemetryDidRecord,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // The factory sets `postsNotificationOnRecord: true` on
            // the InMemoryTelemetrySink in deterministic mode, and
            // the sink stuffs the `TelemetryEvent` into userInfo
            // under `TelemetryNotificationKey.event`. We re-encode
            // into a compact dict so the accessibility-label payload
            // stays under a few hundred bytes even with the full
            // 50-event buffer.
            guard
                let event = notification.userInfo?[TelemetryNotificationKey.event] as? TelemetryEvent
            else { return }
            MainActor.assumeIsolated {
                self?.append(event)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func append(_ event: TelemetryEvent) {
        buffer.append(
            CompactEvent(
                category: event.category,
                name: event.name,
                severity: event.severity.rawValue
            )
        )
        if buffer.count > maxEvents {
            buffer.removeFirst(buffer.count - maxEvents)
        }
        scheduleFlush()
    }

    /// Coalesce publishes instead of publishing per event. Every label
    /// change mutates the accessibility tree, and an AX mutation forces
    /// XCUITest to restart any in-flight query snapshot — during an
    /// active workout telemetry fires about once a second, which starved
    /// query evaluation on render-heavy surfaces ("Failed to get
    /// matching snapshots: Timed out while evaluating UI query").
    /// Events still reach the label within ~2.5s, far inside
    /// `assertTelemetryFired`'s 10s poll window.
    private var flushScheduled = false

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.flushScheduled = false
                self.rebuildJSON()
            }
        }
    }

    private func rebuildJSON() {
        // ISO8601 strings + the original metadata would make the label
        // payload too noisy; the test helper only needs (category, name)
        // matching plus an optional severity check. Keep the schema
        // minimal so a 50-event buffer fits in well under 4 KB.
        if let data = try? JSONEncoder().encode(buffer),
           let json = String(data: data, encoding: .utf8) {
            recentEventsJSON = json
        }
    }

    /// Compact wire-format for the accessibility-overlay payload.
    /// Swift property names are spelled out so SwiftLint's
    /// `identifier_name` rule is happy; `CodingKeys` rewrites them to
    /// single-letter keys at JSON encode time so the label string
    /// stays under 4 KB for the full 50-event buffer.
    private struct CompactEvent: Encodable {
        let category: String
        let name: String
        let severity: String

        enum CodingKeys: String, CodingKey {
            case category = "c"
            case name = "n"
            case severity = "s"
        }
    }
}
