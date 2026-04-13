#if canImport(ActivityKit)
import ActivityKit
import Foundation
import VolumeArcCore

struct VolumeArcLiveActivityController {
    func restoreStoredStateIfAvailable() async {
        guard let stored = PlatformSurfaceDefaultsReader.loadLiveActivityState() else { return }
        await startOrUpdate(from: stored)
    }

    func startOrUpdate(from state: LiveActivityState) async {
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

    func end() async {
        for activity in Activity<ActiveWorkoutAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func currentActivity(for workoutTitle: String) -> Activity<ActiveWorkoutAttributes>? {
        Activity<ActiveWorkoutAttributes>.activities.first {
            $0.attributes.workoutTitle == workoutTitle
        }
    }
}
#endif
