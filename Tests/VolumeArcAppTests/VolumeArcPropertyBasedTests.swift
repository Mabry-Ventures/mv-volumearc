import XCTest
import VolumeArcCore

/// VOL-170: deterministic property-style checks over the numeric and
/// serialization surfaces that have the largest input spaces.
final class VolumeArcPropertyBasedTests: XCTestCase {
    private static let referenceDate = Date(timeIntervalSince1970: 1_720_000_000)

    private let progressionEngine = ProgressionEngine()
    private let readinessModel = ReadinessModel()

    func testProgressionTargetIsMonotonicAcrossRandomTopSetWeights() {
        var rng = SeededPropertyGenerator(seed: 0x170A11CE)
        let goal = StrengthGoal.generalStrength
        let upperRepBound = 8

        for caseIndex in 0..<1_000 {
            let baseWeight = rng.double(in: 0...650)
            let extraWeight = rng.double(in: 0...250)
            let rpe = rng.double(in: 5.0...8.0)
            let level = rng.element(from: AdvancementLevel.allCases)
            let athlete = AthleteProfile(
                name: "Property Athlete \(caseIndex)",
                advancementLevel: level,
                availableEquipment: [.barbell]
            )

            let lighter = progressionState(
                weight: baseWeight,
                reps: upperRepBound,
                rpe: rpe,
                athlete: athlete,
                goal: goal
            )
            let heavier = progressionState(
                weight: baseWeight + extraWeight,
                reps: upperRepBound,
                rpe: rpe,
                athlete: athlete,
                goal: goal
            )

            XCTAssertGreaterThanOrEqual(
                heavier.nextTarget.weight,
                lighter.nextTarget.weight,
                "Case \(caseIndex): higher current top set must never lower next target"
            )
            XCTAssertTrue(lighter.nextTarget.weight.isFinite)
            XCTAssertTrue(heavier.nextTarget.weight.isFinite)
            XCTAssertGreaterThanOrEqual(lighter.nextTarget.weight, 0)
            XCTAssertGreaterThanOrEqual(heavier.nextTarget.weight, 0)
        }
    }

    func testProgressionSuggestedActionTracksTopSetRPEAcrossRandomInputs() {
        var rng = SeededPropertyGenerator(seed: 0x170DEC0A)

        for caseIndex in 0..<1_000 {
            let weight = rng.double(in: 45...500)
            let reps = rng.int(in: 3...12)
            let goal = rng.element(from: StrengthGoal.allCases)
            let athlete = AthleteProfile(
                name: "Action Boundary \(caseIndex)",
                advancementLevel: rng.element(from: AdvancementLevel.allCases),
                availableEquipment: [.barbell],
                weeklyTrainingDays: rng.int(in: 2...5)
            )

            let easyState = progressionEngine.buildAutopilotState(
                for: ExerciseHistory(
                    exerciseID: "back-squat",
                    sessions: [exerciseSession(weight: weight, reps: reps, rpe: rng.double(in: 5.0...7.0))]
                ),
                athlete: athlete,
                goal: goal,
                recentSessions: [],
                memory: CoachMemory()
            )
            let grindingState = progressionEngine.buildAutopilotState(
                for: ExerciseHistory(
                    exerciseID: "back-squat",
                    sessions: [exerciseSession(weight: weight, reps: reps, rpe: rng.double(in: 9.0...10.0))]
                ),
                athlete: athlete,
                goal: goal,
                recentSessions: [],
                memory: CoachMemory()
            )

            XCTAssertEqual(
                easyState.suggestedAction,
                .increase,
                "Case \(caseIndex): easy top sets with rested context should progress"
            )
            XCTAssertEqual(
                grindingState.suggestedAction,
                .hold,
                "Case \(caseIndex): grinding top sets should not progress automatically"
            )
        }
    }

    func testReadinessScoreStaysBoundedAndFallsAsIntensityRises() {
        var rng = SeededPropertyGenerator(seed: 0x170EAD1)

        for caseIndex in 0..<1_000 {
            let athlete = AthleteProfile(
                name: "Readiness \(caseIndex)",
                weeklyTrainingDays: rng.int(in: 3...6)
            )
            let moderate = readinessSessions(using: &rng, averageRPE: rng.double(in: 6.5...7.4))
            let grinding = moderate.map { session in
                RecentSession(
                    date: session.date,
                    durationMinutes: session.durationMinutes,
                    exerciseIDs: session.exerciseIDs,
                    totalVolumeLoad: session.totalVolumeLoad,
                    averageRPE: rng.double(in: 9.5...10.0),
                    completedSetCount: session.completedSetCount
                )
            }

            let moderateAssessment = readinessModel.evaluate(sessions: moderate, athlete: athlete)
            let grindingAssessment = readinessModel.evaluate(sessions: grinding, athlete: athlete)

            for assessment in [moderateAssessment, grindingAssessment] {
                XCTAssertGreaterThanOrEqual(assessment.score, 0, "Case \(caseIndex)")
                XCTAssertLessThanOrEqual(assessment.score, 100, "Case \(caseIndex)")
                XCTAssertEqual(assessment.factors.count, 5, "Case \(caseIndex)")
            }
            XCTAssertLessThanOrEqual(
                grindingAssessment.score,
                moderateAssessment.score,
                "Case \(caseIndex): higher RPE should not improve readiness"
            )
        }
    }

    func testTimestampRoundTripsRandomSecondsAndMilliseconds() throws {
        var rng = SeededPropertyGenerator(seed: 0x17071A1E)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for caseIndex in 0..<10_000 {
            let seconds = rng.double(in: -6_311_520_000...7_258_118_400)
            let milliseconds = seconds * 1_000

            let secondTimestamp = Timestamp.seconds(seconds)
            XCTAssertEqual(
                secondTimestamp.secondsSinceEpoch,
                seconds,
                accuracy: 1e-6,
                "Case \(caseIndex): seconds constructor lost precision"
            )
            XCTAssertEqual(
                secondTimestamp.millisecondsSinceEpoch,
                milliseconds,
                accuracy: 1e-3,
                "Case \(caseIndex): seconds-to-ms derivation lost precision"
            )

            let millisecondTimestamp = Timestamp.milliseconds(milliseconds)
            XCTAssertEqual(
                millisecondTimestamp.secondsSinceEpoch,
                seconds,
                accuracy: 1e-6,
                "Case \(caseIndex): ms constructor lost precision"
            )

            let encoded = try encoder.encode(secondTimestamp)
            let decoded = try decoder.decode(Timestamp.self, from: encoded)
            XCTAssertEqual(
                decoded.secondsSinceEpoch,
                seconds,
                accuracy: 1e-6,
                "Case \(caseIndex): Codable round-trip lost precision"
            )

            let raw = abs(milliseconds) > Timestamp.secondsVsMillisecondsThreshold
                ? milliseconds
                : seconds
            let autoDetected = try XCTUnwrap(Timestamp.autoDetect(raw))
            let expectedSeconds = abs(raw) > Timestamp.secondsVsMillisecondsThreshold
                ? raw / 1_000
                : raw
            XCTAssertEqual(
                autoDetected.secondsSinceEpoch,
                expectedSeconds,
                accuracy: 1e-6,
                "Case \(caseIndex): autoDetect selected wrong unit"
            )
        }
    }

    func testSyncPayloadCodecRoundTripsRandomCloudSyncRecords() throws {
        var rng = SeededPropertyGenerator(seed: 0x170C10D)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for caseIndex in 0..<1_000 {
            let fixture = randomSyncRecordFixture(caseIndex: caseIndex, using: &rng)
            let encoded = try encoder.encode(fixture.record)
            let decoded = try decoder.decode(CloudSyncRecord.self, from: encoded)

            XCTAssertEqual(decoded.kind, fixture.record.kind, "Case \(caseIndex)")
            XCTAssertEqual(decoded.identifier, fixture.record.identifier, "Case \(caseIndex)")
            XCTAssertEqual(decoded.operation, fixture.record.operation, "Case \(caseIndex)")
            XCTAssertEqual(decoded.payloadJSON, fixture.record.payloadJSON, "Case \(caseIndex)")
            XCTAssertEqual(
                decoded.modifiedAt.timeIntervalSince1970,
                fixture.record.modifiedAt.timeIntervalSince1970,
                accuracy: 1e-6,
                "Case \(caseIndex)"
            )

            assertPayloadRoundTrip(fixture, caseIndex: caseIndex)
        }
    }

    // MARK: - Progression helpers

    private func progressionState(
        weight: Double,
        reps: Int,
        rpe: Double,
        athlete: AthleteProfile,
        goal: StrengthGoal
    ) -> WorkoutAutopilotState {
        progressionEngine.buildAutopilotState(
            for: ExerciseHistory(
                exerciseID: "back-squat",
                sessions: [exerciseSession(weight: weight, reps: reps, rpe: rpe)]
            ),
            athlete: athlete,
            goal: goal,
            recentSessions: [],
            memory: CoachMemory()
        )
    }

    private func exerciseSession(weight: Double, reps: Int, rpe: Double) -> ExerciseSession {
        let completedAt = Date(timeIntervalSince1970: 1_720_000_000)
        return ExerciseSession(
            date: completedAt,
            sets: [
                WorkoutSetPerformance(
                    weight: weight,
                    reps: reps,
                    rpe: rpe,
                    completedAt: completedAt
                ),
            ]
        )
    }

    // MARK: - Readiness helpers

    private func readinessSessions(
        using rng: inout SeededPropertyGenerator,
        averageRPE: Double
    ) -> [RecentSession] {
        let now = Self.referenceDate
        let count = rng.int(in: 3...6)
        return (0..<count).map { index in
            RecentSession(
                date: now.addingTimeInterval(TimeInterval(-(index + 1) * rng.int(in: 8...36) * 3_600)),
                durationMinutes: rng.int(in: 35...105),
                exerciseIDs: ["back-squat", "bench-press"],
                totalVolumeLoad: rng.double(in: 3_000...18_000),
                averageRPE: averageRPE,
                completedSetCount: rng.int(in: 6...20)
            )
        }
    }

    // MARK: - Sync payload helpers

    private enum PayloadFixture {
        case userProfile(SyncPayloadCodec.UserProfilePayload)
        case workout(SyncPayloadCodec.WorkoutPayload)
        case trainingPlan(SyncPayloadCodec.TrainingPlanPayload)
        case coachMemory(SyncPayloadCodec.CoachMemoryPayload)
    }

    private struct SyncRecordFixture {
        let record: CloudSyncRecord
        let payload: PayloadFixture
    }

    private func randomSyncRecordFixture(
        caseIndex: Int,
        using rng: inout SeededPropertyGenerator
    ) -> SyncRecordFixture {
        let kind = rng.element(from: CloudSyncRecord.Kind.allCases)
        let operation = rng.element(from: [CloudSyncRecord.Operation.upsert, .delete])
        let modifiedAt = rng.date()

        switch kind {
        case .userProfile:
            let payload = SyncPayloadCodec.UserProfilePayload(
                name: "Athlete \(caseIndex)",
                coachingStyle: rng.element(from: CoachingStyle.allCases).rawValue,
                privacyMode: rng.element(from: PrivacyMode.allCases).rawValue,
                advancementLevel: rng.element(from: AdvancementLevel.allCases).rawValue,
                availableEquipmentCSV: "barbell,dumbbell,bodyweight",
                preferredRepRangeLower: rng.int(in: 3...8),
                preferredRepRangeUpper: rng.int(in: 9...15),
                sessionTimeBudgetMinutes: rng.int(in: 30...120),
                weeklyTrainingDays: rng.int(in: 1...7),
                onboardingCompleted: rng.bool(),
                updatedAt: modifiedAt
            )
            return SyncRecordFixture(
                record: cloudRecord(
                    kind: kind,
                    identifier: kind.defaultIdentifier,
                    operation: operation,
                    payloadJSON: envelopeJSON(["profile": payload]),
                    modifiedAt: modifiedAt
                ),
                payload: .userProfile(payload)
            )
        case .workout:
            let startedAt = rng.date()
            let completedAt = rng.bool()
                ? startedAt.addingTimeInterval(TimeInterval(rng.int(in: 1_800...9_000)))
                : nil
            let payload = SyncPayloadCodec.WorkoutPayload(
                title: "Property Workout \(caseIndex)",
                startedAt: startedAt,
                completedAt: completedAt,
                durationMinutes: rng.int(in: 20...150),
                exerciseIDsCSV: "back-squat,bench-press",
                setsJSON: "[{\"weight\":\(rng.int(in: 45...405)),\"reps\":\(rng.int(in: 1...20))}]",
                totalVolumeLoad: rng.double(in: 0...75_000),
                averageRPE: rng.double(in: 1...10),
                completedSetCount: rng.int(in: 0...40),
                summary: "Generated structural round-trip fixture",
                updatedAt: modifiedAt
            )
            return SyncRecordFixture(
                record: cloudRecord(
                    kind: kind,
                    identifier: "workout-\(caseIndex)",
                    operation: operation,
                    payloadJSON: envelopeJSON(["workout": payload]),
                    modifiedAt: modifiedAt
                ),
                payload: .workout(payload)
            )
        case .trainingPlan:
            let payload = SyncPayloadCodec.TrainingPlanPayload(
                workoutsJSON: "[{\"day\":\"Mon\",\"exercise\":\"back-squat\",\"sets\":\(rng.int(in: 1...8))}]",
                updatedAt: modifiedAt
            )
            return SyncRecordFixture(
                record: cloudRecord(
                    kind: kind,
                    identifier: kind.defaultIdentifier,
                    operation: operation,
                    payloadJSON: envelopeJSON(["plan": payload]),
                    modifiedAt: modifiedAt
                ),
                payload: .trainingPlan(payload)
            )
        case .coachMemory:
            let payload = SyncPayloadCodec.CoachMemoryPayload(
                content: "Cue \(caseIndex): brace hard and move with intent.",
                theme: rng.element(from: ["squat", "bench", "recovery", "progression"]),
                createdAt: modifiedAt
            )
            return SyncRecordFixture(
                record: cloudRecord(
                    kind: kind,
                    identifier: "memory-\(caseIndex)",
                    operation: operation,
                    payloadJSON: envelopeJSON(["memory": payload]),
                    modifiedAt: modifiedAt
                ),
                payload: .coachMemory(payload)
            )
        }
    }

    private func cloudRecord(
        kind: CloudSyncRecord.Kind,
        identifier: String,
        operation: CloudSyncRecord.Operation,
        payloadJSON: String,
        modifiedAt: Date
    ) -> CloudSyncRecord {
        CloudSyncRecord(
            kind: kind,
            identifier: identifier,
            operation: operation,
            payloadJSON: payloadJSON,
            modifiedAt: modifiedAt
        )
    }

    private func envelopeJSON<T: Encodable>(_ envelope: T) -> String {
        guard let json = SyncPayloadCodec.encode(envelope) else {
            XCTFail("Failed to encode payload envelope")
            return "{}"
        }
        return json
    }

    private func assertPayloadRoundTrip(
        _ fixture: SyncRecordFixture,
        caseIndex: Int
    ) {
        switch fixture.payload {
        case let .userProfile(expected):
            let decoded = SyncPayloadCodec.decodeUserProfilePayload(from: fixture.record.payloadJSON)
            XCTAssertEqual(decoded?.name, expected.name, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.coachingStyle, expected.coachingStyle, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.privacyMode, expected.privacyMode, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.advancementLevel, expected.advancementLevel, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.availableEquipmentCSV, expected.availableEquipmentCSV, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.preferredRepRangeLower, expected.preferredRepRangeLower, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.preferredRepRangeUpper, expected.preferredRepRangeUpper, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.sessionTimeBudgetMinutes, expected.sessionTimeBudgetMinutes, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.weeklyTrainingDays, expected.weeklyTrainingDays, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.onboardingCompleted, expected.onboardingCompleted, "Case \(caseIndex)")
            assertDateEqual(decoded?.updatedAt, expected.updatedAt, caseIndex: caseIndex)
        case let .workout(expected):
            let decoded = SyncPayloadCodec.decodeWorkoutPayload(from: fixture.record.payloadJSON)
            XCTAssertEqual(decoded?.title, expected.title, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.durationMinutes, expected.durationMinutes, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.exerciseIDsCSV, expected.exerciseIDsCSV, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.setsJSON, expected.setsJSON, "Case \(caseIndex)")
            assertDoubleEqual(decoded?.totalVolumeLoad, expected.totalVolumeLoad, caseIndex: caseIndex)
            assertDoubleEqual(decoded?.averageRPE, expected.averageRPE, caseIndex: caseIndex)
            XCTAssertEqual(decoded?.completedSetCount, expected.completedSetCount, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.summary, expected.summary, "Case \(caseIndex)")
            assertDateEqual(decoded?.startedAt, expected.startedAt, caseIndex: caseIndex)
            assertDateEqual(decoded?.completedAt, expected.completedAt, caseIndex: caseIndex)
            assertDateEqual(decoded?.updatedAt, expected.updatedAt, caseIndex: caseIndex)
        case let .trainingPlan(expected):
            let decoded = SyncPayloadCodec.decodeTrainingPlanPayload(from: fixture.record.payloadJSON)
            XCTAssertEqual(decoded?.workoutsJSON, expected.workoutsJSON, "Case \(caseIndex)")
            assertDateEqual(decoded?.updatedAt, expected.updatedAt, caseIndex: caseIndex)
        case let .coachMemory(expected):
            let decoded = SyncPayloadCodec.decodeCoachMemoryPayload(from: fixture.record.payloadJSON)
            XCTAssertEqual(decoded?.content, expected.content, "Case \(caseIndex)")
            XCTAssertEqual(decoded?.theme, expected.theme, "Case \(caseIndex)")
            assertDateEqual(decoded?.createdAt, expected.createdAt, caseIndex: caseIndex)
        }
    }

    private func assertDateEqual(
        _ actual: Date?,
        _ expected: Date?,
        caseIndex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case let (actual?, expected?):
            XCTAssertEqual(
                actual.timeIntervalSince1970,
                expected.timeIntervalSince1970,
                accuracy: 0.001,
                "Case \(caseIndex)",
                file: file,
                line: line
            )
        case (nil, nil):
            break
        default:
            XCTFail("Case \(caseIndex): date optional mismatch", file: file, line: line)
        }
    }

    private func assertDoubleEqual(
        _ actual: Double?,
        _ expected: Double,
        caseIndex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Case \(caseIndex): missing double value", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, expected, accuracy: 0.001, "Case \(caseIndex)", file: file, line: line)
    }
}

private struct SeededPropertyGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next()) / Double(UInt64.max)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }

    mutating func bool() -> Bool {
        next().isMultiple(of: 2)
    }

    mutating func element<T>(from values: [T]) -> T {
        values[int(in: 0...(values.count - 1))]
    }

    mutating func element<T: CaseIterable>(from values: T.AllCases) -> T where T.AllCases: Collection {
        let index = values.index(values.startIndex, offsetBy: int(in: 0...(values.count - 1)))
        return values[index]
    }

    mutating func date() -> Date {
        let milliseconds = int(in: -2_208_988_800_000...4_102_444_800_000)
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }
}
