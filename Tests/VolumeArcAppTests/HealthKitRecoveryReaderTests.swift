#if canImport(HealthKit)
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
            strength: RecoveryStrengthLoad(kj: 4200, minutes: 180)
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
        XCTAssertNil(context.appleWatchVitalsScore)
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

        XCTAssertFalse(context.hasAnyData)
        XCTAssertEqual(sink.events(named: "recovery_all_empty").count, 1)
        // Each of the four queries returned nil → four empty events.
        XCTAssertEqual(sink.events(named: "recovery_query_empty").count, 4)
        XCTAssertTrue(sink.events(named: "recovery_partial").isEmpty)
    }

    func testPartialDataEmitsRecoveryPartialWithCount() async {
        let sink = CapturingTelemetrySink()
        // HRV present (both windows), sleep + strength missing → 2 empty fields.
        let source = FakeRecoverySampleSource(hrv7DayMilliseconds: 54, hrv28DayMilliseconds: 58)
        let reader = HealthKitRecoveryReader(source: source, telemetrySink: sink)

        _ = await reader.currentRecovery(now: .now)

        let partial = sink.events(named: "recovery_partial")
        XCTAssertEqual(partial.count, 1)
        XCTAssertEqual(partial.first?.metadata["empty_field_count"], "2")
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
#endif
