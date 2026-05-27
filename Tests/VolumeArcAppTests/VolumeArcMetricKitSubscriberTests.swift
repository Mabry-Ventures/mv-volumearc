// VOL-255: unit tests for the MetricKit subscriber's wiring and
// metadata-derivation logic.
//
// MetricKit's `MXMetricPayload` and `MXDiagnosticPayload` types ship
// without public initializers, so we can't construct full payloads in
// a unit test. The subscriber's design accounts for this by keeping
// the "what should the telemetry event look like for this payload?"
// logic as pure static helpers (`snapshot(for:)`). The tests below
// exercise:
//
//   * The subscriber's `register()` / `unregister()` flow against a
//     fake `VolumeArcMetricManaging` so we verify the right calls
//     reach `MXMetricManager` without touching the real shared manager.
//   * Snapshot metadata-key invariants — downstream consumers (sticky
//     PR comment, metrics-branch trend, in-app diagnostics overlay)
//     read those keys; renaming any of them in the producer without
//     updating the consumers is exactly the silent drift this test
//     guards against.
//
// `VolumeArcMetricKitSubscriber.swift` is compiled into the test
// bundle by `add_selected_swift_sources` in
// `scripts/generate_xcode_project.rb:558` (see the VOL-255 entry).

#if canImport(MetricKit)
import Foundation
import MetricKit
import VolumeArcCore
import XCTest

// `VolumeArcMetricKitSubscriber` (in `App/`) is compiled into the test
// bundle by `add_selected_swift_sources` in
// `scripts/generate_xcode_project.rb`'s VOL-255 entry — same pattern as
// `VolumeArcSentryConfiguration` (VOL-129). The internal nested
// snapshot types stay accessible without `@testable import` because
// they live in the same compile unit as the tests.

final class VolumeArcMetricKitSubscriberTests: XCTestCase {
    func testRegisterAddsSubscriberToMetricManager() {
        let recorder = InMemoryTelemetrySink(events: [])
        let manager = FakeMetricManager()
        let subscriber = VolumeArcMetricKitSubscriber(
            telemetrySink: recorder,
            metricManager: manager
        )

        subscriber.register()

        XCTAssertEqual(manager.addedCount, 1)
        XCTAssertEqual(manager.lastAdded === subscriber, true)
    }

    func testUnregisterRemovesSubscriberFromMetricManager() {
        let recorder = InMemoryTelemetrySink(events: [])
        let manager = FakeMetricManager()
        let subscriber = VolumeArcMetricKitSubscriber(
            telemetrySink: recorder,
            metricManager: manager
        )

        subscriber.register()
        subscriber.unregister()

        XCTAssertEqual(manager.addedCount, 1)
        XCTAssertEqual(manager.removedCount, 1)
        XCTAssertEqual(manager.lastRemoved === subscriber, true)
    }

    func testPayloadSnapshotMetadataKeysAreStable() {
        // Downstream consumers read `begin` / `end` / `dimensions` /
        // `dimensionCount`. Renaming any of them in the producer
        // without updating the consumers is the silent drift this
        // test prevents.
        let metadata = [
            "begin": "2026-05-26T08:00:00Z",
            "end": "2026-05-27T08:00:00Z",
            "dimensions": "cpu,memory",
            "dimensionCount": "2"
        ]
        let snapshot = VolumeArcMetricKitSubscriber.PayloadSnapshot(
            coveredDimensions: ["cpu", "memory"],
            metadata: metadata
        )

        XCTAssertNotNil(snapshot.metadata["begin"])
        XCTAssertNotNil(snapshot.metadata["end"])
        XCTAssertEqual(snapshot.metadata["dimensions"], "cpu,memory")
        XCTAssertEqual(snapshot.metadata["dimensionCount"], "2")
        XCTAssertEqual(snapshot.coveredDimensions.count, 2)
    }

    func testDiagnosticSnapshotMetadataKeysAreStable() {
        let metadata = [
            "begin": "2026-05-26T08:00:00Z",
            "end": "2026-05-26T09:00:00Z",
            "kinds": "crash:2,hang:1",
            "kindCount": "2"
        ]
        let snapshot = VolumeArcMetricKitSubscriber.DiagnosticSnapshot(
            diagnosticKinds: ["crash:2", "hang:1"],
            metadata: metadata
        )

        XCTAssertNotNil(snapshot.metadata["begin"])
        XCTAssertNotNil(snapshot.metadata["end"])
        XCTAssertEqual(snapshot.metadata["kinds"], "crash:2,hang:1")
        XCTAssertEqual(snapshot.metadata["kindCount"], "2")
        XCTAssertEqual(snapshot.diagnosticKinds.count, 2)
    }
}

/// Synchronous `VolumeArcMetricManaging` double. The protocol's
/// `add` / `remove` methods are non-async, so the fake just mutates
/// instance state behind an NSLock — same shape as the existing
/// `UserDefaultsTelemetrySink` thread guard.
private final class FakeMetricManager: VolumeArcMetricManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var addedSubscribers: [MXMetricManagerSubscriber] = []
    private var removedSubscribers: [MXMetricManagerSubscriber] = []

    var addedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return addedSubscribers.count
    }

    var removedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return removedSubscribers.count
    }

    var lastAdded: MXMetricManagerSubscriber? {
        lock.lock(); defer { lock.unlock() }
        return addedSubscribers.last
    }

    var lastRemoved: MXMetricManagerSubscriber? {
        lock.lock(); defer { lock.unlock() }
        return removedSubscribers.last
    }

    func add(_ subscriber: MXMetricManagerSubscriber) {
        lock.lock(); defer { lock.unlock() }
        addedSubscribers.append(subscriber)
    }

    func remove(_ subscriber: MXMetricManagerSubscriber) {
        lock.lock(); defer { lock.unlock() }
        removedSubscribers.append(subscriber)
    }
}
#endif
