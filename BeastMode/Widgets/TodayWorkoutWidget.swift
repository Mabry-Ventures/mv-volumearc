import SwiftUI
import WidgetKit
import AppIntents

/// Widget showing today's workout overview
struct TodayWorkoutWidget: Widget {
    let kind = "TodayWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayWorkoutProvider()) { entry in
            TodayWorkoutWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Workout")
        .description("Quick view of your workout plan for today")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Entry

struct TodayWorkoutEntry: TimelineEntry {
    let date: Date
    let focusArea: String
    let exerciseCount: Int
    let previewExercises: [String]
    let isRestDay: Bool
    let isComplete: Bool
}

// MARK: - Provider

struct TodayWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWorkoutEntry {
        TodayWorkoutEntry(
            date: Date(),
            focusArea: "Push",
            exerciseCount: 6,
            previewExercises: ["Bench Press", "Incline Press", "Overhead Press"],
            isRestDay: false,
            isComplete: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWorkoutEntry) -> Void) {
        let entry = TodayWorkoutEntry(
            date: Date(),
            focusArea: "Push",
            exerciseCount: 6,
            previewExercises: ["Bench Press", "Incline Press", "Overhead Press"],
            isRestDay: false,
            isComplete: false
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWorkoutEntry>) -> Void) {
        // In production, fetch from SwiftData
        let entry = TodayWorkoutEntry(
            date: Date(),
            focusArea: "Push",
            exerciseCount: 6,
            previewExercises: ["Bench Press", "Incline Press", "Overhead Press", "Lateral Raises"],
            isRestDay: false,
            isComplete: false
        )

        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        let timeline = Timeline(entries: [entry], policy: .after(tomorrow))

        completion(timeline)
    }
}

// MARK: - Widget View

struct TodayWorkoutWidgetView: View {
    let entry: TodayWorkoutEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        case .accessoryRectangular:
            accessoryWidget
        default:
            smallWidget
        }
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: entry.isRestDay ? "bed.double.fill" : "figure.strengthtraining.traditional")
                    .foregroundStyle(.purple)
                Text("Beast Mode")
                    .font(.caption.weight(.semibold))
            }

            Text(entry.focusArea)
                .font(.title2.weight(.bold))

            if !entry.isRestDay {
                Text("\(entry.exerciseCount) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if entry.isComplete {
                Label("Complete", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else if !entry.isRestDay {
                Button(intent: StartWorkoutIntent()) {
                    Label("Start", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumWidget: some View {
        HStack(spacing: 16) {
            // Left side: Overview
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: entry.isRestDay ? "bed.double.fill" : "figure.strengthtraining.traditional")
                        .foregroundStyle(.purple)
                    Text("Today")
                        .font(.headline)
                }

                Text(entry.focusArea)
                    .font(.title.weight(.bold))

                if !entry.isRestDay {
                    Text("\(entry.exerciseCount) exercises")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !entry.isComplete && !entry.isRestDay {
                    Button(intent: StartWorkoutIntent()) {
                        Label("Start Workout", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            }

            if !entry.isRestDay {
                Divider()

                // Right side: Exercise list preview
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.previewExercises.prefix(4), id: \.self) { exercise in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.purple.opacity(0.5))
                                .frame(width: 6, height: 6)
                            Text(exercise)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }

                    if entry.exerciseCount > 4 {
                        Text("+\(entry.exerciseCount - 4) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var accessoryWidget: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(entry.focusArea, systemImage: entry.isRestDay ? "bed.double.fill" : "dumbbell.fill")
                .font(.headline)
            if !entry.isRestDay {
                Text("\(entry.exerciseCount) exercises")
                    .font(.caption)
            }
        }
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    TodayWorkoutWidget()
} timeline: {
    TodayWorkoutEntry(date: .now, focusArea: "Push", exerciseCount: 6, previewExercises: ["Bench Press"], isRestDay: false, isComplete: false)
}

#Preview(as: .systemMedium) {
    TodayWorkoutWidget()
} timeline: {
    TodayWorkoutEntry(date: .now, focusArea: "Push", exerciseCount: 6, previewExercises: ["Bench Press", "Incline Press", "OHP", "Lateral Raises"], isRestDay: false, isComplete: false)
}
