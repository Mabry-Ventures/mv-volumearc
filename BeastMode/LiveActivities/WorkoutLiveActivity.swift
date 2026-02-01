import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity for active workout sessions
struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentExercise: String
        var setNumber: Int
        var totalSets: Int
        var elapsedTime: TimeInterval
        var isResting: Bool
        var restTimeRemaining: TimeInterval?
        var completedSets: Int
    }

    var workoutName: String
    var focusArea: String
    var startTime: Date
}

// MARK: - Live Activity Widget

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Lock screen / banner view
            WorkoutLiveActivityView(context: context)
                .padding()
                .activityBackgroundTint(.purple.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded views
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.attributes.focusArea)
                            .font(.caption.weight(.semibold))
                        Text(context.state.currentExercise)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        if context.state.isResting, let restTime = context.state.restTimeRemaining {
                            Text(formatTime(restTime))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.orange)
                            Text("REST")
                                .font(.caption2)
                        } else {
                            Text("Set \(context.state.setNumber)")
                                .font(.title2.weight(.bold))
                            Text("of \(context.state.totalSets)")
                                .font(.caption2)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        // Progress bar
                        ProgressView(
                            value: Double(context.state.completedSets),
                            total: Double(context.state.totalSets)
                        )
                        .tint(.white)

                        Spacer()

                        // Elapsed time
                        Text(formatTime(context.state.elapsedTime))
                            .font(.caption.monospacedDigit())
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.purple)
            } compactTrailing: {
                if context.state.isResting, let restTime = context.state.restTimeRemaining {
                    Text(formatTime(restTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                } else {
                    Text("\(context.state.setNumber)/\(context.state.totalSets)")
                        .font(.caption.monospacedDigit())
                }
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.purple)
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Live Activity View

struct WorkoutLiveActivityView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        HStack {
            // Leading: Exercise info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                    Text(context.attributes.focusArea)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.8))

                Text(context.state.currentExercise)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("Set \(context.state.setNumber) of \(context.state.totalSets)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Trailing: Timer or Rest
            if context.state.isResting, let restTime = context.state.restTimeRemaining {
                VStack(alignment: .trailing) {
                    Text(formatTime(restTime))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Text("REST")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange.opacity(0.8))
                }
            } else {
                // Elapsed time
                VStack(alignment: .trailing) {
                    Text(formatTime(context.state.elapsedTime))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("ELAPSED")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Activity Manager

@MainActor
class WorkoutActivityManager: ObservableObject {
    static let shared = WorkoutActivityManager()

    private var currentActivity: Activity<WorkoutActivityAttributes>?

    private init() {}

    func startActivity(workoutName: String, focusArea: String, totalSets: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }

        let attributes = WorkoutActivityAttributes(
            workoutName: workoutName,
            focusArea: focusArea,
            startTime: .now
        )

        let initialState = WorkoutActivityAttributes.ContentState(
            currentExercise: "Starting...",
            setNumber: 1,
            totalSets: totalSets,
            elapsedTime: 0,
            isResting: false,
            restTimeRemaining: nil,
            completedSets: 0
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    func updateActivity(state: WorkoutActivityAttributes.ContentState) {
        Task {
            await currentActivity?.update(
                ActivityContent(state: state, staleDate: nil)
            )
        }
    }

    func endActivity() {
        Task {
            await currentActivity?.end(nil, dismissalPolicy: .immediate)
            currentActivity = nil
        }
    }
}
