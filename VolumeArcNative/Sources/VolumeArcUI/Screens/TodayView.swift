#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Today tab — hero card with next workout, readiness, quick actions, and recent sessions.
public struct TodayView: View {
    @ObservedObject var model: WorkoutDashboardModel
    @ObservedObject var navigation: DashboardNavigationModel
    @Namespace private var heroNamespace

    public init(model: WorkoutDashboardModel, navigation: DashboardNavigationModel) {
        self.model = model
        self.navigation = navigation
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VA.Space.lg) {
                greeting
                if model.hasLoadedInitialData {
                    readinessCard
                    nextWorkoutCard
                    quickActionsRow
                    recentSessionsSection
                    if !model.operationalSignals.isEmpty {
                        signalsSection
                    }
                } else {
                    // Skeleton loading state for first load — shows while
                    // repositories are fetched on appear.
                    VASkeletonCard()
                    VASkeletonCard()
                    VASkeletonList(count: 2)
                }
            }
            .padding(VA.Space.lg)
        }
        .background(VA.Colors.surfaceSecondary)
        .navigationTitle(DashboardTab.today.title)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.refresh() }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(greetingText)
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(welcomeText)
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
        }
    }

    private var firstName: String {
        model.athlete.name.split(separator: " ").first.map(String.init) ?? model.athlete.name
    }

    private var welcomeText: String {
        if model.athlete.name.isEmpty {
            return String(localized: "Welcome back", comment: "Dashboard greeting when no name is set")
        }
        return String(localized: "Welcome back, \(firstName)", comment: "Dashboard greeting with the athlete's first name")
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 4..<12:
            return String(localized: "Good morning", comment: "Morning greeting header")
        case 12..<17:
            return String(localized: "Good afternoon", comment: "Afternoon greeting header")
        case 17..<22:
            return String(localized: "Good evening", comment: "Evening greeting header")
        default:
            return String(localized: "Hey there", comment: "Late-night greeting header")
        }
    }

    // MARK: - Readiness card

    private var readinessCard: some View {
        VACard(style: .accent) {
            HStack(alignment: .center, spacing: VA.Space.lg) {
                ZStack {
                    VAProgressRing(progress: Double(model.readiness.score) / 100, lineWidth: 10)
                        .frame(width: 88, height: 88)
                    VStack(spacing: 0) {
                        Text("\(model.readiness.score)")
                            .font(VA.Typography.display)
                            .foregroundStyle(VA.Colors.textPrimary)
                            .contentTransition(.numericText())
                        Text(String(
                            localized: "READY",
                            comment: "Caption inside the readiness ring"
                        ))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(1)
                    }
                }
                .accessibilityLabel(String(
                    localized: "Readiness score \(model.readiness.score) out of 100",
                    comment: "VoiceOver label describing the readiness score value"
                ))

                VStack(alignment: .leading, spacing: VA.Space.xs) {
                    Text(String(
                        localized: "READINESS",
                        comment: "Label next to the readiness ring"
                    ))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.5)
                    Text(model.readiness.brief)
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textPrimary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Next workout card

    @ViewBuilder
    private var nextWorkoutCard: some View {
        if let autopilot = model.autopilot {
            let workoutTitle = model.nextWorkout?.title ?? String(
                localized: "Strength Session",
                comment: "Default workout title when no plan name is available"
            )
            let targetLine = String(
                localized: "\(Int(autopilot.nextTarget.weight))\(autopilot.nextTarget.unit) × \(autopilot.nextTarget.repRange.lowerBound)-\(autopilot.nextTarget.repRange.upperBound) @ RPE \(String(format: "%.1f", autopilot.nextTarget.targetRPE))",
                comment: "Target line: weight × rep range @ target RPE for the next set"
            )
            NavigationLink {
                WorkoutDetailView(
                    title: workoutTitle,
                    exerciseName: autopilot.nextExerciseName,
                    target: targetLine,
                    cue: autopilot.bestCue,
                    reason: autopilot.recommendationReason,
                    heroNamespace: heroNamespace
                )
                .navigationTransition(.zoom(sourceID: "next-workout-hero", in: heroNamespace))
            } label: {
                // Hero card adopts the real iOS 26 Liquid Glass treatment via
                // `VACard(style: .glass)`. The zoom hero transition itself is
                // unchanged.
                VACard(style: .glass) {
                    VStack(alignment: .leading, spacing: VA.Space.md) {
                        HStack {
                            VStack(alignment: .leading, spacing: VA.Space.xxs) {
                                Text(String(
                                    localized: "NEXT WORKOUT",
                                    comment: "Section label above the hero next-workout card"
                                ))
                                .font(VA.Typography.caption)
                                .foregroundStyle(VA.Colors.textSecondary)
                                .tracking(0.5)
                                Text(workoutTitle)
                                    .font(VA.Typography.title2)
                                    .foregroundStyle(VA.Colors.textPrimary)
                            }
                            Spacer()
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(VA.Colors.primary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: VA.Space.sm) {
                            Text(String(
                                localized: "Starting lift",
                                comment: "Label above the first exercise of the next workout"
                            ))
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .tracking(0.5)
                            Text(autopilot.nextExerciseName)
                                .font(VA.Typography.headline)
                                .foregroundStyle(VA.Colors.textPrimary)
                            Text(String(
                                localized: "\(Int(autopilot.nextTarget.weight))\(autopilot.nextTarget.unit) × \(autopilot.nextTarget.repRange.lowerBound)-\(autopilot.nextTarget.repRange.upperBound) @ RPE \(String(format: "%.1f", autopilot.nextTarget.targetRPE))",
                                comment: "Target line: weight × rep range @ target RPE for the next set"
                            ))
                            .font(VA.Typography.monoDigit)
                            .foregroundStyle(VA.Colors.primary)
                        }

                        Text(autopilot.recommendationReason)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .padding(.top, VA.Space.xs)
                    }
                }
                .matchedTransitionSource(id: "next-workout-hero", in: heroNamespace)
            }
            .buttonStyle(.plain)
        } else {
            VACard(style: .flat) {
                VAEmptyState(
                    icon: "sparkles",
                    title: String(localized: "No workout queued", comment: "Empty-state title when no autopilot recommendation is available"),
                    message: String(
                        localized: "Complete onboarding to get your first recommendation.",
                        comment: "Empty-state message when no autopilot recommendation is available"
                    ),
                    action: (
                        label: String(localized: "Get Started", comment: "Empty-state action — open onboarding"),
                        handler: { navigation.openProfile() }
                    )
                )
                .frame(minHeight: 180)
            }
        }
    }

    // MARK: - Quick actions

    private var quickActionsRow: some View {
        HStack(spacing: VA.Space.md) {
            VAButton(
                model.isSessionActive
                    ? String(localized: "Continue Session", comment: "Button to resume an in-progress workout")
                    : String(localized: "Start Workout", comment: "Button to begin a new workout"),
                icon: "play.fill",
                style: .primary
            ) {
                Task {
                    VAHaptics.sessionStart()
                    if !model.isSessionActive {
                        await model.startWorkoutSession()
                    }
                }
            }

            VAButton(
                String(localized: "Ask Coach", comment: "Quick action to open the AI coach"),
                icon: "waveform",
                style: .secondary
            ) {
                VAHaptics.tap()
                navigation.openCoach(prompt: String(
                    localized: "What should I focus on today?",
                    comment: "Default coach prompt when opening from quick action"
                ))
            }
        }
    }

    // MARK: - Recent sessions

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            VASectionHeader(
                String(localized: "Recent Sessions", comment: "Section header on Today tab for recent workout history"),
                subtitle: String(
                    localized: "^[\(model.recentSessions.count) this week](inflect: true)",
                    comment: "Subtitle showing how many sessions have been logged this week, with plural agreement"
                )
            )
            if model.recentSessions.isEmpty {
                VACard(style: .flat) {
                    Text(String(
                        localized: "No sessions logged yet. Start your first workout to see your history here.",
                        comment: "Empty-state message when there are no recent sessions"
                    ))
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                }
            } else {
                ForEach(Array(model.recentSessions.prefix(3).enumerated()), id: \.offset) { _, session in
                    sessionRow(session)
                }
            }
        }
    }

    private func sessionRow(_ session: RecentSession) -> some View {
        NavigationLink {
            SessionDetailView(session: session)
                .navigationTransition(.zoom(sourceID: session.date, in: heroNamespace))
        } label: {
            VACard(style: .flat) {
                HStack(spacing: VA.Space.md) {
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(session.date.formatted(.dateTime.weekday(.wide).month().day()))
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(String(
                            localized: "^[\(session.completedSetCount) sets](inflect: true) • \(session.durationMinutes)min • RPE \(String(format: "%.1f", session.averageRPE))",
                            comment: "Session summary metrics showing sets, duration, and average RPE — sets uses plural agreement"
                        ))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                    }
                    Spacer()
                    VAMetricDisplay(
                        label: String(localized: "Load", comment: "Metric label for total weight lifted in a session"),
                        value: "\(Int(session.totalVolumeLoad))",
                        unit: String(localized: "lb", comment: "Weight unit abbreviation — pounds"),
                        style: .compact
                    )
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VA.Colors.textTertiary)
                }
            }
            .matchedTransitionSource(id: session.date, in: heroNamespace)
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(
            localized: "Opens this session's details",
            comment: "Accessibility hint for tapping a recent session row"
        ))
    }

    // MARK: - Signals

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            VASectionHeader(String(
                localized: "System status",
                comment: "Section header on Today tab for operational signals"
            ))
            ForEach(model.operationalSignals, id: \.id) { signal in
                signalRow(signal)
            }
        }
    }

    private func signalRow(_ signal: OperationalSignalSummary) -> some View {
        VACard(style: .flat) {
            HStack(spacing: VA.Space.md) {
                Image(systemName: signalIcon(signal.severity))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(signalColor(signal.severity))
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(signal.title)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(signal.message)
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer()
            }
        }
    }

    private func signalIcon(_ severity: TelemetrySeverity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func signalColor(_ severity: TelemetrySeverity) -> Color {
        switch severity {
        case .info: return VA.Colors.info
        case .warning: return VA.Colors.warning
        case .error: return VA.Colors.error
        }
    }
}
#endif
