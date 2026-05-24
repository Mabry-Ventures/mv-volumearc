#if canImport(HealthKit)
import HealthKit
import XCTest
import VolumeArcCore

/// VOL-136: unit coverage for `HealthKitRecoveryReader`'s orchestration.
///
/// The reader's source file is compiled directly into this test bundle (see
/// `scripts/generate_xcode_project.rb`'s `add_selected_swift_sources` list), so
/// the `internal` `init(source:sleepTargetHours:telemetrySink:)` seam is
/// reachable here without `@testable import`. We inject a
/// `FakeRecoverySampleSource` to drive the HRV-delta / sleep-debt aggregation
/// and the empty / partial / query-failed telemetry routing deterministically —
/// none of which was unit-testable before VOL-136 because the reader talked to
/// a concrete `HKHealthStore`.
final class HealthKitRecoveryReaderTests: XCTestCase {

    // MARK: - Aggregation

    func testComputesHRVDeltaAndSleepDebtFromSourceValues() async {
        let source = FakeRecoverySampleSource(
            hrv7DayMilliseconds: 54,
            hrv28DayMilliseconds: 60,
            asleepHours: 47.2,
            strength: RecoveryStrengthLoad(kj: 4200, minutes: 180),
            effort: RecoveryWorkoutEffort(workoutScore: 7.2, estimatedScore: 6.8),
            wristTemperature7DayCelsius: 36.68,
            wristTemperature28DayCelsius: 36.52,
            respiratoryRate7Day: 15.4,
            respiratoryRate28Day: 14.8
        )
        let reader = HealthKitRecoveryReader(source: source, sleepTargetHours: 8.0)

        let context = await reader.currentRecovery(now: .now)

        XCTAssertEqual(context.hrvMean7Day, 54)
        XCTAssertEqual(context.hrvBaseline28Day, 60)
        // (54 - 60) / 60 * 100 = -10%
        XCTAssertEqual(try XCTUnwrap(context.hrvDeltaPercent), -10.0, accuracy: 0.0001)
        XCTAssertEqual(context.sleep7DayTotalHours, 47.2)
        XCTAssertEqual(context.sleepDailyTargetHours, 8.0)
        // 47.2 - (8 * 7) = -8.8h debt
        XCTAssertEqual(try XCTUnwrap(context.sleepDebtHours), -8.8, accuracy: 0.0001)
        XCTAssertEqual(context.strengthLoad7DayKJ, 4200)
        XCTAssertEqual(context.strengthLoad7DayMinutes, 180)
        XCTAssertEqual(context.appleWorkoutEffort7DayAverage, 7.2)
        XCTAssertEqual(context.appleEstimatedWorkoutEffort7DayAverage, 6.8)
        XCTAssertEqual(context.wristTemperature7DayMeanCelsius, 36.68)
        XCTAssertEqual(context.wristTemperature28DayBaselineCelsius, 36.52)
        XCTAssertEqual(try XCTUnwrap(context.wristTemperatureDeltaCelsius), 0.16, accuracy: 0.0001)
        XCTAssertEqual(context.respiratoryRate7DayMean, 15.4)
        XCTAssertEqual(context.respiratoryRate28DayBaseline, 14.8)
        XCTAssertEqual(try XCTUnwrap(context.respiratoryRateDelta), 0.6, accuracy: 0.0001)
        XCTAssertNil(context.appleWatchVitalsScore)
    }

    func testWorkoutEffortSummaryPreservesEstimatedFallbackWhenExplicitQueryFails() throws {
        let summary = try HealthKitRecoverySampleSource.makeWorkoutEffortSummary(
            explicitScore: nil,
            explicitError: SampleHealthKitError.queryFailed,
            estimatedScore: 6.4
        )

        XCTAssertNil(summary?.workoutScore)
        XCTAssertEqual(summary?.estimatedScore, 6.4)
    }

    func testWorkoutEffortSummaryRethrowsExplicitErrorWhenNoFallbackExists() {
        XCTAssertThrowsError(
            try HealthKitRecoverySampleSource.makeWorkoutEffortSummary(
                explicitScore: nil,
                explicitError: SampleHealthKitError.queryFailed,
                estimatedScore: nil
            )
        )
    }

    func testWorkoutEffortSummarySplitsRelatedExplicitAndEstimatedSamples() throws {
        let explicitA = try makeEffortSample(identifier: .workoutEffortScore, value: 7.0)
        let explicitB = try makeEffortSample(identifier: .workoutEffortScore, value: 9.0)
        let estimated = try makeEffortSample(identifier: .estimatedWorkoutEffortScore, value: 6.5)
        let hrv = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN))
        let unrelated = HKQuantitySample(
            type: hrv,
            quantity: HKQuantity(unit: HKUnit.secondUnit(with: .milli), doubleValue: 54),
            start: .now,
            end: .now
        )

        let summary = try XCTUnwrap(
            HealthKitRecoverySampleSource.makeWorkoutEffortSummary(
                from: [explicitA, estimated, unrelated, explicitB]
            )
        )

        XCTAssertEqual(summary.workoutScore, 8.0)
        XCTAssertEqual(summary.estimatedScore, 6.5)
    }

    func testPositiveHRVDeltaWhenRecentAboveBaseline() async {
        let source = FakeRecoverySampleSource(hrv7DayMilliseconds: 66, hrv28DayMilliseconds: 60)
        let reader = HealthKitRecoveryReader(source: source)

        let context = await reader.currentRecovery(now: .now)

        // (66 - 60) / 60 * 100 = +10%
        XCTAssertEqual(try XCTUnwrap(context.hrvDeltaPercent), 10.0, accuracy: 0.0001)
    }

    func testHRVDeltaNilWhenBaselineMissing() async {
        let source = FakeRecoverySampleSource(hrv7DayMilliseconds: 54, hrv28DayMilliseconds: nil)
        let reader = HealthKitRecoveryReader(source: source)

        let context = await reader.currentRecovery(now: .now)

        XCTAssertEqual(context.hrvMean7Day, 54)
        XCTAssertNil(context.hrvBaseline28Day)
        XCTAssertNil(context.hrvDeltaPercent, "Delta needs both means; missing baseline must yield nil")
    }

    func testSleepDebtNilWhenNoSleepData() async {
        let source = FakeRecoverySampleSource(hrv7DayMilliseconds: 54, asleepHours: nil)
        let reader = HealthKitRecoveryReader(source: source)

        let context = await reader.currentRecovery(now: .now)

        XCTAssertNil(context.sleep7DayTotalHours)
        XCTAssertNil(context.sleepDebtHours)
    }

    // MARK: - Availability gate

    func testUnavailableHealthDataReturnsEmptyAndEmitsTelemetry() async {
        let sink = CapturingTelemetrySink()
        let source = FakeRecoverySampleSource(healthDataAvailable: false)
        let reader = HealthKitRecoveryReader(source: source, telemetrySink: sink)

        let context = await reader.currentRecovery(now: .now)

        XCTAssertFalse(context.hasAnyData, "No data should be read when health data is unavailable")
        XCTAssertEqual(sink.events(named: "recovery_unavailable").count, 1)
    }

    // MARK: - Empty / partial telemetry

    func testAllFieldsEmptyEmitsRecoveryAllEmpty() async {
        let sink = CapturingTelemetrySink()
        let source = FakeRecoverySampleSource() // every field nil, available
        let reader = HealthKitRecoveryReader(source: source, telemetrySink: sink)

        let context = await reader.currentRecovery(now: .now)

        // Every *measured* field is nil. Note `sleepDailyTargetHours` is
        // always populated (it's the configured target, not read data), so
        // `hasAnyData` is intentionally true here — we assert the measured
        // fields rather than `hasAnyData`.
        XCTAssertNil(context.hrvMean7Day)
        XCTAssertNil(context.hrvBaseline28Day)
        XCTAssertNil(context.hrvDeltaPercent)
        XCTAssertNil(context.sleep7DayTotalHours)
        XCTAssertNil(context.sleepDebtHours)
        XCTAssertNil(context.strengthLoad7DayKJ)
        XCTAssertNil(context.strengthLoad7DayMinutes)
        XCTAssertNil(context.appleWorkoutEffort7DayAverage)
        XCTAssertNil(context.appleEstimatedWorkoutEffort7DayAverage)
        XCTAssertNil(context.wristTemperature7DayMeanCelsius)
        XCTAssertNil(context.wristTemperature28DayBaselineCelsius)
        XCTAssertNil(context.wristTemperatureDeltaCelsius)
        XCTAssertNil(context.respiratoryRate7DayMean)
        XCTAssertNil(context.respiratoryRate28DayBaseline)
        XCTAssertNil(context.respiratoryRateDelta)
        XCTAssertEqual(sink.events(named: "recovery_all_empty").count, 1)
        // Each primitive query returned nil.
        XCTAssertEqual(sink.events(named: "recovery_query_empty").count, 9)
        XCTAssertTrue(sink.events(named: "recovery_partial").isEmpty)
    }

    func testPartialDataEmitsRecoveryPartialWithCount() async {
        let sink = CapturingTelemetrySink()
        // HRV present (both windows), sleep / strength / effort / vitals missing.
        let source = FakeRecoverySampleSource(hrv7DayMilliseconds: 54, hrv28DayMilliseconds: 58)
        let reader = HealthKitRecoveryReader(source: source, telemetrySink: sink)

        _ = await reader.currentRecovery(now: .now)

        let partial = sink.events(named: "recovery_partial")
        XCTAssertEqual(partial.count, 1)
        XCTAssertEqual(partial.first?.metadata["empty_field_count"], "7")
        XCTAssertTrue(sink.events(named: "recovery_all_empty").isEmpty)
    }

    // MARK: - Query failure telemetry

    func testQueryFailureEmitsRecoveryQueryFailedAndDegradesField() async {
        let sink = CapturingTelemetrySink()
        let source = FakeRecoverySampleSource(
            hrv7DayMilliseconds: 54,
            hrv28DayMilliseconds: 58,
            sleepError: NSError(domain: "HKErrorDomain", code: 5, userInfo: nil)
        )
        let reader = HealthKitRecoveryReader(source: source, telemetrySink: sink)

        let context = await reader.currentRecovery(now: .now)

        // The failing sleep query degrades to nil, but HRV still populates.
        XCTAssertNil(context.sleep7DayTotalHours)
        XCTAssertEqual(context.hrvMean7Day, 54)
        let failures = sink.events(named: "recovery_query_failed")
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.metadata["field"], "sleep7")
        XCTAssertEqual(failures.first?.metadata["error_code"], "5")
    }
}

private enum SampleHealthKitError: Error {
    case queryFailed
}

private func makeEffortSample(identifier: HKQuantityTypeIdentifier, value: Double) throws -> HKQuantitySample {
    let type = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: identifier))
    let now = Date()
    return HKQuantitySample(
        type: type,
        quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: value),
        start: now,
        end: now
    )
}
#endif
