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
                    nextWorkoutCard
                    quickActionsRow
                    readinessCard
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
        // VOL-99: identifier for the perf scroll test to find the
        // ScrollView and swipe across it.
        .accessibilityIdentifier("today.scroll")
        .background(VA.Colors.surfaceGrouped)
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
            let weight = Int(autopilot.nextTarget.weight)
            let unit = autopilot.nextTarget.unit
            let repRange = autopilot.nextTarget.repRange
            let rpe = String(format: "%.1f", autopilot.nextTarget.targetRPE)
            let targetLine = String(
                localized: "\(weight)\(unit) × \(repRange.lowerBound)-\(repRange.upperBound) @ RPE \(rpe)",
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
                ZStack(alignment: .topTrailing) {
                    VA.Gradients.sunriseHero
                    Circle()
                        .fill(.white.opacity(0.26))
                        .frame(width: 220, height: 220)
                        .blur(radius: 10)
                        .offset(x: 72, y: -78)

                    VStack(alignment: .leading, spacing: VA.Space.lg) {
                        VStack(alignment: .leading, spacing: VA.Space.xs) {
                            Text(String(
                                localized: "NEXT WORKOUT",
                                comment: "Section label above the hero next-workout card"
                            ))
                            .font(VA.Typography.caption)
                            .foregroundStyle(.white.opacity(0.78))
                            .tracking(0.6)
                            Text(workoutTitle)
                                .font(VA.Typography.title)
                                .foregroundStyle(.white)
                            Text(autopilot.nextExerciseName)
                                .font(VA.Typography.body)
                                .foregroundStyle(.white.opacity(0.88))
                        }

                        HStack(spacing: VA.Space.md) {
                            Label(
                                String(localized: "Start workout", comment: "Hero card call-to-action label"),
                                systemImage: "arrow.right"
                            )
                            .font(VA.Typography.button)
                            .foregroundStyle(VA.Colors.primaryDeep)
                            .padding(.horizontal, VA.Space.lg)
                            .frame(height: 46)
                            .background(.white.opacity(0.96), in: Capsule())

                            Text(targetLine)
                                .font(VA.Typography.footnote)
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .padding(.horizontal, VA.Space.xl)
                    .padding(.vertical, VA.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipShape(RoundedRectangle(cornerRadius: VA.Radius.xl, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VA.Radius.xl, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: VA.Colors.primary.opacity(0.22), radius: 24, x: 0, y: 14)
                .matchedTransitionSource(id: "next-workout-hero", in: heroNamespace)
            }
            .buttonStyle(.plain)
            // VOL-93: stable identifier for the XCUITest journey suite so
            // `testOnboardingToFirstWorkout` can assert the dashboard has a
            // workout ready once onboarding finishes. Pinned at the
            // NavigationLink root so the entire hero card lookup resolves
            // reliably regardless of SwiftUI's inner hosting layer.
            .accessibilityIdentifier("today.nextWorkoutCard")
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
            .accessibilityIdentifier("today.startWorkout")

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
            // VOL-99: `testCoachFirstTokenLatency` taps this to route
            // into the Coach tab, so it needs a stable identifier.
            .accessibilityIdentifier("today.askCoach")
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
                // VOL-99: perf-test mode renders the full recent-session
                // pool so the scroll perf test can measure frame rate
                // and hitches across a realistic list length (50 rows).
                let visibleSessions = VolumeArcRuntimeFlags.isPerformanceTestMode
                    ? Array(model.recentSessions)
                    : Array(model.recentSessions.prefix(3))
                ForEach(Array(visibleSessions.enumerated()), id: \.offset) { _, session in
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
                        let rpeText = String(format: "%.1f", session.averageRPE)
                        Text(String(
                            localized: "^[\(session.completedSetCount) sets](inflect: true) • \(session.durationMinutes)min • RPE \(rpeText)",
                            comment: """
                                Session summary metrics showing sets, duration, \
                                and average RPE — sets uses plural agreement
                                """
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
