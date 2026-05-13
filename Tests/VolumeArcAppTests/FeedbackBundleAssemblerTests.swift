// VOL-146 Phase 1A: unit coverage for FeedbackBundleAssembler.
//
// Pins the contract that user feedback always ships with a PII-
// scrubbed description + telemetry messages. The scrub pipeline is
// the same one that protects Sentry events, applied at bundle-
// construction time so every downstream consumer (Sentry user
// feedback, Linear webhook in Phase 2) inherits the guarantee
// without re-implementing the regex layer.

import XCTest
@testable import VolumeArcCore

final class FeedbackBundleAssemblerTests: XCTestCase {

    // MARK: - PII scrubbing

    func testEmailAddressIsRedactedFromDescription() {
        let assembler = FeedbackBundleAssembler()
        let bundle = assembler.makeBundle(inputs: makeInputs(
            userDescription: "I tried logging in with jared@example.com and the app froze."
        ))
        XCTAssertFalse(
            bundle.userDescription.contains("jared@example.com"),
            "Email address must be redacted from user-typed feedback"
        )
        XCTAssertTrue(
            bundle.userDescription.contains("[redacted]"),
            "Scrubber should replace the email with [redacted]"
        )
    }

    func testPhoneNumberShapesAreRedacted() {
        let assembler = FeedbackBundleAssembler()
        let inputs = [
            "Call me at 555-123-4567 to discuss",
            "International: +447911123456 hit",
            "(415) 555-9876 was where I tested",
        ]
        for input in inputs {
            let bundle = assembler.makeBundle(inputs: makeInputs(userDescription: input))
            XCTAssertTrue(
                bundle.userDescription.contains("[redacted]"),
                "Phone shape should be scrubbed: \(input)"
            )
        }
    }

    func testNonPIIDescriptionIsPreserved() {
        let assembler = FeedbackBundleAssembler()
        let bundle = assembler.makeBundle(inputs: makeInputs(
            category: .idea,
            userDescription: "Wish the coach asked about sleep before the morning workout."
        ))
        XCTAssertEqual(
            bundle.userDescription,
            "Wish the coach asked about sleep before the morning workout.",
            "Non-PII feedback text should pass through unchanged"
        )
    }

    func testTelemetryMessagesAreAlsoScrubbed() {
        let assembler = FeedbackBundleAssembler()
        let snapshot = FeedbackBundle.TelemetrySnapshot(
            category: "ai.relay",
            name: "request_failed",
            severity: "warning",
            message: "Relay rejected token for jared@example.com",
            timestampISO8601: "2026-05-13T14:00:00Z"
        )
        let bundle = assembler.makeBundle(inputs: makeInputs(
            userDescription: "Coach unavailable",
            recentTelemetry: [snapshot]
        ))
        let firstTelemetry = bundle.recentTelemetry.first
        XCTAssertNotNil(firstTelemetry)
        XCTAssertFalse(
            firstTelemetry?.message.contains("jared@example.com") ?? true,
            "Telemetry message should be scrubbed for PII"
        )
        XCTAssertTrue(
            firstTelemetry?.message.contains("[redacted]") ?? false,
            "Scrubber should substitute [redacted] in telemetry messages too"
        )
    }

    // MARK: - Bundle bounds

    func testRecentTelemetryIsBoundedByMaxEvents() {
        let assembler = FeedbackBundleAssembler()
        let manySnapshots = (0..<100).map { index in
            FeedbackBundle.TelemetrySnapshot(
                category: "test",
                name: "event_\(index)",
                severity: "info",
                message: "Message \(index)",
                timestampISO8601: "2026-05-13T14:00:00Z"
            )
        }
        let bundle = assembler.makeBundle(
            inputs: makeInputs(category: .other, recentTelemetry: manySnapshots),
            maxTelemetryEvents: 10
        )
        XCTAssertEqual(
            bundle.recentTelemetry.count, 10,
            "Bundle must respect maxTelemetryEvents to keep payload size bounded"
        )
        // Suffix means we keep the MOST RECENT 10 — assert that
        // event_99 (last in input) is present and event_0 (first) is not.
        XCTAssertTrue(
            bundle.recentTelemetry.contains { $0.name == "event_99" },
            "Most-recent telemetry event should be retained"
        )
        XCTAssertFalse(
            bundle.recentTelemetry.contains { $0.name == "event_0" },
            "Oldest telemetry events should be trimmed"
        )
    }

    // MARK: - JSON serialization

    func testEncodeJSONProducesStableSortedOutput() throws {
        let assembler = FeedbackBundleAssembler()
        let bundle = assembler.makeBundle(inputs: makeInputs(
            category: .coachQuality,
            userDescription: "Coach response was off-topic",
            submittedAt: Date(timeIntervalSince1970: 1_715_000_000)
        ))
        let json = try assembler.encodeJSON(bundle)
        // Sorted-keys output is stable across runs — pin anchor
        // substrings to catch a regression in the encoder config
        // (which could leak unscrubbed PII via, e.g., a pretty-print
        // spacing change that breaks downstream parsers).
        XCTAssertTrue(json.contains("\"category\":\"coach_quality\""))
        XCTAssertTrue(json.contains("\"buildVersion\":\"1.0.0\""))
        XCTAssertTrue(json.contains("\"userDescription\":\"Coach response was off-topic\""))
    }

    func testCategoryRoundTripsThroughJSON() throws {
        let assembler = FeedbackBundleAssembler()
        for category in FeedbackBundle.Category.allCases {
            let bundle = assembler.makeBundle(inputs: makeInputs(
                category: category,
                userDescription: "test"
            ))
            let json = try assembler.encodeJSON(bundle)
            let data = try XCTUnwrap(json.data(using: .utf8))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(FeedbackBundle.self, from: data)
            XCTAssertEqual(decoded.category, category)
        }
    }

    // MARK: - Helpers

    /// Factory for `FeedbackBundleAssembler.Inputs` with sensible
    /// defaults. Lets each test override only the fields under test
    /// without restating the boilerplate metadata every call.
    private func makeInputs(
        category: FeedbackBundle.Category = .bug,
        userDescription: String = "",
        buildVersion: String = "1.0.0",
        buildNumber: String = "1",
        osVersion: String = "26.0",
        deviceModel: String = "iPhone17,3",
        recentTelemetry: [FeedbackBundle.TelemetrySnapshot] = [],
        appStateHash: String = "abc",
        submittedAt: Date = Date()
    ) -> FeedbackBundleAssembler.Inputs {
        FeedbackBundleAssembler.Inputs(
            category: category,
            userDescription: userDescription,
            buildVersion: buildVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            deviceModel: deviceModel,
            recentTelemetry: recentTelemetry,
            appStateHash: appStateHash,
            submittedAt: submittedAt
        )
    }
}
