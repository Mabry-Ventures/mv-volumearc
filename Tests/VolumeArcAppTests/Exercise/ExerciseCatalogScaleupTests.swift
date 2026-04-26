import XCTest
import VolumeArcCore

/// VOL-105 — coverage for the schema extension and the scaled-up
/// catalog on top of `ExerciseCatalogTests`. The legacy file keeps
/// asserting the original 11-entry contract; this file owns the new
/// invariants (>= 120 entries, every entry has muscle assignments,
/// the auto-derived `HKActivityTypeMapping` matches the spec, the
/// `DifficultyTier` ordering holds, the alternatives lookup works on
/// the larger set, etc.).
final class ExerciseCatalogScaleupTests: XCTestCase {

    // MARK: - Catalog size + uniqueness

    func test_catalog_hasAtLeast120Entries() {
        // Lower bound — adding entries above this floor doesn't churn
        // the test, but a regression that guts the catalog still fails
        // loudly. Phase 1 ships 130+; tightening the floor is a future
        // ticket (Phase 2's image-gen pipeline depends on a stable ID
        // set, so the count stops moving once Phase 2 starts).
        XCTAssertGreaterThanOrEqual(
            VolumeArcExerciseCatalog.all.count, 120,
            "VOL-105 Phase 1 ships 120+ entries; catalog dropped below the floor."
        )
    }

    func test_allExerciseIDsRemainUnique_atScaledUpSize() {
        // Belt-and-suspenders: the original test_allExerciseIDsAreUnique
        // already covers this, but at 130+ entries hand-typed strings
        // are easier to collide with. Re-asserting here keeps the new
        // invariant local to the VOL-105 surface.
        let ids = VolumeArcExerciseCatalog.all.map(\.id)
        XCTAssertEqual(
            ids.count, Set(ids).count,
            "Duplicate exercise ID would silently shadow lookups via exercise(withID:)"
        )
    }

    // MARK: - Schema extension invariants

    func test_everyEntry_declaresAtLeastOnePrimaryMuscle() {
        for exercise in VolumeArcExerciseCatalog.all {
            XCTAssertFalse(
                exercise.primaryMuscles.isEmpty,
                "\(exercise.name) (\(exercise.id)) ships with no primary muscle group; every entry must declare one"
            )
        }
    }

    func test_secondaryMusclesNeverDuplicatePrimary() {
        for exercise in VolumeArcExerciseCatalog.all {
            let primary = Set(exercise.primaryMuscles)
            let secondary = Set(exercise.secondaryMuscles)
            XCTAssertTrue(
                primary.isDisjoint(with: secondary),
                "\(exercise.name) lists \(primary.intersection(secondary)) as both primary and secondary"
            )
        }
    }

    func test_unilateralFlagOnlyTrueForKnownUnilateralPatterns() {
        // Sanity-check the unilateral marking against a hand-curated
        // ID list that should be flagged. Anything missing here that
        // claims unilateral is fine — it's a strict subset assertion —
        // but anything in this list that *isn't* flagged means we
        // dropped the bit on a known single-side movement.
        let knownUnilateralIDs: Set<String> = [
            "bulgarian-split-squat",
            "single-leg-rdl",
            "single-leg-hip-thrust",
            "b-stance-hip-thrust",
            "single-arm-db-row",
            "leaning-cable-lateral-raise",
            "suitcase-carry",
            "step-up",
            "pallof-press",
            "wood-chop",
            "single-arm-lat-pulldown",
        ]
        for id in knownUnilateralIDs {
            guard let exercise = VolumeArcExerciseCatalog.exercise(withID: id) else {
                return XCTFail("\(id) missing from catalog — VOL-105 hand-list lookup")
            }
            XCTAssertTrue(
                exercise.unilateral,
                "\(id) should be flagged unilateral"
            )
        }
    }

    func test_lengthenedPositionEmphasis_setForKnownStretchBiasMovements() {
        // Locked product decision: VOL-105 hand-curates ~15 entries as
        // stretch-bias. Spot-check that the ones the comment thread
        // called out are flagged.
        let knownStretchBiasIDs: Set<String> = [
            "deficit-deadlift",
            "stiff-leg-deadlift",
            "nordic-ham-curl",
            "leaning-cable-lateral-raise",
            "incline-db-curl",
            "preacher-curl",
            "overhead-tricep-extension",
            "skullcrusher",
            "machine-pec-deck",
            "incline-db-press",
            "pendulum-squat",
            "dumbbell-pullover",
            "pjr-pullover",
        ]
        for id in knownStretchBiasIDs {
            guard let exercise = VolumeArcExerciseCatalog.exercise(withID: id) else {
                return XCTFail("\(id) missing from catalog — stretch-bias contract")
            }
            XCTAssertTrue(
                exercise.lengthenedPositionEmphasis,
                "\(id) should be flagged lengthenedPositionEmphasis (per VOL-105 stretch-bias list)"
            )
        }
    }

    // MARK: - DifficultyTier ordering

    func test_difficultyTier_isComparableLowToHigh() {
        XCTAssertLessThan(DifficultyTier.beginner, DifficultyTier.intermediate)
        XCTAssertLessThan(DifficultyTier.intermediate, DifficultyTier.advanced)
        XCTAssertLessThan(DifficultyTier.beginner, DifficultyTier.advanced)
        XCTAssertGreaterThan(DifficultyTier.advanced, DifficultyTier.beginner)
        XCTAssertEqual(DifficultyTier.beginner, DifficultyTier.beginner)
    }

    // MARK: - HKActivityTypeMapping default rules

    func test_defaultHKType_coreReturnsCore() {
        XCTAssertEqual(
            ExerciseDefinition.defaultHKType(pattern: .core, primaryEquipment: .bodyweight),
            .core
        )
        XCTAssertEqual(
            ExerciseDefinition.defaultHKType(pattern: .core, primaryEquipment: .cable),
            .core,
            "Core pattern wins over equipment — cable crunches are still core"
        )
    }

    func test_defaultHKType_conditioningAndMobilityReturnFunctional() {
        XCTAssertEqual(
            ExerciseDefinition.defaultHKType(pattern: .conditioning, primaryEquipment: .bodyweight),
            .functional
        )
        XCTAssertEqual(
            ExerciseDefinition.defaultHKType(pattern: .mobility, primaryEquipment: .dumbbell),
            .functional
        )
    }

    func test_defaultHKType_loadedEquipmentMapsToTraditional() {
        // The four "loaded plate-and-pin" implements all map to
        // traditional regardless of pattern (excluding core /
        // conditioning / mobility, which are caught by the earlier
        // branches).
        let loaded: [Equipment] = [.barbell, .dumbbell, .machine, .cable]
        let neutralPatterns: [MovementPattern] = [
            .squat, .hinge, .horizontalPush, .verticalPush,
            .horizontalPull, .verticalPull, .lunge, .isolation, .carry,
        ]
        for pattern in neutralPatterns {
            for equipment in loaded {
                XCTAssertEqual(
                    ExerciseDefinition.defaultHKType(pattern: pattern, primaryEquipment: equipment),
                    .traditional,
                    "\(pattern.rawValue) + \(equipment.rawValue) should map to .traditional"
                )
            }
        }
    }

    func test_defaultHKType_unloadedEquipmentMapsToFunctional() {
        // The three "unloaded/rotational" implements default to
        // functional for non-core patterns. Bodyweight pull-ups,
        // kettlebell swings, banded rows all bucket the same way in
        // Apple's Fitness analytics.
        let unloaded: [Equipment] = [.bodyweight, .kettlebell, .band]
        let neutralPatterns: [MovementPattern] = [
            .squat, .hinge, .horizontalPush, .verticalPush,
            .horizontalPull, .verticalPull, .lunge, .isolation, .carry,
        ]
        for pattern in neutralPatterns {
            for equipment in unloaded {
                XCTAssertEqual(
                    ExerciseDefinition.defaultHKType(pattern: pattern, primaryEquipment: equipment),
                    .functional,
                    "\(pattern.rawValue) + \(equipment.rawValue) should map to .functional"
                )
            }
        }
    }

    func test_initWithoutHKOverride_resolvesToAutoDerivedValue() {
        // The init's `healthKitActivityType: HKActivityTypeMapping? = nil`
        // contract: nil resolves to the static `defaultHKType` value.
        // Catalog entries declared without an explicit override must
        // round-trip the auto-derive logic.
        let bench = VolumeArcExerciseCatalog.benchPress
        XCTAssertEqual(bench.healthKitActivityType, .traditional)

        let pullUp = VolumeArcExerciseCatalog.pullUp
        XCTAssertEqual(pullUp.healthKitActivityType, .functional)

        let plank = VolumeArcExerciseCatalog.plank
        XCTAssertEqual(plank.healthKitActivityType, .core)
    }

    func test_initWithExplicitHKOverride_keepsCallerProvidedValue() {
        // The override path: pass an explicit value and the auto-derive
        // result is ignored. Verifies the conditional resolution in
        // `init` doesn't accidentally clobber overrides.
        let custom = ExerciseDefinition(
            id: "custom-test",
            name: "Custom",
            pattern: .squat,
            primaryEquipment: .barbell,
            defaultRepRange: 5...8,
            defaultRPE: 7.5,
            isCompound: true,
            cues: ["Test."],
            healthKitActivityType: .core
        )
        XCTAssertEqual(
            custom.healthKitActivityType, .core,
            "Auto-derive should defer to caller-provided HK type override"
        )
    }

    // MARK: - Alternatives on the larger set

    func test_alternatives_findsMultipleSquatPatternMatches() {
        guard let backSquat = VolumeArcExerciseCatalog.exercise(withID: "back-squat") else {
            return XCTFail("back-squat must exist")
        }
        let alts = VolumeArcExerciseCatalog.alternatives(
            for: backSquat,
            availableEquipment: [.barbell, .dumbbell, .machine, .bodyweight, .kettlebell]
        )
        // Pre-VOL-105 the catalog had two squat alternates (front + goblet).
        // VOL-105 ships a dozen+ — the larger set must surface at least
        // five distinct alternates given a broad equipment set.
        XCTAssertGreaterThanOrEqual(
            alts.count, 5,
            "Scaled-up catalog must offer multiple squat alternates with broad equipment"
        )
        for alt in alts {
            XCTAssertEqual(alt.pattern, .squat, "Alternates must share the source pattern")
            XCTAssertNotEqual(alt.id, backSquat.id, "Alternates must exclude the source")
        }
    }

    func test_alternatives_includesNewLungePatternEntries() {
        // Lunge pattern was added in VOL-105 — verify the new pattern
        // surfaces alternates within itself.
        guard let walking = VolumeArcExerciseCatalog.exercise(withID: "walking-lunge") else {
            return XCTFail("walking-lunge must exist")
        }
        let alts = VolumeArcExerciseCatalog.alternatives(
            for: walking,
            availableEquipment: [.dumbbell, .barbell, .bodyweight]
        )
        let altIDs = Set(alts.map(\.id))
        XCTAssertTrue(
            altIDs.contains("reverse-lunge"),
            "Reverse Lunge should be a viable alternate for Walking Lunge"
        )
    }

    func test_aliasField_carriesShorthandForCommonLifts() {
        // Spot-check the alias surface on movements with well-known
        // shorthand. Picker UI search will eventually hit this field;
        // unit-pinning the populated subset keeps regressions from
        // silently emptying the field.
        XCTAssertEqual(
            VolumeArcExerciseCatalog.exercise(withID: "romanian-deadlift")?.aliases,
            ["RDL"]
        )
        XCTAssertEqual(
            VolumeArcExerciseCatalog.exercise(withID: "bulgarian-split-squat")?.aliases,
            ["BSS", "Split Squat"]
        )
    }

    // MARK: - Programming invariants for the new entries

    func test_everyAdvancedEntry_hasHigherDefaultRPE() {
        // Soft assertion that advanced movements aren't accidentally
        // declared with beginner-grade defaults (RPE < 7.0). The
        // intent is "advanced movements demand intent" — if a future
        // entry slips in at RPE 6.5 we want the test to flag it for
        // review, not silently ship.
        for exercise in VolumeArcExerciseCatalog.all where exercise.difficulty == .advanced {
            XCTAssertGreaterThanOrEqual(
                exercise.defaultRPE, 7.0,
                "\(exercise.name) is .advanced but ships defaultRPE \(exercise.defaultRPE) — under-specified intensity"
            )
        }
    }

    func test_everyEntryReachableViaExerciseLookup() {
        // `all` is a static array; `exercise(withID:)` is the public
        // surface most callers use. Round-trip every entry through the
        // lookup to make sure the array and the lookup stay in sync.
        for exercise in VolumeArcExerciseCatalog.all {
            XCTAssertEqual(
                VolumeArcExerciseCatalog.exercise(withID: exercise.id)?.id,
                exercise.id,
                "exercise(withID:) failed to round-trip \(exercise.id)"
            )
        }
    }

    func test_persistenceSurface_exerciseIDsAreCSVSafe() {
        // `WorkoutRecord.exerciseIDsCSV` joins exercise IDs with `,`.
        // Any ID containing a comma would corrupt the round trip. Same
        // pre-existing constraint for the original 11; re-asserting
        // here for the new entries.
        for exercise in VolumeArcExerciseCatalog.all {
            XCTAssertFalse(
                exercise.id.contains(","),
                "\(exercise.id) contains a comma — would corrupt exerciseIDsCSV round-trip"
            )
            XCTAssertFalse(
                exercise.id.contains(" "),
                "\(exercise.id) contains whitespace — kebab-case convention violated"
            )
        }
    }
}
