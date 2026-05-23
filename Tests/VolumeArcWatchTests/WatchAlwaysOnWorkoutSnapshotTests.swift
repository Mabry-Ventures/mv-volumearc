import Foundation
import XCTest
@testable import VolumeArcCore

final class WatchAlwaysOnWorkoutSnapshotTests: XCTestCase {
    func test_aodSnapshot_capturesDimmedWorkoutSurface() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let snapshot = WatchAlwaysOnWorkoutSnapshot.make(
            autopilot: WorkoutAutopilotState(
                nextExerciseID: "back-squat",
                nextExerciseName: "Back Squat",
                nextTarget: WorkoutTarget(weight: 225, unit: "lb", repRange: 5...8, targetRPE: 8),
                bestCue: "Brace before you descend.",
                recommendationReason: "Own the next set.",
                suggestedAction: .hold
            ),
            restEndsAt: now.addingTimeInterval(42),
            now: now,
            heartRateBPM: 118
        )

        try assertInlineJSONSnapshot(
            of: snapshot,
            matches:
            """
            {
              "animationPolicy" : "disabled",
              "heartRateText" : "HR 118 bpm",
              "interactiveControlsVisible" : false,
              "palette" : [
                "black",
                "white",
                "gray",
                "brandPrimary@0.22"
              ],
              "restAccessibilityLabel" : "Rest timer",
              "restAccessibilityValue" : "42 seconds remaining",
              "restTimerText" : "42s",
              "setLine" : "Back Squat - 225lb x 5-8"
            }
            """
        )
    }

    func test_aodSnapshot_suppressesHeartRateWhenUnavailable() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let snapshot = WatchAlwaysOnWorkoutSnapshot.make(
            autopilot: WorkoutAutopilotState(
                nextExerciseID: "deadlift",
                nextExerciseName: "Deadlift",
                nextTarget: WorkoutTarget(weight: 315, unit: "lb", repRange: 3...5, targetRPE: 8.5),
                bestCue: "Push the floor away.",
                recommendationReason: "Heavy pull.",
                suggestedAction: .hold
            ),
            restEndsAt: now,
            now: now,
            heartRateBPM: nil
        )

        try assertInlineJSONSnapshot(
            of: snapshot,
            matches:
            """
            {
              "animationPolicy" : "disabled",
              "interactiveControlsVisible" : false,
              "palette" : [
                "black",
                "white",
                "gray",
                "brandPrimary@0.22"
              ],
              "restAccessibilityLabel" : "Rest complete",
              "restAccessibilityValue" : "Ready for the next set",
              "restTimerText" : "GO",
              "setLine" : "Deadlift - 315lb x 3-5"
            }
            """
        )
    }

    private func assertInlineJSONSnapshot(
        of value: some Encodable,
        matches expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let actual = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
}
