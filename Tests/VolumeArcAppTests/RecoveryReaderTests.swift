import XCTest
@testable import VolumeArcCore

/// VOL-181 Phase 1B: unit coverage for the `RecoveryReader` protocol
/// seam and the `UnavailableRecoveryReader` fallback that lives in
/// VolumeArcCore. The App-layer `HealthKitRecoveryReader` is tested
/// indirectly via `VolumeArcDashboardIntegrationTests` (which
/// exercises the wiring with a fake reader) — direct unit tests on
/// the iOS-only implementation would need `HKHealthStore` mocking
/// infrastructure that isn't in this PR.
final class RecoveryReaderTests: XCTestCase {

    // MARK: - UnavailableRecoveryReader

    func testUnavailableRecoveryReader_returnsEmptyContext() async {
        let reader = UnavailableRecoveryReader()
        let context = await reader.currentRecovery(now: .now)
        XCTAssertFalse(
            context.hasAnyData,
            "UnavailableRecoveryReader must return a context that gates the prompt's recovery section off"
        )
    }

    func testUnavailableRecoveryReader_returnsContextWithAllNilFields() async {
        let reader = UnavailableRecoveryReader()
        let context = await reader.currentRecovery(now: .now)

        XCTAssertNil(context.hrvMean7Day)
        XCTAssertNil(context.hrvBaseline28Day)
        XCTAssertNil(context.hrvDeltaPercent)
        XCTAssertNil(context.sleep7DayTotalHours)
        XCTAssertNil(context.sleepDailyTargetHours)
        XCTAssertNil(context.sleepDebtHours)
        XCTAssertNil(context.strengthLoad7DayKJ)
        XCTAssertNil(context.strengthLoad7DayMinutes)
        XCTAssertNil(context.appleWatchVitalsScore)
    }

    func testUnavailableRecoveryReader_isStableAcrossInvocations() async {
        // The empty contract is intentionally deterministic — the
        // dashboard's `refreshRecovery()` can call it repeatedly
        // without expecting any side effects or stateful drift.
        let reader = UnavailableRecoveryReader()
        let first = await reader.currentRecovery(now: .now)
        let second = await reader.currentRecovery(now: .now)
        XCTAssertEqual(first, second)
    }

    // MARK: - Protocol conformance via local fake

    func testProtocolSeam_allowsCustomReaderToPropagateData() async {
        struct PinnedReader: RecoveryReader {
            func currentRecovery(now: Date) async -> RecoveryContext {
                RecoveryContext(
                    hrvMean7Day: 60,
                    hrvBaseline28Day: 55,
                    hrvDeltaPercent: 9.1,
                    sleep7DayTotalHours: 58,
                    sleepDailyTargetHours: 8,
                    sleepDebtHours: 2
                )
            }
        }
        let context = await PinnedReader().currentRecovery(now: .now)
        XCTAssertTrue(context.hasAnyData)
        XCTAssertEqual(context.hrvMean7Day, 60)
        XCTAssertEqual(context.sleepDebtHours, 2)
    }
}
