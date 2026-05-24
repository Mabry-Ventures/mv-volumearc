#if os(watchOS)
import SwiftUI
import WidgetKit
import VolumeArcCore

/// VOL-237: Smart Stack widget for the watchOS wrist-flick surface.
///
/// Apple positions Smart Stack as the surface for context-relevant
/// information. The existing `VolumeArcWatchComplication` powers watch
/// face complications — those are the "always-visible at a glance"
/// surface. The Smart Stack widget is distinct: it shows up when the
/// user flicks their wrist and is ranked by `RelevantContext` /
/// timeline-entry `relevance`. During an active workout this widget
/// surfaces the rest timer and next-set prescription so the lifter
/// never has to navigate into VolumeArc mid-set.
///
/// State sources:
///   * `LiveActivityState` (already populated by the iOS app during a
///     workout) drives the active-workout mode. When non-nil, render
///     the rest timer + target summary.
///   * `WidgetSummarySnapshot` (already populated by the iOS app at
///     every dashboard refresh) drives the idle mode. Render
///     readiness + the "push / hold / rest" recommendation derived
///     from the coach prompt.
///
/// Refresh policy:
///   * Active mode — every 30 seconds (the rest timer needs
///     freshness to stay glanceable).
///   * Idle mode — every hour (matches the existing complication's
///     refresh cadence; nothing actionable changes more often).
///
/// Relevance:
///   * Active mode — `RelevantContext` rank 100 (max). The Smart
///     Stack should bubble VolumeArc to the top of the wrist-flick
///     stack whenever a workout is in progress.
///   * Idle mode — relevance unset (default). Lets readiness
///     surface naturally in the stack but doesn't crowd out other
///     apps' active contexts.
struct VolumeArcSmartStackProvider: TimelineProvider {

    func placeholder(in context: Context) -> VolumeArcSmartStackEntry {
        VolumeArcSmartStackEntry(
            date: .now,
            mode: .idle(PlatformSurfaceFactory.makeEmptyWidgetSnapshot())
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (VolumeArcSmartStackEntry) -> Void
    ) {
        completion(currentEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<VolumeArcSmartStackEntry>) -> Void
    ) {
        let entry = currentEntry()
        let refreshInterval: TimeInterval
        switch entry.mode {
        case .active:
            refreshInterval = 30 // 30s — rest-timer freshness
        case .idle:
            refreshInterval = 60 * 60 // 1h — idle cadence
        }
        let next = Date.now.addingTimeInterval(refreshInterval)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> VolumeArcSmartStackEntry {
        if let liveActivity = PlatformSurfaceDefaultsReader.loadLiveActivityState() {
            return VolumeArcSmartStackEntry(date: .now, mode: .active(liveActivity))
        }
        let snapshot = PlatformSurfaceDefaultsReader.loadWidgetSnapshot()
            ?? PlatformSurfaceFactory.makeEmptyWidgetSnapshot()
        return VolumeArcSmartStackEntry(date: .now, mode: .idle(snapshot))
    }
}

struct VolumeArcSmartStackEntry: TimelineEntry {
    let date: Date
    let mode: Mode

    enum Mode {
        case active(LiveActivityState)
        case idle(WidgetSummarySnapshot)
    }

    /// Smart Stack ranks entries by this `relevance` value. iOS / watchOS
    /// picks high-ranked entries to surface on the wrist-flick surface.
    /// Active workout → max (100); idle stays unranked so the system's
    /// own heuristics pick the slot.
    var relevance: TimelineEntryRelevance? {
        switch mode {
        case .active:
            return TimelineEntryRelevance(score: 100)
        case .idle:
            return nil
        }
    }
}

/// SwiftUI view dispatched on widget family + mode. Each accessory
/// family gets a layout matched to the available glyph budget.
struct VolumeArcSmartStackView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VolumeArcSmartStackEntry

    var body: some View {
        switch entry.mode {
        case .active(let state):
            activeView(state)
        case .idle(let snapshot):
            idleView(snapshot)
        }
    }

    // MARK: - Active workout

    @ViewBuilder
    private func activeView(_ state: LiveActivityState) -> some View {
        // Codex review on PR #238 flagged that the previous layout
        // always paired a "0:00" countdown with a `REST` label when
        // `restSecondsRemaining` was nil, misrepresenting "actively
        // exercising" state as "resting." Split into a resting layout
        // (countdown + REST label) vs an active-set layout (no
        // countdown, SET label highlighting the exercise + target).
        // `LiveActivityState.restSecondsRemaining` is the authoritative
        // signal — nil OR <= 0 ⇒ no rest period.
        let isResting = (state.restSecondsRemaining ?? 0) > 0

        switch family {
        case .accessoryCircular:
            if isResting { restingCircular(state) } else { activeSetCircular(state) }
        case .accessoryRectangular:
            if isResting { restingRectangular(state) } else { activeSetRectangular(state) }
        case .accessoryInline:
            if isResting { restingInline(state) } else { activeSetInline(state) }
        case .accessoryCorner:
            if isResting { restingCorner(state) } else { activeSetCorner(state) }
        default:
            if isResting { restingRectangular(state) } else { activeSetRectangular(state) }
        }
    }

    // MARK: - Resting layouts (rest-timer countdown visible)

    private func restingCircular(_ state: LiveActivityState) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: VA.Space.xxs) {
                Text(restCountdownText(for: state))
                    .font(VA.Typography.scoreDisplay)
                    .monospacedDigit()
                Text(String(
                    localized: "REST",
                    comment: "Watch Smart Stack circular badge during active workout's rest timer"
                ))
                    .font(VA.Typography.microLabel)
                    .tracking(VA.Tracking.microLabel)
            }
        }
        .widgetURL(VolumeArcDeepLink.url(for: .nextWorkout))
    }

    private func restingRectangular(_ state: LiveActivityState) -> some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: VA.Space.xs) {
                Text(restCountdownText(for: state))
                    .font(VA.Typography.rectHeadline)
                    .monospacedDigit()
                Text(String(
                    localized: "REST",
                    comment: "Watch Smart Stack rectangular label next to the rest-timer countdown"
                ))
                    .font(VA.Typography.microLabel)
                    .tracking(VA.Tracking.microLabel)
                    .foregroundStyle(VA.Colors.textSecondary)
            }
            Text(state.activeExerciseName)
                .font(VA.Typography.rectCaption)
                .lineLimit(1)
            Text(state.targetSummary)
                .font(VA.Typography.rectFootnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .lineLimit(1)
        }
        .widgetURL(VolumeArcDeepLink.url(for: .nextWorkout))
    }

    private func restingInline(_ state: LiveActivityState) -> some View {
        Text(
            String(
                localized: "Rest \(restCountdownText(for: state)) • \(state.activeExerciseName)",
                comment: "Watch Smart Stack accessoryInline summary while resting; placeholders: rest-timer countdown, active exercise name"
            )
        )
            .widgetURL(VolumeArcDeepLink.url(for: .nextWorkout))
    }

    private func restingCorner(_ state: LiveActivityState) -> some View {
        Text(restCountdownText(for: state))
            .font(VA.Typography.scoreCompact)
            .monospacedDigit()
            .widgetLabel {
                Text(state.activeExerciseName)
                    .font(VA.Typography.rectCaption)
                    .lineLimit(1)
            }
            .widgetURL(VolumeArcDeepLink.url(for: .nextWorkout))
    }

    // MARK: - Active-set layouts (between rest periods — no countdown)

    private func activeSetCircular(_ state: LiveActivityState) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: VA.Space.xxs) {
                // No rest countdown — surface the exercise as the
                // glanceable identity instead. Aggressively truncated
                // because the circular family is small.
                Text(state.activeExerciseName.prefix(4).uppercased())
                    .font(VA.Typography.scoreDisplay)
                    .lineLimit(1)
                Text(String(
                    localized: "SET",
                    comment: "Watch Smart Stack circular badge while user is actively executing a set (not resting)"
                ))
                    .font(VA.Typography.microLabel)
                    .tracking(VA.Tracking.microLabel)
            }
        }
        .widgetURL(VolumeArcDeepLink.url(for: .nextWorkout))
    }

    private func activeSetRectangular(_ state: LiveActivityState) -> some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: VA.Space.xs) {
                Text(state.activeExerciseName)
                    .font(VA.Typography.rectHeadline)
                    .lineLimit(1)
                Text(String(
                    localized: "SET",
                    comment: "Watch Smart Stack rectangular label while user is actively executing a set"
                ))
                    .font(VA.Typography.microLabel)
                    .tracking(VA.Tracking.microLabel)
                    .foregroundStyle(VA.Colors.textSecondary)
            }
            Text(state.targetSummary)
                .font(VA.Typography.rectCaption)
                .lineLimit(1)
            Text(String(
                localized: "Tap to log",
                comment: "Watch Smart Stack call-to-action while a set is in progress"
            ))
                .font(VA.Typography.rectFootnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .lineLimit(1)
        }
        .widgetURL(VolumeArcDeepLink.url(for: .nextWorkout))
    }

    private func activeSetInline(_ state: LiveActivityState) -> some View {
        Text(
            String(
                localized: "\(state.activeExerciseName) • \(state.targetSummary)",
                comment: "Watch Smart Stack accessoryInline summary for active set; placeholders: exercise name, target summary"
            )
        )
            .widgetURL(VolumeArcDeepLink.url(for: .nextWorkout))
    }

    private func activeSetCorner(_ state: LiveActivityState) -> some View {
        Text(state.activeExerciseName.prefix(6).uppercased())
            .font(VA.Typography.scoreCompact)
            .widgetLabel {
                Text(state.targetSummary)
                    .font(VA.Typography.rectCaption)
                    .lineLimit(1)
            }
            .widgetURL(VolumeArcDeepLink.url(for: .nextWorkout))
    }

    // MARK: - Idle

    @ViewBuilder
    private func idleView(_ snapshot: WidgetSummarySnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            idleCircular(snapshot)
        case .accessoryRectangular:
            idleRectangular(snapshot)
        case .accessoryInline:
            idleInline(snapshot)
        case .accessoryCorner:
            idleCorner(snapshot)
        default:
            idleRectangular(snapshot)
        }
    }

    private func idleCircular(_ snapshot: WidgetSummarySnapshot) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: VA.Space.xxs) {
                Text(snapshot.readinessScore)
                    .font(VA.Typography.scoreDisplay)
                Text(recommendationBadge(for: snapshot))
                    .font(VA.Typography.microLabel)
                    .tracking(VA.Tracking.microLabel)
            }
        }
        .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    private func idleRectangular(_ snapshot: WidgetSummarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: VA.Space.xs) {
                Text(snapshot.readinessScore)
                    .font(VA.Typography.rectHeadline)
                Text(recommendationBadge(for: snapshot))
                    .font(VA.Typography.microLabel)
                    .tracking(VA.Tracking.microLabel)
                    .foregroundStyle(VA.Colors.textSecondary)
            }
            Text(snapshot.nextWorkoutTitle)
                .font(VA.Typography.rectCaption)
                .lineLimit(1)
            Text(snapshot.primaryLiftForecast)
                .font(VA.Typography.rectFootnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .lineLimit(1)
        }
        .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    private func idleInline(_ snapshot: WidgetSummarySnapshot) -> some View {
        Text(
            String(
                localized: "\(recommendationBadge(for: snapshot)) • \(snapshot.readinessScore) • \(snapshot.nextWorkoutTitle)",
                comment: "Watch Smart Stack accessoryInline idle summary; placeholders: recommendation badge, readiness score, next workout title"
            )
        )
            .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    private func idleCorner(_ snapshot: WidgetSummarySnapshot) -> some View {
        Text(snapshot.readinessScore)
            .font(VA.Typography.scoreCompact)
            .widgetLabel {
                Text(recommendationBadge(for: snapshot))
                    .font(VA.Typography.rectCaption)
            }
            .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    // MARK: - Formatting

    private func restCountdownText(for state: LiveActivityState) -> String {
        guard let remaining = state.restSecondsRemaining, remaining > 0 else {
            return "0:00"
        }
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Maps the WidgetSummarySnapshot to a "PUSH" / "HOLD" / "REST"
    /// recommendation. The coach prompt is free-form text, so this is
    /// a heuristic — looks for action keywords and falls back to
    /// "READY" matching the existing complication's idle label.
    fileprivate func recommendationBadge(for snapshot: WidgetSummarySnapshot) -> String {
        let lowered = snapshot.coachPrompt.lowercased()
        if lowered.contains("push") || lowered.contains("hard") {
            return String(
                localized: "PUSH",
                comment: "Watch Smart Stack idle badge — push recommendation"
            )
        }
        if lowered.contains("rest") || lowered.contains("recover") {
            return String(
                localized: "REST",
                comment: "Watch Smart Stack idle badge — rest / recovery recommendation"
            )
        }
        if lowered.contains("hold") || lowered.contains("maintain") {
            return String(
                localized: "HOLD",
                comment: "Watch Smart Stack idle badge — hold / maintain recommendation"
            )
        }
        return String(
            localized: "READY",
            comment: "Watch Smart Stack idle badge fallback when no specific recommendation applies"
        )
    }
}

struct VolumeArcSmartStackWidget: Widget {
    let kind = "VolumeArcSmartStackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VolumeArcSmartStackProvider()) { entry in
            VolumeArcSmartStackView(entry: entry)
        }
        .configurationDisplayName(
            String(
                localized: "VolumeArc Live",
                comment: "Watch Smart Stack widget display name — surfaces active workout state"
            )
        )
        .description(
            String(
                localized: "Rest timer and next set during workouts; readiness when idle.",
                comment: "Watch Smart Stack widget description shown in the add-widget picker"
            )
        )
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}
#endif
