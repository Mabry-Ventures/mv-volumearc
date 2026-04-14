#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Workouts tab — active session screen with set logging, rest timer, coach cue.
public struct WorkoutsView: View {
    @ObservedObject var model: WorkoutDashboardModel
    @State private var restEndsAt: Date = .now.addingTimeInterval(90)
    @State private var restActive: Bool = false

    public init(model: WorkoutDashboardModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VA.Space.lg) {
                if model.isSessionActive {
                    activeSessionHeader
                    currentExerciseCard
                    restTimerCard
                    logSetButton
                    completeButton
                } else {
                    idleState
                }
            }
            .padding(VA.Space.lg)
        }
        .background(VA.Colors.surfaceSecondary)
        .navigationTitle(model.isSessionActive ? "Session" : "Workouts")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Active session

    private var activeSessionHeader: some View {
        VACard(style: .accent) {
            HStack {
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text("LIVE SESSION")
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.primary)
                        .tracking(0.5)
                    Text(model.activeWorkoutTitle ?? "Strength Session")
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text("\(model.loggedSetCountThisSession) sets logged")
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "record.circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(VA.Colors.primary)
                    .symbolEffect(.pulse, options: .repeating)
            }
        }
    }

    @ViewBuilder
    private var currentExerciseCard: some View {
        if let autopilot = model.autopilot {
            VACard(style: .elevated) {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    VASectionHeader("Next Set")
                    Text(autopilot.nextExerciseName)
                        .font(VA.Typography.title)
                        .foregroundStyle(VA.Colors.textPrimary)

                    HStack(spacing: VA.Space.xl) {
                        VAMetricDisplay(
                            label: "Weight",
                            value: "\(Int(autopilot.nextTarget.weight))",
                            unit: autopilot.nextTarget.unit,
                            style: .standard
                        )
                        VAMetricDisplay(
                            label: "Reps",
                            value: "\(autopilot.nextTarget.repRange.lowerBound)-\(autopilot.nextTarget.repRange.upperBound)",
                            style: .standard
                        )
                        VAMetricDisplay(
                            label: "RPE",
                            value: String(format: "%.1f", autopilot.nextTarget.targetRPE),
                            style: .standard
                        )
                    }

                    Divider()

                    HStack(alignment: .top, spacing: VA.Space.sm) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 13))
                            .foregroundStyle(VA.Colors.primary)
                        Text(autopilot.bestCue)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .italic()
                    }
                }
            }
        }
    }

    private var restTimerCard: some View {
        VACard(style: .glass) {
            VStack(spacing: VA.Space.md) {
                HStack {
                    Text("REST TIMER")
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.5)
                    Spacer()
                    if restActive {
                        Button("Reset") {
                            restEndsAt = .now.addingTimeInterval(90)
                            VAHaptics.tap()
                        }
                        .font(VA.Typography.button)
                        .foregroundStyle(VA.Colors.primary)
                    }
                }

                RestTimerDisplay(
                    endsAt: restEndsAt,
                    active: restActive,
                    onComplete: { VAHaptics.restComplete() }
                )

                if !restActive {
                    VAButton("Start Rest (90s)", icon: "timer", style: .secondary) {
                        restEndsAt = .now.addingTimeInterval(90)
                        restActive = true
                        VAHaptics.tap()
                    }
                }
            }
        }
    }

    private var logSetButton: some View {
        VAButton("Log Set", icon: "checkmark.circle.fill", style: .primary) {
            Task {
                VAHaptics.setLogged()
                await model.logRecommendedSet()
                restEndsAt = .now.addingTimeInterval(90)
                restActive = true
            }
        }
    }

    private var completeButton: some View {
        VAButton("Complete Workout", icon: "flag.checkered", style: .secondary) {
            Task {
                VAHaptics.workoutComplete()
                await model.completeWorkoutSession()
            }
        }
    }

    // MARK: - Idle state

    private var idleState: some View {
        VStack(spacing: VA.Space.lg) {
            VAEmptyState(
                icon: "figure.strengthtraining.traditional",
                title: "No Active Session",
                message: "Ready to train? Start a workout from the Today tab or begin one now.",
                action: (label: "Start Workout", handler: {
                    Task {
                        VAHaptics.sessionStart()
                        await model.startWorkoutSession()
                    }
                })
            )
            .frame(minHeight: 300)

            if !model.recentSessions.isEmpty {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    VASectionHeader("Recent History")
                    ForEach(Array(model.recentSessions.prefix(5).enumerated()), id: \.offset) { _, session in
                        VACard(style: .flat) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.date.formatted(.dateTime.month().day()))
                                        .font(VA.Typography.headline)
                                    Text("\(session.completedSetCount) sets")
                                        .font(VA.Typography.footnote)
                                        .foregroundStyle(VA.Colors.textSecondary)
                                }
                                Spacer()
                                Text("\(Int(session.totalVolumeLoad)) lb load")
                                    .font(VA.Typography.monoDigit)
                                    .foregroundStyle(VA.Colors.primary)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Dedicated subview for the rest timer so only this view re-renders each second,
/// not the whole WorkoutsView.
private struct RestTimerDisplay: View {
    let endsAt: Date
    let active: Bool
    let onComplete: () -> Void

    @State private var lastFired: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endsAt.timeIntervalSince(context.date)))
            let total: TimeInterval = 90
            let elapsed = total - endsAt.timeIntervalSince(context.date)
            let progress = max(0, min(1, elapsed / total))

            ZStack {
                VAProgressRing(progress: progress, lineWidth: 12, color: remaining == 0 ? VA.Colors.success : VA.Colors.primary)
                    .frame(width: 140, height: 140)
                VStack(spacing: 0) {
                    Text("\(remaining)")
                        .font(VA.Typography.timerDisplay)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(remaining == 0 ? "GO" : "seconds")
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(1)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Rest timer")
            .accessibilityValue(remaining == 0 ? "Go time" : "\(remaining) seconds remaining")
            .onChange(of: remaining) { _, newValue in
                if active && newValue == 0 && !lastFired {
                    lastFired = true
                    onComplete()
                }
                if newValue > 0 { lastFired = false }
            }
        }
        .frame(height: 160)
    }
}
#endif
