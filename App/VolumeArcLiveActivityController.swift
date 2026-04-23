#if canImport(ActivityKit)
import ActivityKit
import Foundation
import VolumeArcCore

struct VolumeArcLiveActivityController {
    /// VOL-61: `.liveActivities` flag gates the entire start/update path so
    /// disabling Dynamic Island + lock-screen activities becomes a runtime
    /// decision rather than a compile-time decision. When off, every
    /// controller method becomes a no-op. Active sessions end on the next
    /// `end()` call; new sessions never start.
    let flagGate: FlagGateTelemetry?

    init(flagGate: FlagGateTelemetry? = nil) {
        self.flagGate = flagGate
    }

    func restoreStoredStateIfAvailable() async {
        guard isEnabled else { return }
        guard let stored = PlatformSurfaceDefaultsReader.loadLiveActivityState() else { return }
        await startOrUpdate(from: stored)
    }

    func startOrUpdate(from state: LiveActivityState) async {
        guard isEnabled else { return }
        let attributes = ActiveWorkoutAttributes(workoutTitle: state.workoutTitle)
        let contentState = ActiveWorkoutAttributes.ContentState(
            activeExerciseName: state.activeExerciseName,
            targetSummary: state.targetSummary,
            restSecondsRemaining: state.restSecondsRemaining
        )

        if let currentActivity = currentActivity(for: state.workoutTitle) {
            await currentActivity.update(ActivityContent(state: contentState, staleDate: nil))
            return
        }

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: contentState, staleDate: nil),
                pushType: nil
            )
        } catch {
            return
        }
    }

    /// Ending activities is intentionally NOT gated: once the flag flips
    /// off, any already-started activity should still be tearable down so
    /// the Dynamic Island doesn't leak past the user disabling the feature.
    func end() async {
        for activity in Activity<ActiveWorkoutAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private var isEnabled: Bool {
        flagGate?.recordIfFirst(.liveActivities) ?? true
    }

    private func currentActivity(for workoutTitle: String) -> Activity<ActiveWorkoutAttributes>? {
        Activity<ActiveWorkoutAttributes>.activities.first {
            $0.attributes.workoutTitle == workoutTitle
        }
    }
}
#endif
