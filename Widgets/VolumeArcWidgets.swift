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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("VOLUMEARC")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(VA.Colors.primary)
                    .tracking(0.5)
                Spacer()
                streakBadge
            }

            Spacer(minLength: 2)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.snapshot.readinessScore)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(VA.Colors.textPrimary)
                    .contentTransition(.numericText())
                Text("READY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.5)
            }

            Text(entry.snapshot.nextWorkoutTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VA.Colors.textPrimary)
                .lineLimit(2)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [VA.Colors.primary.opacity(0.12), VA.Colors.surfacePrimary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    // MARK: - System Medium (full summary)

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            // Left: readiness ring
            ZStack {
                Circle()
                    .stroke(VA.Colors.primary.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: readinessFraction)
                    .stroke(VA.Colors.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(entry.snapshot.readinessScore)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("READY")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.5)
                }
            }
            .frame(width: 72, height: 72)
            .accessibilityLabel("Readiness score: \(entry.snapshot.readinessScore)")

            // Right: workout details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("NEXT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(VA.Colors.primary)
                        .tracking(0.5)
                    Spacer()
                    streakBadge
                }

                Text(entry.snapshot.nextWorkoutTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(VA.Colors.textPrimary)
                    .lineLimit(1)

                Text(entry.snapshot.primaryLiftForecast)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VA.Colors.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(entry.snapshot.nextActionTitle, systemImage: "play.fill")
                    Spacer()
                    Label("Coach", systemImage: "waveform")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(VA.Colors.textSecondary)
                .padding(.top, 2)
            }
        }
        .containerBackground(for: .widget) {
            Rectangle().fill(.regularMaterial)
        }
        .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    // MARK: - System Large (training plan overview)

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("VOLUMEARC")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(VA.Colors.primary)
                    .tracking(0.5)
                Spacer()
                streakBadge
            }

            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().stroke(VA.Colors.primary.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: readinessFraction)
                        .stroke(VA.Colors.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(entry.snapshot.readinessScore)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("READY")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(VA.Colors.textSecondary)
                            .tracking(0.5)
                    }
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.snapshot.nextWorkoutTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(VA.Colors.textPrimary)
                        .lineLimit(2)
                    Text(entry.snapshot.primaryLiftForecast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VA.Colors.primary)
                        .lineLimit(2)
                }
            }

            Divider()

            Text(entry.snapshot.coachPrompt)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(VA.Colors.textSecondary)
                .italic()
                .lineLimit(3)

            Spacer(minLength: 0)

            HStack {
                Label(entry.snapshot.nextActionTitle, systemImage: "play.fill")
                Spacer()
                Label("Coach", systemImage: "waveform")
                Spacer()
                Label(entry.snapshot.syncSummary, systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.system(size: 11, weight: .semibold))
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
            VStack(spacing: 0) {
                Text(entry.snapshot.readinessScore)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("READY")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.5)
            }
        }
        .widgetURL(VolumeArcDeepLink.url(for: .signals))
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("READINESS \(entry.snapshot.readinessScore)")
                .font(.headline)
            Text(entry.snapshot.nextWorkoutTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(entry.snapshot.primaryLiftForecast)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    private var accessoryInline: some View {
        Text("\(entry.snapshot.nextWorkoutTitle) • Ready \(entry.snapshot.readinessScore)")
            .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    // MARK: - Helpers

    private var readinessFraction: Double {
        Double(Int(entry.snapshot.readinessScore) ?? 0) / 100.0
    }

    private var streakBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9, weight: .bold))
            Text("\(entry.snapshot.streakDays)d")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(VA.Colors.primary)
        .accessibilityLabel("Training streak: \(entry.snapshot.streakDays) days")
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.workoutTitle.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(VA.Colors.primary)
                        .tracking(0.5)
                    Text(context.state.activeExerciseName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(context.state.targetSummary)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VA.Colors.primary)
                }
                Spacer()
                if let rest = context.state.restSecondsRemaining {
                    VStack(spacing: 0) {
                        Text("\(rest)")
                            .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text("REST")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(VA.Colors.textSecondary)
                            .tracking(0.5)
                    }
                    .frame(width: 52, height: 52)
                    .background(VA.Colors.primary.opacity(0.12))
                    .clipShape(Circle())
                }
            }
            .padding(14)
            .activityBackgroundTint(VA.Colors.surfacePrimary)
            .activitySystemActionForegroundColor(VA.Colors.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.workoutTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(context.state.activeExerciseName)
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let rest = context.state.restSecondsRemaining {
                        Text("\(rest)s")
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(VA.Colors.primary)
                    } else {
                        Text("GO")
                            .font(.title3.bold())
                            .foregroundStyle(VA.Colors.success)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.targetSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(VA.Colors.primary)
            } compactTrailing: {
                if let rest = context.state.restSecondsRemaining {
                    Text("\(rest)s")
                        .font(.caption.monospacedDigit().bold())
                } else {
                    Text("GO").font(.caption.bold())
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
