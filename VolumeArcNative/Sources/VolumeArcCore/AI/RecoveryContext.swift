import Foundation

/// VOL-145 Phase 1A: HealthKit-depth recovery signals the coach prompt
/// can reference when the user has Apple Watch + HealthKit data
/// available. Pure value type — no HealthKit imports — so the type
/// compiles on every platform and the prompt-side wiring can be
/// unit-tested independent of `HKHealthStore`.
///
/// The HealthKit reader that produces this value lives in a follow-up
/// (VOL-145 Phase 1B) and runs at the App layer where the
/// `HKHealthStore` instance is already injected. This module only
/// owns the contract.
///
/// Semantics:
/// - **HRV trend**: 7-day mean HRV vs the 28-day rolling baseline.
///   Positive `hrvDeltaPercent` means HRV is up (better recovery
///   signal); negative means down (parasympathetic backed off).
/// - **Sleep debt**: 7-day total minus 7 × target. Negative is "owe
///   sleep"; positive is "ahead of plan" (rare).
/// - **Training load**: 7-day total kJ of strength-training energy
///   plus total minutes. The coach uses the ratio to decide whether
///   a high-frequency week was high-intensity or just high-time.
/// - **Apple Watch Vitals**: optional 0-100 score from watchOS 26's
///   Vitals app. When present, it short-circuits the per-metric
///   reading because Apple's composite is meaningful on its own.
///
/// Every field is `Double?` instead of throwing or substituting zero
/// when a metric is unavailable. The coach prompt block lists only
/// the populated fields so a user without Apple Watch sees a clean
/// "no recovery data" branch rather than three "0/0 baseline" lines.
public struct RecoveryContext: Sendable, Equatable {
    /// 7-day mean HRV in milliseconds. Nil when HK read returned no
    /// recent samples.
    public let hrvMean7Day: Double?

    /// 28-day rolling baseline HRV in milliseconds. Nil when the user
    /// has < 28 days of data.
    public let hrvBaseline28Day: Double?

    /// Percent delta: `(7-day - 28-day) / 28-day * 100`. Nil when
    /// either component is nil. Negative = HRV down vs baseline.
    public let hrvDeltaPercent: Double?

    /// 7-day total sleep in hours.
    public let sleep7DayTotalHours: Double?

    /// User's daily sleep target (typically 8.0). Used to compute the
    /// 7-day target as `7 * target`. Nil when no target is configured.
    public let sleepDailyTargetHours: Double?

    /// Signed sleep debt in hours: `7DayTotal - 7 * dailyTarget`.
    /// Negative = owe sleep.
    public let sleepDebtHours: Double?

    /// 7-day total active energy burned during strength training, in
    /// kilojoules.
    public let strengthLoad7DayKJ: Double?

    /// 7-day total minutes spent in strength-training workouts.
    public let strengthLoad7DayMinutes: Double?

    /// Optional Apple Watch Vitals composite score (0-100). watchOS
    /// 26+ only. When set, the coach prompt block uses it directly
    /// in addition to the per-metric breakdown.
    public let appleWatchVitalsScore: Int?

    public init(
        hrvMean7Day: Double? = nil,
        hrvBaseline28Day: Double? = nil,
        hrvDeltaPercent: Double? = nil,
        sleep7DayTotalHours: Double? = nil,
        sleepDailyTargetHours: Double? = nil,
        sleepDebtHours: Double? = nil,
        strengthLoad7DayKJ: Double? = nil,
        strengthLoad7DayMinutes: Double? = nil,
        appleWatchVitalsScore: Int? = nil
    ) {
        self.hrvMean7Day = hrvMean7Day
        self.hrvBaseline28Day = hrvBaseline28Day
        self.hrvDeltaPercent = hrvDeltaPercent
        self.sleep7DayTotalHours = sleep7DayTotalHours
        self.sleepDailyTargetHours = sleepDailyTargetHours
        self.sleepDebtHours = sleepDebtHours
        self.strengthLoad7DayKJ = strengthLoad7DayKJ
        self.strengthLoad7DayMinutes = strengthLoad7DayMinutes
        self.appleWatchVitalsScore = appleWatchVitalsScore
    }

    /// True when at least one HK-derived field is populated. Used by
    /// `CoachContext.asPromptBlock` to decide whether to emit the
    /// `## Recovery (Apple Health)` section at all.
    public var hasAnyData: Bool {
        hrvMean7Day != nil
            || hrvBaseline28Day != nil
            || hrvDeltaPercent != nil
            || sleep7DayTotalHours != nil
            || sleepDailyTargetHours != nil
            || sleepDebtHours != nil
            || strengthLoad7DayKJ != nil
            || strengthLoad7DayMinutes != nil
            || appleWatchVitalsScore != nil
    }

    /// Format the recovery context as Markdown bullets for the coach
    /// prompt. Returns an empty string when `hasAnyData == false` so
    /// `CoachContext.asPromptBlock` can concat unconditionally without
    /// emitting an orphan section header.
    ///
    /// Privacy: HK metrics are never PII (they're numeric aggregates)
    /// so the strict-privacy-mode redaction path leaves them alone —
    /// the redaction logic is at the `CoachContext` level and only
    /// touches name + last-session text.
    public func asPromptBullets() -> String {
        guard hasAnyData else { return "" }

        var lines: [String] = []
        lines.append("## Recovery (Apple Health)")

        if let score = appleWatchVitalsScore {
            lines.append("- Apple Watch Vitals: \(score)/100")
        }

        if let mean = hrvMean7Day, let baseline = hrvBaseline28Day, let delta = hrvDeltaPercent {
            let direction = delta >= 0 ? "+" : ""
            lines.append(
                "- HRV: \(format(mean, decimals: 0))ms 7-day vs \(format(baseline, decimals: 0))ms baseline " +
                "(\(direction)\(format(delta, decimals: 1))%)"
            )
        } else if let mean = hrvMean7Day {
            lines.append("- HRV: \(format(mean, decimals: 0))ms (7-day mean, baseline pending)")
        }

        if let debt = sleepDebtHours, let target = sleepDailyTargetHours {
            let descriptor: String
            if debt < -2 {
                descriptor = "significant deficit"
            } else if debt < 0 {
                descriptor = "behind target"
            } else if debt < 2 {
                descriptor = "near target"
            } else {
                descriptor = "ahead of plan"
            }
            let weeklyTarget = target * 7
            let total = sleep7DayTotalHours ?? (weeklyTarget + debt)
            lines.append(
                "- Sleep: \(format(total, decimals: 1))h over 7d vs \(format(weeklyTarget, decimals: 1))h target — " +
                "\(format(debt, decimals: 1))h \(descriptor)"
            )
        } else if let total = sleep7DayTotalHours {
            lines.append("- Sleep: \(format(total, decimals: 1))h over 7d (no target configured)")
        }

        if let kj = strengthLoad7DayKJ, let minutes = strengthLoad7DayMinutes {
            lines.append(
                "- Training load (7d strength): \(format(kj, decimals: 0))kJ across " +
                "\(format(minutes, decimals: 0))min"
            )
        } else if let kj = strengthLoad7DayKJ {
            lines.append("- Training load (7d strength): \(format(kj, decimals: 0))kJ")
        } else if let minutes = strengthLoad7DayMinutes {
            lines.append("- Training load (7d strength): \(format(minutes, decimals: 0))min")
        }

        return lines.joined(separator: "\n")
    }

    private func format(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
