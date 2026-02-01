// TodayWorkoutComplication.swift
// BeastModeWatch
// Today's workout complication for Apple Watch

import SwiftUI
import WidgetKit

/// Widget configuration for Today's Workout complication
struct TodayWorkoutWidget: Widget {
    let kind: String = "TodayWorkout"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BeastModeTimelineProvider()) { entry in
            TodayWorkoutComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Workout")
        .description("Shows today's planned workout from your active plan")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

// MARK: - Complication Views

struct TodayWorkoutComplicationView: View {
    let entry: BeastModeTimelineEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        case .accessoryCorner:
            cornerView
        default:
            circularView
        }
    }

    // MARK: - Circular

    private var circularView: some View {
        ZStack {
            if let workout = entry.data.todayWorkout {
                if workout.isRestDay {
                    VStack(spacing: 2) {
                        Image(systemName: "bed.double.fill")
                            .font(.title3)
                        Text("Rest")
                            .font(.caption2)
                    }
                } else if workout.isCompleted {
                    VStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text("Done")
                            .font(.caption2)
                    }
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title3)
                        Text("\(workout.exerciseCount)")
                            .font(.headline)
                    }
                }
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title3)
                    Text("Plan")
                        .font(.caption2)
                }
            }
        }
    }

    // MARK: - Rectangular

    private var rectangularView: some View {
        HStack(spacing: 8) {
            if let workout = entry.data.todayWorkout {
                if workout.isRestDay {
                    Image(systemName: "bed.double.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading) {
                        Text("Rest Day")
                            .font(.headline)
                        Text("Recovery time")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: workout.isCompleted ? "checkmark.circle.fill" : "figure.strengthtraining.traditional")
                        .font(.title3)
                        .foregroundStyle(workout.isCompleted ? .green : .orange)

                    VStack(alignment: .leading) {
                        Text(workout.dayName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(workout.isCompleted ? "Completed" : "\(workout.exerciseCount) exercises")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3)

                VStack(alignment: .leading) {
                    Text("No Plan")
                        .font(.headline)
                    Text("Set an active plan")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Inline

    private var inlineView: some View {
        Group {
            if let workout = entry.data.todayWorkout {
                if workout.isRestDay {
                    Label("Rest Day", systemImage: "bed.double.fill")
                } else if workout.isCompleted {
                    Label("Workout Done", systemImage: "checkmark.circle.fill")
                } else {
                    Label("\(workout.dayName) - \(workout.exerciseCount) exercises", systemImage: "figure.strengthtraining.traditional")
                }
            } else {
                Label("No workout plan", systemImage: "calendar")
            }
        }
    }

    // MARK: - Corner

    private var cornerView: some View {
        ZStack {
            if let workout = entry.data.todayWorkout {
                if workout.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if workout.isRestDay {
                    Image(systemName: "bed.double.fill")
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(.orange)
                }
            } else {
                Image(systemName: "calendar")
            }
        }
        .widgetLabel {
            if let workout = entry.data.todayWorkout {
                Text(workout.isRestDay ? "Rest" : workout.dayName)
            } else {
                Text("Beast Mode")
            }
        }
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    TodayWorkoutWidget()
} timeline: {
    BeastModeTimelineEntry(
        date: .now,
        data: ComplicationData(
            currentStreak: 7,
            todayWorkout: TodayWorkoutData(
                dayName: "Push Day",
                exerciseCount: 6,
                isRestDay: false,
                isCompleted: false
            ),
            weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
            lastUpdated: .now
        )
    )

    BeastModeTimelineEntry(
        date: .now,
        data: ComplicationData(
            currentStreak: 7,
            todayWorkout: TodayWorkoutData(
                dayName: "Rest",
                exerciseCount: 0,
                isRestDay: true,
                isCompleted: false
            ),
            weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
            lastUpdated: .now
        )
    )
}

#Preview(as: .accessoryRectangular) {
    TodayWorkoutWidget()
} timeline: {
    BeastModeTimelineEntry(
        date: .now,
        data: ComplicationData(
            currentStreak: 7,
            todayWorkout: TodayWorkoutData(
                dayName: "Push Day",
                exerciseCount: 6,
                isRestDay: false,
                isCompleted: false
            ),
            weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
            lastUpdated: .now
        )
    )
}
