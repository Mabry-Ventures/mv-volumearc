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

    /// PR #363 review (Codex P2): logged history keyed by catalog IDs
    /// (`back-squat`) carries no implement token, but a barbell-qualified
    /// plan name means the same lift by the file's own convention — it
    /// must inherit the demonstrated top, not the no-history cap.
    func testBarbellQualifiedPlanInheritsCatalogIDHistory() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["back-squat": 200]
        )

        let (plan, events) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(name: "Barbell Back Squat", weight: 315)]), input: input
        )

        XCTAssertEqual(plan.exercises.first?.weight, 220,
                       "Catalog-ID history must beat the 135 lb first-exposure fallback")
        XCTAssertEqual(events.map(\.kind), [.loadCap])
    }

    func testDumbbellQualifiedPlanDoesNotInheritUnqualifiedHistory() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["bench-press": 200]
        )

        let (plan, _) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(name: "Dumbbell Bench Press", weight: 90)]), input: input
        )

        let weight = try? XCTUnwrap(plan.exercises.first?.weight)
        XCTAssertEqual(weight, CoachPrescriptionClamp.noHistoryCap(for: "Dumbbell Bench Press", symptomContext: false),
                       "Unqualified history is barbell-class; a dumbbell plan must keep its first-exposure cap")
    }

    /// PR #363 review (CodeRabbit): the subset gate admits sparse custom
    /// keys ("press" ⊂ "barbell-bench-press"), so the catalog-ID bridge
    /// must demand an implement-only delta — unrelated history can never
    /// widen a qualified plan's cap.
    func testSparseUnqualifiedKeyDoesNotLendHistoryToQualifiedPlan() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["press": 200]
        )

        let (plan, events) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(name: "Barbell Bench Press", weight: 300)]), input: input
        )

        XCTAssertEqual(plan.exercises.first?.weight, CoachPrescriptionClamp.noHistoryBarbellCap,
                       "A sparse custom key must not widen the demonstrated-top cap")
        XCTAssertEqual(events.map(\.kind), [.noHistoryCap])
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

    func testVolumeCapReducesRepsAfterSetFloorWithoutEliminatingExercise() {
        let input = CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: ["barbell-back-squat": 200],
            maxRecentSessionVolume: 100
        )

        let (plan, events) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(sets: 5, reps: 10, weight: 200)]), input: input
        )

        // PR #363 review: after the set floor, reps reduce too. The
        // exercise itself is never deleted (signed policy), so the
        // enforced floor is one rep of the weight-clamped load — residual
        // volume above the cap at the 1x1 floor is accepted by design.
        XCTAssertEqual(plan.exercises.first?.sets, 1)
        XCTAssertEqual(plan.exercises.first?.reps, 1)
        XCTAssertEqual(plan.exercises.count, 1)
        XCTAssertTrue(events.contains { $0.kind == .sessionVolumeCap && $0.field == "sets" })
        XCTAssertTrue(events.contains { $0.kind == .sessionVolumeCap && $0.field == "reps" })
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
            "Token matching connects coach phrasing to logged exercise IDs"
        )
    }

    // PR #363 review (Codex P2 + CodeRabbit Major): history must not
    // transfer across implements or lift variants.

    func testDumbbellVariantDoesNotInheritHeavierHistory() {
        let table = ["bench-press": 200.0, "barbell-bench-press": 225.0]

        XCTAssertNil(
            CoachPrescriptionClamp.topWeight(for: "Dumbbell Bench Press", in: table),
            "A dumbbell plan must never inherit barbell/unqualified history"
        )

        let (plan, events) = CoachPrescriptionClamp.clamp(
            makePlan([makeExercise(name: "Dumbbell Bench Press", weight: 200)]),
            input: CoachPrescriptionClamp.Input(topWeightByExerciseKey: table)
        )
        XCTAssertEqual(plan.exercises.first?.weight, CoachPrescriptionClamp.noHistoryDumbbellCap)
        XCTAssertEqual(events.map(\.kind), [.noHistoryCap])
    }

    func testVariantQualifierBlocksHistoryTransfer() {
        XCTAssertNil(
            CoachPrescriptionClamp.topWeight(for: "Deadlift", in: ["romanian-deadlift": 245]),
            "Conventional deadlift must not inherit romanian-deadlift history"
        )
        XCTAssertNil(
            CoachPrescriptionClamp.topWeight(for: "Romanian Deadlift", in: ["deadlift": 405]),
            "Romanian deadlift must not inherit conventional history either"
        )
    }

    func testUnqualifiedNamePrefersHeavyClassAndClampsConservatively() {
        let table = [
            "barbell-bench-press": 225.0,
            "dumbbell-bench-press": 70.0,
        ]

        XCTAssertEqual(
            CoachPrescriptionClamp.topWeight(for: "Bench Press", in: table),
            225,
            "A plain compound name means the heavy-class lift; dumbbell history is ignored"
        )

        let ambiguous = ["barbell-bench-press": 225.0, "bench-press": 205.0]
        XCTAssertEqual(
            CoachPrescriptionClamp.topWeight(for: "Bench Press", in: ambiguous),
            205,
            "Within a class, ambiguity resolves to the LOWEST top so clamps stay conservative"
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
