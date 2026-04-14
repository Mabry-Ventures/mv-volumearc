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
            LazyVStack(alignment: .leading, spacing: VA.Space.lg) {
                readinessHero
                readinessFactors
                volumeCard
                trainingFrequencyCard
            }
            .padding(VA.Space.lg)
        }
        .background(VA.Colors.surfaceSecondary)
        .navigationTitle(DashboardTab.signals.title)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.refresh() }
    }

    // MARK: - Readiness hero

    private var readinessHero: some View {
        VACard(style: .accent) {
            HStack(spacing: VA.Space.xl) {
                VAProgressRing(
                    progress: Double(model.readiness.score) / 100,
                    lineWidth: 14,
                    color: readinessColor
                )
                .frame(width: 120, height: 120)
                .overlay {
                    VStack(spacing: 0) {
                        Text("\(model.readiness.score)")
                            .font(VA.Typography.display)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(String(localized: "READY", comment: "Caption inside the readiness ring"))
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .tracking(1)
                    }
                }

                VStack(alignment: .leading, spacing: VA.Space.sm) {
                    Text(String(localized: "STATUS", comment: "Label above the readiness brief on Signals tab"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.5)
                    Text(model.readiness.brief)
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textPrimary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "Readiness score: \(model.readiness.score). \(model.readiness.brief)",
            comment: "VoiceOver label for the readiness hero on Signals tab"
        ))
    }

    private var readinessColor: Color {
        switch model.readiness.score {
        case 75...: return VA.Colors.success
        case 50..<75: return VA.Colors.warning
        default: return VA.Colors.error
        }
    }

    // MARK: - Factors

    @ViewBuilder
    private var readinessFactors: some View {
        if !model.readiness.factors.isEmpty {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                VASectionHeader(String(
                    localized: "Contributing Factors",
                    comment: "Section header for readiness breakdown factors"
                ))
                ForEach(model.readiness.factors) { factor in
                    factorRow(factor)
                }
            }
        }
    }

    private func factorRow(_ factor: ReadinessAssessment.Factor) -> some View {
        VACard(style: .flat) {
            HStack {
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(factor.name)
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(factor.detail)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer()
                Text(factor.impact > 0 ? "+\(factor.impact)" : "\(factor.impact)")
                    .font(VA.Typography.title2)
                    .foregroundStyle(factorColor(factor.impact))
                    .contentTransition(.numericText())
            }
        }
    }

    private func factorColor(_ impact: Int) -> Color {
        switch impact {
        case 0: return VA.Colors.textSecondary
        case 1...: return VA.Colors.success
        default: return VA.Colors.warning
        }
    }

    // MARK: - Volume card

    private var volumeCard: some View {
        VACard(style: .elevated) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                VASectionHeader(
                    String(localized: "Training Volume", comment: "Section header on Signals tab for volume card"),
                    subtitle: String(localized: "Last 7 days", comment: "Subtitle — last 7 days timeframe")
                )
                HStack(spacing: VA.Space.xl) {
                    VAMetricDisplay(
                        label: String(localized: "Total Load", comment: "Metric label — total training volume load"),
                        value: "\(Int(totalVolume))",
                        unit: String(localized: "lb", comment: "Weight unit abbreviation — pounds"),
                        style: .hero
                    )
                    Spacer()
                    VAMetricDisplay(
                        label: String(localized: "Sessions", comment: "Metric label — number of sessions"),
                        value: "\(model.recentSessions.count)",
                        style: .standard
                    )
                }
            }
        }
    }

    private var totalVolume: Double {
        model.recentSessions.map(\.totalVolumeLoad).reduce(0, +)
    }

    // MARK: - Frequency

    private var trainingFrequencyCard: some View {
        VACard(style: .flat) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                VASectionHeader(String(
                    localized: "Training Frequency",
                    comment: "Section header on Signals tab for frequency card"
                ))
                HStack(spacing: VA.Space.md) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        dayCircle(for: dayIndex)
                    }
                }
                Text(String(
                    localized: "\(model.recentSessions.count) of \(model.athlete.weeklyTrainingDays) weekly sessions",
                    comment: "Frequency summary — actual vs target weekly sessions"
                ))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
            }
        }
    }

    private func dayCircle(for dayIndex: Int) -> some View {
        let calendar = Calendar.current
        let today = Date.now
        let dayDate = calendar.date(byAdding: .day, value: -dayIndex, to: today) ?? today
        let hasSession = model.recentSessions.contains { session in
            calendar.isDate(session.date, inSameDayAs: dayDate)
        }
        let label = dayDate.formatted(.dateTime.weekday(.narrow))

        return VStack(spacing: VA.Space.xs) {
            Circle()
                .fill(hasSession ? VA.Colors.primary : VA.Colors.surfaceTertiary)
                .frame(width: 32, height: 32)
                .overlay {
                    if hasSession {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
            Text(label)
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
