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
    @Environment(\.widgetFamily) private var family
    let entry: NextWorkoutProvider.Entry

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
                comment: "Widget streak badge value; placeholder is the number of consecutive training days (e.g. '7d'). The 'd' suffix is shorthand for days."
            ))
                .font(VA.Typography.widgetStreakNumber)
        }
        .foregroundStyle(VA.Colors.primary)
        .accessibilityLabel(
            String(
                localized: "Training streak: ^[\(entry.snapshot.streakDays) day](inflect: true)",
                comment: "Widget streak badge accessibility label; placeholder is the number of consecutive training days. Uses automatic grammar inflection for singular/plural agreement."
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
struct ActiveWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActiveWorkoutAttributes.self) { context in
            // Lock screen / banner presentation
            HStack(spacing: VA.Space.md) {
                VStack(alignment: .leading, spacing: VA.Space.xs) {
                    Text(context.attributes.workoutTitle.uppercased())
                        .font(VA.Typography.widgetHeroBadge)
                        .foregroundStyle(VA.Colors.primary)
                        .tracking(VA.Widget.microTracking)
                    Text(context.state.activeExerciseName)
                        .font(VA.Typography.widgetActivityTitle)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(context.state.targetSummary)
                        .font(VA.Typography.widgetBody)
                        .foregroundStyle(VA.Colors.primary)
                }
                Spacer()
                if let rest = context.state.restSecondsRemaining {
                    VStack(spacing: VA.Space.xxs) {
                        Text(
                            String(
                                localized: "\(rest)",
                                comment: "Live Activity rest-timer countdown; placeholder is the number of seconds remaining"
                            )
                        )
                            .font(VA.Typography.widgetTimerDisplay)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(String(
                            localized: "REST",
                            comment: "Live Activity all-caps badge labeling the rest countdown"
                        ))
                            .font(VA.Typography.widgetMicro)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .tracking(VA.Widget.microTracking)
                    }
                    .frame(width: VA.Widget.activityPill, height: VA.Widget.activityPill)
                    .background(VA.Colors.primary.opacity(VA.Widget.backgroundTint))
                    .clipShape(Circle())
                }
            }
            .padding(VA.Space.widgetOuter)
            .activityBackgroundTint(VA.Colors.surfacePrimary)
            .activitySystemActionForegroundColor(VA.Colors.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(context.attributes.workoutTitle)
                            .font(VA.Typography.captionLarge)
                            .foregroundStyle(VA.Colors.textSecondary)
                        Text(context.state.activeExerciseName)
                            .font(VA.Typography.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let rest = context.state.restSecondsRemaining {
                        Text(
                            String(
                                localized: "\(rest)s",
                                comment: "Dynamic Island rest-timer countdown; placeholder is the number of seconds remaining"
                            )
                        )
                            .font(VA.Typography.dynamicIslandTitle.monospacedDigit())
                            .foregroundStyle(VA.Colors.primary)
                    } else {
                        Text(String(
                            localized: "GO",
                            comment: "Dynamic Island rest-complete label when the rest timer hits zero"
                        ))
                            .font(VA.Typography.dynamicIslandTitle)
                            .foregroundStyle(VA.Colors.success)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.targetSummary)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(VA.Colors.primary)
            } compactTrailing: {
                if let rest = context.state.restSecondsRemaining {
                    Text(
                        String(
                            localized: "\(rest)s",
                            comment: "Dynamic Island rest-timer countdown; placeholder is the number of seconds remaining"
                        )
                    )
                        .font(VA.Typography.dynamicIslandCompact.monospacedDigit())
                } else {
                    Text(String(
                        localized: "GO",
                        comment: "Dynamic Island rest-complete label when the rest timer hits zero"
                    ))
                        .font(VA.Typography.dynamicIslandCompact)
                }
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(VA.Colors.primary)
            }
            .keylineTint(VA.Colors.primary)
        }
    }
}
#endif

@main
struct VolumeArcWidgets: WidgetBundle {
    var body: some Widget {
        NextWorkoutWidget()
        #if canImport(ActivityKit)
        ActiveWorkoutLiveActivity()
        #endif
    }
}
