#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Signals tab — readiness breakdown, volume trends, training load.
public struct SignalsView: View {
    @ObservedObject var model: WorkoutDashboardModel

    public init(model: WorkoutDashboardModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VA.Space.xxl) {
                signalsHeader
                readinessSummaryCard
                inputsSection
                weeklyVolumeSection
                frequencySection
            }
            .padding(VA.Space.lg)
            .padding(.bottom, VA.Space.xxl)
        }
        .background(VA.Colors.surfaceGrouped)
        .navigationTitle(DashboardTab.signals.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }

    private var signalsHeader: some View {
        VStack(alignment: .leading, spacing: VA.Space.xxs) {
            Text(DashboardTab.signals.title)
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
            Text(String(
                localized: "From your recovery data and training history",
                comment: "Signals screen subtitle"
            ))
            .font(VA.Typography.footnote)
            .foregroundStyle(VA.Colors.textSecondary)
        }
        .padding(.top, VA.Space.sm)
    }

    private var readinessSummaryCard: some View {
        VACard(style: .glass) {
            HStack(alignment: .center, spacing: VA.Space.lg) {
                VStack(alignment: .leading, spacing: VA.Space.xs) {
                    Text(String(localized: "Readiness today", comment: "Signals readiness card label"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                    Text("\(model.readiness.score)")
                        .font(VA.Typography.display)
                        .foregroundStyle(VA.Colors.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    HStack(spacing: VA.Space.xs) {
                        WorkoutChip(text: readinessDeltaLabel, tone: readinessDeltaTone)
                        Text(String(localized: "vs 7-day avg", comment: "Signals readiness comparison label"))
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textTertiary)
                    }
                }

                SignalSparkline(values: readinessTrend, color: VA.Colors.primary)
                    .frame(minWidth: 120, maxWidth: .infinity)
                    .frame(height: 72)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "Readiness today \(model.readiness.score), \(readinessDeltaLabel) versus the seven day average",
            comment: "VoiceOver label for the Signals readiness summary"
        ))
    }

    private var inputsSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            Text(String(localized: "Inputs", comment: "Signals readiness inputs section title"))
                .font(VA.Typography.title2)
                .foregroundStyle(VA.Colors.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: VA.Space.md) {
                ForEach(signalInputs) { input in
                    SignalInputCard(input: input)
                }
            }
        }
    }

    private var weeklyVolumeSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Weekly volume", comment: "Signals weekly volume section title"))
                    .font(VA.Typography.title2)
                    .foregroundStyle(VA.Colors.textPrimary)
                Spacer()
                Text(String(localized: "6 weeks", comment: "Signals weekly volume range label"))
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textTertiary)
            }

            VACard(style: .elevated) {
                VStack(alignment: .leading, spacing: VA.Space.lg) {
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(String(localized: "This week", comment: "Signals current week volume label"))
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: VA.Space.xs) {
                            Text("\(Int(thisWeekVolume))")
                                .font(VA.Typography.display)
                                .foregroundStyle(VA.Colors.textPrimary)
                                .monospacedDigit()
                                .minimumScaleFactor(0.7)
                            Text(String(localized: "lb so far", comment: "Signals current week volume unit"))
                                .font(VA.Typography.footnote)
                                .foregroundStyle(VA.Colors.textSecondary)
                        }
                    }

                    WeeklyVolumeBars(weeks: weeklyVolumes)
                        .frame(height: 156)
                }
            }
        }
    }

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            Text(String(localized: "Frequency", comment: "Signals training frequency section title"))
                .font(VA.Typography.title2)
                .foregroundStyle(VA.Colors.textPrimary)
            VACard(style: .flat) {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    FrequencyHeatmap(sessions: model.recentSessions)
                    HStack {
                        Text(String(localized: "M T W T F S S", comment: "Signals frequency weekday legend"))
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textTertiary)
                        Spacer()
                        Text(String(
                            localized: "\(currentWeekSessionCount) of ^[\(model.athlete.weeklyTrainingDays) weekly sessions](inflect: true)",
                            comment: "Signals frequency summary"
                        ))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                    }
                }
            }
        }
    }

    private var readinessDelta: Int {
        model.readiness.factors.map(\.impact).reduce(0, +)
    }

    private var readinessDeltaLabel: String {
        readinessDelta > 0 ? "+\(readinessDelta)" : "\(readinessDelta)"
    }

    private var readinessDeltaTone: WorkoutChip.Tone {
        readinessDelta >= 0 ? .success : .neutral
    }

    private var readinessTrend: [Double] {
        let score = Double(model.readiness.score)
        return [score - 12, score - 8, score - 10, score - 4, score - 2, score]
            .map { min(100, max(0, $0)) }
    }

    private var signalInputs: [SignalInput] {
        let mappedFactors = model.readiness.factors.prefix(4).map { factor in
            SignalInput(
                title: factor.name,
                value: factor.impact > 0 ? "+\(factor.impact)" : "\(factor.impact)",
                detail: factor.detail,
                icon: factor.impact >= 0 ? "arrow.up.right" : "arrow.down.right",
                trend: trendValues(for: factor.impact),
                color: factorColor(factor.impact)
            )
        }

        if !mappedFactors.isEmpty {
            return Array(mappedFactors)
        }

        return [
            SignalInput(
                title: "HRV",
                value: "71 ms",
                detail: "Above baseline",
                icon: "heart.fill",
                trend: [62, 64, 66, 64, 68, 71],
                color: VA.Colors.success
            ),
            SignalInput(
                title: "Sleep",
                value: "7.4h",
                detail: "Consistent",
                icon: "bed.double.fill",
                trend: [7.0, 7.2, 6.8, 7.0, 7.2, 7.4],
                color: VA.Colors.success
            ),
            SignalInput(
                title: "Recovery",
                value: "Good",
                detail: "Ready to train",
                icon: "waveform.path.ecg",
                trend: [70, 72, 74, 76, 75, 78],
                color: VA.Colors.primary
            ),
            SignalInput(
                title: "Soreness",
                value: "2/10",
                detail: "Low",
                icon: "figure.run",
                trend: [4, 3, 3, 2, 2, 2],
                color: VA.Colors.textSecondary
            ),
        ]
    }

    private var weeklyVolumes: [WeeklyVolume] {
        let calendar = Calendar.current
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (0..<6).reversed().map { offset in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek) ?? currentWeek
            let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart)
            let volume = model.recentSessions
                .filter { session in interval?.contains(session.date) == true }
                .map(\.totalVolumeLoad)
                .reduce(0, +)
            return WeeklyVolume(
                label: weekStart.formatted(.dateTime.day()),
                volume: volume,
                isPartial: offset == 0
            )
        }
    }

    private var thisWeekVolume: Double {
        weeklyVolumes.last?.volume ?? 0
    }

    private var currentWeekSessionCount: Int {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: .now)
        return model.recentSessions.filter { session in interval?.contains(session.date) == true }.count
    }

    private func trendValues(for impact: Int) -> [Double] {
        let baseline = 70.0 + Double(impact * 2)
        return [baseline - 8, baseline - 4, baseline - 5, baseline - 1, baseline, baseline + 2]
    }

    private func factorColor(_ impact: Int) -> Color {
        switch impact {
        case 1...: return VA.Colors.success
        case 0: return VA.Colors.textSecondary
        default: return VA.Colors.warning
        }
    }
}

private struct SignalInput: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let icon: String
    let trend: [Double]
    let color: Color
}

private struct WeeklyVolume: Identifiable {
    let id = UUID()
    let label: String
    let volume: Double
    let isPartial: Bool
}

private struct SignalInputCard: View {
    let input: SignalInput

    var body: some View {
        VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                HStack(spacing: VA.Space.xs) {
                    Image(systemName: input.icon)
                        .font(VA.Typography.caption)
                        .foregroundStyle(input.color)
                    Text(input.title)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Text(input.value)
                    .font(VA.Typography.title2)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(input.detail)
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textTertiary)
                    .lineLimit(2)
                SignalSparkline(values: input.trend, color: input.color)
                    .frame(height: 32)
            }
        }
    }
}

private struct SignalSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let values = values.isEmpty ? [0, 0] : values
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, 1)
        let step = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - CGFloat((value - minValue) / range) * size.height
            )
        }
    }
}

private struct WeeklyVolumeBars: View {
    let weeks: [WeeklyVolume]

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: VA.Space.sm) {
                ForEach(weeks) { week in
                    VStack(spacing: VA.Space.xs) {
                        RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous)
                            .fill(barFill(week))
                            .frame(height: barHeight(for: week, in: proxy.size.height - 24))
                        Text(week.label)
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var maxVolume: Double {
        max(weeks.map(\.volume).max() ?? 1, 1)
    }

    private func barHeight(for week: WeeklyVolume, in availableHeight: CGFloat) -> CGFloat {
        max(8, CGFloat(week.volume / maxVolume) * availableHeight)
    }

    private func barFill(_ week: WeeklyVolume) -> LinearGradient {
        LinearGradient(
            colors: week.isPartial
                ? [VA.Colors.primary.opacity(0.35), VA.Colors.primary.opacity(0.18)]
                : [VA.Colors.primary, VA.Colors.sunriseA],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

private struct FrequencyHeatmap: View {
    let sessions: [RecentSession]

    var body: some View {
        VStack(spacing: VA.Space.xs) {
            heatmapRow(week: 0)
            heatmapRow(week: 1)
            heatmapRow(week: 2)
            heatmapRow(week: 3)
            heatmapRow(week: 4)
            heatmapRow(week: 5)
            heatmapRow(week: 6)
            heatmapRow(week: 7)
        }
        .accessibilityHidden(true)
    }

    private func heatmapRow(week: Int) -> some View {
        HStack(spacing: VA.Space.xs) {
            Text("W\(week + 1)")
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textTertiary)
                .frame(width: 28, alignment: .leading)
            heatmapCell(week: week, day: 0)
            heatmapCell(week: week, day: 1)
            heatmapCell(week: week, day: 2)
            heatmapCell(week: week, day: 3)
            heatmapCell(week: week, day: 4)
            heatmapCell(week: week, day: 5)
            heatmapCell(week: week, day: 6)
        }
    }

    private func heatmapCell(week: Int, day: Int) -> some View {
        RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous)
            .fill(fillColor(week: week, day: day))
            .aspectRatio(1, contentMode: .fit)
    }

    private func fillColor(week: Int, day: Int) -> Color {
        let calendar = Calendar.current
        let daysAgo = ((7 - week) * 7) + (6 - day)
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let hasSession = sessions.contains { calendar.isDate($0.date, inSameDayAs: date) }
        if hasSession {
            return VA.Colors.primary.opacity(0.76)
        }
        return VA.Colors.textTertiary.opacity(0.12)
    }
}
#endif
