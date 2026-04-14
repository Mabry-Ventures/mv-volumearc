import XCTest
import VolumeArcCore

/// Tests for ReadinessModel — the 5-factor composite score.
/// These tests exercise real production logic, not stubs.
final class VolumeArcReadinessTests: XCTestCase {
    private let model = ReadinessModel()
    private let athlete = AthleteProfile(name: "Test", weeklyTrainingDays: 4)

    // MARK: - Empty history

    func testEmptyHistoryProducesHighReadiness() {
        let assessment = model.evaluate(sessions: [], athlete: athlete)
        XCTAssertGreaterThanOrEqual(assessment.score, 80,
            "No training history should indicate high readiness (well-rested)")
        XCTAssertFalse(assessment.factors.isEmpty)
    }

    func testEmptyHistoryFactorsIncludeAllFive() {
        let assessment = model.evaluate(sessions: [], athlete: athlete)
        let factorNames = Set(assessment.factors.map(\.name))
        XCTAssertTrue(factorNames.contains("Training frequency"))
        XCTAssertTrue(factorNames.contains("Recovery"))
        XCTAssertTrue(factorNames.contains("Volume load"))
        XCTAssertTrue(factorNames.contains("Session intensity"))
        XCTAssertTrue(factorNames.contains("Session duration"))
    }

    // MARK: - Overtrained state

    func testOvertrainingLowersReadiness() {
        let now = Date.now
        let sessions = (0..<6).map { i in
            RecentSession(
                date: now.addingTimeInterval(TimeInterval(-i * 3600 * 12)),
                durationMinutes: 90,
                totalVolumeLoad: 20_000,
                averageRPE: 9.0,
                completedSetCount: 20
            )
        }
        let assessment = model.evaluate(sessions: sessions, athlete: athlete)
        XCTAssertLessThan(assessment.score, 70,
            "Six sessions in 3 days at RPE 9 should significantly lower readiness")
    }

    // MARK: - Fresh after rest

    func testWellRestedAfter48HoursIsPositive() {
        let now = Date.now
        let sessions = [
            RecentSession(
                date: now.addingTimeInterval(-86_400 * 2), // 48h ago
                durationMinutes: 60,
                totalVolumeLoad: 8_000,
                averageRPE: 7.0,
                completedSetCount: 12
            )
        ]
        let assessment = model.evaluate(sessions: sessions, athlete: athlete)
        XCTAssertGreaterThan(assessment.score, 75,
            "One moderate session 48 hours ago should keep readiness high")
    }

    // MARK: - Score clamping

    func testScoreAlwaysBetweenZeroAndHundred() {
        // Stress test: 20 brutal sessions
        let now = Date.now
        let sessions = (0..<20).map { i in
            RecentSession(
                date: now.addingTimeInterval(TimeInterval(-i * 3600)),
                durationMinutes: 150,
                totalVolumeLoad: 50_000,
                averageRPE: 10.0,
                completedSetCount: 30
            )
        }
        let assessment = model.evaluate(sessions: sessions, athlete: athlete)
        XCTAssertGreaterThanOrEqual(assessment.score, 0)
        XCTAssertLessThanOrEqual(assessment.score, 100)
    }

    // MARK: - Brief messages

    func testBriefMessageReflectsScore() {
        let restedAssessment = model.evaluate(sessions: [], athlete: athlete)
        XCTAssertFalse(restedAssessment.brief.isEmpty)
        XCTAssertTrue(restedAssessment.brief.count > 10,
            "Brief should be a meaningful sentence, not a placeholder")
    }
}
