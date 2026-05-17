import XCTest
@testable import VolumeArcCore

/// VOL-145 Phase 1A: unit coverage for `RecoveryContext` + its
/// integration with `CoachContext.asPromptBlock`. Pure value-type
/// tests — no HealthKit imports, no async, no `HKHealthStore`. The
/// HK reader that produces real `RecoveryContext` values is Phase 1B
/// and lands at the App layer.
final class RecoveryContextTests: XCTestCase {

    // MARK: - hasAnyData

    func testHasAnyData_emptyContext_returnsFalse() {
        let context = RecoveryContext()
        XCTAssertFalse(context.hasAnyData)
    }

    func testHasAnyData_anySingleFieldPopulated_returnsTrue() {
        XCTAssertTrue(RecoveryContext(hrvMean7Day: 42).hasAnyData)
        XCTAssertTrue(RecoveryContext(sleep7DayTotalHours: 50).hasAnyData)
        XCTAssertTrue(RecoveryContext(strengthLoad7DayMinutes: 200).hasAnyData)
        XCTAssertTrue(RecoveryContext(appleWatchVitalsScore: 75).hasAnyData)
    }

    // MARK: - asPromptBullets — empty path

    func testAsPromptBullets_noData_returnsEmptyString() {
        XCTAssertEqual(RecoveryContext().asPromptBullets(), "")
    }

    // MARK: - asPromptBullets — Apple Watch Vitals (composite)

    func testAsPromptBullets_vitalsOnly_rendersScoreLine() {
        let bullets = RecoveryContext(appleWatchVitalsScore: 82).asPromptBullets()
        XCTAssertTrue(bullets.contains("## Recovery (Apple Health)"))
        XCTAssertTrue(bullets.contains("Apple Watch Vitals: 82/100"))
    }

    // MARK: - asPromptBullets — HRV (full triple)

    func testAsPromptBullets_hrvTriple_rendersDeltaWithDirection() {
        let positive = RecoveryContext(
            hrvMean7Day: 58.4,
            hrvBaseline28Day: 54.0,
            hrvDeltaPercent: 8.1
        ).asPromptBullets()
        XCTAssertTrue(positive.contains("HRV: 58ms 7-day vs 54ms baseline (+8.1%)"))

        let negative = RecoveryContext(
            hrvMean7Day: 48.0,
            hrvBaseline28Day: 54.0,
            hrvDeltaPercent: -11.1
        ).asPromptBullets()
        XCTAssertTrue(negative.contains("HRV: 48ms 7-day vs 54ms baseline (-11.1%)"))
    }

    func testAsPromptBullets_hrvOnly7Day_rendersBaselinePendingNote() {
        let bullets = RecoveryContext(hrvMean7Day: 52.0).asPromptBullets()
        XCTAssertTrue(bullets.contains("HRV: 52ms (7-day mean, baseline pending)"))
    }

    // MARK: - asPromptBullets — sleep descriptors

    func testAsPromptBullets_sleepDebt_classifiesDescriptor() {
        let cases: [(debt: Double, descriptor: String)] = [
            (-4.0, "significant deficit"),
            (-1.0, "behind target"),
            (0.5, "near target"),
            (3.0, "ahead of plan")
        ]
        for (debt, descriptor) in cases {
            let bullets = RecoveryContext(
                sleep7DayTotalHours: 56.0 + debt,
                sleepDailyTargetHours: 8.0,
                sleepDebtHours: debt
            ).asPromptBullets()
            XCTAssertTrue(
                bullets.contains(descriptor),
                "Expected '\(descriptor)' for debt \(debt); got bullets:\n\(bullets)"
            )
        }
    }

    func testAsPromptBullets_sleepTotalWithoutTarget_omitsDescriptor() {
        let bullets = RecoveryContext(sleep7DayTotalHours: 52.5).asPromptBullets()
        XCTAssertTrue(bullets.contains("Sleep: 52.5h over 7d (no target configured)"))
        XCTAssertFalse(bullets.contains("deficit"))
        XCTAssertFalse(bullets.contains("ahead"))
    }

    // MARK: - asPromptBullets — training load combinations

    func testAsPromptBullets_trainingLoadBoth_rendersBothFields() {
        let bullets = RecoveryContext(
            strengthLoad7DayKJ: 2_400,
            strengthLoad7DayMinutes: 240
        ).asPromptBullets()
        XCTAssertTrue(bullets.contains("Training load (7d strength): 2400kJ across 240min"))
    }

    func testAsPromptBullets_trainingLoadEnergyOnly_omitsMinutes() {
        let bullets = RecoveryContext(strengthLoad7DayKJ: 1_800).asPromptBullets()
        XCTAssertTrue(bullets.contains("Training load (7d strength): 1800kJ"))
        XCTAssertFalse(bullets.contains("min"))
    }

    func testAsPromptBullets_trainingLoadMinutesOnly_omitsKJ() {
        let bullets = RecoveryContext(strengthLoad7DayMinutes: 180).asPromptBullets()
        XCTAssertTrue(bullets.contains("Training load (7d strength): 180min"))
        XCTAssertFalse(bullets.contains("kJ"))
    }

    // MARK: - CoachContext integration

    func testCoachContext_promptBlock_omitsRecoverySectionWhenNil() {
        let context = CoachContext(
            athleteName: "Sam",
            advancementLevel: "intermediate",
            readinessScore: 78,
            readinessBrief: "ready"
        )
        let rendered = context.asPromptBlock(privacyMode: .standard)
        XCTAssertFalse(rendered.contains("Recovery (Apple Health)"))
    }

    func testCoachContext_promptBlock_omitsRecoverySectionWhenEmpty() {
        let context = CoachContext(
            athleteName: "Sam",
            advancementLevel: "intermediate",
            readinessScore: 78,
            readinessBrief: "ready",
            recovery: RecoveryContext()
        )
        let rendered = context.asPromptBlock(privacyMode: .standard)
        XCTAssertFalse(rendered.contains("Recovery (Apple Health)"))
    }

    func testCoachContext_promptBlock_includesRecoverySectionWhenPopulated() {
        let context = CoachContext(
            athleteName: "Sam",
            advancementLevel: "intermediate",
            readinessScore: 78,
            readinessBrief: "ready",
            recovery: RecoveryContext(
                hrvMean7Day: 58,
                hrvBaseline28Day: 54,
                hrvDeltaPercent: 7.4,
                sleep7DayTotalHours: 53,
                sleepDailyTargetHours: 8.0,
                sleepDebtHours: -3.0,
                strengthLoad7DayKJ: 2_100,
                strengthLoad7DayMinutes: 210
            )
        )
        let rendered = context.asPromptBlock(privacyMode: .standard)
        XCTAssertTrue(rendered.contains("## Recovery (Apple Health)"))
        XCTAssertTrue(rendered.contains("HRV: 58ms 7-day vs 54ms baseline"))
        XCTAssertTrue(rendered.contains("behind target"))
        XCTAssertTrue(rendered.contains("Training load (7d strength): 2100kJ across 210min"))
    }

    func testCoachContext_promptBlock_recoverySectionSurvivesStrictPrivacy() {
        // Numeric aggregates aren't PII; strict-privacy redaction
        // should leave them alone (it only touches name + last
        // session text).
        let context = CoachContext(
            athleteName: "Sam Smith",
            advancementLevel: "intermediate",
            readinessScore: 78,
            readinessBrief: "ready",
            recovery: RecoveryContext(hrvMean7Day: 50, hrvBaseline28Day: 55, hrvDeltaPercent: -9.1)
        )
        let rendered = context.asPromptBlock(privacyMode: .strict)
        XCTAssertTrue(rendered.contains("the athlete"))
        XCTAssertFalse(rendered.contains("Sam Smith"))
        XCTAssertTrue(rendered.contains("## Recovery (Apple Health)"))
        XCTAssertTrue(rendered.contains("HRV: 50ms 7-day vs 55ms baseline"))
    }

    // MARK: - Equatable

    func testRecoveryContext_equatable() {
        let lhs = RecoveryContext(hrvMean7Day: 50, hrvBaseline28Day: 55, hrvDeltaPercent: -9.1)
        let rhs = RecoveryContext(hrvMean7Day: 50, hrvBaseline28Day: 55, hrvDeltaPercent: -9.1)
        XCTAssertEqual(lhs, rhs)

        let different = RecoveryContext(hrvMean7Day: 49, hrvBaseline28Day: 55, hrvDeltaPercent: -10.9)
        XCTAssertNotEqual(lhs, different)
    }
}
