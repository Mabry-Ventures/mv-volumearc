import Foundation
import VolumeArcCore

enum TestFixtures {
    static func liveActivityState(
        workoutTitle: String = "Strength Day",
        exercise: String = "Back Squat",
        target: String = "225 x 5",
        rest: Int? = 90
    ) -> LiveActivityState {
        LiveActivityState(
            workoutTitle: workoutTitle,
            activeExerciseName: exercise,
            targetSummary: target,
            restSecondsRemaining: rest
        )
    }

    static func watchPayload(
        kind: WatchPayloadKind = .liveState,
        workoutID: String = "test-session",
        body: String = "action=hold"
    ) -> WatchPayload {
        WatchPayload(kind: kind, workoutID: workoutID, body: body)
    }

    static func operationalSignal(
        id: String = "test-signal",
        title: String = "Test",
        message: String = "Test signal message",
        severity: TelemetrySeverity = .warning
    ) -> OperationalSignalSummary {
        OperationalSignalSummary(id: id, title: title, message: message, severity: severity)
    }

    static func telemetryEvent(
        category: String = "test",
        name: String = "test_event",
        severity: TelemetrySeverity = .info,
        message: String = "Test event"
    ) -> TelemetryEvent {
        TelemetryEvent(category: category, name: name, severity: severity, message: message)
    }
}
