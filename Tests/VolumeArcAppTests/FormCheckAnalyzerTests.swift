import XCTest
@testable import VolumeArcCore

final class FormCheckAnalyzerTests: XCTestCase {
    func testInferTargetsBenchSquatAndDeadliftOnly() {
        XCTAssertEqual(FormCheckExercise.infer(exerciseID: "back-squat", name: "Back Squat"), .squat)
        XCTAssertEqual(FormCheckExercise.infer(exerciseID: "barbell-bench-press", name: "Bench Press"), .benchPress)
        XCTAssertEqual(FormCheckExercise.infer(exerciseID: "deadlift", name: "Conventional Deadlift"), .deadlift)
        XCTAssertNil(FormCheckExercise.infer(exerciseID: "leg-press", name: "Leg Press"))
        XCTAssertNil(FormCheckExercise.infer(exerciseID: "overhead-press", name: "Overhead Press"))
        XCTAssertNil(FormCheckExercise.infer(exerciseID: "lat-pulldown", name: "Lat Pulldown"))
    }

    func testAnalyzerReturnsInconclusiveForEmptyFrames() {
        let analysis = FormCheckAnalyzer(exercise: .squat).analyze(frames: [])

        XCTAssertEqual(analysis.verdict, .inconclusive)
        XCTAssertEqual(analysis.hapticCode, .inconclusive)
        XCTAssertEqual(analysis.repCount, 0)
        XCTAssertTrue(analysis.flags.contains(.lowConfidence))
        XCTAssertTrue(analysis.flags.contains(.noRepDetected))
    }

    func testSquatRepCounterDetectsThreeControlledReps() {
        let frames = downThenUpFrames(repetitions: 3)
        let analysis = FormCheckAnalyzer(exercise: .squat).analyze(
            frames: frames,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(analysis.verdict, .solid)
        XCTAssertEqual(analysis.repCount, 3)
        XCTAssertEqual(analysis.hapticCode, .solid)
        XCTAssertTrue(analysis.flags.isEmpty, "Controlled synthetic reps should not emit review flags")
        XCTAssertEqual(analysis.averageRepDuration ?? 0, 0.9, accuracy: 0.15)
        XCTAssertTrue(analysis.promptFragment.contains("Latest form check"))
    }

    func testDeadliftRepCounterUsesUpThenDownMovement() {
        let frames = upThenDownFrames(repetitions: 2)
        let analysis = FormCheckAnalyzer(exercise: .deadlift).analyze(frames: frames)

        XCTAssertEqual(analysis.verdict, .solid)
        XCTAssertEqual(analysis.repCount, 2)
        XCTAssertEqual(analysis.reps.first?.concentricDuration ?? 0, 0.6, accuracy: 0.2)
        XCTAssertEqual(analysis.reps.first?.eccentricDuration ?? 0, 0.9, accuracy: 0.2)
    }

    func testUnstablePathIsReviewVerdict() {
        let frames = downThenUpFrames(
            repetitions: 2,
            xValues: [0.42, 0.48, 0.58, 0.72, 0.65, 0.55, 0.43],
            joint: .leftWrist
        )
        let analysis = FormCheckAnalyzer(exercise: .benchPress).analyze(frames: frames)

        XCTAssertEqual(analysis.verdict, .review)
        XCTAssertTrue(analysis.flags.contains(.unstableBarPath))
        XCTAssertEqual(analysis.hapticCode, .review)
        XCTAssertTrue(analysis.cueText.contains("side drift"))
    }

    func testCoachContextIncludesDerivedFormMetricsWithoutVideo() {
        let analysis = FormCheckAnalyzer(exercise: .squat).analyze(frames: downThenUpFrames(repetitions: 2))
        let context = CoachContext(
            athleteName: "Jared",
            advancementLevel: "intermediate",
            readinessScore: 82,
            readinessBrief: "Ready",
            nextExercise: "Back Squat",
            nextTarget: "225lb x 5",
            formCheck: analysis
        )
        let prompt = context.asPromptBlock(privacyMode: .strict)

        XCTAssertTrue(prompt.contains("## Latest form check"))
        XCTAssertTrue(prompt.contains("- Exercise: Squat"))
        XCTAssertTrue(prompt.contains("- Privacy: video frames were processed on-device"))
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("video upload"))
        XCTAssertFalse(prompt.contains("Jared"))
    }

    private func downThenUpFrames(
        repetitions: Int,
        xValues: [Double]? = nil,
        joint: FormCheckJointName = .root,
        confidence: Double = 0.92
    ) -> [FormCheckFrame] {
        repeatedFrames(
            repetitions: repetitions,
            yValues: [0.84, 0.72, 0.52, 0.28, 0.48, 0.70, 0.84],
            xValues: xValues ?? [0.50, 0.50, 0.51, 0.50, 0.49, 0.50, 0.50],
            joint: joint,
            confidence: confidence
        )
    }

    private func upThenDownFrames(
        repetitions: Int,
        confidence: Double = 0.92
    ) -> [FormCheckFrame] {
        repeatedFrames(
            repetitions: repetitions,
            yValues: [0.24, 0.42, 0.66, 0.84, 0.66, 0.42, 0.24],
            xValues: [0.50, 0.50, 0.51, 0.50, 0.50, 0.49, 0.50],
            joint: .leftWrist,
            confidence: confidence
        )
    }

    private func repeatedFrames(
        repetitions: Int,
        yValues: [Double],
        xValues: [Double],
        joint: FormCheckJointName,
        confidence: Double
    ) -> [FormCheckFrame] {
        precondition(xValues.count == yValues.count, "xValues and yValues must have equal lengths")
        var frames: [FormCheckFrame] = []
        var timestamp: TimeInterval = 0
        for _ in 0..<repetitions {
            for index in yValues.indices {
                frames.append(FormCheckFrame(
                    timestamp: timestamp,
                    joints: [
                        joint: FormCheckPoint(
                            x: xValues[index],
                            y: yValues[index],
                            confidence: confidence
                        ),
                    ]
                ))
                timestamp += 0.30
            }
        }
        return frames
    }
}
