#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Workouts tab — active session screen with set logging, rest timer, coach cue.
public struct WorkoutsView: View {
    @ObservedObject var model: WorkoutDashboardModel
    @EnvironmentObject private var toastPresenter: VAToastPresenter
    @State private var restEndsAt: Date = .now.addingTimeInterval(90)
    @State private var restActive: Bool = false
    @State private var summary: CompletedSessionSnapshot?

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
        .navigationTitle(model.isSessionActive
                         ? String(localized: "Session", comment: "Workouts tab title during an active session")
                         : String(localized: "Workouts", comment: "Workouts tab title when idle"))
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $summary) { snapshot in
            SessionSummaryView(
                sets: snapshot.sets,
                totalVolume: snapshot.totalVolume,
                duration: snapshot.duration,
                averageRPE: snapshot.averageRPE,
                primaryLift: snapshot.primaryLift
            ) {
                summary = nil
            }
        }
    }

    /// Captured snapshot of the session state at completion time.
    /// Held locally so the summary sheet can display metrics even after
    /// the model has cleared its `isSessionActive` state.
    struct CompletedSessionSnapshot: Identifiable {
        let id = UUID()
        let sets: Int
        let totalVolume: Double
        let duration: Int
        let averageRPE: Double
        let primaryLift: String
    }

    // MARK: - Active session

    private var activeSessionHeader: some View {
        VACard(style: .accent) {
            HStack {
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(String(localized: "LIVE SESSION", comment: "Label above the active session card"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.primary)
                        .tracking(0.5)
                    Text(model.activeWorkoutTitle ?? String(
                        localized: "Strength Session",
                        comment: "Default title when no workout title is set"
                    ))
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(String(
                        localized: "^[\(model.loggedSetCountThisSession) sets](inflect: true) logged",
                        comment: """
                            Active session subtitle showing how many sets have \
                            been logged. Uses Apple's inflection syntax for \
                            plural agreement.
                            """
                    ))
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
                    VASectionHeader(String(localized: "Next Set", comment: "Section header above the upcoming set card"))
                    Text(autopilot.nextExerciseName)
                        .font(VA.Typography.title)
                        .foregroundStyle(VA.Colors.textPrimary)

                    HStack(spacing: VA.Space.xl) {
                        VAMetricDisplay(
                            label: String(localized: "Weight", comment: "Metric label — target weight"),
                            value: "\(Int(autopilot.nextTarget.weight))",
                            unit: autopilot.nextTarget.unit,
                            style: .standard
                        )
                        VAMetricDisplay(
                            label: String(localized: "Reps", comment: "Metric label — target rep range"),
                            value: "\(autopilot.nextTarget.repRange.lowerBound)-\(autopilot.nextTarget.repRange.upperBound)",
                            style: .standard
                        )
                        VAMetricDisplay(
                            label: String(localized: "RPE", comment: "Metric label — target rate of perceived exertion"),
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
                    Text(String(localized: "REST TIMER", comment: "Label above the rest timer"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.5)
                    Spacer()
                    if restActive {
                        Button(String(localized: "Reset", comment: "Rest timer reset button")) {
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
                    VAButton(
                        String(localized: "Start Rest (90s)", comment: "Button to start a 90-second rest timer"),
                        icon: "timer",
                        style: .secondary
                    ) {
                        restEndsAt = .now.addingTimeInterval(90)
                        restActive = true
                        VAHaptics.tap()
                    }
                }
            }
        }
    }

    private var logSetButton: some View {
        VAButton(
            String(localized: "Log Set", comment: "Button to record the current set"),
            icon: "checkmark.circle.fill",
            style: .primary,
            accessibilityHint: String(localized: "Records this set and starts the rest timer",
                                      comment: "Log Set button VoiceOver hint")
        ) {
            Task {
                VAHaptics.setLogged()
                await model.logRecommendedSet()
                restEndsAt = .now.addingTimeInterval(90)
                restActive = true
                toastPresenter.show(VAToast(
                    kind: .success,
                    title: String(localized: "Set logged", comment: "Toast after logging a set"),
                    message: String(localized: "Starting your 90-second rest.", comment: "Toast detail")
                ))
            }
        }
    }

    private var completeButton: some View {
        VAButton(
            String(localized: "Complete Workout", comment: "Button to finish the current workout session"),
            icon: "flag.checkered",
            style: .secondary
        ) {
            Task {
                VAHaptics.workoutComplete()

                let capturedSets = model.loggedSetCountThisSession
                let capturedRPE = model.autopilot?.nextTarget.targetRPE ?? 7.5
                let capturedLift = model.autopilot?.nextExerciseName ?? String(
                    localized: "your workout",
                    comment: "Fallback phrase for the primary lift when none is identified"
                )

                let completedSession = await model.completeWorkoutSession()

                summary = CompletedSessionSnapshot(
                    sets: completedSession?.completedSetCount ?? max(1, capturedSets),
                    totalVolume: max(completedSession?.totalVolumeLoad ?? 0, 1),
                    duration: max(completedSession?.durationMinutes ?? 0, 1),
                    averageRPE: completedSession?.averageRPE ?? capturedRPE,
                    primaryLift: capturedLift
                )
            }
        }
    }

    // MARK: - Idle state

    private var idleState: some View {
        VStack(spacing: VA.Space.lg) {
            VAEmptyState(
                icon: "figure.strengthtraining.traditional",
                title: String(localized: "No Active Session", comment: "Empty state title on Workouts tab"),
                message: String(
                    localized: "Ready to train? Start a workout from the Today tab or begin one now.",
                    comment: "Empty state message on Workouts tab"
                ),
                action: (
                    label: String(localized: "Start Workout", comment: "Empty state action — begin a workout"),
                    handler: {
                        Task {
                            VAHaptics.sessionStart()
                            await model.startWorkoutSession()
                        }
                    }
                )
            )
            .frame(minHeight: 300)

            if !model.recentSessions.isEmpty {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    VASectionHeader(String(localized: "Recent History", comment: "Section header listing recent sessions"))
                    ForEach(Array(model.recentSessions.prefix(5).enumerated()), id: \.offset) { _, session in
                        VACard(style: .flat) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.date.formatted(.dateTime.month().day()))
                                        .font(VA.Typography.headline)
                                    Text(String(
                                        localized: "^[\(session.completedSetCount) sets](inflect: true)",
                                        comment: "Recent history row — pluralized set count"
                                    ))
                                    .font(VA.Typography.footnote)
                                    .foregroundStyle(VA.Colors.textSecondary)
                                }
                                Spacer()
                                Text(String(
                                    localized: "\(Int(session.totalVolumeLoad)) lb load",
                                    comment: "Recent history row — total volume load"
                                ))
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
