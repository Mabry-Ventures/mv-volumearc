#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import VolumeArcCore

struct WorkoutIdleLibrary: View {
    let featuredTitle: String
    let featuredFocus: String
    let startWorkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.xl) {
            featuredWorkoutCard
            thisWeekSection
            templatesSection
        }
    }

    private var featuredWorkoutCard: some View {
        Button(action: startWorkout) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [VA.Colors.sunriseA, VA.Colors.sunriseB, VA.Colors.sunriseC],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(VA.Typography.onboardingIcon)
                    .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.26))
                    .offset(x: 18, y: -18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: VA.Space.sm) {
                    Text(String(localized: "SCHEDULED · TODAY", comment: "Featured workout scheduled label"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.84))
                        .tracking(0.6)
                    Text(featuredTitle)
                        .font(VA.Typography.title)
                        .foregroundStyle(VA.Colors.textOnPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    Text(featuredFocus)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.86))
                        .lineLimit(2)
                    featuredMeta
                    featuredStartPill
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(VA.Space.xl)
            }
            .frame(maxWidth: .infinity, minHeight: 230, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: VA.Radius.xl, style: .continuous))
            .vaShadow(.lg)
        }
        .buttonStyle(.plain)
    }

    private var featuredMeta: some View {
        HStack(spacing: VA.Space.sm) {
            Text(String(localized: "45 min", comment: "Featured workout duration"))
            Text("·").foregroundStyle(VA.Colors.textOnPrimary.opacity(0.58))
            Text(String(localized: "5 exercises", comment: "Featured workout exercise count"))
        }
        .font(VA.Typography.footnote)
        .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.9))
    }

    private var featuredStartPill: some View {
        HStack(spacing: VA.Space.sm) {
            Image(systemName: "arrow.right")
                .font(VA.Typography.caption)
            Text(String(localized: "Start workout", comment: "Featured workout start label"))
                .font(VA.Typography.button)
        }
        .foregroundStyle(VA.Colors.primaryDeep)
        .padding(.horizontal, VA.Space.lg)
        .padding(.vertical, VA.Space.md)
        .background(VA.Colors.textOnPrimary.opacity(0.96), in: Capsule())
        .padding(.top, VA.Space.xs)
    }

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            VASectionHeader(
                String(localized: "This week", comment: "Workouts this week section")
            )
            VStack(spacing: VA.Space.md) {
                workoutPlanRow(
                    title: String(localized: "Pull A", comment: "Workout library row title"),
                    focus: String(localized: "Back · Biceps", comment: "Workout library row focus"),
                    schedule: String(localized: "Sat", comment: "Workout library row schedule"),
                    icon: "dumbbell.fill",
                    duration: 50,
                    exercises: 6
                )
                workoutPlanRow(
                    title: String(localized: "Legs", comment: "Workout library row title"),
                    focus: String(localized: "Quads · Hams · Glutes", comment: "Workout library row focus"),
                    schedule: String(localized: "Mon", comment: "Workout library row schedule"),
                    icon: "figure.strengthtraining.traditional",
                    duration: 55,
                    exercises: 5
                )
                workoutPlanRow(
                    title: String(localized: "Mobility", comment: "Workout library row title"),
                    focus: String(localized: "Hips · T-spine", comment: "Workout library row focus"),
                    schedule: String(localized: "Wed", comment: "Workout library row schedule"),
                    icon: "figure.cooldown",
                    duration: 20,
                    exercises: 8
                )
            }
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            Text(String(localized: "Templates", comment: "Workout templates section title"))
                .font(VA.Typography.title2)
                .foregroundStyle(VA.Colors.textPrimary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VA.Space.md) {
                    ForEach(Self.templates) { template in
                        templateCard(template)
                    }
                }
                VStack(spacing: VA.Space.md) {
                    ForEach(Self.templates) { template in
                        templateCard(template)
                    }
                }
            }
        }
    }

    private func workoutPlanRow(
        title: String,
        focus: String,
        schedule: String,
        icon: String,
        duration: Int,
        exercises: Int
    ) -> some View {
        Button(action: startWorkout) {
            VACard(style: .flat) {
                HStack(alignment: .center, spacing: VA.Space.md) {
                    WorkoutIllustrationTile(systemImage: icon, size: 64, accent: VA.Colors.primary)
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        HStack(spacing: VA.Space.xs) {
                            Text(title)
                                .font(VA.Typography.headline)
                                .foregroundStyle(VA.Colors.textPrimary)
                            WorkoutChip(text: schedule, tone: .neutral)
                        }
                        Text(focus)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                        Text(String(
                            localized: "\(duration) min · \(workoutSurfaceLocalizedExerciseCount(exercises))",
                            comment: "Workout library row duration and exercise count"
                        ))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func templateCard(_ template: WorkoutTemplateSummary) -> some View {
        Button(action: startWorkout) {
            VACard(style: .elevated) {
                VStack(alignment: .leading, spacing: VA.Space.sm) {
                    WorkoutIllustrationTile(systemImage: template.icon, size: 72, accent: VA.Colors.primary)
                    Text(template.title)
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(String(localized: "\(template.duration) min", comment: "Workout template duration"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                    Text(template.detail)
                        .font(VA.Typography.captionLarge)
                        .foregroundStyle(VA.Colors.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private static var templates: [WorkoutTemplateSummary] {
        [
            WorkoutTemplateSummary(
                title: String(localized: "Upper Strength", comment: "Workout template title"),
                detail: String(localized: "Press, pull, accessories", comment: "Workout template detail"),
                duration: 50,
                icon: "dumbbell.fill"
            ),
            WorkoutTemplateSummary(
                title: String(localized: "Lower Strength", comment: "Workout template title"),
                detail: String(localized: "Squat, hinge, trunk", comment: "Workout template detail"),
                duration: 55,
                icon: "figure.strengthtraining.traditional"
            ),
            WorkoutTemplateSummary(
                title: String(localized: "Full Body", comment: "Workout template title"),
                detail: String(localized: "Three big patterns", comment: "Workout template detail"),
                duration: 45,
                icon: "figure.mixed.cardio"
            ),
            WorkoutTemplateSummary(
                title: String(localized: "Conditioning", comment: "Workout template title"),
                detail: String(localized: "Short intervals, clean form", comment: "Workout template detail"),
                duration: 24,
                icon: "figure.run"
            ),
            WorkoutTemplateSummary(
                title: String(localized: "Recovery Lift", comment: "Workout template title"),
                detail: String(localized: "Easy technique and mobility", comment: "Workout template detail"),
                duration: 28,
                icon: "figure.cooldown"
            ),
        ]
    }
}

private struct WorkoutTemplateSummary: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let duration: Int
    let icon: String
}

struct WorkoutBuilderCard: View {
    let profileSummary: String
    let startManual: () -> Void
    let askCoach: () -> Void

    var body: some View {
        VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.lg) {
                HStack(alignment: .top, spacing: VA.Space.md) {
                    Image(systemName: "slider.horizontal.3")
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.primary)
                        .frame(width: 44, height: 44)
                        .background(VA.Colors.primary.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(String(localized: "Build a workout", comment: "Workouts builder card title"))
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(String(
                            localized: "Start \(profileSummary) now, or ask the coach to design a session you can schedule.",
                            comment: "Workouts builder card subtitle"
                        ))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: VA.Space.md) { actions }
                    VStack(spacing: VA.Space.md) { actions }
                }
            }
        }
        .accessibilityIdentifier("workouts.builder")
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actions: some View {
        VAButton(
            String(localized: "Manual start", comment: "Workouts manual builder action"),
            icon: "plus",
            style: .primary,
            accessibilityIdentifier: "workouts.builder.manual",
            action: startManual
        )
        VAButton(
            String(localized: "Ask Coach", comment: "Workouts coach builder action"),
            icon: "brain.head.profile",
            style: .secondary,
            accessibilityIdentifier: "workouts.builder.coach",
            action: askCoach
        )
    }
}

struct WorkoutHistorySection: View {
    let sessions: [RecentSession]
    let onOpen: (RecentSession) -> Void
    let onDelete: (RecentSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            VASectionHeader(
                String(localized: "History", comment: "Workouts history section title"),
                subtitle: subtitle
            )
            ForEach(Array(visibleSessions.enumerated()), id: \.offset) { _, session in
                historyRow(session)
            }
        }
    }

    private var visibleSessions: [RecentSession] {
        VolumeArcRuntimeFlags.isPerformanceTestMode ? sessions : Array(sessions.prefix(5))
    }

    private var subtitle: String {
        sessions.count == 1
            ? String(localized: "1 completed session", comment: "Workouts history subtitle, singular")
            : String(localized: "\(sessions.count) completed sessions", comment: "Workouts history subtitle, plural")
    }

    private func historyRow(_ session: RecentSession) -> some View {
        HStack(alignment: .center, spacing: VA.Space.sm) {
            NavigationLink {
                SessionDetailView(session: session) {
                    onOpen(session)
                }
            } label: {
                historyRowCard(session)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityHint(String(
                localized: "Opens this session's details",
                comment: "Accessibility hint for tapping a workout history row"
            ))
            .accessibilityIdentifier("workouts.historyRow")

            if session.isUserDeletable {
                Button(role: .destructive) {
                    onDelete(session)
                } label: {
                    Image(systemName: "trash")
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.error)
                        .frame(width: 44, height: 44)
                        .background(VA.Colors.error.opacity(VA.Opacity.subtleFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(
                    localized: "Delete session",
                    comment: "VoiceOver label for workout history delete button"
                ))
                .accessibilityHint(String(
                    localized: "Asks for confirmation before removing this session from history.",
                    comment: "VoiceOver hint for workout history delete button"
                ))
                .accessibilityIdentifier(deleteIdentifier(for: session))
            }
        }
    }

    private func historyRowCard(_ session: RecentSession) -> some View {
        VACard(style: .flat) {
            HStack(spacing: VA.Space.md) {
                WorkoutIllustrationTile(systemImage: "checkmark.circle.fill", size: 52, accent: VA.Colors.success)
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(title(for: session))
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(summary(for: session))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer()
                VAMetricDisplay(
                    label: metricLabel(for: session),
                    value: metricValue(for: session),
                    unit: metricUnit(for: session),
                    style: .compact
                )
                Image(systemName: "chevron.right")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textTertiary)
            }
        }
    }

    private func deleteIdentifier(for session: RecentSession) -> String {
        guard let identifier = session.identifier else { return "workouts.deleteSession" }
        let safeIdentifier = identifier
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return "workouts.deleteSession.\(safeIdentifier)"
    }

    private func title(for session: RecentSession) -> String {
        if session.isExternalHealthSession, let title = session.title, !title.isEmpty {
            return title
        }
        return session.date.formatted(.dateTime.weekday(.wide).month().day())
    }

    private func summary(for session: RecentSession) -> String {
        if session.isExternalHealthSession {
            let source = session.sourceName ?? String(localized: "Apple Health", comment: "Fallback source for HealthKit workouts")
            return "\(source) - \(session.durationMinutes)min"
        }
        let rpeText = String(format: "%.1f", session.averageRPE)
        let setsText = workoutSurfaceLocalizedSetCount(session.completedSetCount)
        return "\(setsText) - \(session.durationMinutes)min - RPE \(rpeText)"
    }

    private func metricLabel(for session: RecentSession) -> String {
        session.isExternalHealthSession
            ? String(localized: "Time", comment: "Metric label for HealthKit workout duration")
            : String(localized: "Load", comment: "Metric label for total weight lifted in a session")
    }

    private func metricValue(for session: RecentSession) -> String {
        session.isExternalHealthSession ? "\(session.durationMinutes)" : "\(Int(session.totalVolumeLoad))"
    }

    private func metricUnit(for session: RecentSession) -> String {
        session.isExternalHealthSession
            ? String(localized: "min", comment: "Minute unit abbreviation")
            : String(localized: "lb", comment: "Weight unit abbreviation - pounds")
    }
}

struct WorkoutChip: View {
    enum Tone {
        case neutral
        case primary
        case success
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(VA.Typography.caption)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, VA.Space.sm)
            .padding(.vertical, VA.Space.xs)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return VA.Colors.textSecondary
        case .primary: return VA.Colors.primary
        case .success: return VA.Colors.success
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return VA.Colors.textTertiary.opacity(0.12)
        case .primary: return VA.Colors.primary.opacity(0.14)
        case .success: return VA.Colors.success.opacity(0.14)
        }
    }
}

struct WorkoutIllustrationTile: View {
    let systemImage: String
    let size: CGFloat
    let accent: Color
    var illustrationAssetName: String?

    var body: some View {
        ZStack {
            tileContent
        }
        .frame(width: size, height: size)
        .background(VA.Colors.textTertiary.opacity(0.10), in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var tileContent: some View {
        #if canImport(UIKit)
        if let illustrationAssetName,
           let image = UIImage(named: illustrationAssetName, in: .main, compatibleWith: nil) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        } else {
            fallbackIcon
        }
        #else
        // On the shipping Apple app target these assets live in the main app
        // bundle. Non-UIKit preview/test hosts fall back if the bundle does not
        // expose asset lookup.
        if let illustrationAssetName {
            Image(illustrationAssetName, bundle: .main)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        } else {
            fallbackIcon
        }
        #endif
    }

    private var fallbackIcon: some View {
        Image(systemName: systemImage)
            .font(size >= 80 ? VA.Typography.title : VA.Typography.headline)
            .foregroundStyle(accent)
    }
}

struct SetLogRow: View {
    let setNumber: Int
    let isDone: Bool
    let target: String
    let rpe: Double

    var body: some View {
        HStack(spacing: VA.Space.md) {
            completionGlyph
            Text(String(localized: "Set \(setNumber)", comment: "Active workout set log row label"))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .frame(width: 44, alignment: .leading)
            Text(target)
                .font(VA.Typography.monoDigit)
                .foregroundStyle(isDone ? VA.Colors.textPrimary : VA.Colors.textTertiary)
                .monospacedDigit()
            Spacer()
            Text(isDone ? String(format: "%.1f", rpe) : "—")
                .font(VA.Typography.monoDigit)
                .foregroundStyle(isDone ? VA.Colors.textPrimary : VA.Colors.textTertiary)
                .monospacedDigit()
        }
        .padding(.vertical, VA.Space.sm)
        .accessibilityElement(children: .combine)
    }

    private var completionGlyph: some View {
        ZStack {
            Circle()
                .fill(isDone ? VA.Colors.success : VA.Colors.textTertiary.opacity(0.14))
            if isDone {
                Image(systemName: "checkmark")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textOnPrimary)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// Dedicated subview for the rest timer so only this view re-renders each second,
/// not the whole WorkoutsView.
struct RestTimerDisplay: View {
    let endsAt: Date
    let active: Bool
    let totalDuration: TimeInterval
    let onComplete: () -> Void

    @State private var lastFired: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endsAt.timeIntervalSince(context.date)))
            let total: TimeInterval = max(1, totalDuration)
            let elapsed = total - endsAt.timeIntervalSince(context.date)
            let progress = max(0, min(1, elapsed / total))

            restRing(remaining: remaining, progress: progress)
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Rest timer", comment: "Rest timer accessibility label"))
                .accessibilityValue(
                    remaining == 0
                        ? String(localized: "Go time", comment: "Rest timer complete accessibility value")
                        : String(
                            localized: "\(workoutSurfaceLocalizedSecondCount(remaining)) remaining",
                            comment: "Rest timer countdown accessibility value"
                        )
                )
                .task(id: remaining) {
                    updateCompletionState(remaining: remaining)
                }
                .onChange(of: remaining) { _, newValue in
                    updateCompletionState(remaining: newValue)
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 212)
        .accessibilityIdentifier("workouts.restTimer")
    }

    private func restRing(remaining: Int, progress: Double) -> some View {
        ZStack {
            VAProgressRing(
                progress: progress,
                lineWidth: 10,
                color: remaining == 0 ? VA.Colors.success : VA.Colors.primary
            )
            .frame(width: 190, height: 190)
            VStack(spacing: VA.Space.xs) {
                Text(restDisplay(remaining))
                    .font(VA.Typography.timerDisplay)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                Text(remaining == 0 ? "GO" : "seconds")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(1)
            }
        }
    }

    private func restDisplay(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    @MainActor
    private func updateCompletionState(remaining: Int) {
        if active && remaining == 0 && !lastFired {
            lastFired = true
            onComplete()
        }
        if remaining > 0 {
            lastFired = false
        }
    }
}

private func workoutSurfaceLocalizedExerciseCount(_ count: Int) -> String {
    if count == 1 {
        return String(localized: "1 exercise", comment: "Singular workout exercise count")
    }
    return String(
        localized: "\(count) exercises",
        comment: "Plural workout exercise count; placeholder is the number of exercises"
    )
}

private func workoutSurfaceLocalizedSetCount(_ count: Int) -> String {
    if count == 1 {
        return String(localized: "1 set", comment: "Singular session summary set count")
    }
    return String(
        localized: "\(count) sets",
        comment: "Plural session summary set count; placeholder is the number of sets"
    )
}

private func workoutSurfaceLocalizedSecondCount(_ count: Int) -> String {
    if count == 1 {
        return String(localized: "1 second", comment: "Singular rest timer duration in seconds")
    }
    return String(
        localized: "\(count) seconds",
        comment: "Plural rest timer duration in seconds; placeholder is the number of seconds"
    )
}
#endif
