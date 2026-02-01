import SwiftUI
import WidgetKit

/// Widget showing weekly workout progress
struct WeeklyProgressWidget: Widget {
    let kind = "WeeklyProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyProgressProvider()) { entry in
            WeeklyProgressWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weekly Progress")
        .description("See your workout completion this week")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Entry

struct WeeklyProgressEntry: TimelineEntry {
    let date: Date
    let daysCompleted: Int
    let totalDays: Int
    let weekDays: [WeekDayStatus]
    let totalVolume: Double
    let totalSets: Int

    struct WeekDayStatus: Identifiable {
        let id = UUID()
        let dayLetter: String
        let isCompleted: Bool
        let isToday: Bool
        let isRestDay: Bool
    }
}

// MARK: - Provider

struct WeeklyProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyProgressEntry {
        createSampleEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyProgressEntry) -> Void) {
        completion(createSampleEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyProgressEntry>) -> Void) {
        let entry = createSampleEntry()

        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    private func createSampleEntry() -> WeeklyProgressEntry {
        let weekDays = [
            WeeklyProgressEntry.WeekDayStatus(dayLetter: "M", isCompleted: true, isToday: false, isRestDay: false),
            WeeklyProgressEntry.WeekDayStatus(dayLetter: "T", isCompleted: true, isToday: false, isRestDay: false),
            WeeklyProgressEntry.WeekDayStatus(dayLetter: "W", isCompleted: true, isToday: false, isRestDay: false),
            WeeklyProgressEntry.WeekDayStatus(dayLetter: "T", isCompleted: false, isToday: true, isRestDay: false),
            WeeklyProgressEntry.WeekDayStatus(dayLetter: "F", isCompleted: false, isToday: false, isRestDay: false),
            WeeklyProgressEntry.WeekDayStatus(dayLetter: "S", isCompleted: false, isToday: false, isRestDay: false),
            WeeklyProgressEntry.WeekDayStatus(dayLetter: "S", isCompleted: false, isToday: false, isRestDay: true)
        ]

        return WeeklyProgressEntry(
            date: Date(),
            daysCompleted: 3,
            totalDays: 6,
            weekDays: weekDays,
            totalVolume: 45000,
            totalSets: 72
        )
    }
}

// MARK: - Widget View

struct WeeklyProgressWidgetView: View {
    let entry: WeeklyProgressEntry

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
                Image(systemName: "calendar")
                    .foregroundStyle(.purple)
                Text("This Week")
                    .font(.caption.weight(.semibold))
            }

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.purple.opacity(0.2), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: Double(entry.daysCompleted) / Double(entry.totalDays))
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(entry.daysCompleted)")
                        .font(.title.weight(.bold))
                    Text("of \(entry.totalDays)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            // Day indicators
            HStack(spacing: 4) {
                ForEach(entry.weekDays) { day in
                    dayIndicator(day)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var mediumWidget: some View {
        HStack(spacing: 16) {
            // Left: Progress ring
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.purple.opacity(0.2), lineWidth: 10)

                    Circle()
                        .trim(from: 0, to: Double(entry.daysCompleted) / Double(entry.totalDays))
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(entry.daysCompleted)/\(entry.totalDays)")
                            .font(.title2.weight(.bold))
                        Text("days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 100, height: 100)

                // Day indicators
                HStack(spacing: 4) {
                    ForEach(entry.weekDays) { day in
                        dayIndicator(day)
                    }
                }
            }

            Divider()

            // Right: Stats
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly Stats")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    statRow(icon: "scalemass.fill", label: "Volume", value: formatVolume(entry.totalVolume))
                    statRow(icon: "number", label: "Total Sets", value: "\(entry.totalSets)")
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var accessoryWidget: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(entry.daysCompleted)/\(entry.totalDays)")
                    .font(.headline)
                Text("workouts")
                    .font(.caption)
            }

            HStack(spacing: 2) {
                ForEach(entry.weekDays) { day in
                    Circle()
                        .fill(day.isCompleted ? Color.purple : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
    }

    private func dayIndicator(_ day: WeeklyProgressEntry.WeekDayStatus) -> some View {
        ZStack {
            Circle()
                .fill(dayColor(day))
                .frame(width: 20, height: 20)

            Text(day.dayLetter)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(day.isCompleted ? .white : .primary)
        }
    }

    private func dayColor(_ day: WeeklyProgressEntry.WeekDayStatus) -> Color {
        if day.isCompleted {
            return .purple
        } else if day.isToday {
            return .purple.opacity(0.3)
        } else if day.isRestDay {
            return .gray.opacity(0.2)
        }
        return .gray.opacity(0.1)
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.purple)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk lbs", volume / 1000)
        }
        return "\(Int(volume)) lbs"
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    WeeklyProgressWidget()
} timeline: {
    WeeklyProgressEntry(
        date: .now,
        daysCompleted: 3,
        totalDays: 6,
        weekDays: [],
        totalVolume: 45000,
        totalSets: 72
    )
}
