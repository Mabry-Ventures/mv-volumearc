import SwiftUI
import WidgetKit

/// Widget showing PR streak and recent achievements
struct PRStreakWidget: Widget {
    let kind = "PRStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRStreakProvider()) { entry in
            PRStreakWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("PR Streak")
        .description("Track your personal record achievements")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: - Entry

struct PRStreakEntry: TimelineEntry {
    let date: Date
    let totalPRs: Int
    let recentPRExercise: String?
    let recentPRValue: String?
    let weeklyPRCount: Int
}

// MARK: - Provider

struct PRStreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> PRStreakEntry {
        PRStreakEntry(
            date: Date(),
            totalPRs: 42,
            recentPRExercise: "Bench Press",
            recentPRValue: "185 x 8",
            weeklyPRCount: 3
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PRStreakEntry) -> Void) {
        let entry = PRStreakEntry(
            date: Date(),
            totalPRs: 42,
            recentPRExercise: "Bench Press",
            recentPRValue: "185 x 8",
            weeklyPRCount: 3
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PRStreakEntry>) -> Void) {
        let entry = PRStreakEntry(
            date: Date(),
            totalPRs: 42,
            recentPRExercise: "Bench Press",
            recentPRValue: "185 x 8",
            weeklyPRCount: 3
        )

        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }
}

// MARK: - Widget View

struct PRStreakWidgetView: View {
    let entry: PRStreakEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .accessoryCircular:
            circularWidget
        default:
            smallWidget
        }
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.orange)
                Text("PRs")
                    .font(.caption.weight(.semibold))
            }

            Text("\(entry.totalPRs)")
                .font(.system(size: 48, weight: .bold, design: .rounded))

            Spacer()

            if let exercise = entry.recentPRExercise, let value = entry.recentPRValue {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latest PR")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(exercise)
                        .font(.caption.weight(.semibold))
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var circularWidget: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("\(entry.weeklyPRCount)")
                    .font(.title2.weight(.bold))
                Text("PRs")
                    .font(.caption2)
            }
        }
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    PRStreakWidget()
} timeline: {
    PRStreakEntry(date: .now, totalPRs: 42, recentPRExercise: "Bench Press", recentPRValue: "185 x 8", weeklyPRCount: 3)
}
