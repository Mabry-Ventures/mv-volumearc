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
/// - **Apple effort**: 7-day mean Apple Workout Effort score when the
///   watch has associated effort samples, plus the estimated score
///   HealthKit can produce from session strain.
/// - **Vitals trends**: overnight wrist-temperature and respiratory-rate
///   trend lines, expressed as 7-day mean vs 28-day baseline.
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

    /// 7-day average of Apple Workout Effort scores attached to recent
    /// strength workouts. Nil when HealthKit has no related effort samples.
    public let appleWorkoutEffort7DayAverage: Double?

    /// 7-day average of HealthKit's estimated Workout Effort score for
    /// recent sessions. Useful when the user has not manually rated effort.
    public let appleEstimatedWorkoutEffort7DayAverage: Double?

    /// 7-day mean overnight wrist temperature, in degrees Celsius.
    public let wristTemperature7DayMeanCelsius: Double?

    /// 28-day baseline overnight wrist temperature, in degrees Celsius.
    public let wristTemperature28DayBaselineCelsius: Double?

    /// Signed wrist-temperature delta: 7-day mean minus 28-day baseline.
    public let wristTemperatureDeltaCelsius: Double?

    /// 7-day mean respiratory rate, in breaths per minute.
    public let respiratoryRate7DayMean: Double?

    /// 28-day baseline respiratory rate, in breaths per minute.
    public let respiratoryRate28DayBaseline: Double?

    /// Signed respiratory-rate delta: 7-day mean minus 28-day baseline.
    public let respiratoryRateDelta: Double?

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
        appleWorkoutEffort7DayAverage: Double? = nil,
        appleEstimatedWorkoutEffort7DayAverage: Double? = nil,
        wristTemperature7DayMeanCelsius: Double? = nil,
        wristTemperature28DayBaselineCelsius: Double? = nil,
        wristTemperatureDeltaCelsius: Double? = nil,
        respiratoryRate7DayMean: Double? = nil,
        respiratoryRate28DayBaseline: Double? = nil,
        respiratoryRateDelta: Double? = nil,
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
        self.appleWorkoutEffort7DayAverage = appleWorkoutEffort7DayAverage
        self.appleEstimatedWorkoutEffort7DayAverage = appleEstimatedWorkoutEffort7DayAverage
        self.wristTemperature7DayMeanCelsius = wristTemperature7DayMeanCelsius
        self.wristTemperature28DayBaselineCelsius = wristTemperature28DayBaselineCelsius
        self.wristTemperatureDeltaCelsius = wristTemperatureDeltaCelsius
        self.respiratoryRate7DayMean = respiratoryRate7DayMean
        self.respiratoryRate28DayBaseline = respiratoryRate28DayBaseline
        self.respiratoryRateDelta = respiratoryRateDelta
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
            || appleWorkoutEffort7DayAverage != nil
            || appleEstimatedWorkoutEffort7DayAverage != nil
            || wristTemperature7DayMeanCelsius != nil
            || wristTemperature28DayBaselineCelsius != nil
            || wristTemperatureDeltaCelsius != nil
            || respiratoryRate7DayMean != nil
            || respiratoryRate28DayBaseline != nil
            || respiratoryRateDelta != nil
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
        appendAppleWatchVitals(to: &lines)
        appendHRV(to: &lines)
        appendSleep(to: &lines)
        appendStrengthLoad(to: &lines)
        appendWorkoutEffort(to: &lines)
        appendWristTemperature(to: &lines)
        appendRespiratoryRate(to: &lines)

        return lines.joined(separator: "\n")
    }

    private func appendAppleWatchVitals(to lines: inout [String]) {
        if let score = appleWatchVitalsScore {
            lines.append("- Apple Watch Vitals: \(score)/100")
        }
    }

    private func appendHRV(to lines: inout [String]) {
        if let mean = hrvMean7Day, let baseline = hrvBaseline28Day, let delta = hrvDeltaPercent {
            let direction = delta >= 0 ? "+" : ""
            lines.append(
                "- HRV: \(format(mean, decimals: 0))ms 7-day vs \(format(baseline, decimals: 0))ms baseline " +
                "(\(direction)\(format(delta, decimals: 1))%)"
            )
        } else if let mean = hrvMean7Day {
            lines.append("- HRV: \(format(mean, decimals: 0))ms (7-day mean, baseline pending)")
        }
    }

    private func appendSleep(to lines: inout [String]) {
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
    }

    private func appendStrengthLoad(to lines: inout [String]) {
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
    }

    private func appendWorkoutEffort(to lines: inout [String]) {
        if let effort = appleWorkoutEffort7DayAverage {
            lines.append("- Apple Workout Effort (7d): \(format(effort, decimals: 1))/10 average")
        } else if let estimated = appleEstimatedWorkoutEffort7DayAverage {
            lines.append("- Apple estimated Workout Effort (7d): \(format(estimated, decimals: 1))/10 average")
        }
    }

    private func appendWristTemperature(to lines: inout [String]) {
        if let mean = wristTemperature7DayMeanCelsius,
           let baseline = wristTemperature28DayBaselineCelsius,
           let delta = wristTemperatureDeltaCelsius {
            let sign = delta >= 0 ? "+" : ""
            lines.append(
                "- Wrist temperature: \(format(mean, decimals: 2))°C 7-day vs " +
                "\(format(baseline, decimals: 2))°C baseline (\(sign)\(format(delta, decimals: 2))°C)"
            )
        } else if let mean = wristTemperature7DayMeanCelsius {
            lines.append("- Wrist temperature: \(format(mean, decimals: 2))°C 7-day mean")
        }
    }

    private func appendRespiratoryRate(to lines: inout [String]) {
        if let mean = respiratoryRate7DayMean,
           let baseline = respiratoryRate28DayBaseline,
           let delta = respiratoryRateDelta {
            let sign = delta >= 0 ? "+" : ""
            lines.append(
                "- Respiratory rate: \(format(mean, decimals: 1)) br/min 7-day vs " +
                "\(format(baseline, decimals: 1)) br/min baseline (\(sign)\(format(delta, decimals: 1)) br/min)"
            )
        } else if let mean = respiratoryRate7DayMean {
            lines.append("- Respiratory rate: \(format(mean, decimals: 1)) br/min 7-day mean")
        }
    }

    private func format(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
