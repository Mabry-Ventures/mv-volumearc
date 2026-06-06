import SwiftUI
import WidgetKit
import VolumeArcCore
import VolumeArcUI

#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Next Workout Widget

struct NextWorkoutEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSummarySnapshot
}

struct NextWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextWorkoutEntry {
        NextWorkoutEntry(date: .now, snapshot: PlatformSurfaceFactory.makeEmptyWidgetSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (NextWorkoutEntry) -> Void) {
        completion(NextWorkoutEntry(date: .now, snapshot: makeSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextWorkoutEntry>) -> Void) {
        let entry = NextWorkoutEntry(date: .now, snapshot: makeSnapshot())
        // Refresh more frequently when state is stale
        let nextRefresh = Date.now.addingTimeInterval(60 * 15) // 15 minutes
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeSnapshot() -> WidgetSummarySnapshot {
        PlatformSurfaceDefaultsReader.loadWidgetSnapshot() ?? PlatformSurfaceFactory.makeEmptyWidgetSnapshot()
    }
}

struct NextWorkoutWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    private let familyOverride: WidgetFamily?
    let entry: NextWorkoutProvider.Entry

    init(entry: NextWorkoutProvider.Entry, family: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = family
    }

    private var family: WidgetFamily {
        familyOverride ?? environmentFamily
    }

    var body: some View {
        switch family {
        case .systemSmall:
            smallLayout
        case .systemMedium:
            mediumLayout
        case .systemLarge:
            largeLayout
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        case .accessoryInline:
            accessoryInline
        default:
            smallLayout
        }
    }

    // MARK: - System Small (glanceable readiness + next lift)

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: VA.Space.widgetTight) {
            HStack {
                Text(String(
                    localized: "VOLUMEARC",
                    comment: "Widget branding lockup; product name rendered in all-caps (non-translatable brand mark)"
                ))
                    .font(VA.Typography.widgetMicroBadge)
                    .foregroundStyle(VA.Colors.primary)
                    .tracking(VA.Widget.microTracking)
                Spacer()
                streakBadge
            }

            Spacer(minLength: VA.Space.xxs)

            HStack(alignment: .firstTextBaseline, spacing: VA.Space.xs) {
                Text(entry.snapshot.readinessScore)
                    .font(VA.Typography.widgetScoreLarge)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .contentTransition(.numericText())
                Text(String(
                    localized: "READY",
                    comment: "Widget all-caps badge next to the readiness score"
                ))
                    .font(VA.Typography.widgetMicroBadge)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(VA.Widget.microTracking)
            }

            Text(entry.snapshot.nextWorkoutTitle)
                .font(VA.Typography.widgetBody)
                .foregroundStyle(VA.Colors.textPrimary)
                .lineLimit(2)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [VA.Colors.primary.opacity(VA.Widget.backgroundTint), VA.Colors.surfacePrimary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    // MARK: - System Medium (full summary)

    private var mediumLayout: some View {
        HStack(spacing: VA.Space.widgetStack) {
            // Left: readiness ring
            ZStack {
                Circle()
                    .stroke(VA.Colors.primary.opacity(VA.Widget.ringBackOpacity), lineWidth: VA.Widget.ringStrokeMedium)
                Circle()
                    .trim(from: 0, to: readinessFraction)
                    .stroke(
                        VA.Colors.primary,
                        style: StrokeStyle(lineWidth: VA.Widget.ringStrokeMedium, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: VA.Space.xxs) {
                    Text(entry.snapshot.readinessScore)
                        .font(VA.Typography.widgetScoreSmall)
                    Text(String(
                        localized: "READY",
                        comment: "Widget all-caps badge next to the readiness score"
                    ))
                        .font(VA.Typography.widgetAccessoryLabel)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(VA.Widget.microTracking)
                }
            }
            .frame(width: VA.Widget.ringSizeMedium, height: VA.Widget.ringSizeMedium)
            .accessibilityLabel(
                String(
                    localized: "Readiness score: \(entry.snapshot.readinessScore)",
                    comment: "Widget readiness ring accessibility label; placeholder is the numeric score"
                )
            )

            // Right: workout details
            VStack(alignment: .leading, spacing: VA.Space.xs) {
                HStack {
                    Text(String(
                        localized: "NEXT",
                        comment: "Widget all-caps header labeling the next workout"
                    ))
                        .font(VA.Typography.widgetMicro)
                        .foregroundStyle(VA.Colors.primary)
                        .tracking(VA.Widget.microTracking)
                    Spacer()
                    streakBadge
                }

                Text(entry.snapshot.nextWorkoutTitle)
                    .font(VA.Typography.widgetHeadlineCompact)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .lineLimit(1)

                Text(entry.snapshot.primaryLiftForecast)
                    .font(VA.Typography.widgetBodyMedium)
                    .foregroundStyle(VA.Colors.primary)
                    .lineLimit(1)

                HStack(spacing: VA.Space.widgetTight) {
                    Label(entry.snapshot.nextActionTitle, systemImage: "play.fill")
                    Spacer()
                    Label(
                        String(
                            localized: "Coach",
                            comment: "Widget label pointing to the in-app coach surface"
                        ),
                        systemImage: "waveform"
                    )
                }
                .font(VA.Typography.widgetMetaCompact)
                .foregroundStyle(VA.Colors.textSecondary)
                .padding(.top, VA.Space.xxs)
            }
        }
        .containerBackground(for: .widget) {
            Rectangle().fill(.regularMaterial)
        }
        .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    // MARK: - System Large (training plan overview)

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: VA.Space.widgetRow) {
            HStack {
                Text(String(
                    localized: "VOLUMEARC",
                    comment: "Widget branding lockup; product name rendered in all-caps (non-translatable brand mark)"
                ))
                    .font(VA.Typography.widgetHeroBadgeLarge)
                    .foregroundStyle(VA.Colors.primary)
                    .tracking(VA.Widget.microTracking)
                Spacer()
                streakBadge
            }

            HStack(alignment: .top, spacing: VA.Space.widgetStack) {
                ZStack {
                    Circle().stroke(VA.Colors.primary.opacity(VA.Widget.ringBackOpacity), lineWidth: VA.Widget.ringStrokeLarge)
                    Circle()
                        .trim(from: 0, to: readinessFraction)
                        .stroke(
                            VA.Colors.primary,
                            style: StrokeStyle(lineWidth: VA.Widget.ringStrokeLarge, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: VA.Space.xxs) {
                        Text(entry.snapshot.readinessScore)
                            .font(VA.Typography.widgetScoreMedium)
                        Text(String(
                            localized: "READY",
                            comment: "Widget all-caps badge next to the readiness score"
                        ))
                            .font(VA.Typography.widgetMicro)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .tracking(VA.Widget.microTracking)
                    }
                }
                .frame(width: VA.Widget.ringSizeLarge, height: VA.Widget.ringSizeLarge)

                VStack(alignment: .leading, spacing: VA.Space.widgetTight) {
                    Text(entry.snapshot.nextWorkoutTitle)
                        .font(VA.Typography.widgetHeadline)
                        .foregroundStyle(VA.Colors.textPrimary)
                        .lineLimit(2)
                    Text(entry.snapshot.primaryLiftForecast)
                        .font(VA.Typography.widgetFootnote)
                        .foregroundStyle(VA.Colors.primary)
                        .lineLimit(2)
                }
            }

            Divider()

            Text(entry.snapshot.coachPrompt)
                .font(VA.Typography.widgetCoachBody)
                .foregroundStyle(VA.Colors.textSecondary)
                .italic()
                .lineLimit(3)

            Spacer(minLength: 0)

            HStack {
                Label(entry.snapshot.nextActionTitle, systemImage: "play.fill")
                Spacer()
                Label(
                    String(
                        localized: "Coach",
                        comment: "Widget label pointing to the in-app coach surface"
                    ),
                    systemImage: "waveform"
                )
                Spacer()
                Label(entry.snapshot.syncSummary, systemImage: "arrow.triangle.2.circlepath")
            }
            .font(VA.Typography.widgetMeta)
            .foregroundStyle(VA.Colors.textSecondary)
        }
        .containerBackground(for: .widget) {
            Rectangle().fill(.regularMaterial)
        }
        .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    // MARK: - Accessory widgets (Lock Screen / StandBy)

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: VA.Space.xxs) {
                Text(entry.snapshot.readinessScore)
                    .font(VA.Typography.widgetAccessoryScore)
                Text(String(
                    localized: "READY",
                    comment: "Widget all-caps badge next to the readiness score"
                ))
                    .font(VA.Typography.widgetAccessoryLabel)
                    .tracking(VA.Widget.microTracking)
            }
        }
        .widgetURL(VolumeArcDeepLink.url(for: .signals))
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: VA.Space.xxs) {
            Text(
                String(
                    localized: "READINESS \(entry.snapshot.readinessScore)",
                    comment: "Accessory rectangular widget readiness headline; placeholder is the numeric score"
                )
            )
                .font(VA.Typography.headline)
            Text(entry.snapshot.nextWorkoutTitle)
                .font(VA.Typography.captionLarge)
                .foregroundStyle(VA.Colors.textSecondary)
                .lineLimit(1)
            Text(entry.snapshot.primaryLiftForecast)
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .lineLimit(1)
        }
        .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    private var accessoryInline: some View {
        Text(
            String(
                localized: "\(entry.snapshot.nextWorkoutTitle) • Ready \(entry.snapshot.readinessScore)",
                comment: "Accessory inline widget summary; placeholders are the next-workout title and readiness score"
            )
        )
            .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    // MARK: - Helpers

    private var readinessFraction: Double {
        Double(Int(entry.snapshot.readinessScore) ?? 0) / 100.0
    }

    private var streakBadge: some View {
        HStack(spacing: VA.Space.widgetHairline) {
            Image(systemName: "flame.fill")
                .font(VA.Typography.widgetStreakIcon)
            Text(String(
                localized: "\(entry.snapshot.streakDays)d",
                comment: """
                    Widget streak badge value; placeholder is the number of \
                    consecutive training days (e.g. '7d'). The 'd' suffix is \
                    shorthand for days.
                    """
            ))
                .font(VA.Typography.widgetStreakNumber)
        }
        .foregroundStyle(VA.Colors.primary)
        .accessibilityLabel(
            String(
                localized: "Training streak: ^[\(entry.snapshot.streakDays) day](inflect: true)",
                comment: """
                    Widget streak badge accessibility label; placeholder is \
                    the number of consecutive training days. Uses automatic \
                    grammar inflection for singular/plural agreement.
                    """
            )
        )
    }
}

struct NextWorkoutWidget: Widget {
    let kind = "NextWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextWorkoutProvider()) { entry in
            NextWorkoutWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Next Workout", comment: "Widget display name"))
        .description(String(localized: "See readiness, next session, and primary lift momentum.", comment: "Widget description"))
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

// MARK: - Live Activity

#if canImport(ActivityKit)
struct ActiveWorkoutLiveActivitySnapshot: Equatable {
    let workoutTitle: String
    let activeExerciseName: String
    let targetSummary: String
    let setProgressSummary: String?
    let restSecondsRemaining: Int?

    init(
        workoutTitle: String,
        activeExerciseName: String,
        targetSummary: String,
        setProgressSummary: String?,
        restSecondsRemaining: Int?
    ) {
        self.workoutTitle = workoutTitle
        self.activeExerciseName = activeExerciseName
        self.targetSummary = targetSummary
        self.setProgressSummary = setProgressSummary
        self.restSecondsRemaining = restSecondsRemaining
    }

    init(context: ActivityViewContext<ActiveWorkoutAttributes>) {
        self.init(
            workoutTitle: context.attributes.workoutTitle,
            activeExerciseName: context.state.activeExerciseName,
            targetSummary: context.state.targetSummary,
            setProgressSummary: context.state.setProgressSummary,
            restSecondsRemaining: context.state.restSecondsRemaining
        )
    }

    var setLine: String {
        setProgressSummary ?? targetSummary
    }

    var restHeadline: String {
        guard let restSecondsRemaining else {
            return String(localized: "GO", comment: "Live Activity rest-complete label when the rest timer hits zero")
        }
        return String(
            localized: "\(restSecondsRemaining)",
            comment: "Live Activity rest-timer countdown; placeholder is the number of seconds remaining"
        )
    }

    var restCompactHeadline: String {
        guard let restSecondsRemaining else {
            return String(localized: "GO", comment: "Live Activity rest-complete label when the rest timer hits zero")
        }
        return String(
            localized: "\(restSecondsRemaining)s",
            comment: "Dynamic Island rest-timer countdown; placeholder is the number of seconds remaining"
        )
    }
}

struct ActiveWorkoutLiveActivityContentView: View {
    @Environment(\.activityFamily) private var environmentActivityFamily

    let snapshot: ActiveWorkoutLiveActivitySnapshot
    private let activityFamilyOverride: ActivityFamily?

    init(snapshot: ActiveWorkoutLiveActivitySnapshot, activityFamily: ActivityFamily? = nil) {
        self.snapshot = snapshot
        self.activityFamilyOverride = activityFamily
    }

    private var activityFamily: ActivityFamily {
        activityFamilyOverride ?? environmentActivityFamily
    }

    var body: some View {
        switch activityFamily {
        case .small:
            watchFaceLayout
        default:
            lockScreenLayout
        }
    }

    private var lockScreenLayout: some View {
        HStack(spacing: VA.Space.md) {
            VStack(alignment: .leading, spacing: VA.Space.xs) {
                Text(snapshot.workoutTitle.uppercased())
                    .font(VA.Typography.widgetHeroBadge)
                    .foregroundStyle(VA.Colors.primary)
                    .tracking(VA.Widget.microTracking)
                Text(snapshot.activeExerciseName)
                    .font(VA.Typography.widgetActivityTitle)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(snapshot.setLine)
                    .font(VA.Typography.widgetBody)
                    .foregroundStyle(VA.Colors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(VA.Widget.liveActivitySetLineMinimumScale)
            }
            Spacer()
            restCountdownCircle(diameter: VA.Widget.activityPill)
        }
        .padding(VA.Space.widgetOuter)
    }

    private var watchFaceLayout: some View {
        HStack(spacing: VA.Space.widgetTight) {
            restCountdownCircle(diameter: VA.Widget.watchLiveActivityPill)
            VStack(alignment: .leading, spacing: VA.Space.xxs) {
                Text(snapshot.setLine)
                    .font(VA.Typography.widgetBody)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(VA.Widget.watchLiveActivitySetLineMinimumScale)
                Text(snapshot.activeExerciseName)
                    .font(VA.Typography.widgetFootnoteSmall)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .lineLimit(1)
                Text(snapshot.workoutTitle)
                    .font(VA.Typography.widgetMicro)
                    .foregroundStyle(VA.Colors.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VA.Space.md)
        .padding(.vertical, VA.Space.sm)
    }

    private func restCountdownCircle(diameter: CGFloat) -> some View {
        VStack(spacing: VA.Space.xxs) {
            Text(snapshot.restHeadline)
                .font(VA.Typography.widgetTimerDisplay)
                .foregroundStyle(snapshot.restSecondsRemaining == nil ? VA.Colors.success : VA.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(VA.Widget.liveActivityTimerMinimumScale)
            Text(String(
                localized: "REST",
                comment: "Live Activity all-caps badge labeling the rest countdown"
            ))
                .font(VA.Typography.widgetMicro)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(VA.Widget.microTracking)
        }
        .frame(width: diameter, height: diameter)
        .background(VA.Colors.primary.opacity(VA.Widget.backgroundTint))
        .clipShape(Circle())
        .accessibilityLabel(restCountdownAccessibilityLabel)
    }

    private var restCountdownAccessibilityLabel: String {
        if let restSecondsRemaining = snapshot.restSecondsRemaining {
            return String(
                localized: "Rest timer: ^[\(restSecondsRemaining) second](inflect: true) remaining",
                comment: "Accessibility label for the Live Activity rest timer"
            )
        }
        return String(localized: "Rest complete", comment: "Accessibility label for rest-complete Live Activity state")
    }
}

struct ActiveWorkoutDynamicIslandView {
    let snapshot: ActiveWorkoutLiveActivitySnapshot

    var body: DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                ActiveWorkoutDynamicIslandLeadingView(snapshot: snapshot)
            }
            DynamicIslandExpandedRegion(.trailing) {
                ActiveWorkoutDynamicIslandTrailingView(snapshot: snapshot)
            }
            DynamicIslandExpandedRegion(.bottom) {
                ActiveWorkoutDynamicIslandBottomView(snapshot: snapshot)
            }
        } compactLeading: {
            ActiveWorkoutDynamicIslandGlyphView()
        } compactTrailing: {
            ActiveWorkoutDynamicIslandCompactTimerView(snapshot: snapshot)
        } minimal: {
            ActiveWorkoutDynamicIslandGlyphView()
        }
        .keylineTint(VA.Colors.primary)
    }
}

struct ActiveWorkoutDynamicIslandExpandedPreview: View {
    let snapshot: ActiveWorkoutLiveActivitySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            HStack(alignment: .center, spacing: VA.Space.md) {
                ActiveWorkoutDynamicIslandLeadingView(snapshot: snapshot)
                Spacer(minLength: VA.Space.sm)
                ActiveWorkoutDynamicIslandTrailingView(snapshot: snapshot)
            }
            ActiveWorkoutDynamicIslandBottomView(snapshot: snapshot)
        }
        .padding(.horizontal, VA.Space.lg)
        .padding(.vertical, VA.Space.md)
        .background(VA.Colors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
    }
}

private struct ActiveWorkoutDynamicIslandLeadingView: View {
    let snapshot: ActiveWorkoutLiveActivitySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.xxs) {
            Text(snapshot.workoutTitle)
                .font(VA.Typography.captionLarge)
                .foregroundStyle(VA.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(snapshot.activeExerciseName)
                .font(VA.Typography.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}

private struct ActiveWorkoutDynamicIslandTrailingView: View {
    let snapshot: ActiveWorkoutLiveActivitySnapshot

    var body: some View {
        Text(snapshot.restCompactHeadline)
            .font(VA.Typography.dynamicIslandTitle.monospacedDigit())
            .foregroundStyle(snapshot.restSecondsRemaining == nil ? VA.Colors.success : VA.Colors.primary)
            .lineLimit(1)
            .minimumScaleFactor(VA.Widget.liveActivityTimerMinimumScale)
    }
}

private struct ActiveWorkoutDynamicIslandBottomView: View {
    let snapshot: ActiveWorkoutLiveActivitySnapshot

    var body: some View {
        Text(snapshot.setLine)
            .font(VA.Typography.footnote)
            .foregroundStyle(VA.Colors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(VA.Widget.liveActivitySetLineMinimumScale)
    }
}

private struct ActiveWorkoutDynamicIslandGlyphView: View {
    var body: some View {
        Image(systemName: "figure.strengthtraining.traditional")
            .foregroundStyle(VA.Colors.primary)
    }
}

private struct ActiveWorkoutDynamicIslandCompactTimerView: View {
    let snapshot: ActiveWorkoutLiveActivitySnapshot

    var body: some View {
        Text(snapshot.restCompactHeadline)
            .font(VA.Typography.dynamicIslandCompact.monospacedDigit())
    }
}

struct ActiveWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActiveWorkoutAttributes.self) { context in
            // Lock screen / banner presentation
            ActiveWorkoutLiveActivityContentView(
                snapshot: ActiveWorkoutLiveActivitySnapshot(context: context)
            )
            .activityBackgroundTint(VA.Colors.surfacePrimary)
            .activitySystemActionForegroundColor(VA.Colors.primary)
        } dynamicIsland: { context in
            ActiveWorkoutDynamicIslandView(
                snapshot: ActiveWorkoutLiveActivitySnapshot(context: context)
            ).body
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}
#endif

#if !VOLUMEARC_WIDGET_SNAPSHOT_TESTING
@main
#endif
struct VolumeArcWidgets: WidgetBundle {
    var body: some Widget {
        NextWorkoutWidget()
        #if canImport(ActivityKit)
        ActiveWorkoutLiveActivity()
        #endif
    }
}
