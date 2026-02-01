import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity for rest timer between sets
struct RestTimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var timeRemaining: TimeInterval
        var totalDuration: TimeInterval
        var exerciseName: String
        var nextSetNumber: Int
    }

    var workoutFocusArea: String
}

// MARK: - Rest Timer Live Activity Widget

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerActivityAttributes.self) { context in
            // Lock screen / banner view
            RestTimerLiveActivityView(context: context)
                .padding()
                .activityBackgroundTint(.orange.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded views
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 8) {
                        Text("REST")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))

                        Text(formatTime(context.state.timeRemaining))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Next: \(context.state.exerciseName) - Set \(context.state.nextSetNumber)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)

                        // Progress bar
                        ProgressView(
                            value: context.state.totalDuration - context.state.timeRemaining,
                            total: context.state.totalDuration
                        )
                        .tint(.white)
                        .padding(.horizontal)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(formatTime(context.state.timeRemaining))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.orange)
            } minimal: {
                Text(formatTimeMinimal(context.state.timeRemaining))
                    .font(.caption2.weight(.bold).monospacedDigit())
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatTimeMinimal(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        if totalSeconds >= 60 {
            return "\(totalSeconds / 60)m"
        }
        return "\(totalSeconds)"
    }
}

// MARK: - Rest Timer Live Activity View

struct RestTimerLiveActivityView: View {
    let context: ActivityViewContext<RestTimerActivityAttributes>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "timer")
                    Text("REST")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.8))

                Text(context.state.exerciseName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("Set \(context.state.nextSetNumber) next")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Timer display
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 6)
                    .frame(width: 70, height: 70)

                Circle()
                    .trim(from: 0, to: context.state.timeRemaining / context.state.totalDuration)
                    .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))

                Text(formatTime(context.state.timeRemaining))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Rest Timer Activity Manager

@MainActor
class RestTimerActivityManager: ObservableObject {
    static let shared = RestTimerActivityManager()

    private var currentActivity: Activity<RestTimerActivityAttributes>?
    private var timer: Timer?

    private init() {}

    func startRestTimer(
        duration: TimeInterval,
        exerciseName: String,
        nextSetNumber: Int,
        focusArea: String
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        // End any existing rest timer activity
        endRestTimer()

        let attributes = RestTimerActivityAttributes(workoutFocusArea: focusArea)

        let initialState = RestTimerActivityAttributes.ContentState(
            timeRemaining: duration,
            totalDuration: duration,
            exerciseName: exerciseName,
            nextSetNumber: nextSetNumber
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date().addingTimeInterval(duration)),
                pushType: nil
            )

            // Start countdown timer
            startCountdownTimer(duration: duration, exerciseName: exerciseName, nextSetNumber: nextSetNumber)
        } catch {
            print("Failed to start rest timer activity: \(error)")
        }
    }

    private func startCountdownTimer(duration: TimeInterval, exerciseName: String, nextSetNumber: Int) {
        var remaining = duration

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            remaining -= 1

            if remaining <= 0 {
                self?.endRestTimer()
            } else {
                let state = RestTimerActivityAttributes.ContentState(
                    timeRemaining: remaining,
                    totalDuration: duration,
                    exerciseName: exerciseName,
                    nextSetNumber: nextSetNumber
                )
                self?.updateActivity(state: state)
            }
        }
    }

    func updateActivity(state: RestTimerActivityAttributes.ContentState) {
        Task {
            await currentActivity?.update(
                ActivityContent(state: state, staleDate: Date().addingTimeInterval(state.timeRemaining))
            )
        }
    }

    func endRestTimer() {
        timer?.invalidate()
        timer = nil

        Task {
            await currentActivity?.end(nil, dismissalPolicy: .immediate)
            currentActivity = nil
        }
    }
}
