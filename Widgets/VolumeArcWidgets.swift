import SwiftUI
import WidgetKit
import VolumeArcCore

#if canImport(ActivityKit)
import ActivityKit
#endif

struct NextWorkoutEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSummarySnapshot
}

struct NextWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextWorkoutEntry {
        NextWorkoutEntry(date: .now, snapshot: makeSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (NextWorkoutEntry) -> Void) {
        completion(NextWorkoutEntry(date: .now, snapshot: makeSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextWorkoutEntry>) -> Void) {
        let entry = NextWorkoutEntry(date: .now, snapshot: makeSnapshot())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 30))))
    }

    private func makeSnapshot() -> WidgetSummarySnapshot {
        if let stored = PlatformSurfaceDefaultsReader.loadWidgetSnapshot() {
            return stored
        }
        return PlatformSurfaceFactory.makeEmptyWidgetSnapshot()
    }
}

struct NextWorkoutWidgetView: View {
    let entry: NextWorkoutProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("VolumeArc")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.snapshot.streakDays)d streak")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }

            Text(entry.snapshot.nextWorkoutTitle)
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Readiness \(entry.snapshot.readinessScore)")
                .font(.subheadline.bold())
                .foregroundStyle(.primary)

            Text(entry.snapshot.primaryLiftForecast)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Label(entry.snapshot.nextActionTitle, systemImage: "play.fill")
                Spacer()
                Label("Coach", systemImage: "waveform.and.mic")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            Text(entry.snapshot.syncSummary)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(VolumeArcDeepLink.url(for: .nextWorkout))
    }
}

struct NextWorkoutWidget: Widget {
    let kind = "NextWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextWorkoutProvider()) { entry in
            NextWorkoutWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Workout")
        .description("See readiness, next session, and primary lift momentum.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if canImport(ActivityKit)
struct ActiveWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActiveWorkoutAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.workoutTitle)
                    .font(.caption.weight(.semibold))
                Text(context.state.activeExerciseName)
                    .font(.headline)
                Text(context.state.targetSummary)
                    .font(.footnote)
                if let rest = context.state.restSecondsRemaining {
                    Text("Rest \(rest)s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.88))
            .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.activeExerciseName)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.targetSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text("VA")
            } compactTrailing: {
                Text(context.state.restSecondsRemaining.map { "\($0)" } ?? "Go")
            } minimal: {
                Text("VA")
            }
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
