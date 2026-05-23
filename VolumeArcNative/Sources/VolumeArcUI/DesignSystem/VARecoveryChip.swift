#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// VOL-181 Phase 1B: Today-tab insight chip that surfaces the
/// **dominant recovery signal** from a `RecoveryContext`. Tap opens a
/// sheet with the full breakdown.
///
/// Priority (first match wins):
/// 1. HRV delta if `|hrvDeltaPercent| > 5` (the threshold above which
///    Apple's own coaching surfaces flag a trend change)
/// 2. Sleep debt if `|sleepDebtHours| > 2` (a deficit large enough
///    that programming should react)
/// 3. Apple Watch Vitals score, when present
/// 4. Wrist-temperature or respiratory-rate vitals trend
/// 5. Apple Workout Effort / Training Load score
/// 6. "All systems normal" fallback when data is present but
///    unremarkable
///
/// Renders nothing (`EmptyView`) when `recovery.hasAnyData == false` —
/// caller doesn't need to gate, the chip self-suppresses on the no-HK
/// path.
public struct VARecoveryChip: View {

    private let recovery: RecoveryContext
    @State private var isDetailPresented: Bool = false

    public init(recovery: RecoveryContext) {
        self.recovery = recovery
    }

    public var body: some View {
        if recovery.hasAnyData {
            content
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var content: some View {
        Button {
            isDetailPresented = true
        } label: {
            HStack(spacing: VA.Space.sm) {
                Image(systemName: dominantSignal.iconName)
                    .font(VA.Typography.headline)
                    .foregroundStyle(dominantSignal.tint)
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(String(localized: "Vitals say", comment: "Recovery chip leading label"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                    Text(dominantSignal.headline)
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                }
                Spacer(minLength: VA.Space.sm)
                Image(systemName: "chevron.right")
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textTertiary)
            }
            .padding(.horizontal, VA.Space.lg)
            .padding(.vertical, VA.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                    .fill(VA.Colors.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                    .strokeBorder(dominantSignal.tint.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.recoveryChip")
        .accessibilityLabel(Text(dominantSignal.accessibilityLabel))
        .sheet(isPresented: $isDetailPresented) {
            VARecoveryDetailSheet(recovery: recovery)
        }
    }

    // MARK: - Dominant signal selection

    private struct Signal {
        let headline: String
        let iconName: String
        let tint: Color
        let accessibilityLabel: String
    }

    private var dominantSignal: Signal {
        if let delta = recovery.hrvDeltaPercent, abs(delta) > 5 {
            let sign = delta >= 0 ? "↑" : "↓"
            let pct = String(format: "%.0f", abs(delta))
            let direction = delta >= 0 ? "up" : "down"
            return Signal(
                headline: String(
                    localized: "HRV \(sign) \(pct)% vs baseline",
                    comment: "Recovery chip headline for HRV trend"
                ),
                iconName: delta >= 0 ? "heart.text.square.fill" : "heart.text.square",
                tint: delta >= 0 ? VA.Colors.success : VA.Colors.warning,
                accessibilityLabel: "HRV \(direction) \(pct)% versus baseline"
            )
        }

        if let debt = recovery.sleepDebtHours, abs(debt) > 2 {
            let hours = String(format: "%.0f", abs(debt))
            if debt < 0 {
                return Signal(
                    headline: String(
                        localized: "Sleep deficit: -\(hours)h",
                        comment: "Recovery chip headline for sleep debt"
                    ),
                    iconName: "moon.zzz",
                    tint: VA.Colors.warning,
                    accessibilityLabel: "Sleep deficit of \(hours) hours"
                )
            } else {
                return Signal(
                    headline: String(
                        localized: "Sleep +\(hours)h vs target",
                        comment: "Recovery chip headline for ahead-of-target sleep"
                    ),
                    iconName: "moon.zzz.fill",
                    tint: VA.Colors.success,
                    accessibilityLabel: "Sleep \(hours) hours ahead of target"
                )
            }
        }

        if let score = recovery.appleWatchVitalsScore {
            return Signal(
                headline: String(
                    localized: "Apple Watch Vitals: \(score)/100",
                    comment: "Recovery chip headline for Apple Watch Vitals score"
                ),
                iconName: "applewatch",
                tint: VA.Colors.secondary,
                accessibilityLabel: "Apple Watch Vitals score \(score) of 100"
            )
        }

        if let delta = recovery.wristTemperatureDeltaCelsius, abs(delta) >= 0.15 {
            let sign = delta >= 0 ? "+" : ""
            let value = String(format: "%.2f", delta)
            return Signal(
                headline: String(
                    localized: "Wrist temp \(sign)\(value)°C",
                    comment: "Recovery chip headline for overnight wrist-temperature trend"
                ),
                iconName: delta >= 0 ? "thermometer.high" : "thermometer.low",
                tint: abs(delta) >= 0.3 ? VA.Colors.warning : VA.Colors.secondary,
                accessibilityLabel: "Wrist temperature \(sign)\(value) degrees Celsius versus baseline"
            )
        }

        if let delta = recovery.respiratoryRateDelta, abs(delta) >= 0.5 {
            let sign = delta >= 0 ? "+" : ""
            let value = String(format: "%.1f", delta)
            return Signal(
                headline: String(
                    localized: "Breathing \(sign)\(value) br/min",
                    comment: "Recovery chip headline for respiratory-rate trend"
                ),
                iconName: "lungs.fill",
                tint: delta > 0 ? VA.Colors.warning : VA.Colors.success,
                accessibilityLabel: "Respiratory rate \(sign)\(value) breaths per minute versus baseline"
            )
        }

        if let effort = recovery.appleWorkoutEffort7DayAverage
            ?? recovery.appleEstimatedWorkoutEffort7DayAverage {
            let value = String(format: "%.1f", effort)
            return Signal(
                headline: String(
                    localized: "Training load \(value)/10",
                    comment: "Recovery chip headline for Apple Workout Effort"
                ),
                iconName: "figure.strengthtraining.traditional",
                tint: effort >= 8 ? VA.Colors.warning : VA.Colors.primary,
                accessibilityLabel: "Apple training load effort \(value) out of 10"
            )
        }

        return Signal(
            headline: String(
                localized: "All systems normal",
                comment: "Recovery chip headline when data is present but unremarkable"
            ),
            iconName: "checkmark.seal.fill",
            tint: VA.Colors.success,
            accessibilityLabel: "Recovery signals are all in the normal range"
        )
    }
}

/// Detail sheet shown when the chip is tapped. Renders every populated
/// `RecoveryContext` field with its raw value so the athlete can see
/// the data behind the headline. No premium gating in this surface —
/// the data is theirs.
public struct VARecoveryDetailSheet: View {

    private let recovery: RecoveryContext
    @Environment(\.dismiss) private var dismiss

    public init(recovery: RecoveryContext) {
        self.recovery = recovery
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VA.Space.lg) {
                    Text(String(localized: "From Apple Health · Last 7 days", comment: "Recovery detail sheet source line"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)

                    if recovery.hrvMean7Day != nil
                        || recovery.hrvBaseline28Day != nil
                        || recovery.hrvDeltaPercent != nil {
                        section(title: String(localized: "Heart Rate Variability", comment: "Recovery detail HRV section title")) {
                            if let mean = recovery.hrvMean7Day {
                                row(label: String(localized: "7-day mean", comment: "Recovery detail HRV mean label"),
                                    value: String(format: "%.0f ms", mean))
                            }
                            if let baseline = recovery.hrvBaseline28Day {
                                row(label: String(localized: "28-day baseline", comment: "Recovery detail HRV baseline label"),
                                    value: String(format: "%.0f ms", baseline))
                            }
                            if let delta = recovery.hrvDeltaPercent {
                                let sign = delta >= 0 ? "+" : ""
                                row(label: String(localized: "Trend", comment: "Recovery detail HRV trend label"),
                                    value: "\(sign)\(String(format: "%.1f", delta))%")
                            }
                        }
                    }

                    if recovery.sleep7DayTotalHours != nil
                        || recovery.sleepDebtHours != nil {
                        section(title: String(localized: "Sleep", comment: "Recovery detail sleep section title")) {
                            if let total = recovery.sleep7DayTotalHours {
                                row(label: String(localized: "7-day total", comment: "Recovery detail sleep total label"),
                                    value: String(format: "%.1fh", total))
                            }
                            if let target = recovery.sleepDailyTargetHours {
                                let weekly = target * 7
                                row(label: String(localized: "Weekly target", comment: "Recovery detail sleep target label"),
                                    value: String(format: "%.1fh", weekly))
                            }
                            if let debt = recovery.sleepDebtHours {
                                let sign = debt >= 0 ? "+" : ""
                                row(label: String(localized: "vs target", comment: "Recovery detail sleep debt label"),
                                    value: "\(sign)\(String(format: "%.1f", debt))h")
                            }
                        }
                    }

                    if recovery.strengthLoad7DayKJ != nil
                        || recovery.strengthLoad7DayMinutes != nil {
                        section(title: String(localized: "Strength load (7d)", comment: "Recovery detail strength load section title")) {
                            if let kj = recovery.strengthLoad7DayKJ {
                                row(label: String(localized: "Energy", comment: "Recovery detail strength load energy label"),
                                    value: String(format: "%.0f kJ", kj))
                            }
                            if let minutes = recovery.strengthLoad7DayMinutes {
                                row(label: String(localized: "Time", comment: "Recovery detail strength load time label"),
                                    value: String(format: "%.0f min", minutes))
                            }
                        }
                    }

                    if recovery.appleWorkoutEffort7DayAverage != nil
                        || recovery.appleEstimatedWorkoutEffort7DayAverage != nil {
                        section(title: String(localized: "Apple Training Load", comment: "Recovery detail Apple training load section title")) {
                            if let effort = recovery.appleWorkoutEffort7DayAverage {
                                row(label: String(localized: "Workout Effort", comment: "Recovery detail Apple Workout Effort label"),
                                    value: String(format: "%.1f/10", effort))
                            }
                            if let effort = recovery.appleEstimatedWorkoutEffort7DayAverage {
                                row(label: String(localized: "Estimated effort", comment: "Recovery detail estimated Workout Effort label"),
                                    value: String(format: "%.1f/10", effort))
                            }
                        }
                    }

                    if recovery.wristTemperature7DayMeanCelsius != nil
                        || recovery.wristTemperatureDeltaCelsius != nil
                        || recovery.respiratoryRate7DayMean != nil
                        || recovery.respiratoryRateDelta != nil {
                        section(title: String(localized: "Vitals trends", comment: "Recovery detail Vitals trend section title")) {
                            if let temp = recovery.wristTemperature7DayMeanCelsius {
                                row(label: String(localized: "Wrist temp 7d", comment: "Recovery detail wrist temperature mean label"),
                                    value: String(format: "%.2f°C", temp))
                            }
                            if let delta = recovery.wristTemperatureDeltaCelsius {
                                let sign = delta >= 0 ? "+" : ""
                                row(label: String(localized: "Wrist temp vs baseline", comment: "Recovery detail wrist temperature delta label"),
                                    value: "\(sign)\(String(format: "%.2f", delta))°C")
                            }
                            if let rate = recovery.respiratoryRate7DayMean {
                                row(label: String(localized: "Respiratory rate 7d", comment: "Recovery detail respiratory rate mean label"),
                                    value: String(format: "%.1f br/min", rate))
                            }
                            if let delta = recovery.respiratoryRateDelta {
                                let sign = delta >= 0 ? "+" : ""
                                row(label: String(localized: "Breathing vs baseline", comment: "Recovery detail respiratory rate delta label"),
                                    value: "\(sign)\(String(format: "%.1f", delta)) br/min")
                            }
                        }
                    }

                    if let score = recovery.appleWatchVitalsScore {
                        section(title: String(localized: "Apple Watch Vitals", comment: "Recovery detail Vitals section title")) {
                            row(label: String(localized: "Composite score", comment: "Recovery detail Vitals score label"),
                                value: "\(score)/100")
                        }
                    }
                }
                .padding(VA.Space.lg)
            }
            .background(VA.Colors.surfaceGrouped)
            .navigationTitle(Text(String(localized: "Recovery", comment: "Recovery detail sheet title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done", comment: "Recovery detail sheet dismiss button")) {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            Text(title)
                .font(VA.Typography.headline)
                .foregroundStyle(VA.Colors.textPrimary)
            VStack(spacing: VA.Space.xs) {
                content()
            }
            .padding(VA.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                    .fill(VA.Colors.surfacePrimary)
            )
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(VA.Typography.body)
                .foregroundStyle(VA.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(VA.Typography.headline)
                .foregroundStyle(VA.Colors.textPrimary)
        }
    }
}
#endif
