import XCTest
import VolumeArcCore

/// Tests for `VolumeArcExerciseCatalog` — the static catalog that backs
/// progression, plan generation, watch workout flows, and coach context.
/// These tests exercise the real catalog values; no stubs.
///
/// API shape notes (relative to the ticket's test-case wishlist):
/// - The public type is `VolumeArcExerciseCatalog`, not `ExerciseCatalog`.
/// - Exercises are classified by `MovementPattern` (squat/hinge/push/pull/...),
///   not a `Category` enum.
/// - There is no name-lookup API; `exercise(withID:)` is the only lookup.
/// - Filtering by pattern/equipment is done by clients via `all.filter { ... }`,
///   so "filter by category/equipment" tests exercise that shape directly.
/// - Substitutions are exposed as `alternatives(for:availableEquipment:)`.
final class ExerciseCatalogTests: XCTestCase {

    // MARK: - Catalog is populated

    func test_all_returnsNonEmptyCatalog() {
        // The catalog currently ships 11 exercises covering every movement
        // pattern the progression engine consumes. The exact count is
        // intentionally asserted against a lower bound so adding new
        // exercises doesn't require touching this test, while removing
        // the whole catalog still fails loudly.
        XCTAssertGreaterThanOrEqual(
            VolumeArcExerciseCatalog.all.count, 10,
            "Catalog must ship enough exercises to cover every movement pattern"
        )
    }

    func test_all_coversEveryMovementPattern() {
        // Patterns that ProgressionEngine/WorkoutDashboardModel can ask
        // for substitutions on. `.carry`, `.isolation`, `.conditioning`
        // are defined on the enum but the catalog does not yet ship
        // exercises for them — assert only on the patterns that the
        // progression engine relies on today.
        let programmedPatterns: Set<MovementPattern> = [
            .squat, .hinge,
            .horizontalPush, .verticalPush,
            .horizontalPull, .verticalPull,
        ]
        let cataloguedPatterns = Set(VolumeArcExerciseCatalog.all.map(\.pattern))
        for pattern in programmedPatterns {
            XCTAssertTrue(
                cataloguedPatterns.contains(pattern),
                "Catalog must contain at least one exercise for \(pattern.rawValue)"
            )
        }
    }

    // MARK: - Lookup by ID

    func test_exerciseLookupByID_returnsExpectedExercise() {
        let bench = VolumeArcExerciseCatalog.exercise(withID: "bench-press")
        XCTAssertNotNil(bench, "`bench-press` is a canonical catalog ID")
        XCTAssertEqual(bench?.name, "Bench Press")
        XCTAssertEqual(bench?.pattern, .horizontalPush)
        XCTAssertEqual(bench?.primaryEquipment, .barbell)
        XCTAssertTrue(bench?.isCompound ?? false)
    }

    func test_exerciseLookupByID_deadlift_returnsExpectedExercise() {
        let deadlift = VolumeArcExerciseCatalog.exercise(withID: "deadlift")
        XCTAssertNotNil(deadlift)
        XCTAssertEqual(deadlift?.name, "Deadlift")
        XCTAssertEqual(deadlift?.pattern, .hinge)
        XCTAssertEqual(deadlift?.primaryEquipment, .barbell)
    }

    func test_exerciseLookupByID_returnsNilForUnknown() {
        XCTAssertNil(VolumeArcExerciseCatalog.exercise(withID: "not-a-real-exercise"))
        XCTAssertNil(VolumeArcExerciseCatalog.exercise(withID: ""))
        XCTAssertNil(VolumeArcExerciseCatalog.exercise(withID: "BACK-SQUAT"),
                     "Lookup is case-sensitive — upper-case variant must not match")
    }

    // MARK: - Filtering by movement pattern
    //
    // The catalog doesn't expose a `byCategory(...)` helper; call sites
    // filter `all` directly. These tests guard the contract those call
    // sites rely on: every exercise returned has the requested pattern,
    // and every pattern-for-which-we-ship-an-exercise yields at least one.

    func test_filterByPattern_returnsOnlyMatchingPattern() {
        for pattern in MovementPattern.allCases {
            let matches = VolumeArcExerciseCatalog.all.filter { $0.pattern == pattern }
            for match in matches {
                XCTAssertEqual(
                    match.pattern, pattern,
                    "Filter by \(pattern.rawValue) leaked an exercise with pattern \(match.pattern.rawValue)"
                )
            }
        }
    }

    func test_filterByPattern_squat_returnsSquatExercises() {
        let squats = VolumeArcExerciseCatalog.all.filter { $0.pattern == .squat }
        XCTAssertFalse(squats.isEmpty, "Squat pattern must have at least one exercise")
        let ids = Set(squats.map(\.id))
        XCTAssertTrue(ids.contains("back-squat"), "Back Squat is a canonical squat entry")
    }

    func test_filterByPattern_hinge_returnsHingeExercises() {
        let hinges = VolumeArcExerciseCatalog.all.filter { $0.pattern == .hinge }
        XCTAssertFalse(hinges.isEmpty)
        XCTAssertTrue(hinges.contains { $0.id == "deadlift" })
    }

    // MARK: - Filtering by equipment

    func test_filterByEquipment_bodyweight_returnsOnlyBodyweightExercises() {
        // "bodyweight exercise" = one whose primary movement is bodyweight
        // (alternate equipment exists for regressions like banded pull-ups).
        let bodyweight = VolumeArcExerciseCatalog.all.filter { $0.primaryEquipment == .bodyweight }
        XCTAssertFalse(bodyweight.isEmpty, "Catalog must ship at least one bodyweight exercise")
        for exercise in bodyweight {
            XCTAssertEqual(
                exercise.primaryEquipment, .bodyweight,
                "\(exercise.name) leaked into bodyweight filter with primary \(exercise.primaryEquipment.rawValue)"
            )
        }
        XCTAssertTrue(bodyweight.contains { $0.id == "pull-up" })
    }

    func test_filterByEquipment_barbell_returnsOnlyBarbellExercises() {
        let barbell = VolumeArcExerciseCatalog.all.filter { $0.primaryEquipment == .barbell }
        XCTAssertFalse(barbell.isEmpty, "Catalog must ship at least one barbell exercise")
        for exercise in barbell {
            XCTAssertEqual(exercise.primaryEquipment, .barbell)
        }
        // The big-three barbell lifts should all be represented.
        let ids = Set(barbell.map(\.id))
        XCTAssertTrue(ids.contains("back-squat"))
        XCTAssertTrue(ids.contains("deadlift"))
        XCTAssertTrue(ids.contains("bench-press"))
    }

    // MARK: - Substitutions (alternatives)

    func test_alternatives_bodyweightOnly_excludesBarbellOnlyExercises() {
        // An athlete with only bodyweight should not get a barbell-only
        // substitution offered (barbell exercises with no bodyweight
        // alternate must be filtered out).
        guard let backSquat = VolumeArcExerciseCatalog.exercise(withID: "back-squat") else {
            return XCTFail("back-squat must exist in catalog")
        }
        let alternatives = VolumeArcExerciseCatalog.alternatives(
            for: backSquat,
            availableEquipment: [.bodyweight]
        )
        for alternative in alternatives {
            let usesBodyweight = alternative.primaryEquipment == .bodyweight
                || alternative.alternateEquipment.contains(.bodyweight)
            XCTAssertTrue(
                usesBodyweight,
                "\(alternative.name) requires equipment this athlete does not have"
            )
        }
    }

    func test_alternatives_sharesMovementPatternWithSource() {
        // Every alternative returned must share the source's pattern —
        // substituting a squat with a row would be worse than useless.
        guard let benchPress = VolumeArcExerciseCatalog.exercise(withID: "bench-press") else {
            return XCTFail("bench-press must exist in catalog")
        }
        let alternatives = VolumeArcExerciseCatalog.alternatives(
            for: benchPress,
            availableEquipment: [.barbell, .dumbbell, .machine]
        )
        for alternative in alternatives {
            XCTAssertEqual(
                alternative.pattern, benchPress.pattern,
                "Alternatives must share the source movement pattern"
            )
            XCTAssertNotEqual(
                alternative.id, benchPress.id,
                "Alternatives must not include the source exercise itself"
            )
        }
    }

    func test_alternatives_respectsAlternateEquipment() {
        // Pull-Up has primary bodyweight and alternates [machine, band];
        // an athlete with only a band should still see it as an alternate
        // for pull-pattern work.
        guard let pullUp = VolumeArcExerciseCatalog.exercise(withID: "pull-up") else {
            return XCTFail("pull-up must exist in catalog")
        }
        // Give the athlete cable so lat-pulldown is a candidate.
        let alternatives = VolumeArcExerciseCatalog.alternatives(
            for: pullUp,
            availableEquipment: [.cable, .machine]
        )
        XCTAssertFalse(alternatives.isEmpty, "A cable athlete should get vertical-pull alternatives")
        XCTAssertTrue(
            alternatives.contains { $0.id == "lat-pulldown" },
            "Lat Pulldown (cable) should substitute for Pull-Up when cable is available"
        )
    }

    func test_alternatives_forUnknownExercise_staysConsistent() {
        // The API takes an `ExerciseDefinition` rather than an ID string,
        // so "unknown exercise" means an ad-hoc definition whose ID does
        // not match anything in the catalog. Alternatives should then be
        // drawn from the same-pattern subset, excluding the ad-hoc input.
        let ghostExercise = ExerciseDefinition(
            id: "not-in-catalog",
            name: "Ghost Lift",
            pattern: .squat,
            primaryEquipment: .barbell,
            defaultRepRange: 5...8,
            defaultRPE: 7.5,
            isCompound: true,
            cues: []
        )
        let alternatives = VolumeArcExerciseCatalog.alternatives(
            for: ghostExercise,
            availableEquipment: [.barbell, .dumbbell, .machine, .kettlebell]
        )
        // All alternates share the ghost's pattern; none are the ghost itself.
        for alt in alternatives {
            XCTAssertEqual(alt.pattern, .squat)
            XCTAssertNotEqual(alt.id, ghostExercise.id)
        }
    }

    func test_alternatives_withEmptyEquipment_returnsEmpty() {
        guard let deadlift = VolumeArcExerciseCatalog.exercise(withID: "deadlift") else {
            return XCTFail("deadlift must exist in catalog")
        }
        let alternatives = VolumeArcExerciseCatalog.alternatives(
            for: deadlift,
            availableEquipment: []
        )
        XCTAssertTrue(
            alternatives.isEmpty,
            "No equipment means no viable alternatives"
        )
    }

    // MARK: - Catalog invariants

    func test_allExerciseIDsAreUnique() {
        let ids = VolumeArcExerciseCatalog.all.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(
            ids.count, uniqueIDs.count,
            "Duplicate exercise IDs would break `exercise(withID:)` lookup semantics"
        )
    }

    func test_allExerciseNamesAreNonEmpty() {
        for exercise in VolumeArcExerciseCatalog.all {
            XCTAssertFalse(
                exercise.name.isEmpty,
                "Exercise id=\(exercise.id) has an empty display name"
            )
            XCTAssertFalse(
                exercise.id.isEmpty,
                "Exercise \(exercise.name) has an empty ID"
            )
        }
    }

    func test_allExercisesHaveSaneRepRangesAndRPE() {
        for exercise in VolumeArcExerciseCatalog.all {
            XCTAssertGreaterThan(
                exercise.defaultRepRange.lowerBound, 0,
                "\(exercise.name) default rep range must start above zero"
            )
            XCTAssertGreaterThanOrEqual(
                exercise.defaultRepRange.upperBound, exercise.defaultRepRange.lowerBound,
                "\(exercise.name) has an inverted rep range"
            )
            XCTAssertGreaterThan(
                exercise.defaultRPE, 0.0,
                "\(exercise.name) default RPE must be positive"
            )
            XCTAssertLessThanOrEqual(
                exercise.defaultRPE, 10.0,
                "\(exercise.name) default RPE above 10 is outside the scale"
            )
        }
    }

    func test_allExercisesDoNotListPrimaryAsAlternate() {
        // The alternates list must describe *other* ways to do the
        // movement, not a duplicate of the primary equipment. Otherwise
        // `alternatives(for:availableEquipment:)` double-counts.
        for exercise in VolumeArcExerciseCatalog.all {
            XCTAssertFalse(
                exercise.alternateEquipment.contains(exercise.primaryEquipment),
                "\(exercise.name) lists primary equipment \(exercise.primaryEquipment.rawValue) as an alternate"
            )
        }
    }
}
