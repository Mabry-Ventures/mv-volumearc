#if os(watchOS)
import SwiftUI
import WidgetKit
import VolumeArcCore

/// Complication provider that reads the shared widget snapshot from the
/// app group and exposes it as a watchOS widget family. This drives
/// Smart Stack cards, Lock Screen complications, and watch face tiles.
struct VolumeArcWatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> VolumeArcComplicationEntry {
        VolumeArcComplicationEntry(
            date: .now,
            snapshot: PlatformSurfaceFactory.makeEmptyWidgetSnapshot()
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (VolumeArcComplicationEntry) -> Void
    ) {
        completion(VolumeArcComplicationEntry(
            date: .now,
            snapshot: loadSnapshot()
        ))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<VolumeArcComplicationEntry>) -> Void
    ) {
        let entry = VolumeArcComplicationEntry(date: .now, snapshot: loadSnapshot())
        // Refresh every 30 minutes; the app will also force a reload when
        // state changes via WidgetCenter.reloadAllTimelines().
        let nextRefresh = Date.now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSnapshot() -> WidgetSummarySnapshot {
        PlatformSurfaceDefaultsReader.loadWidgetSnapshot()
            ?? PlatformSurfaceFactory.makeEmptyWidgetSnapshot()
    }
}

struct VolumeArcComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSummarySnapshot
}

/// Main complication view that adapts to every watchOS family.
struct VolumeArcComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VolumeArcComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        case .accessoryRectangular:
            rectangularView
        default:
            rectangularView
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: VA.Space.xxs) {
                Text(entry.snapshot.readinessScore)
                    .font(VA.Typography.scoreDisplay)
                Text(String(
                    localized: "READY",
                    comment: "Watch complication all-caps badge next to the readiness score"
                ))
                    .font(VA.Typography.microLabel)
                    .tracking(VA.Tracking.microLabel)
            }
        }
        .widgetURL(VolumeArcDeepLink.url(for: .signals))
    }

    private var cornerView: some View {
        Text(entry.snapshot.readinessScore)
            .font(VA.Typography.scoreCompact)
            .widgetLabel {
                Text(entry.snapshot.nextWorkoutTitle)
                    .font(VA.Typography.rectCaption)
            }
            .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    private var inlineView: some View {
        Text(
            String(
                localized: "\(entry.snapshot.nextWorkoutTitle) • \(entry.snapshot.readinessScore)",
                comment: "Accessory inline watch complication summary; placeholders are the next-workout title and the readiness score"
            )
        )
            .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(
                String(
                    localized: "READY \(entry.snapshot.readinessScore)",
                    comment: "Accessory rectangular watch complication headline; placeholder is the readiness score"
                )
            )
                .font(VA.Typography.rectHeadline)
            Text(entry.snapshot.nextWorkoutTitle)
                .font(VA.Typography.rectCaption)
                .foregroundStyle(VA.Colors.textSecondary)
                .lineLimit(1)
            Text(entry.snapshot.primaryLiftForecast)
                .font(VA.Typography.rectFootnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .lineLimit(1)
        }
        .widgetURL(VolumeArcDeepLink.url(for: .today))
    }
}

struct VolumeArcWatchComplication: Widget {
    let kind = "VolumeArcWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VolumeArcWatchComplicationProvider()) { entry in
            VolumeArcComplicationView(entry: entry)
        }
        .configurationDisplayName(
            String(
                localized: "VolumeArc",
                comment: "Watch complication display name; product name (non-translatable brand mark)"
            )
        )
        .description(
            String(
                localized: "Readiness score and next workout at a glance.",
                comment: "Watch complication description shown in the add-complication picker"
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
