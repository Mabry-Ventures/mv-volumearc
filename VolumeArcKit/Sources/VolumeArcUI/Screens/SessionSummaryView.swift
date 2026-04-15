#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// Session summary shown after a workout is completed.
/// Celebrates the win and surfaces the key metrics with a staggered appear animation.
public struct SessionSummaryView: View {
    private let sets: Int
    private let totalVolume: Double
    private let duration: Int
    private let averageRPE: Double
    private let primaryLift: String
    private let onContinue: () -> Void

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        sets: Int,
        totalVolume: Double,
        duration: Int,
        averageRPE: Double,
        primaryLift: String,
        onContinue: @escaping () -> Void
    ) {
        self.sets = sets
        self.totalVolume = totalVolume
        self.duration = duration
        self.averageRPE = averageRPE
        self.primaryLift = primaryLift
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: VA.Space.xl) {
            Spacer()
            celebration
            metricsGrid
            Spacer()
            continueButton
        }
        .padding(VA.Space.xl)
        .background(
            LinearGradient(
                colors: [
                    VA.Colors.primary.opacity(0.2),
                    VA.Colors.success.opacity(0.1),
                    VA.Colors.surfacePrimary,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onAppear {
            VAHaptics.workoutComplete()
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(VAAnimation.bouncy.delay(0.1)) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: - Celebration

    private var celebration: some View {
        VStack(spacing: VA.Space.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [VA.Colors.success, VA.Colors.primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .scaleEffect(hasAppeared ? 1 : 0.2)
                    .opacity(hasAppeared ? 1 : 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Color.white)
                    .scaleEffect(hasAppeared ? 1 : 0.5)
                    .opacity(hasAppeared ? 1 : 0)
            }

            Text(String(localized: "Session Complete", comment: "Session summary celebration headline"))
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)

            Text(String(
                localized: "Great work on \(primaryLift).",
                comment: "Session summary subtitle congratulating the user on the primary lift"
            ))
                .font(VA.Typography.body)
                .foregroundStyle(VA.Colors.textSecondary)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
        }
    }

    // MARK: - Metrics grid

    private var metricsGrid: some View {
        VStack(spacing: VA.Space.md) {
            HStack(spacing: VA.Space.md) {
                metricCard(
                    label: String(localized: "SETS", comment: "Session summary metric label — sets"),
                    value: "\(sets)",
                    icon: "checkmark.circle.fill",
                    color: VA.Colors.success
                )
                metricCard(
                    label: String(localized: "VOLUME", comment: "Session summary metric label — total volume"),
                    value: "\(Int(totalVolume))",
                    unit: String(localized: "lb", comment: "Weight unit abbreviation — pounds"),
                    icon: "scalemass.fill",
                    color: VA.Colors.primary
                )
            }
            HStack(spacing: VA.Space.md) {
                metricCard(
                    label: String(localized: "DURATION", comment: "Session summary metric label — duration"),
                    value: "\(duration)",
                    unit: String(localized: "min", comment: "Duration unit abbreviation — minutes"),
                    icon: "clock.fill",
                    color: VA.Colors.secondary
                )
                metricCard(
                    label: String(localized: "AVG RPE", comment: "Session summary metric label — average RPE"),
                    value: String(format: "%.1f", averageRPE),
                    icon: "flame.fill",
                    color: VA.Colors.warning
                )
            }
        }
    }

    private func metricCard(
        label: String,
        value: String,
        unit: String? = nil,
        icon: String,
        color: Color
    ) -> some View {
        VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.xs) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                    Spacer()
                }
                Text(label)
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.5)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(VA.Typography.display)
                        .foregroundStyle(VA.Colors.textPrimary)
                        .contentTransition(.numericText())
                    if let unit {
                        Text(unit)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                    }
                }
            }
        }
        .scaleEffect(hasAppeared ? 1 : 0.85)
        .opacity(hasAppeared ? 1 : 0)
    }

    // MARK: - Continue

    private var continueButton: some View {
        VAButton(
            String(localized: "Done", comment: "Session summary dismiss button"),
            icon: "arrow.right",
            style: .primary
        ) {
            VAHaptics.tap()
            onContinue()
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 20)
    }
}
#endif
