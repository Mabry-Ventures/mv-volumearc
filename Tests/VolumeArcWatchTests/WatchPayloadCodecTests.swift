import XCTest
@testable import VolumeArcCore

/// VOL-138 Phase A: payload codec coverage for `WatchPayload` and
/// `WatchSessionSnapshot`. Both types straddle the phone ↔ watch boundary
/// — they round-trip through `WCSession.transferUserInfo` as
/// `[String: Any]` (the dictionary form) and through `UserDefaults`-backed
/// persistence as JSON `Data` (the Codable form). A regression in either
/// codec silently corrupts the connectivity stream.
///
/// These assertions live against the watchOS-compiled flavor of
/// `VolumeArcCore` (i.e. the `VolumeArcCoreWatch` static library that
/// `Watch/VolumeArcWatchApp.swift` links). The same types compile for
/// iOS and are exercised separately by `VolumeArcAppTests`, but proving
/// the codec is stable on the watchOS SDK in isolation is what unblocks
/// the rest of VOL-138's watch-only coverage.
final class WatchPayloadCodecTests: XCTestCase {

    // MARK: - Dictionary round-trip

    func test_payload_dictionary_roundtrip_preserves_every_field() {
        let original = WatchPayload(
            kind: .coachCue,
            workoutID: "workout-42",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: "rest 90s then drive the next set"
        )

        let dict = original.asDictionary()
        let decoded = WatchPayload(dictionary: dict)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.kind, original.kind)
        XCTAssertEqual(decoded?.workoutID, original.workoutID)
        XCTAssertEqual(decoded?.body, original.body)
        XCTAssertEqual(
            decoded?.createdAt.timeIntervalSince1970 ?? 0,
            original.createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func test_payload_dictionary_roundtrip_for_every_kind() {
        for kind in [
            WatchPayloadKind.restTimer,
            .liveState,
            .startSession,
            .endSession,
            .coachCue,
            .completedWorkout,
        ] {
            let original = WatchPayload(
                kind: kind,
                workoutID: "w-\(kind.rawValue)",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                body: "{}"
            )
            let decoded = WatchPayload(dictionary: original.asDictionary())
            XCTAssertEqual(decoded?.kind, kind, "Kind \(kind) failed round-trip")
        }
    }

    func test_payload_dictionary_missing_required_field_returns_nil() {
        let missingKind: [String: Any] = [
            "workoutID": "w-1",
            "body": "{}",
        ]
        XCTAssertNil(WatchPayload(dictionary: missingKind))

        let missingWorkoutID: [String: Any] = [
            "kind": WatchPayloadKind.restTimer.rawValue,
            "body": "{}",
        ]
        XCTAssertNil(WatchPayload(dictionary: missingWorkoutID))

        let missingBody: [String: Any] = [
            "kind": WatchPayloadKind.restTimer.rawValue,
            "workoutID": "w-1",
        ]
        XCTAssertNil(WatchPayload(dictionary: missingBody))
    }

    func test_payload_dictionary_unknown_kind_returns_nil() {
        let dict: [String: Any] = [
            "kind": "totallyMadeUp",
            "workoutID": "w-1",
            "body": "{}",
        ]
        XCTAssertNil(WatchPayload(dictionary: dict))
    }

    func test_payload_dictionary_missing_createdAt_defaults_to_now() {
        // Real WCSession payloads sometimes drop createdAt if the
        // sender is on an older app version. The decoder treats that
        // as "now" rather than failing — assert the recovery.
        let dict: [String: Any] = [
            "kind": WatchPayloadKind.restTimer.rawValue,
            "workoutID": "w-1",
            "body": "{}",
        ]
        let before = Date()
        let decoded = WatchPayload(dictionary: dict)
        let after = Date()

        XCTAssertNotNil(decoded)
        if let createdAt = decoded?.createdAt {
            XCTAssertGreaterThanOrEqual(createdAt, before.addingTimeInterval(-1))
            XCTAssertLessThanOrEqual(createdAt, after.addingTimeInterval(1))
        }
    }

    // MARK: - Codable JSON round-trip

    func test_payload_json_codable_roundtrip() throws {
        let original = WatchPayload(
            kind: .liveState,
            workoutID: "live-state",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: "{\"set\":3,\"rep\":8}"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let decoded = try decoder.decode(WatchPayload.self, from: data)

        XCTAssertEqual(decoded.kind, original.kind)
        XCTAssertEqual(decoded.workoutID, original.workoutID)
        XCTAssertEqual(decoded.body, original.body)
        XCTAssertEqual(
            decoded.createdAt.timeIntervalSince1970,
            original.createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    // MARK: - WatchSessionSnapshot

    func test_session_snapshot_codable_roundtrip_preserves_every_field() throws {
        let original = WatchSessionSnapshot(
            selectedAction: .increase,
            restEndsAt: Date(timeIntervalSince1970: 1_700_000_300),
            coachPrompt: "Drive the next set hard.",
            sessionActive: true,
            statusMessage: "Set 3 / 5"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchSessionSnapshot.self, from: data)

        XCTAssertEqual(decoded.selectedAction, original.selectedAction)
        XCTAssertEqual(decoded.coachPrompt, original.coachPrompt)
        XCTAssertEqual(decoded.sessionActive, original.sessionActive)
        XCTAssertEqual(decoded.statusMessage, original.statusMessage)
        XCTAssertEqual(
            decoded.restEndsAt.timeIntervalSince1970,
            original.restEndsAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func test_session_snapshot_handles_every_workout_action() throws {
        for action in WorkoutAction.allCases {
            let original = WatchSessionSnapshot(
                selectedAction: action,
                restEndsAt: Date(timeIntervalSince1970: 1_700_000_000),
                coachPrompt: "p",
                sessionActive: false,
                statusMessage: "s"
            )
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(WatchSessionSnapshot.self, from: data)
            XCTAssertEqual(decoded.selectedAction, action)
        }
    }
}
