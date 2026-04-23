import XCTest
import VolumeArcCore

/// Tests for `VolumeArcAIConfiguration.validatedRelayURL(from:telemetrySink:)`.
///
/// These guard the read-time validation that gates the OpenAI relay URL
/// before any request is built. A malformed value flowing through the
/// Info.plist -> Keychain -> runtime pipeline must be rejected here so
/// cloud AI traffic never escapes to an unintended host (and so the
/// `LocalHeuristicAICoachProvider` fallback kicks in cleanly).
final class VolumeArcRelayURLValidationTests: XCTestCase {

    // MARK: - Happy path

    func testValidHttpsAllowlistedHostReturnsURL() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(
            from: "https://relay.volumearc.app/",
            telemetrySink: sink
        )
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host?.lowercased(), "relay.volumearc.app")
        XCTAssertTrue(sink.currentEvents.isEmpty, "Happy path should not record telemetry")
    }

    func testValidSecondAllowlistedHostReturnsURL() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(
            from: "https://relay.mabryventures.com/coach",
            telemetrySink: sink
        )
        XCTAssertNotNil(url)
        XCTAssertTrue(sink.currentEvents.isEmpty)
    }

    func testAllowlistedHostUppercaseMatchesCaseInsensitively() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(
            from: "https://RELAY.VolumeArc.APP/",
            telemetrySink: sink
        )
        XCTAssertNotNil(url, "Host matching must be case-insensitive")
        XCTAssertTrue(sink.currentEvents.isEmpty)
    }

    // MARK: - Scheme rejection

    func testHttpSchemeReturnsNil() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(
            from: "http://relay.volumearc.app/",
            telemetrySink: sink
        )
        XCTAssertNil(url)
        assertRejection(sink, rule: "non-https-scheme")
    }

    func testMissingSchemeReturnsNil() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(
            from: "relay.volumearc.app",
            telemetrySink: sink
        )
        XCTAssertNil(url)
        // A schemeless host parses as a URLComponents with no scheme AND
        // no host (the whole thing becomes a path), so either the
        // non-https-scheme or missing-host rule can catch it. Both are
        // acceptable — the contract is "returns nil with a recorded
        // .error event".
        XCTAssertFalse(sink.currentEvents.isEmpty)
        XCTAssertEqual(sink.currentEvents.last?.severity, .error)
    }

    func testJavascriptSchemeReturnsNil() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(
            from: "javascript:alert(1)",
            telemetrySink: sink
        )
        XCTAssertNil(url)
        XCTAssertFalse(sink.currentEvents.isEmpty)
    }

    // MARK: - Whitespace contamination

    func testLeadingWhitespaceReturnsNil() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(
            from: "  https://relay.volumearc.app/",
            telemetrySink: sink
        )
        XCTAssertNil(url)
        assertRejection(sink, rule: "whitespace")
    }

    func testTrailingWhitespaceReturnsNil() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(
            from: "https://relay.volumearc.app/\n",
            telemetrySink: sink
        )
        XCTAssertNil(url)
        assertRejection(sink, rule: "whitespace")
    }

    // MARK: - Host allowlist

    func testNonAllowlistedHostReturnsNil() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(
            from: "https://evil.com/",
            telemetrySink: sink
        )
        XCTAssertNil(url)
        assertRejection(sink, rule: "host-not-allowlisted")
    }

    func testSimilarLookingHostIsRejected() {
        // A near-miss — this is the kind of typo that would silently
        // route traffic to an attacker without the allowlist.
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(
            from: "https://relay.volumearc.app.evil.com/",
            telemetrySink: sink
        )
        XCTAssertNil(url)
        assertRejection(sink, rule: "host-not-allowlisted")
    }

    // MARK: - Empty / nil

    func testEmptyStringReturnsNil() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(from: "", telemetrySink: sink)
        XCTAssertNil(url)
        assertRejection(sink, rule: "empty")
    }

    func testWhitespaceOnlyReturnsNil() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(from: "   ", telemetrySink: sink)
        XCTAssertNil(url)
        // Whitespace-only collapses to empty after trimming.
        assertRejection(sink, rule: "empty")
    }

    func testNilReturnsNil() {
        let sink = InMemoryTelemetrySink()
        let url = VolumeArcAIConfiguration.validatedRelayURL(from: nil, telemetrySink: sink)
        XCTAssertNil(url)
        assertRejection(sink, rule: "missing")
    }

    // MARK: - Telemetry payload hygiene

    func testTelemetryDoesNotContainURLValue() {
        // Critical safety property: we must never echo the raw URL
        // value back into telemetry, because a misconfigured pipeline
        // could stuff a credential into it.
        let sensitiveValue = "https://evil.com/?token=supersecret123"
        let sink = InMemoryTelemetrySink()
        _ = VolumeArcAIConfiguration.validatedRelayURL(
            from: sensitiveValue,
            telemetrySink: sink
        )

        XCTAssertFalse(sink.currentEvents.isEmpty)
        for event in sink.currentEvents {
            XCTAssertFalse(event.message.contains("supersecret123"),
                           "Telemetry message must not echo the URL value")
            XCTAssertFalse(event.message.contains("evil.com"),
                           "Telemetry message must not echo the URL host")
            for (_, value) in event.metadata {
                XCTAssertFalse(value.contains("supersecret123"),
                               "Telemetry metadata must not echo the URL value")
                XCTAssertFalse(value.contains("evil.com"),
                               "Telemetry metadata must not echo the URL host")
            }
        }
    }

    func testTelemetryEmittedAtErrorSeverity() {
        let sink = InMemoryTelemetrySink()
        _ = VolumeArcAIConfiguration.validatedRelayURL(
            from: "http://relay.volumearc.app/",
            telemetrySink: sink
        )
        XCTAssertEqual(sink.currentEvents.last?.severity, .error)
        XCTAssertEqual(sink.currentEvents.last?.category,
                       VolumeArcAIConfiguration.telemetryCategory)
    }

    func testNoTelemetrySinkDoesNotCrash() {
        // The read-time getter intentionally passes no sink so the
        // .error doesn't fire on every AI request. Confirm that path
        // is safe.
        let url = VolumeArcAIConfiguration.validatedRelayURL(
            from: "not a url",
            telemetrySink: nil
        )
        XCTAssertNil(url)
    }

    // MARK: - Allowlist shape

    func testAllowlistIsNotEmpty() {
        // Guards against an accidental clear of the allowlist set —
        // that would silently disable cloud AI in production.
        XCTAssertFalse(VolumeArcAIConfiguration.allowedHosts.isEmpty)
    }

    // MARK: - Helpers

    private func assertRejection(
        _ sink: InMemoryTelemetrySink,
        rule expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let event = sink.currentEvents.last else {
            XCTFail("Expected a telemetry event", file: file, line: line)
            return
        }
        XCTAssertEqual(event.severity, .error, file: file, line: line)
        XCTAssertEqual(event.category,
                       VolumeArcAIConfiguration.telemetryCategory,
                       file: file,
                       line: line)
        XCTAssertEqual(event.metadata["rule"], expected, file: file, line: line)
    }
}
