#if canImport(HealthKit)
import Foundation

/// VOL-136: deterministic, in-memory `RecoverySampleSource` for unit-testing
/// `HealthKitRecoveryReader`'s orchestration (HRV-delta / sleep-debt
/// aggregation + empty / partial / query-failed telemetry routing) without a
/// live `HKHealthStore`.
///
/// Each field is set independently so a test can model "HRV present, sleep
/// missing, strength query failed" etc. A `nil` value means "no samples in the
/// window" (the reader treats that as an empty field); setting the matching
/// `*Error` makes that query throw, which the reader routes to a
/// `recovery_query_failed` telemetry event.
///
/// The reader only ever requests HRV for 7- and 28-day windows, so HRV is
/// modeled as two explicit fields rather than a day-keyed map.
final class FakeRecoverySampleSource: RecoverySampleSource, @unchecked Sendable {
    var healthDataAvailable: Bool
    var hrv7DayMilliseconds: Double?
    var hrv28DayMilliseconds: Double?
    var asleepHours: Double?
    var strength: RecoveryStrengthLoad?
    var effort: RecoveryWorkoutEffort?
    var wristTemperature7DayCelsius: Double?
    var wristTemperature28DayCelsius: Double?
    var respiratoryRate7Day: Double?
    var respiratoryRate28Day: Double?

    var hrvError: Error?
    var sleepError: Error?
    var strengthError: Error?
    var effortError: Error?
    var wristTemperatureError: Error?
    var respiratoryRateError: Error?

    init(
        healthDataAvailable: Bool = true,
        hrv7DayMilliseconds: Double? = nil,
        hrv28DayMilliseconds: Double? = nil,
        asleepHours: Double? = nil,
        strength: RecoveryStrengthLoad? = nil,
        effort: RecoveryWorkoutEffort? = nil,
        wristTemperature7DayCelsius: Double? = nil,
        wristTemperature28DayCelsius: Double? = nil,
        respiratoryRate7Day: Double? = nil,
        respiratoryRate28Day: Double? = nil,
        hrvError: Error? = nil,
        sleepError: Error? = nil,
        strengthError: Error? = nil,
        effortError: Error? = nil,
        wristTemperatureError: Error? = nil,
        respiratoryRateError: Error? = nil
    ) {
        self.healthDataAvailable = healthDataAvailable
        self.hrv7DayMilliseconds = hrv7DayMilliseconds
        self.hrv28DayMilliseconds = hrv28DayMilliseconds
        self.asleepHours = asleepHours
        self.strength = strength
        self.effort = effort
        self.wristTemperature7DayCelsius = wristTemperature7DayCelsius
        self.wristTemperature28DayCelsius = wristTemperature28DayCelsius
        self.respiratoryRate7Day = respiratoryRate7Day
        self.respiratoryRate28Day = respiratoryRate28Day
        self.hrvError = hrvError
        self.sleepError = sleepError
        self.strengthError = strengthError
        self.effortError = effortError
        self.wristTemperatureError = wristTemperatureError
        self.respiratoryRateError = respiratoryRateError
    }

    var isHealthDataAvailable: Bool { healthDataAvailable }

    func meanHRVMilliseconds(overDays days: Int, now: Date) async throws -> Double? {
        if let hrvError { throw hrvError }
        // The reader requests 7- and 28-day windows; treat anything <= 7 as
        // the recent mean and everything else as the baseline.
        return days <= 7 ? hrv7DayMilliseconds : hrv28DayMilliseconds
    }

    func totalAsleepHours(overDays days: Int, now: Date) async throws -> Double? {
        if let sleepError { throw sleepError }
        return asleepHours
    }

    func strengthLoad(overDays days: Int, now: Date) async throws -> RecoveryStrengthLoad? {
        if let strengthError { throw strengthError }
        return strength
    }

    func workoutEffort(overDays days: Int, now: Date) async throws -> RecoveryWorkoutEffort? {
        if let effortError { throw effortError }
        return effort
    }

    func meanWristTemperatureCelsius(overDays days: Int, now: Date) async throws -> Double? {
        if let wristTemperatureError { throw wristTemperatureError }
        return days <= 7 ? wristTemperature7DayCelsius : wristTemperature28DayCelsius
    }

    func meanRespiratoryRate(overDays days: Int, now: Date) async throws -> Double? {
        if let respiratoryRateError { throw respiratoryRateError }
        return days <= 7 ? respiratoryRate7Day : respiratoryRate28Day
    }
}
#endif
