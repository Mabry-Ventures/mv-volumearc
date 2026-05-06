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
            LazyVStack(alignment: .leading, spacing: VA.Space.xl) {
                greeting
                if model.hasLoadedInitialData {
                    nextWorkoutCard
                    quickActionsRow
                    planTomorrowCard
                    coachBriefingCard
                    overviewMetrics
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
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }

    // MARK: - Greeting

    private var greeting: some View {
        HStack(alignment: .bottom, spacing: VA.Space.lg) {
            VStack(alignment: .leading, spacing: VA.Space.xs) {
                Text(todayLabel)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                Text(welcomeText)
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: VA.Space.md)
            avatar
        }
        .padding(.top, VA.Space.sm)
    }

    private var firstName: String {
        model.athlete.name.split(separator: " ").first.map(String.init) ?? model.athlete.name
    }

    private var welcomeText: String {
        if model.athlete.name.isEmpty {
            return greetingText
        }
        return String(localized: "\(greetingText), \(firstName)", comment: "Dashboard greeting with the athlete's first name")
    }

    private var todayLabel: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
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

    private var initials: String {
        model.athlete.initials
    }

    private var avatar: some View {
        Text(initials)
            .font(VA.Typography.footnote)
            .foregroundStyle(VA.Colors.textOnPrimary)
            .frame(width: VA.Space.avatar, height: VA.Space.avatar)
            .background(
                LinearGradient(
                    colors: [VA.Colors.sunriseA, VA.Colors.sunriseC],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .vaShadow(.md)
            .accessibilityLabel(String(
                localized: "Profile for \(avatarName)",
                comment: "VoiceOver label for the Today screen profile avatar"
            ))
    }

    private var avatarName: String {
        model.athlete.name.isEmpty ? String(localized: "VolumeArc") : model.athlete.name
    }

    // MARK: - Overview metrics

    private var overviewMetrics: some View {
        TodayOverviewMetrics(
            readiness: model.readiness,
            weeklyVolumeLoad: weeklyVolumeLoad,
            sparklineValues: weeklySparklineValues,
            trendLabel: volumeTrendLabel,
            trendIsPositive: volumeTrendIsPositive
        )
    }

    // MARK: - Next workout card

    @ViewBuilder
    private var nextWorkoutCard: some View {
        if let autopilot = model.autopilot {
            let workoutTitle = model.nextWorkout?.title ?? String(
                localized: "Strength Session",
                comment: "Default workout title when no plan name is available"
            )
            let targetLine = targetLine(for: autopilot)
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
                        .fill(VA.Colors.textOnPrimary.opacity(VA.Opacity.heroGlow))
                        .frame(width: VA.Space.heroGlowSize, height: VA.Space.heroGlowSize)
                        .blur(radius: VA.Space.heroGlowBlur)
                        .offset(x: VA.Space.heroGlowOffsetX, y: VA.Space.heroGlowOffsetY)

                    VStack(alignment: .leading, spacing: VA.Space.lg) {
                        VStack(alignment: .leading, spacing: VA.Space.xs) {
                            Text(String(
                                localized: "NEXT WORKOUT",
                                comment: "Section label above the hero next-workout card"
                            ))
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textOnPrimary.opacity(VA.Opacity.textMutedOnPrimary))
                            .tracking(VA.Typography.eyebrowTracking)
                            Text(workoutTitle)
                                .font(VA.Typography.title)
                                .foregroundStyle(VA.Colors.textOnPrimary)
                            Text(autopilot.nextExerciseName)
                                .font(VA.Typography.body)
                                .foregroundStyle(VA.Colors.textOnPrimary.opacity(VA.Opacity.textSecondaryOnPrimary))
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
                            .background(
                                VA.Colors.textOnPrimary.opacity(VA.Opacity.elevatedSurfaceOnPrimary),
                                in: Capsule()
                            )

                            Text(targetLine)
                                .font(VA.Typography.footnote)
                                .foregroundStyle(VA.Colors.textOnPrimary.opacity(VA.Opacity.textMutedOnPrimary))
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
                        .stroke(
                            VA.Colors.textOnPrimary.opacity(VA.Opacity.strokeOnPrimary),
                            lineWidth: VA.Space.border
                        )
                }
                .vaShadow(.lg)
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

    // MARK: - Planning and coach briefing

    private var planTomorrowCard: some View {
        Button {
            VAHaptics.tap()
            navigation.openCoach(prompt: String(
                localized: "Help me plan tomorrow's workout.",
                comment: "Default coach prompt from the Today plan tomorrow card"
            ))
        } label: {
            HStack(spacing: VA.Space.zero) {
                ZStack {
                    LinearGradient(
                        colors: [
                            VA.Colors.primary.opacity(VA.Opacity.iconPanelPrimary),
                            VA.Colors.sunriseC.opacity(VA.Opacity.iconPanelAccent),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(VA.Typography.title)
                        .foregroundStyle(VA.Colors.primary)
                }
                .frame(width: VA.Space.actionMediaRail)

                HStack(alignment: .center, spacing: VA.Space.md) {
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(String(localized: "WITH COACH", comment: "Plan tomorrow card eyebrow"))
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.primary)
                            .tracking(VA.Typography.eyebrowTracking)
                        Text(String(localized: "Plan tomorrow", comment: "Plan tomorrow card title"))
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(planTomorrowSubtitle)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: VA.Space.sm)
                    Image(systemName: "chevron.right")
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textTertiary)
                }
                .padding(.horizontal, VA.Space.lg)
                .padding(.vertical, VA.Space.md)
            }
            .frame(maxWidth: .infinity, minHeight: VA.Space.actionCardMinHeight, alignment: .leading)
            .background(VA.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous)
                    .stroke(VA.Colors.textTertiary.opacity(VA.Opacity.subtleSeparator), lineWidth: VA.Space.hairline)
            }
            .clipShape(RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
            .vaShadow(.sm)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.planTomorrow")
    }

    private var coachBriefingCard: some View {
        Button {
            VAHaptics.tap()
            navigation.openCoach(prompt: String(
                localized: "Brief me on today's training plan.",
                comment: "Default coach prompt from the Today coach briefing card"
            ))
        } label: {
            HStack(alignment: .top, spacing: VA.Space.md) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.primary)
                    .frame(width: VA.Space.iconBadge, height: VA.Space.iconBadge)
                    .background(VA.Colors.primary.opacity(VA.Opacity.subtleFill), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: VA.Space.xs) {
                    Text(String(localized: "Coach briefing", comment: "Today coach briefing card title"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                    Text(coachBriefingText)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: VA.Space.sm)
                Image(systemName: "chevron.right")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textTertiary)
                    .padding(.top, VA.Space.xs)
            }
            .padding(.horizontal, VA.Space.lg)
            .padding(.vertical, VA.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .vaGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.coachBriefing")
    }

    // MARK: - Recent sessions

    private var recentSessionsSection: some View {
        let count = weeklyVolumeSummary.currentWeekSessionCount
        let subtitle = count == 1
            ? String(localized: "1 session this week", comment: "Recent sessions subtitle, singular form")
            : String(localized: "\(count) sessions this week", comment: "Recent sessions subtitle, zero or plural form")
        return VStack(alignment: .leading, spacing: VA.Space.md) {
            VASectionHeader(
                String(localized: "Recent", comment: "Section header on Today tab for recent workout history"),
                subtitle: subtitle,
                action: (
                    label: String(localized: "See all", comment: "Recent sessions section action to open Workouts"),
                    handler: { navigation.selectedTab = .workouts }
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
                    Circle()
                        .fill(VA.Colors.primary.opacity(VA.Opacity.prominentFill))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(session.date.formatted(.dateTime.weekday(.wide).month().day()))
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        let rpeText = String(format: "%.1f", session.averageRPE)
                        let setsText = session.completedSetCount == 1
                            ? String(localized: "1 set", comment: "Session summary set count, singular")
                            : String(localized: "\(session.completedSetCount) sets", comment: "Session summary set count, plural")
                        Text("\(setsText) • \(session.durationMinutes)min • RPE \(rpeText)")
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
                        .font(VA.Typography.caption)
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

    // MARK: - Derived display values

    private var planTomorrowSubtitle: String {
        let title = model.nextWorkout?.title ?? String(
            localized: "Next training day",
            comment: "Fallback title in the Today plan tomorrow card"
        )
        return String(
            localized: "\(title) queued — review and tweak together",
            comment: "Plan tomorrow card subtitle describing the next queued workout"
        )
    }

    private var coachBriefingText: String {
        guard let autopilot = model.autopilot else {
            return String(
                localized: "Readiness \(model.readiness.score). Finish onboarding or log a session to unlock a grounded training brief.",
                comment: "Coach briefing fallback when no recommendation is available"
            )
        }

        let target = targetLine(for: autopilot)
        return String(
            localized: """
                Readiness \(model.readiness.score). \(autopilot.nextExerciseName) \
                is queued at \(target) — \(autopilot.recommendationReason)
                """,
            comment: "Coach briefing summary using readiness, next lift target, and recommendation reason"
        )
    }

    private var weeklyVolumeLoad: Double {
        weeklyVolumeSummary.currentVolumeLoad
    }

    private var weeklySparklineValues: [Double] {
        weeklyVolumeSummary.sparklineValues
    }

    private var volumeTrendPercent: Int? {
        weeklyVolumeSummary.trendPercent
    }

    private var volumeTrendLabel: String {
        guard let percent = volumeTrendPercent else {
            return String(localized: "On track", comment: "Weekly volume neutral trend label")
        }
        if percent > 0 {
            return String(localized: "+\(percent)%", comment: "Weekly volume positive trend label")
        }
        return percent == 0
            ? String(localized: "Flat", comment: "Weekly volume flat trend label")
            : String(localized: "\(percent)%", comment: "Weekly volume negative trend label")
    }

    private var volumeTrendIsPositive: Bool {
        (volumeTrendPercent ?? 0) > 0
    }

    private var weeklyVolumeSummary: TodayWeeklyVolumeSummary {
        TodayWeeklyVolumeSummary(sessions: model.recentSessions)
    }

    private func targetLine(for autopilot: WorkoutAutopilotState) -> String {
        let weight = autopilot.nextTarget.weight.formatted(.number.precision(.fractionLength(0...1)))
        let unit = autopilot.nextTarget.unit
        let repRange = autopilot.nextTarget.repRange
        let rpe = String(format: "%.1f", autopilot.nextTarget.targetRPE)
        return String(
            localized: "\(weight)\(unit) × \(repRange.lowerBound)-\(repRange.upperBound) @ RPE \(rpe)",
            comment: "Target line: weight × rep range @ target RPE for the next set"
        )
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
                    .font(VA.Typography.headline)
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
