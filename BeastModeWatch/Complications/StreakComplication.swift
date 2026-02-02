// StreakComplication.swift
// BeastModeWatch
// Streak and weekly progress complication for Apple Watch

import SwiftUI
import WidgetKit
import AppIntents

/// Widget configuration for Streak complication with configurable display mode
struct StreakWidget: Widget {
    let kind: String = "Streak"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: StreakWidgetConfigurationIntent.self,
            provider: StreakTimelineProvider()
        ) { entry in
            ConfigurableStreakComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Workout Streak")
        .description("Shows your workout streak with configurable display options")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

// MARK: - Configurable Complication Views

/// Configurable view that displays streak based on user configuration
struct ConfigurableStreakComplicationView: View {
    let entry: StreakTimelineEntry

    @Environment(\.widgetFamily) var family

    private var displayMode: StreakDisplayMode {
        entry.configuration.displayMode
    }

    private var streakValue: Int {
        entry.data.streak(for: displayMode)
    }

    private var streakLabel: String {
        switch displayMode {
        case .currentStreak: return "day streak"
        case .longestStreak: return "best streak"
        }
    }

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
            // Progress ring
            Circle()
                .stroke(lineWidth: 4)
                .opacity(0.3)

            Circle()
                .trim(from: 0, to: entry.data.weeklyProgress.progressPercentage)
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .foregroundStyle(displayMode == .longestStreak ? .yellow : .orange)
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: 0) {
                Image(systemName: displayMode == .longestStreak ? "trophy.fill" : "flame.fill")
                    .font(.caption)
                    .foregroundStyle(displayMode == .longestStreak ? .yellow : .orange)

                Text("\(streakValue)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
        }
        .padding(4)
    }

    // MARK: - Rectangular

    private var rectangularView: some View {
        HStack(spacing: 12) {
            // Streak icon
            ZStack {
                Circle()
                    .fill((displayMode == .longestStreak ? Color.yellow : Color.orange).opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: displayMode == .longestStreak ? "trophy.fill" : "flame.fill")
                    .font(.title3)
                    .foregroundStyle(displayMode == .longestStreak ? .yellow : .orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(streakValue) \(streakLabel)")
                        .font(.headline)

                    Spacer()
                }

                // Weekly progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.secondary.opacity(0.3))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(.green)
                            .frame(width: geo.size.width * entry.data.weeklyProgress.progressPercentage, height: 4)
                    }
                }
                .frame(height: 4)

                Text("\(entry.data.weeklyProgress.completed)/\(entry.data.weeklyProgress.target) this week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Inline

    private var inlineView: some View {
        Label("\(streakValue) \(streakLabel)", systemImage: displayMode == .longestStreak ? "trophy.fill" : "flame.fill")
    }

    // MARK: - Corner

    private var cornerView: some View {
        ZStack {
            Image(systemName: displayMode == .longestStreak ? "trophy.fill" : "flame.fill")
                .foregroundStyle(displayMode == .longestStreak ? .yellow : .orange)
        }
        .widgetLabel {
            Gauge(value: Double(streakValue), in: 0...max(Double(streakValue), 30)) {
                Text("")
            } currentValueLabel: {
                Text("\(streakValue)")
            }
            .gaugeStyle(.accessoryLinear)
            .tint(displayMode == .longestStreak ? .yellow : .orange)
        }
    }
}

// MARK: - Legacy Complication Views (for backwards compatibility)

struct StreakComplicationView: View {
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
            // Progress ring
            Circle()
                .stroke(lineWidth: 4)
                .opacity(0.3)

            Circle()
                .trim(from: 0, to: entry.data.weeklyProgress.progressPercentage)
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .foregroundStyle(.orange)
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Text("\(entry.data.currentStreak)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
        }
        .padding(4)
    }

    // MARK: - Rectangular

    private var rectangularView: some View {
        HStack(spacing: 12) {
            // Streak flame
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(entry.data.currentStreak) day streak")
                        .font(.headline)

                    Spacer()
                }

                // Weekly progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.secondary.opacity(0.3))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(.green)
                            .frame(width: geo.size.width * entry.data.weeklyProgress.progressPercentage, height: 4)
                    }
                }
                .frame(height: 4)

                Text("\(entry.data.weeklyProgress.completed)/\(entry.data.weeklyProgress.target) this week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Inline

    private var inlineView: some View {
        Label("\(entry.data.currentStreak) day streak", systemImage: "flame.fill")
    }

    // MARK: - Corner

    private var cornerView: some View {
        ZStack {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
        }
        .widgetLabel {
            Gauge(value: Double(entry.data.currentStreak), in: 0...max(Double(entry.data.currentStreak), 30)) {
                Text("")
            } currentValueLabel: {
                Text("\(entry.data.currentStreak)")
            }
            .gaugeStyle(.accessoryLinear)
            .tint(.orange)
        }
    }
}

// MARK: - Weekly Progress Widget

/// Widget configuration for Weekly Progress complication with configurable goal
struct WeeklyProgressWidget: Widget {
    let kind: String = "WeeklyProgress"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WeeklyProgressWidgetConfigurationIntent.self,
            provider: WeeklyProgressTimelineProvider()
        ) { entry in
            ConfigurableWeeklyProgressComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weekly Progress")
        .description("Shows your workout progress with a configurable weekly goal")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

/// Configurable view that displays weekly progress based on user-set goal
struct ConfigurableWeeklyProgressComplicationView: View {
    let entry: WeeklyProgressTimelineEntry

    @Environment(\.widgetFamily) var family

    private var configuredTarget: Int {
        entry.configuration.weeklyGoal.rawValue
    }

    private var progressPercentage: Double {
        guard configuredTarget > 0 else { return 0 }
        return min(1.0, Double(entry.data.weeklyProgress.completed) / Double(configuredTarget))
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    // MARK: - Circular

    private var circularView: some View {
        Gauge(value: progressPercentage) {
            Image(systemName: "figure.strengthtraining.traditional")
        } currentValueLabel: {
            Text("\(entry.data.weeklyProgress.completed)")
                .font(.system(.title3, design: .rounded, weight: .bold))
        } minimumValueLabel: {
            Text("")
        } maximumValueLabel: {
            Text("\(configuredTarget)")
                .font(.caption2)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(progressGradient)
    }

    // MARK: - Rectangular

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Weekly Goal")
                    .font(.headline)
                Spacer()
                Text("\(entry.data.weeklyProgress.completed)/\(configuredTarget)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Day indicators based on configured target
            HStack(spacing: 4) {
                ForEach(0..<configuredTarget, id: \.self) { day in
                    Circle()
                        .fill(day < entry.data.weeklyProgress.completed ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: max(8, 56 / CGFloat(configuredTarget)), height: max(8, 56 / CGFloat(configuredTarget)))
                }
            }

            if entry.data.weeklyProgress.completed >= configuredTarget {
                Text("Goal reached!")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text("\(configuredTarget - entry.data.weeklyProgress.completed) more to go")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Inline

    private var inlineView: some View {
        Label("\(entry.data.weeklyProgress.completed)/\(configuredTarget) workouts", systemImage: "calendar")
    }

    private var progressGradient: Gradient {
        if entry.data.weeklyProgress.completed >= configuredTarget {
            return Gradient(colors: [.green, .green])
        } else if progressPercentage >= 0.5 {
            return Gradient(colors: [.yellow, .green])
        } else {
            return Gradient(colors: [.orange, .yellow])
        }
    }
}

/// Legacy view for backwards compatibility
struct WeeklyProgressComplicationView: View {
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
        default:
            circularView
        }
    }

    // MARK: - Circular

    private var circularView: some View {
        Gauge(value: entry.data.weeklyProgress.progressPercentage) {
            Image(systemName: "figure.strengthtraining.traditional")
        } currentValueLabel: {
            Text("\(entry.data.weeklyProgress.completed)")
                .font(.system(.title3, design: .rounded, weight: .bold))
        } minimumValueLabel: {
            Text("")
        } maximumValueLabel: {
            Text("\(entry.data.weeklyProgress.target)")
                .font(.caption2)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(progressGradient)
    }

    // MARK: - Rectangular

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Weekly Goal")
                    .font(.headline)
                Spacer()
                Text("\(entry.data.weeklyProgress.completed)/\(entry.data.weeklyProgress.target)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Day indicators
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { day in
                    Circle()
                        .fill(day < entry.data.weeklyProgress.completed ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 12, height: 12)
                }
            }

            if entry.data.weeklyProgress.completed >= entry.data.weeklyProgress.target {
                Text("Goal reached!")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text("\(entry.data.weeklyProgress.target - entry.data.weeklyProgress.completed) more to go")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Inline

    private var inlineView: some View {
        Label("\(entry.data.weeklyProgress.completed)/\(entry.data.weeklyProgress.target) workouts", systemImage: "calendar")
    }

    private var progressGradient: Gradient {
        if entry.data.weeklyProgress.completed >= entry.data.weeklyProgress.target {
            return Gradient(colors: [.green, .green])
        } else if entry.data.weeklyProgress.progressPercentage >= 0.5 {
            return Gradient(colors: [.yellow, .green])
        } else {
            return Gradient(colors: [.orange, .yellow])
        }
    }
}

// MARK: - Widget Bundle

@main
struct BeastModeWidgets: WidgetBundle {
    var body: some Widget {
        TodayWorkoutWidget()
        StreakWidget()
        WeeklyProgressWidget()
    }
}

// MARK: - Previews

#Preview("Streak - Current", as: .accessoryCircular) {
    StreakWidget()
} timeline: {
    StreakTimelineEntry(
        date: .now,
        data: ComplicationData(
            currentStreak: 14,
            longestStreak: 30,
            todayWorkout: nil,
            weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
            lastUpdated: .now
        ),
        configuration: StreakWidgetConfigurationIntent(displayMode: .currentStreak)
    )
}

#Preview("Streak - Longest", as: .accessoryCircular) {
    StreakWidget()
} timeline: {
    StreakTimelineEntry(
        date: .now,
        data: ComplicationData(
            currentStreak: 14,
            longestStreak: 30,
            todayWorkout: nil,
            weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
            lastUpdated: .now
        ),
        configuration: StreakWidgetConfigurationIntent(displayMode: .longestStreak)
    )
}

#Preview("Streak Rectangular", as: .accessoryRectangular) {
    StreakWidget()
} timeline: {
    StreakTimelineEntry(
        date: .now,
        data: ComplicationData(
            currentStreak: 7,
            longestStreak: 21,
            todayWorkout: nil,
            weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
            lastUpdated: .now
        ),
        configuration: StreakWidgetConfigurationIntent(displayMode: .currentStreak)
    )
}

#Preview("Weekly Progress - 4 Goal", as: .accessoryCircular) {
    WeeklyProgressWidget()
} timeline: {
    WeeklyProgressTimelineEntry(
        date: .now,
        data: ComplicationData(
            currentStreak: 7,
            longestStreak: 14,
            todayWorkout: nil,
            weeklyProgress: WeeklyProgressData(completed: 3, target: 4),
            lastUpdated: .now
        ),
        configuration: WeeklyProgressWidgetConfigurationIntent(weeklyGoal: .four)
    )
}

#Preview("Weekly Progress - 6 Goal", as: .accessoryRectangular) {
    WeeklyProgressWidget()
} timeline: {
    WeeklyProgressTimelineEntry(
        date: .now,
        data: ComplicationData(
            currentStreak: 7,
            longestStreak: 14,
            todayWorkout: nil,
            weeklyProgress: WeeklyProgressData(completed: 4, target: 4),
            lastUpdated: .now
        ),
        configuration: WeeklyProgressWidgetConfigurationIntent(weeklyGoal: .six)
    )
}
