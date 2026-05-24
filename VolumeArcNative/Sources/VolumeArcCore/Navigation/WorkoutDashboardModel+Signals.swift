import Foundation

/// VOL-200 Phase 5: Signals-surface telemetry.
///
/// Kept in an extension so the main `WorkoutDashboardModel` file stays
/// under SwiftLint's 750-line ceiling. Same pattern as
/// `WorkoutDashboardModel+CoachContext.swift`.
public extension WorkoutDashboardModel {
    /// Emit the journey-catalog telemetry events for the Signals tab.
    /// Wired from `SignalsView.task` so cold-launching the Signals
    /// surface produces the three documented events
    /// (`signals.readiness.opened`, `signals.volume.opened`,
    /// `signals.frequency.opened`).
    ///
    /// VOL-200 Phase 5: the journey catalog originally read these
    /// events as drill-down gestures, but the current SignalsView
    /// renders all three sections on a single scroll view — there
    /// is no separate "open" interaction. Emitting them together on
    /// view appearance is the implementation that matches today's
    /// product; future work that adds per-section expand/collapse
    /// affordances can split this into three independent emits.
    @MainActor
    func recordSignalsViewed() {
        telemetrySink.record(TelemetryEvent(
            category: "signals",
            name: "readiness.opened",
            severity: .info,
            message: "Signals readiness section viewed",
            metadata: ["readiness": "\(readiness.score)"]
        ))
        telemetrySink.record(TelemetryEvent(
            category: "signals",
            name: "volume.opened",
            severity: .info,
            message: "Signals weekly-volume section viewed"
        ))
        telemetrySink.record(TelemetryEvent(
            category: "signals",
            name: "frequency.opened",
            severity: .info,
            message: "Signals frequency heatmap viewed"
        ))
    }

    /// Emit the journey-catalog event for opening a historical workout
    /// detail view from the Workouts tab.
    @MainActor
    func recordWorkoutDetailOpened(session: RecentSession) {
        telemetrySink.record(TelemetryEvent(
            category: "workout",
            name: "detail.opened",
            severity: .info,
            message: "Workout detail opened",
            metadata: [
                "sets": "\(session.completedSetCount)",
                "durationMinutes": "\(session.durationMinutes)",
                "volumeLoad": "\(Int(session.totalVolumeLoad))",
            ]
        ))
    }
}
