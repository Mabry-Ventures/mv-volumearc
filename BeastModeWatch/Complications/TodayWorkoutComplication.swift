import SwiftUI
import WidgetKit

/// Complication showing today's workout focus
struct TodayWorkoutComplication: Widget {
    let kind = "TodayWorkoutComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutComplicationProvider()) { entry in
            TodayWorkoutComplicationView(entry: entry)
        }
        .configurationDisplayName("Today's Workout")
        .description("See your workout focus for today")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - Timeline Entry

struct WorkoutComplicationEntry: TimelineEntry {
    let date: Date
    let focusArea: String
    let exerciseCount: Int
    let isRestDay: Bool
}

// MARK: - Provider

struct WorkoutComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutComplicationEntry {
        WorkoutComplicationEntry(
            date: Date(),
            focusArea: "Push",
            exerciseCount: 6,
            isRestDay: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutComplicationEntry) -> Void) {
        let entry = WorkoutComplicationEntry(
            date: Date(),
            focusArea: "Push",
            exerciseCount: 6,
            isRestDay: false
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutComplicationEntry>) -> Void) {
        // Get today's workout from data store
        let entry = WorkoutComplicationEntry(
            date: Date(),
            focusArea: "Push",
            exerciseCount: 6,
            isRestDay: false
        )

        // Refresh at midnight
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        let timeline = Timeline(entries: [entry], policy: .after(tomorrow))

        completion(timeline)
    }
}

// MARK: - Complication View

struct TodayWorkoutComplicationView: View {
    let entry: WorkoutComplicationEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView

        case .accessoryRectangular:
            rectangularView

        case .accessoryCorner:
            cornerView

        case .accessoryInline:
            inlineView

        @unknown default:
            circularView
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: entry.isRestDay ? "bed.double.fill" : "figure.strengthtraining.traditional")
                    .font(.title3)
                Text(entry.focusArea)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                Text("Beast Mode")
                    .font(.headline)
            }
            Text(entry.focusArea)
                .font(.body)
            if !entry.isRestDay {
                Text("\(entry.exerciseCount) exercises")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cornerView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: entry.isRestDay ? "bed.double.fill" : "dumbbell.fill")
                .font(.title3)
        }
    }

    private var inlineView: some View {
        Label(entry.focusArea, systemImage: entry.isRestDay ? "bed.double.fill" : "dumbbell.fill")
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    TodayWorkoutComplication()
} timeline: {
    WorkoutComplicationEntry(date: .now, focusArea: "Push", exerciseCount: 6, isRestDay: false)
    WorkoutComplicationEntry(date: .now, focusArea: "Rest", exerciseCount: 0, isRestDay: true)
}
