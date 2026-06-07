#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

struct TodayOverviewMetrics: View {
    let readiness: ReadinessAssessment
    let isHealthAuthorized: Bool
    let weeklyVolumeLoad: Double
    let sparklineValues: [Double]
    let trendLabel: String
    let trendIsPositive: Bool
    let onReadinessTap: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: VA.Space.md) {
                readinessTile
                    .frame(maxWidth: .infinity)
                weeklyVolumeTile
                    .frame(maxWidth: .infinity)
            }
            VStack(spacing: VA.Space.md) {
                readinessTile
                weeklyVolumeTile
            }
        }
    }

    private var readinessTile: some View {
        Button(action: onReadinessTap) {
            VACard(style: .glass) {
                if isHealthAuthorized {
                    connectedReadinessContent
                } else {
                    healthUnlockContent
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(readinessAccessibilityLabel)
        .accessibilityHint(readinessAccessibilityHint)
        .accessibilityIdentifier("today.readinessTile")
    }

    private var connectedReadinessContent: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            Text(String(localized: "Readiness", comment: "Today overview card label for readiness"))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)

            HStack {
                Spacer(minLength: 0)
                ZStack {
                    VAProgressRing(progress: Double(readiness.score) / 100, lineWidth: 9)
                        .frame(width: 108, height: 108)
                    VStack(spacing: VA.Space.xxs) {
                        Text("\(readiness.score)")
                            .font(VA.Typography.title)
                            .foregroundStyle(VA.Colors.textPrimary)
                            .contentTransition(.numericText())
                        Text(String(localized: "OF 100", comment: "Readiness score denominator label"))
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            Text(readiness.brief)
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var healthUnlockContent: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            Text(String(localized: "Readiness", comment: "Today overview card label for readiness"))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)

            HStack(spacing: VA.Space.md) {
                Image(systemName: "heart.text.square.fill")
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.primary)
                    .frame(width: 58, height: 58)
                    .background(VA.Colors.primary.opacity(VA.Opacity.subtleFill), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: VA.Space.xs) {
                    Text(String(
                        localized: "Grant Health to unlock",
                        comment: "Today readiness fallback title when Apple Health is not connected"
                    ))
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                    Text(String(
                        localized: "Connect Apple Health to bring recovery, sleep, and training history into today's prescription.",
                        comment: "Today readiness fallback body when Apple Health is not connected"
                    ))
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var readinessAccessibilityLabel: String {
        if isHealthAuthorized {
            return String(
                localized: "Readiness score \(readiness.score) out of 100. \(readiness.brief)",
                comment: "VoiceOver label describing the readiness overview card"
            )
        }

        return String(
            localized: """
            Grant Health to unlock readiness. Connect Apple Health to bring \
            recovery, sleep, and training history into today's prescription.
            """,
            comment: "VoiceOver label for the Today readiness fallback card"
        )
    }

    private var readinessAccessibilityHint: String {
        isHealthAuthorized
            ? String(localized: "Opens training signals", comment: "VoiceOver hint for connected Today readiness card")
            : String(localized: "Opens Profile to connect Apple Health", comment: "VoiceOver hint for disconnected Today readiness card")
    }

    private var weeklyVolumeTile: some View {
        VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "This week", comment: "Today overview card label for weekly volume"))
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)

                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text("\(Int(weeklyVolumeLoad))")
                        .font(VA.Typography.title)
                        .foregroundStyle(VA.Colors.textPrimary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.72)
                    Text(String(localized: "lb of volume", comment: "Weekly volume unit label"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }

                VAMiniSparkline(values: sparklineValues, color: VA.Colors.primary)
                    .frame(height: 38)

                HStack(spacing: VA.Space.xs) {
                    VAPill(
                        text: trendLabel,
                        icon: trendIsPositive ? "arrow.up.right" : "arrow.right",
                        color: trendIsPositive ? VA.Colors.success : VA.Colors.textSecondary
                    )
                    Text(String(localized: "vs last week", comment: "Weekly volume trend comparison label"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "This week \(Int(weeklyVolumeLoad)) pounds of volume, \(trendLabel) versus last week",
            comment: "VoiceOver label for the weekly volume overview card"
        ))
    }
}

private struct VAPill: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: VA.Space.xs) {
            Image(systemName: icon)
                .font(VA.Typography.caption)
            Text(text)
                .font(VA.Typography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, VA.Space.sm)
        .padding(.vertical, VA.Space.xs)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct VAMiniSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            ZStack {
                Path { path in
                    guard let first = points.first, let last = points.last else { return }
                    path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                    path.addLine(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.24), color.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let sanitizedValues = values.isEmpty ? [0, 0] : values
        let minValue = sanitizedValues.min() ?? 0
        let maxValue = sanitizedValues.max() ?? 1
        let range = max(maxValue - minValue, 1)
        let step = sanitizedValues.count > 1 ? size.width / CGFloat(sanitizedValues.count - 1) : 0

        return sanitizedValues.enumerated().map { index, value in
            let normalized = (value - minValue) / range
            return CGPoint(
                x: CGFloat(index) * step,
                y: size.height - (CGFloat(normalized) * size.height)
            )
        }
    }
}

struct TodayWeeklyVolumeSummary {
    let currentVolumeLoad: Double
    let currentWeekSessionCount: Int
    let sparklineValues: [Double]
    let trendPercent: Int?

    init(sessions: [RecentSession], calendar: Calendar = .current, now: Date = .now) {
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        let currentSessions = Self.sessions(sessions, in: currentWeek)
        let previousSessions: [RecentSession]

        if
            let currentWeek,
            let previousWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek.start) {
            previousSessions = Self.sessions(sessions, in: calendar.dateInterval(of: .weekOfYear, for: previousWeekDate))
        } else {
            previousSessions = []
        }

        currentVolumeLoad = currentSessions.map(\.totalVolumeLoad).reduce(0, +)
        currentWeekSessionCount = currentSessions.count
        sparklineValues = Self.sparklineValues(from: currentSessions)

        let previousVolumeLoad = previousSessions.map(\.totalVolumeLoad).reduce(0, +)
        trendPercent = previousVolumeLoad > 0
            ? Int(((currentVolumeLoad - previousVolumeLoad) / previousVolumeLoad * 100).rounded())
            : nil
    }

    private static func sessions(_ sessions: [RecentSession], in interval: DateInterval?) -> [RecentSession] {
        guard let interval else { return [] }
        return sessions.filter { interval.contains($0.date) }
    }

    private static func sparklineValues(from sessions: [RecentSession]) -> [Double] {
        let volumes = sessions.sorted { $0.date < $1.date }.suffix(6).map(\.totalVolumeLoad)
        return volumes.isEmpty ? [0, 0, 0, 0, 0, 0] : Array(volumes)
    }
}
#endif
