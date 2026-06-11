import XCTest
import VolumeArcCore

// VOL-284: deterministic prescription clamp rules.
//
// The clamp is the structural guarantee that no coach brain — cloud,
// on-device, or heuristic — can schedule a dangerous prescription. These
// tests pin each policy bound at its boundary, the name/ID matching that
// connects coach free-text to logged history, and idempotency (clamping
// a clamped plan changes nothing), which the schedule-time backstop
// relies on.
final class CoachPrescriptionClampTests: XCTestCase {

    private func makeExercise(
        name: String = "Barbell Back Squat",
        sets: Int = 3,
        reps: Int = 5,
        weight: Int,
        targetRPE: Int = 7,
        restSeconds: Int = 120
    ) -> WeeklyWorkoutExercise {
        WeeklyWorkoutExercise(
            name: name, sets: sets, reps: reps,
            weight: weight, targetRPE: targetRPE, restSeconds: restSeconds
        )
    }

    private func makePlan(_ exercises: [WeeklyWorkoutExercise], targetRPE: Int? = 7) -> WorkoutSessionPlan {
        WorkoutSessionPlan(title: "Coach Workout", durationMinutes: 45, targetRPE: targetRPE, exercises: exercises)
    }

    // MARK: - Load cap vs history

    func testLoadCapAgainstDemonstratedHistory() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["barbell-back-squat": 200]
        )

        let (plan, events) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(weight: 855)]), input: input
        )

        XCTAssertEqual(plan.exercises.first?.weight, 220, "10% over a 200 lb top is the ceiling")
        XCTAssertEqual(events.map(\.kind), [.loadCap])
    }

    func testSmallImplementAlwaysAllowsOneFivePoundJump() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["dumbbell-curl": 20]
        )

        let (allowed, allowedEvents) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(name: "Dumbbell Curl", weight: 25)]), input: input
        )
        XCTAssertEqual(allowed.exercises.first?.weight, 25, "20 -> 25 is one increment; 10% alone would forbid it")
        XCTAssertTrue(allowedEvents.isEmpty)

        let (clamped, clampedEvents) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(name: "Dumbbell Curl", weight: 40)]), input: input
        )
        XCTAssertEqual(clamped.exercises.first?.weight, 25)
        XCTAssertEqual(clampedEvents.map(\.kind), [.loadCap])
    }

    // MARK: - No-history first-exposure caps

    func testNoHistoryBarbellCap() {
        let (plan, events) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(weight: 315)]), input: CoachPrescriptionClamp.Input()
        )

        XCTAssertEqual(plan.exercises.first?.weight, CoachPrescriptionClamp.noHistoryBarbellCap)
        XCTAssertEqual(events.map(\.kind), [.noHistoryCap])
    }

    func testNoHistoryFamilies() {
        XCTAssertEqual(CoachPrescriptionClamp.noHistoryCap(for: "Dumbbell Row", symptomContext: false), 50)
        XCTAssertEqual(CoachPrescriptionClamp.noHistoryCap(for: "Deadlift", symptomContext: false), 135)
        XCTAssertEqual(CoachPrescriptionClamp.noHistoryCap(for: "Cable Fly", symptomContext: false), 75)
        XCTAssertEqual(CoachPrescriptionClamp.noHistoryCap(for: "Bench Press", symptomContext: true), 45)
        XCTAssertEqual(CoachPrescriptionClamp.noHistoryCap(for: "Dumbbell Press", symptomContext: true), 20)
    }

    // MARK: - Symptom context

    func testSymptomContextFreezesLoadAndRPE() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["barbell-back-squat": 200],
            hasSymptomContext: true
        )

        let (plan, events) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(weight: 185, targetRPE: 8)], targetRPE: 8), input: input
        )

        XCTAssertEqual(plan.exercises.first?.weight, 120, "60% of the 200 lb top")
        XCTAssertEqual(plan.exercises.first?.targetRPE, 6)
        XCTAssertEqual(plan.targetRPE, 6)
        XCTAssertEqual(Set(events.map(\.kind)), [.symptomFreeze, .symptomRPECap])
    }

    // MARK: - Heavy rest floor

    func testHeavyLoadGetsRestFloor() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["barbell-back-squat": 200]
        )

        let (plan, events) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(weight: 190, restSeconds: 60)]), input: input
        )

        XCTAssertEqual(plan.exercises.first?.restSeconds, CoachPrescriptionClamp.heavyRestFloorSeconds)
        XCTAssertEqual(events.map(\.kind), [.heavyRestFloor])
    }

    // MARK: - Session volume cap

    func testSessionVolumeCapReducesSets() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["barbell-back-squat": 200],
            maxRecentSessionVolume: 4000
        )

        // 5 x 10 x 200 = 10,000 against a 4,800 cap -> sets fall to 2 (4,000).
        let (plan, events) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(sets: 5, reps: 10, weight: 200)]), input: input
        )

        XCTAssertEqual(plan.exercises.first?.sets, 2)
        XCTAssertTrue(events.contains { $0.kind == .sessionVolumeCap && $0.original == 5 && $0.clamped == 2 })
    }

    func testVolumeCapNeverEliminatesAnExercise() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["barbell-back-squat": 200],
            maxRecentSessionVolume: 100
        )

        let (plan, _) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(sets: 5, reps: 10, weight: 200)]), input: input
        )

        XCTAssertEqual(plan.exercises.first?.sets, 1, "Sets floor at 1 even when the cap is unreachable")
    }

    // MARK: - Matching, idempotency, clean pass-through

    func testNameMatchingBridgesLoggedIDAndDisplayName() {
        XCTAssertEqual(
            CoachPrescriptionClamp.normalizedExerciseKey("Barbell Back Squat"),
            "barbell-back-squat"
        )
        XCTAssertEqual(
            CoachPrescriptionClamp.topWeight(for: "Back Squat", in: ["barbell-back-squat": 200]),
            200,
            "Containment matching connects coach phrasing to logged exercise IDs"
        )
    }

    func testCleanPlanPassesThroughUntouched() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["barbell-back-squat": 200],
            maxRecentSessionVolume: 10_000
        )
        let original = makePlan([makeExercise(weight: 205, restSeconds: 120)])

        let (plan, events) = CoachPrescriptionClamp.clamp(original, input: input)

        XCTAssertEqual(plan, original)
        XCTAssertTrue(events.isEmpty)
    }

    func testClampIsIdempotent() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["barbell-back-squat": 200],
            maxRecentSessionVolume: 4000,
            hasSymptomContext: true
        )
        let wild = makePlan([makeExercise(sets: 8, reps: 12, weight: 855, targetRPE: 9)], targetRPE: 9)

        let (once, firstEvents) = CoachPrescriptionClamp.clamp(wild, input: input)
        let (twice, secondEvents) = CoachPrescriptionClamp.clamp(once, input: input)

        XCTAssertFalse(firstEvents.isEmpty)
        XCTAssertEqual(once, twice, "Schedule-time backstop relies on idempotency")
        XCTAssertTrue(secondEvents.isEmpty)
    }
}
