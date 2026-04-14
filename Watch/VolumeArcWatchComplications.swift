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
            VStack(spacing: 0) {
                Text(entry.snapshot.readinessScore)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("READY")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.5)
            }
        }
        .widgetURL(VolumeArcDeepLink.url(for: .signals))
    }

    private var cornerView: some View {
        Text(entry.snapshot.readinessScore)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .widgetLabel {
                Text(entry.snapshot.nextWorkoutTitle)
                    .font(.caption)
            }
            .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    private var inlineView: some View {
        Text("\(entry.snapshot.nextWorkoutTitle) • \(entry.snapshot.readinessScore)")
            .widgetURL(VolumeArcDeepLink.url(for: .today))
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("READY \(entry.snapshot.readinessScore)")
                .font(.headline.monospacedDigit())
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
}

struct VolumeArcWatchComplication: Widget {
    let kind = "VolumeArcWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VolumeArcWatchComplicationProvider()) { entry in
            VolumeArcComplicationView(entry: entry)
        }
        .configurationDisplayName("VolumeArc")
        .description("Readiness score and next workout at a glance.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}
#endif
