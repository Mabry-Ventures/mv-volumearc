import XCTest
@testable import VolumeArcCore

/// VOL-149: pins the contract that `InMemoryTelemetrySink` only posts
/// `.volumeArcTelemetryDidRecord` when explicitly opted in via
/// `postsNotificationOnRecord`. The deterministic-mode factory enables
/// the flag; production-mode sinks must not (avoids spamming
/// NotificationCenter and the overlay observer on every event).
final class InMemoryTelemetrySinkNotificationTests: XCTestCase {
    func testDoesNotPostWhenFlagIsFalse() {
        let sink = InMemoryTelemetrySink(postsNotificationOnRecord: false)

        let expectation = expectation(
            forNotification: .volumeArcTelemetryDidRecord,
            object: nil
        )
        expectation.isInverted = true

        sink.record(
            TelemetryEvent(
                category: "diagnostic",
                name: "noisy_event",
                severity: .info,
                message: "Should not notify"
            )
        )

        wait(for: [expectation], timeout: 0.5)
    }

    func testPostsWhenFlagIsTrue() {
        let sink = InMemoryTelemetrySink(postsNotificationOnRecord: true)

        let expectation = expectation(
            forNotification: .volumeArcTelemetryDidRecord,
            object: nil
        )

        sink.record(
            TelemetryEvent(
                category: "diagnostic",
                name: "noisy_event",
                severity: .info,
                message: "Should notify"
            )
        )

        wait(for: [expectation], timeout: 1.0)
    }

    func testNotificationCarriesTheRecordedEvent() {
        let sink = InMemoryTelemetrySink(postsNotificationOnRecord: true)

        let expectation = expectation(
            forNotification: .volumeArcTelemetryDidRecord,
            object: nil
        ) { notification in
            // Pins the userInfo schema the probe + matcher depend on.
            // A regression here breaks every XCUITest journey that uses
            // the assertion helper, so the assertion is strict.
            guard
                let event = notification.userInfo?[TelemetryNotificationKey.event] as? TelemetryEvent
            else {
                return false
            }
            return event.category == "diagnostic"
                && event.name == "noisy_event"
                && event.severity == .info
        }

        sink.record(
            TelemetryEvent(
                category: "diagnostic",
                name: "noisy_event",
                severity: .info,
                message: "Pinned schema test"
            )
        )

        wait(for: [expectation], timeout: 1.0)
    }

    func testCurrentEventsAccessorStillWorksWithNotifications() {
        // Recording with notification posting enabled must still
        // populate `currentEvents` — the notification is a side
        // channel, not a replacement for the in-memory buffer.
        let sink = InMemoryTelemetrySink(postsNotificationOnRecord: true)
        sink.record(TelemetryEvent(category: "a", name: "b", severity: .info, message: "m"))
        sink.record(TelemetryEvent(category: "c", name: "d", severity: .warning, message: "m"))

        let snapshot = sink.currentEvents
        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot[0].category, "a")
        XCTAssertEqual(snapshot[1].name, "d")
    }
}
