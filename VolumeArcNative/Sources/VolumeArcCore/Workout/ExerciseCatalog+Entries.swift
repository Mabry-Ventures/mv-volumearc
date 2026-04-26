import Foundation

// VOL-105 Phase 1 — exercise catalog scale-up 11 → 120+.
//
// Sources for the additive entries:
//
// - The original 11 (back squat, front squat, goblet squat, deadlift,
//   romanian deadlift, bench press, db bench press, overhead press,
//   barbell row, pull-up, lat pulldown) are preserved with backfilled
//   `primaryMuscles` / `secondaryMuscles` / `difficulty`. Their IDs
//   stay the same so persisted `WorkoutRecord.exerciseIDsCSV` rows
//   continue to round-trip.
//
// - ~95 entries derived from the taxonomy/name list in
//   github.com/yuhonas/free-exercise-db (license: The Unlicense — public
//   domain dedication). Names and equipment categorization are taken
//   from that dataset; cues, aliases, and muscle-group splits are
//   author-original. The upstream `instructions` field is *not* used —
//   it's verbose and includes anatomically dated copy.
//
// - ~25 hand-authored modern-evidence movements per the locked
//   product decisions on Linear VOL-105 (Bulgarian split squats, pec
//   deck, leaning lateral raise, single-leg hip thrust, Nordic, Pendlay,
//   Meadows, seal row, PJR pullover, tibialis raise, paused/pin
//   variants, etc.).
//
// Author cues match the existing voice ("Pull the slack out before you
// break the floor.") — short, action-oriented, no jargon hedging.
//
// Hard constraints:
//
// - No image bundling. Per-exercise illustrations land in Phase 2 via a
//   separate Codex CLI image-generation pass that lives in its own PR.
// - File-length is intentionally allowed to exceed `ExerciseCatalog.swift`
//   because this is pure data; the helpers + struct stay in the parent
//   file.

// swiftlint:disable file_length

public extension VolumeArcExerciseCatalog {

    // MARK: - Squat pattern (existing 11 + VOL-105 additions)

    static let backSquat = ExerciseDefinition(
        id: "back-squat",
        name: "Back Squat",
        pattern: .squat,
        primaryEquipment: .barbell,
        alternateEquipment: [.machine],
        defaultRepRange: 5...8,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Brace hard, break at the hips first.",
            "Knees track over toes the whole way down.",
            "Drive the floor away on the way up.",
        ],
        aliases: ["BSQ"],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings, .lowerBack, .abs, .adductors],
        difficulty: .intermediate
    )

    static let frontSquat = ExerciseDefinition(
        id: "front-squat",
        name: "Front Squat",
        pattern: .squat,
        primaryEquipment: .barbell,
        defaultRepRange: 5...8,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Elbows high, chest proud.",
            "Stay upright — this is a vertical torso lift.",
        ],
        aliases: ["FSQ"],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.abs, .upperChest, .lowerBack],
        difficulty: .intermediate
    )

    static let gobletSquat = ExerciseDefinition(
        id: "goblet-squat",
        name: "Goblet Squat",
        pattern: .squat,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.kettlebell],
        defaultRepRange: 8...12,
        defaultRPE: 7.0,
        isCompound: true,
        cues: ["Drive your elbows inside your knees at the bottom."],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.abs, .upperChest, .adductors],
        difficulty: .beginner
    )

    static let lowBarSquat = ExerciseDefinition(
        id: "low-bar-squat",
        name: "Low-Bar Back Squat",
        pattern: .squat,
        primaryEquipment: .barbell,
        defaultRepRange: 3...6,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Bar sits on your rear delts, not your traps.",
            "Sit back into the hips before the knees bend.",
        ],
        primaryMuscles: [.glutes, .hamstrings, .quads],
        secondaryMuscles: [.lowerBack, .adductors, .abs],
        difficulty: .advanced
    )

    static let highBarSquat = ExerciseDefinition(
        id: "high-bar-squat",
        name: "High-Bar Back Squat",
        pattern: .squat,
        primaryEquipment: .barbell,
        defaultRepRange: 5...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Bar sits on the traps, torso stays vertical.",
            "Drive knees forward, ride the quads to depth.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.adductors, .abs, .lowerBack],
        difficulty: .intermediate
    )

    static let zercherSquat = ExerciseDefinition(
        id: "zercher-squat",
        name: "Zercher Squat",
        pattern: .squat,
        primaryEquipment: .barbell,
        defaultRepRange: 5...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Lock the bar in the crook of your elbows.",
            "Stay tall — this is brutal trunk work.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.abs, .upperChest, .biceps, .lowerBack],
        difficulty: .advanced
    )

    static let boxSquat = ExerciseDefinition(
        id: "box-squat",
        name: "Box Squat",
        pattern: .squat,
        primaryEquipment: .barbell,
        defaultRepRange: 3...6,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Sit back to the box — don't drop straight down.",
            "Settle, then explode off the box.",
        ],
        primaryMuscles: [.glutes, .quads],
        secondaryMuscles: [.hamstrings, .lowerBack, .abs],
        difficulty: .intermediate
    )

    static let pausedBackSquat = ExerciseDefinition(
        id: "paused-back-squat",
        name: "Paused Back Squat",
        pattern: .squat,
        primaryEquipment: .barbell,
        defaultRepRange: 3...6,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Hold the hole for a full two-count.",
            "No bouncing — drive out cold.",
        ],
        aliases: ["Pause Squat"],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.lowerBack, .abs, .adductors],
        difficulty: .advanced,
        lengthenedPositionEmphasis: true
    )

    static let pinSquat = ExerciseDefinition(
        id: "pin-squat",
        name: "Pin Squat",
        pattern: .squat,
        primaryEquipment: .barbell,
        defaultRepRange: 3...6,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Sit the bar on the pins — kill all the stretch reflex.",
            "Brace, then explode from a dead stop.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.lowerBack, .abs, .adductors],
        difficulty: .advanced
    )

    static let smithSquat = ExerciseDefinition(
        id: "smith-squat",
        name: "Smith Machine Squat",
        pattern: .squat,
        primaryEquipment: .machine,
        defaultRepRange: 6...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Walk your feet forward to bias the quads.",
            "Push the bar straight up the rails.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.adductors, .hamstrings],
        difficulty: .beginner
    )

    static let pendulumSquat = ExerciseDefinition(
        id: "pendulum-squat",
        name: "Pendulum Squat",
        pattern: .squat,
        primaryEquipment: .machine,
        defaultRepRange: 8...12,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Push your knees over your toes — this is full quad stretch.",
            "Pause one heartbeat at the bottom, then drive.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.adductors, .hamstrings],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let beltSquat = ExerciseDefinition(
        id: "belt-squat",
        name: "Belt Squat",
        pattern: .squat,
        primaryEquipment: .machine,
        defaultRepRange: 8...15,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Belt loaded — your spine gets a free pass today.",
            "Stand tall, drive through midfoot.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.adductors, .hamstrings],
        difficulty: .beginner
    )

    static let hackSquat = ExerciseDefinition(
        id: "hack-squat",
        name: "Hack Squat",
        pattern: .squat,
        primaryEquipment: .machine,
        defaultRepRange: 8...12,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Feet low and narrow — quads do the work.",
            "Full ROM beats heavy half-reps every time.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.adductors, .hamstrings],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let machineHackSquat = ExerciseDefinition(
        id: "machine-hack-squat",
        name: "Plate-Loaded Hack Squat",
        pattern: .squat,
        primaryEquipment: .machine,
        defaultRepRange: 8...12,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Heels down the whole rep.",
            "Bottom out — that's where the growth lives.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.adductors],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let legPress = ExerciseDefinition(
        id: "leg-press",
        name: "Leg Press",
        pattern: .squat,
        primaryEquipment: .machine,
        defaultRepRange: 8...15,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Knees track over toes — don't let them cave.",
            "Stop just shy of locking out at the top.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.adductors, .hamstrings],
        difficulty: .beginner
    )

    static let sissySquat = ExerciseDefinition(
        id: "sissy-squat",
        name: "Sissy Squat",
        pattern: .squat,
        primaryEquipment: .bodyweight,
        alternateEquipment: [.machine],
        defaultRepRange: 8...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Drive your knees forward, lean back as a counterbalance.",
            "Pure quad burn — keep the hips locked.",
        ],
        primaryMuscles: [.quads],
        secondaryMuscles: [.abs],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let bulgarianSplitSquat = ExerciseDefinition(
        id: "bulgarian-split-squat",
        name: "Bulgarian Split Squat",
        pattern: .squat,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.barbell, .bodyweight],
        defaultRepRange: 8...12,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Front foot far enough out that your shin stays vertical.",
            "Lower under control — let the rear leg follow, not lead.",
        ],
        aliases: ["BSS", "Split Squat"],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings, .adductors, .abs],
        difficulty: .intermediate,
        unilateral: true,
        lengthenedPositionEmphasis: true
    )

    static let stepUp = ExerciseDefinition(
        id: "step-up",
        name: "Step-Up",
        pattern: .squat,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.barbell, .bodyweight, .kettlebell],
        defaultRepRange: 8...12,
        defaultRPE: 7.0,
        isCompound: true,
        cues: [
            "Drive through the heel of the working leg.",
            "No push-off from the bottom foot — let the top leg do everything.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings, .abs],
        difficulty: .beginner,
        unilateral: true
    )

    // MARK: - Hinge pattern (existing 2 + VOL-105 additions)

    static let deadlift = ExerciseDefinition(
        id: "deadlift",
        name: "Deadlift",
        pattern: .hinge,
        primaryEquipment: .barbell,
        defaultRepRange: 3...5,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Wedge yourself under the bar — create full-body tension.",
            "Pull the slack out before you break the floor.",
            "Push the earth away, don't yank the bar.",
        ],
        aliases: ["DL", "Conventional Deadlift"],
        primaryMuscles: [.glutes, .hamstrings, .lowerBack],
        secondaryMuscles: [.quads, .traps, .lats, .forearms, .abs],
        difficulty: .advanced
    )

    static let romanianDeadlift = ExerciseDefinition(
        id: "romanian-deadlift",
        name: "Romanian Deadlift",
        pattern: .hinge,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell],
        defaultRepRange: 6...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: ["Push your hips back, feel the stretch in the hamstrings."],
        aliases: ["RDL"],
        primaryMuscles: [.hamstrings, .glutes],
        secondaryMuscles: [.lowerBack, .lats, .forearms],
        difficulty: .intermediate
    )

    static let sumoDeadlift = ExerciseDefinition(
        id: "sumo-deadlift",
        name: "Sumo Deadlift",
        pattern: .hinge,
        primaryEquipment: .barbell,
        defaultRepRange: 3...6,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Knees out hard, hips drop in.",
            "Pull the slack, then push the floor away.",
        ],
        aliases: ["Sumo DL"],
        primaryMuscles: [.glutes, .quads, .hamstrings],
        secondaryMuscles: [.adductors, .traps, .forearms, .abs],
        difficulty: .advanced
    )

    static let trapBarDeadlift = ExerciseDefinition(
        id: "trap-bar-deadlift",
        name: "Trap-Bar Deadlift",
        pattern: .hinge,
        primaryEquipment: .barbell,
        defaultRepRange: 5...8,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Stand tall through the handles, no rounding.",
            "Drive up like a mid-thigh squat.",
        ],
        aliases: ["Trap Bar", "Hex Bar Deadlift"],
        primaryMuscles: [.glutes, .quads, .hamstrings],
        secondaryMuscles: [.lowerBack, .traps, .forearms, .abs],
        difficulty: .intermediate
    )

    static let deficitDeadlift = ExerciseDefinition(
        id: "deficit-deadlift",
        name: "Deficit Deadlift",
        pattern: .hinge,
        primaryEquipment: .barbell,
        defaultRepRange: 3...6,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Stand on a 1-2 inch plate — extra range, extra stretch.",
            "Don't sag your hips — break the floor at the same angle.",
        ],
        primaryMuscles: [.glutes, .hamstrings, .quads],
        secondaryMuscles: [.lowerBack, .traps, .forearms],
        difficulty: .advanced,
        lengthenedPositionEmphasis: true
    )

    static let blockPulls = ExerciseDefinition(
        id: "block-pulls",
        name: "Block Pulls",
        pattern: .hinge,
        primaryEquipment: .barbell,
        defaultRepRange: 3...6,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Bar above the knee — overload the lockout.",
            "Same setup as a full pull, just with less range.",
        ],
        aliases: ["Rack Pull"],
        primaryMuscles: [.glutes, .lowerBack, .traps],
        secondaryMuscles: [.hamstrings, .lats, .forearms],
        difficulty: .intermediate
    )

    static let pausedDeadlift = ExerciseDefinition(
        id: "paused-deadlift",
        name: "Paused Deadlift",
        pattern: .hinge,
        primaryEquipment: .barbell,
        defaultRepRange: 3...5,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Pause one second below the knee on the way up.",
            "Hold position — don't drift forward.",
        ],
        primaryMuscles: [.glutes, .hamstrings, .lowerBack],
        secondaryMuscles: [.lats, .traps, .forearms],
        difficulty: .advanced
    )

    static let stiffLegDeadlift = ExerciseDefinition(
        id: "stiff-leg-deadlift",
        name: "Stiff-Leg Deadlift",
        pattern: .hinge,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell],
        defaultRepRange: 6...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Knees nearly locked — push the hips way back.",
            "Stop when your hamstrings tap out, not when your back rounds.",
        ],
        aliases: ["SLDL"],
        primaryMuscles: [.hamstrings, .glutes],
        secondaryMuscles: [.lowerBack],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let singleLegRDL = ExerciseDefinition(
        id: "single-leg-rdl",
        name: "Single-Leg RDL",
        pattern: .hinge,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.kettlebell, .bodyweight],
        defaultRepRange: 6...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Hips square — don't open up to the side.",
            "Reach the dumbbell down the standing leg, not toward the floor.",
        ],
        aliases: ["SLRDL"],
        primaryMuscles: [.hamstrings, .glutes],
        secondaryMuscles: [.lowerBack, .abs, .adductors],
        difficulty: .intermediate,
        unilateral: true
    )

    static let dumbbellRDL = ExerciseDefinition(
        id: "db-rdl",
        name: "Dumbbell Romanian Deadlift",
        pattern: .hinge,
        primaryEquipment: .dumbbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Dumbbells brush the thighs the whole way down.",
            "Hips back, not knees back.",
        ],
        aliases: ["DB RDL"],
        primaryMuscles: [.hamstrings, .glutes],
        secondaryMuscles: [.lowerBack, .forearms],
        difficulty: .beginner
    )

    static let kettlebellSwing = ExerciseDefinition(
        id: "kettlebell-swing",
        name: "Kettlebell Swing",
        pattern: .hinge,
        primaryEquipment: .kettlebell,
        defaultRepRange: 12...20,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Snap the hips — the bell is along for the ride.",
            "Bell breast height max, not overhead.",
        ],
        aliases: ["KB Swing"],
        primaryMuscles: [.glutes, .hamstrings],
        secondaryMuscles: [.lowerBack, .abs, .lats, .forearms],
        difficulty: .intermediate
    )

    static let backExtension45 = ExerciseDefinition(
        id: "back-extension-45",
        name: "45° Back Extension",
        pattern: .hinge,
        primaryEquipment: .machine,
        alternateEquipment: [.bodyweight],
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Round and unround the spine — that's the point of this lift.",
            "Squeeze the glutes hard at the top.",
        ],
        aliases: ["Back Ext", "45 Degree Hyper"],
        primaryMuscles: [.glutes, .hamstrings, .lowerBack],
        secondaryMuscles: [],
        difficulty: .beginner
    )

    static let ghdBackExtension = ExerciseDefinition(
        id: "ghd-back-extension",
        name: "GHD Back Extension",
        pattern: .hinge,
        primaryEquipment: .machine,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Hinge at the hips, not the lower back.",
            "Pause when your torso lines up with your legs.",
        ],
        primaryMuscles: [.hamstrings, .glutes, .lowerBack],
        secondaryMuscles: [],
        difficulty: .intermediate
    )

    static let goodMorning = ExerciseDefinition(
        id: "good-morning",
        name: "Good Morning",
        pattern: .hinge,
        primaryEquipment: .barbell,
        defaultRepRange: 6...10,
        defaultRPE: 7.0,
        isCompound: true,
        cues: [
            "Soft knees, hips back, not down.",
            "Stop when your hamstrings cap out — don't chase the floor.",
        ],
        primaryMuscles: [.hamstrings, .glutes, .lowerBack],
        secondaryMuscles: [.abs],
        difficulty: .intermediate
    )

    static let barbellHipThrust = ExerciseDefinition(
        id: "barbell-hip-thrust",
        name: "Barbell Hip Thrust",
        pattern: .hinge,
        primaryEquipment: .barbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Tuck the chin, ribs down — flat spine all the way.",
            "Squeeze the glutes hard at the top.",
        ],
        aliases: ["Hip Thrust"],
        primaryMuscles: [.glutes],
        secondaryMuscles: [.hamstrings, .abs, .quads],
        difficulty: .intermediate
    )

    static let singleLegHipThrust = ExerciseDefinition(
        id: "single-leg-hip-thrust",
        name: "Single-Leg Hip Thrust",
        pattern: .hinge,
        primaryEquipment: .bodyweight,
        alternateEquipment: [.dumbbell, .barbell],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Working leg drives — the other knee tucks in.",
            "Hips stay level — don't let one drop.",
        ],
        primaryMuscles: [.glutes],
        secondaryMuscles: [.hamstrings, .abs],
        difficulty: .intermediate,
        unilateral: true
    )

    static let bStanceHipThrust = ExerciseDefinition(
        id: "b-stance-hip-thrust",
        name: "B-Stance Hip Thrust",
        pattern: .hinge,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Working foot flat — supporting foot on the heel only.",
            "Almost a single-leg, but easier to load progressively.",
        ],
        primaryMuscles: [.glutes],
        secondaryMuscles: [.hamstrings, .abs],
        difficulty: .intermediate,
        unilateral: true
    )

    static let machineHipThrust = ExerciseDefinition(
        id: "machine-hip-thrust",
        name: "Machine Hip Thrust",
        pattern: .hinge,
        primaryEquipment: .machine,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Drive through the heels.",
            "Let the machine handle the path — you handle the squeeze.",
        ],
        primaryMuscles: [.glutes],
        secondaryMuscles: [.hamstrings],
        difficulty: .beginner
    )

    static let machineGluteKickback = ExerciseDefinition(
        id: "machine-glute-kickback",
        name: "Machine Glute Kickback",
        pattern: .hinge,
        primaryEquipment: .machine,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Hinge from the hip, not the lower back.",
            "Squeeze hard at full extension.",
        ],
        primaryMuscles: [.glutes],
        secondaryMuscles: [.hamstrings],
        difficulty: .beginner,
        unilateral: true
    )

    static let cableGluteKickback = ExerciseDefinition(
        id: "cable-glute-kickback",
        name: "Cable Glute Kickback",
        pattern: .hinge,
        primaryEquipment: .cable,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Slow eccentric — let the cable stretch the glute.",
            "Stand tall — no leaning into the cable.",
        ],
        primaryMuscles: [.glutes],
        secondaryMuscles: [.hamstrings],
        difficulty: .beginner,
        unilateral: true
    )

    static let nordicHamCurl = ExerciseDefinition(
        id: "nordic-ham-curl",
        name: "Nordic Hamstring Curl",
        pattern: .hinge,
        primaryEquipment: .bodyweight,
        alternateEquipment: [.band],
        defaultRepRange: 4...8,
        defaultRPE: 9.0,
        isCompound: false,
        cues: [
            "Brutal eccentric — fight gravity all the way down.",
            "Catch yourself at the bottom, push off to reset.",
        ],
        aliases: ["Nordics"],
        primaryMuscles: [.hamstrings],
        secondaryMuscles: [.glutes, .abs],
        difficulty: .advanced,
        lengthenedPositionEmphasis: true
    )

    static let sliderHamCurl = ExerciseDefinition(
        id: "slider-ham-curl",
        name: "Slider Hamstring Curl",
        pattern: .hinge,
        primaryEquipment: .bodyweight,
        defaultRepRange: 8...12,
        defaultRPE: 8.0,
        isCompound: false,
        cues: [
            "Heels on the sliders, hips up the whole time.",
            "Pull the heels under the hips, don't let them drift.",
        ],
        primaryMuscles: [.hamstrings],
        secondaryMuscles: [.glutes, .abs],
        difficulty: .intermediate
    )

    static let seatedLegCurl = ExerciseDefinition(
        id: "seated-leg-curl",
        name: "Seated Leg Curl",
        pattern: .hinge,
        primaryEquipment: .machine,
        defaultRepRange: 10...15,
        defaultRPE: 8.0,
        isCompound: false,
        cues: [
            "Full stretch at the top — feet pulled up.",
            "Squeeze the heels to the glutes.",
        ],
        primaryMuscles: [.hamstrings],
        secondaryMuscles: [],
        difficulty: .beginner,
        lengthenedPositionEmphasis: true
    )

    static let lyingLegCurl = ExerciseDefinition(
        id: "lying-leg-curl",
        name: "Lying Leg Curl",
        pattern: .hinge,
        primaryEquipment: .machine,
        defaultRepRange: 10...15,
        defaultRPE: 8.0,
        isCompound: false,
        cues: [
            "Hips pinned to the pad.",
            "Curl the heels all the way to the glutes.",
        ],
        primaryMuscles: [.hamstrings],
        secondaryMuscles: [.calves],
        difficulty: .beginner
    )

    // MARK: - Lunge pattern (VOL-105 new)

    static let walkingLunge = ExerciseDefinition(
        id: "walking-lunge",
        name: "Walking Lunge",
        pattern: .lunge,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.barbell, .bodyweight],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Long stride — push the front knee forward.",
            "Step through, don't rebound off the back foot.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings, .adductors, .abs],
        difficulty: .intermediate,
        unilateral: true
    )

    static let reverseLunge = ExerciseDefinition(
        id: "reverse-lunge",
        name: "Reverse Lunge",
        pattern: .lunge,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.barbell, .bodyweight, .kettlebell],
        defaultRepRange: 8...12,
        defaultRPE: 7.0,
        isCompound: true,
        cues: [
            "Step back into the lunge — front knee stacks over the ankle.",
            "Drive through the front heel to come up.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings, .adductors, .abs],
        difficulty: .beginner,
        unilateral: true
    )

    static let forwardLunge = ExerciseDefinition(
        id: "forward-lunge",
        name: "Forward Lunge",
        pattern: .lunge,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.barbell, .bodyweight, .kettlebell],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Long step forward — short steps overload the knee.",
            "Drive through the heel back to the start.",
        ],
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings, .adductors, .abs],
        difficulty: .intermediate,
        unilateral: true
    )

    static let curtsyLunge = ExerciseDefinition(
        id: "curtsy-lunge",
        name: "Curtsy Lunge",
        pattern: .lunge,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.bodyweight],
        defaultRepRange: 8...12,
        defaultRPE: 7.0,
        isCompound: true,
        cues: [
            "Cross one leg behind and outside the other.",
            "Stay tall — chest doesn't dip with the hips.",
        ],
        primaryMuscles: [.glutes, .quads],
        secondaryMuscles: [.adductors, .abductors],
        difficulty: .intermediate,
        unilateral: true
    )

    static let lateralLunge = ExerciseDefinition(
        id: "lateral-lunge",
        name: "Lateral Lunge",
        pattern: .lunge,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.bodyweight, .kettlebell],
        defaultRepRange: 8...12,
        defaultRPE: 7.0,
        isCompound: true,
        cues: [
            "Push your hips way out to one side.",
            "Stretch the other adductor — that's the goal.",
        ],
        aliases: ["Side Lunge"],
        primaryMuscles: [.adductors, .glutes, .quads],
        secondaryMuscles: [.hamstrings],
        difficulty: .beginner,
        unilateral: true,
        lengthenedPositionEmphasis: true
    )

    // MARK: - Horizontal push (existing 2 + VOL-105 additions)

    static let benchPress = ExerciseDefinition(
        id: "bench-press",
        name: "Bench Press",
        pattern: .horizontalPush,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell, .machine],
        defaultRepRange: 5...8,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Pull your shoulder blades down and back.",
            "Touch your chest with control — then drive through the floor.",
        ],
        aliases: ["BP"],
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .frontDelts],
        difficulty: .intermediate
    )

    static let dumbbellBenchPress = ExerciseDefinition(
        id: "db-bench-press",
        name: "Dumbbell Bench Press",
        pattern: .horizontalPush,
        primaryEquipment: .dumbbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: ["Stretch at the bottom, squeeze at the top."],
        aliases: ["DB Bench"],
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .frontDelts],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let inclineBenchPress = ExerciseDefinition(
        id: "incline-bench-press",
        name: "Incline Bench Press",
        pattern: .horizontalPush,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell, .machine],
        defaultRepRange: 6...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "30 degrees — anything steeper recruits the front delts too much.",
            "Bar to the upper chest, no flaring.",
        ],
        aliases: ["Incline BP"],
        primaryMuscles: [.upperChest],
        secondaryMuscles: [.frontDelts, .triceps],
        difficulty: .intermediate
    )

    static let inclineDumbbellPress = ExerciseDefinition(
        id: "incline-db-press",
        name: "Incline Dumbbell Press",
        pattern: .horizontalPush,
        primaryEquipment: .dumbbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Stretch the dumbbells deep at the bottom.",
            "Press together at the top — squeeze the upper chest.",
        ],
        aliases: ["Incline DB"],
        primaryMuscles: [.upperChest],
        secondaryMuscles: [.frontDelts, .triceps],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let declineBenchPress = ExerciseDefinition(
        id: "decline-bench-press",
        name: "Decline Bench Press",
        pattern: .horizontalPush,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell, .machine],
        defaultRepRange: 6...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Bar to the lower chest line.",
            "Strict touch — no bouncing off the chest.",
        ],
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .frontDelts],
        difficulty: .intermediate
    )

    static let closeGripBenchPress = ExerciseDefinition(
        id: "close-grip-bench",
        name: "Close-Grip Bench Press",
        pattern: .horizontalPush,
        primaryEquipment: .barbell,
        defaultRepRange: 6...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Hands shoulder-width — elbows tucked tight.",
            "Drive the bar in a straight line over your face.",
        ],
        aliases: ["CGBP"],
        primaryMuscles: [.triceps, .chest],
        secondaryMuscles: [.frontDelts],
        difficulty: .intermediate
    )

    static let pausedBenchPress = ExerciseDefinition(
        id: "paused-bench-press",
        name: "Paused Bench Press",
        pattern: .horizontalPush,
        primaryEquipment: .barbell,
        defaultRepRange: 3...6,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "One full count on the chest — no bounce.",
            "Press straight off the chest, not forward.",
        ],
        aliases: ["Pause Bench"],
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .frontDelts],
        difficulty: .advanced,
        lengthenedPositionEmphasis: true
    )

    static let machineChestPress = ExerciseDefinition(
        id: "machine-chest-press",
        name: "Machine Chest Press",
        pattern: .horizontalPush,
        primaryEquipment: .machine,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Set the seat so the handles line up with the lower chest.",
            "Push and squeeze — don't lock out hard.",
        ],
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .frontDelts],
        difficulty: .beginner
    )

    static let smithBenchPress = ExerciseDefinition(
        id: "smith-bench-press",
        name: "Smith Machine Bench Press",
        pattern: .horizontalPush,
        primaryEquipment: .machine,
        defaultRepRange: 6...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Set the bench so the bar tracks over the lower chest.",
            "Lower with control — the bar can't drift on you.",
        ],
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .frontDelts],
        difficulty: .beginner
    )

    static let cableFly = ExerciseDefinition(
        id: "cable-fly",
        name: "Cable Fly",
        pattern: .horizontalPush,
        primaryEquipment: .cable,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Soft elbows — bend the angle just enough.",
            "Stretch wide, then hug a tree at the top.",
        ],
        primaryMuscles: [.chest],
        secondaryMuscles: [.frontDelts],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let machinePecDeck = ExerciseDefinition(
        id: "machine-pec-deck",
        name: "Machine Pec Deck",
        pattern: .horizontalPush,
        primaryEquipment: .machine,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Squeeze the chest, not the arms.",
            "Slow eccentric — feel the deep stretch.",
        ],
        aliases: ["Pec Deck"],
        primaryMuscles: [.chest],
        secondaryMuscles: [.frontDelts],
        difficulty: .beginner,
        lengthenedPositionEmphasis: true
    )

    static let dumbbellFly = ExerciseDefinition(
        id: "dumbbell-fly",
        name: "Dumbbell Fly",
        pattern: .horizontalPush,
        primaryEquipment: .dumbbell,
        defaultRepRange: 10...15,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Soft elbow — keep that angle locked.",
            "Stretch deep, then squeeze.",
        ],
        primaryMuscles: [.chest],
        secondaryMuscles: [.frontDelts],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let inclineDumbbellFly = ExerciseDefinition(
        id: "incline-db-fly",
        name: "Incline Dumbbell Fly",
        pattern: .horizontalPush,
        primaryEquipment: .dumbbell,
        defaultRepRange: 10...15,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Soft elbow throughout the rep.",
            "Stretch the dumbbells out wide — that's the upper-chest cue.",
        ],
        primaryMuscles: [.upperChest],
        secondaryMuscles: [.frontDelts],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let pushUp = ExerciseDefinition(
        id: "push-up",
        name: "Push-Up",
        pattern: .horizontalPush,
        primaryEquipment: .bodyweight,
        defaultRepRange: 10...20,
        defaultRPE: 7.0,
        isCompound: true,
        cues: [
            "Plank from heels to head — no hip sag.",
            "Touch your chest, then drive the floor away.",
        ],
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .frontDelts, .abs],
        difficulty: .beginner
    )

    static let deficitPushUp = ExerciseDefinition(
        id: "deficit-push-up",
        name: "Deficit Push-Up",
        pattern: .horizontalPush,
        primaryEquipment: .bodyweight,
        defaultRepRange: 8...15,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Hands on parallettes or risers — extra range.",
            "Pause at the bottom — feel the chest stretch.",
        ],
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .frontDelts, .abs],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let divePushUp = ExerciseDefinition(
        id: "dive-push-up",
        name: "Dive-Bomber Push-Up",
        pattern: .horizontalPush,
        primaryEquipment: .bodyweight,
        defaultRepRange: 6...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Start in down dog, dive forward and up.",
            "Reverse the path back to start — full body chain.",
        ],
        primaryMuscles: [.chest, .frontDelts],
        secondaryMuscles: [.triceps, .upperChest, .abs],
        difficulty: .intermediate
    )

    // MARK: - Vertical push (existing 1 + VOL-105 additions)

    static let overheadPress = ExerciseDefinition(
        id: "overhead-press",
        name: "Overhead Press",
        pattern: .verticalPush,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell],
        defaultRepRange: 5...8,
        defaultRPE: 7.5,
        isCompound: true,
        cues: ["Squeeze your glutes, press the bar past your forehead."],
        aliases: ["OHP", "Strict Press"],
        primaryMuscles: [.frontDelts, .sideDelts],
        secondaryMuscles: [.triceps, .upperChest, .traps, .abs],
        difficulty: .intermediate
    )

    static let seatedDumbbellPress = ExerciseDefinition(
        id: "seated-db-press",
        name: "Seated Dumbbell Press",
        pattern: .verticalPush,
        primaryEquipment: .dumbbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Lower the dumbbells to ear height for the full stretch.",
            "Drive up — don't bang the dumbbells together.",
        ],
        aliases: ["Seated DB Press"],
        primaryMuscles: [.frontDelts, .sideDelts],
        secondaryMuscles: [.triceps, .upperChest],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let standingDumbbellPress = ExerciseDefinition(
        id: "standing-db-press",
        name: "Standing Dumbbell Press",
        pattern: .verticalPush,
        primaryEquipment: .dumbbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Brace the trunk — no leaning back.",
            "Press straight overhead, not forward.",
        ],
        primaryMuscles: [.frontDelts, .sideDelts],
        secondaryMuscles: [.triceps, .upperChest, .abs],
        difficulty: .intermediate
    )

    static let machineShoulderPress = ExerciseDefinition(
        id: "machine-shoulder-press",
        name: "Machine Shoulder Press",
        pattern: .verticalPush,
        primaryEquipment: .machine,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Set the seat so your elbows track in the natural press path.",
            "Push and squeeze — don't lock out hard.",
        ],
        primaryMuscles: [.frontDelts, .sideDelts],
        secondaryMuscles: [.triceps, .upperChest],
        difficulty: .beginner
    )

    static let arnoldPress = ExerciseDefinition(
        id: "arnold-press",
        name: "Arnold Press",
        pattern: .verticalPush,
        primaryEquipment: .dumbbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Start palms-in, rotate to palms-out as you press.",
            "Reverse the rotation on the way down.",
        ],
        primaryMuscles: [.frontDelts, .sideDelts],
        secondaryMuscles: [.triceps],
        difficulty: .intermediate
    )

    static let pushPress = ExerciseDefinition(
        id: "push-press",
        name: "Push Press",
        pattern: .verticalPush,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell, .kettlebell],
        defaultRepRange: 3...6,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Quick dip — shallow knee bend, no squat.",
            "Drive with the legs and finish with the shoulders.",
        ],
        primaryMuscles: [.frontDelts, .sideDelts, .triceps],
        secondaryMuscles: [.quads, .glutes, .upperChest, .abs],
        difficulty: .advanced
    )

    static let zPress = ExerciseDefinition(
        id: "z-press",
        name: "Z Press",
        pattern: .verticalPush,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell, .kettlebell],
        defaultRepRange: 5...8,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Seated on the floor, legs straight in front.",
            "No leg drive — pure shoulder strength.",
        ],
        primaryMuscles: [.frontDelts, .sideDelts],
        secondaryMuscles: [.triceps, .abs, .upperChest],
        difficulty: .advanced
    )

    static let landminePress = ExerciseDefinition(
        id: "landmine-press",
        name: "Landmine Press",
        pattern: .verticalPush,
        primaryEquipment: .barbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Start at the shoulder, press up and out at the angle.",
            "Drive the opposite hip back as a counterbalance.",
        ],
        primaryMuscles: [.frontDelts, .upperChest],
        secondaryMuscles: [.triceps, .abs],
        difficulty: .intermediate,
        unilateral: true
    )

    static let dumbbellLateralRaise = ExerciseDefinition(
        id: "db-lateral-raise",
        name: "Dumbbell Lateral Raise",
        pattern: .verticalPush,
        primaryEquipment: .dumbbell,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Lead with the elbow, not the wrist.",
            "Stop at shoulder height — going higher recruits traps.",
        ],
        aliases: ["Side Raise", "Lateral Raise"],
        primaryMuscles: [.sideDelts],
        secondaryMuscles: [.traps],
        difficulty: .beginner
    )

    static let cableLateralRaise = ExerciseDefinition(
        id: "cable-lateral-raise",
        name: "Cable Lateral Raise",
        pattern: .verticalPush,
        primaryEquipment: .cable,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Stand with the cable behind you — constant tension throughout.",
            "Lift to the side at a slight forward angle.",
        ],
        primaryMuscles: [.sideDelts],
        secondaryMuscles: [.traps],
        difficulty: .intermediate
    )

    static let leaningCableLateralRaise = ExerciseDefinition(
        id: "leaning-cable-lateral-raise",
        name: "Leaning Cable Lateral Raise",
        pattern: .verticalPush,
        primaryEquipment: .cable,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Lean away from the cable — extra range past midline.",
            "Slow eccentric — feel the deep delt stretch.",
        ],
        aliases: ["Lean-Away Raise"],
        primaryMuscles: [.sideDelts],
        secondaryMuscles: [],
        difficulty: .intermediate,
        unilateral: true,
        lengthenedPositionEmphasis: true
    )

    static let machineLateralRaise = ExerciseDefinition(
        id: "machine-lateral-raise",
        name: "Machine Lateral Raise",
        pattern: .verticalPush,
        primaryEquipment: .machine,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Set the pads against the outside of the elbow.",
            "Push out, not up — the machine handles the arc.",
        ],
        primaryMuscles: [.sideDelts],
        secondaryMuscles: [],
        difficulty: .beginner
    )

    static let frontRaise = ExerciseDefinition(
        id: "front-raise",
        name: "Front Raise",
        pattern: .verticalPush,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.cable, .barbell, .band],
        defaultRepRange: 10...15,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Lift to eye level, not the ceiling.",
            "Slow eccentric — control the lower.",
        ],
        primaryMuscles: [.frontDelts],
        secondaryMuscles: [.upperChest],
        difficulty: .beginner
    )

    static let uprightRow = ExerciseDefinition(
        id: "upright-row",
        name: "Upright Row",
        pattern: .verticalPush,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell, .cable],
        defaultRepRange: 8...12,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Wide grip — narrow grip pinches the shoulder.",
            "Pull to chest height, elbows lead.",
        ],
        primaryMuscles: [.sideDelts, .traps],
        secondaryMuscles: [.biceps, .forearms],
        difficulty: .intermediate
    )

    // MARK: - Horizontal pull (existing 1 + VOL-105 additions)

    static let barbellRow = ExerciseDefinition(
        id: "barbell-row",
        name: "Barbell Row",
        pattern: .horizontalPull,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell, .cable],
        defaultRepRange: 6...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: ["Row to your lower chest, squeeze your back at the top."],
        aliases: ["BBR", "Bent-Over Row"],
        primaryMuscles: [.midBack, .lats],
        secondaryMuscles: [.rearDelts, .biceps, .lowerBack, .forearms],
        difficulty: .intermediate
    )

    static let pendlayRow = ExerciseDefinition(
        id: "pendlay-row",
        name: "Pendlay Row",
        pattern: .horizontalPull,
        primaryEquipment: .barbell,
        defaultRepRange: 5...8,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Bar resets on the floor every rep — dead-stop strict.",
            "Explosive pull, controlled lower.",
        ],
        primaryMuscles: [.midBack, .lats],
        secondaryMuscles: [.rearDelts, .biceps, .lowerBack],
        difficulty: .advanced
    )

    static let yatesRow = ExerciseDefinition(
        id: "yates-row",
        name: "Yates Row",
        pattern: .horizontalPull,
        primaryEquipment: .barbell,
        defaultRepRange: 6...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Underhand grip, torso about 45°.",
            "Row to the belly, big lat squeeze.",
        ],
        primaryMuscles: [.lats, .midBack],
        secondaryMuscles: [.biceps, .rearDelts, .lowerBack],
        difficulty: .intermediate
    )

    static let tBarRow = ExerciseDefinition(
        id: "t-bar-row",
        name: "T-Bar Row",
        pattern: .horizontalPull,
        primaryEquipment: .machine,
        alternateEquipment: [.barbell],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Chest into the pad — let the pad do the support work.",
            "Squeeze the back, then lower with control.",
        ],
        aliases: ["T-Bar"],
        primaryMuscles: [.midBack, .lats],
        secondaryMuscles: [.rearDelts, .biceps, .traps],
        difficulty: .intermediate
    )

    static let meadowsRow = ExerciseDefinition(
        id: "meadows-row",
        name: "Meadows Row",
        pattern: .horizontalPull,
        primaryEquipment: .barbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Stand perpendicular to a landmine setup.",
            "Pronated grip, row up and back — heavy lat-pump finisher.",
        ],
        primaryMuscles: [.lats, .midBack],
        secondaryMuscles: [.rearDelts, .biceps, .forearms],
        difficulty: .intermediate,
        unilateral: true
    )

    static let sealRow = ExerciseDefinition(
        id: "seal-row",
        name: "Seal Row",
        pattern: .horizontalPull,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Chest pinned to the bench — no body english allowed.",
            "Pure back work — pull the bar to the underside of the bench.",
        ],
        primaryMuscles: [.midBack, .lats],
        secondaryMuscles: [.rearDelts, .biceps],
        difficulty: .intermediate
    )

    static let chestSupportedRow = ExerciseDefinition(
        id: "chest-supported-row",
        name: "Chest-Supported Row",
        pattern: .horizontalPull,
        primaryEquipment: .machine,
        alternateEquipment: [.dumbbell],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Chest pinned, drive the elbows back hard.",
            "Stretch at full extension before each pull.",
        ],
        aliases: ["CSR"],
        primaryMuscles: [.midBack, .lats],
        secondaryMuscles: [.rearDelts, .biceps],
        difficulty: .beginner
    )

    static let singleArmDumbbellRow = ExerciseDefinition(
        id: "single-arm-db-row",
        name: "Single-Arm Dumbbell Row",
        pattern: .horizontalPull,
        primaryEquipment: .dumbbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Knee and free hand on the bench — flat back.",
            "Row to the hip, full stretch at the bottom.",
        ],
        aliases: ["DB Row", "One-Arm Row"],
        primaryMuscles: [.lats, .midBack],
        secondaryMuscles: [.rearDelts, .biceps, .forearms],
        difficulty: .beginner,
        unilateral: true
    )

    static let cableRow = ExerciseDefinition(
        id: "cable-row",
        name: "Seated Cable Row",
        pattern: .horizontalPull,
        primaryEquipment: .cable,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Stretch forward at the start — full lat reach.",
            "Drive the elbows behind you, squeeze the mid-back.",
        ],
        primaryMuscles: [.midBack, .lats],
        secondaryMuscles: [.rearDelts, .biceps, .forearms],
        difficulty: .beginner
    )

    static let invertedRow = ExerciseDefinition(
        id: "inverted-row",
        name: "Inverted Row",
        pattern: .horizontalPull,
        primaryEquipment: .bodyweight,
        defaultRepRange: 8...15,
        defaultRPE: 7.0,
        isCompound: true,
        cues: [
            "Body straight from heels to head.",
            "Pull the chest to the bar, no hip sag.",
        ],
        aliases: ["Bodyweight Row"],
        primaryMuscles: [.midBack, .lats],
        secondaryMuscles: [.rearDelts, .biceps, .abs],
        difficulty: .beginner
    )

    static let facePull = ExerciseDefinition(
        id: "face-pull",
        name: "Face Pull",
        pattern: .horizontalPull,
        primaryEquipment: .cable,
        alternateEquipment: [.band],
        defaultRepRange: 12...15,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Pull to the bridge of the nose, hands wide.",
            "External rotation at the end — squeeze the rear delts.",
        ],
        primaryMuscles: [.rearDelts],
        secondaryMuscles: [.traps, .midBack],
        difficulty: .beginner
    )

    static let cableRearDeltFly = ExerciseDefinition(
        id: "cable-rear-delt-fly",
        name: "Cable Rear-Delt Fly",
        pattern: .horizontalPull,
        primaryEquipment: .cable,
        defaultRepRange: 10...15,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Cross the cables in front of you, stretch wide.",
            "Pull back and out — squeeze the rear delts at the end.",
        ],
        aliases: ["Reverse Cable Fly"],
        primaryMuscles: [.rearDelts],
        secondaryMuscles: [.midBack, .traps],
        difficulty: .intermediate
    )

    static let dumbbellRearDeltFly = ExerciseDefinition(
        id: "db-rear-delt-fly",
        name: "Dumbbell Rear-Delt Fly",
        pattern: .horizontalPull,
        primaryEquipment: .dumbbell,
        defaultRepRange: 10...15,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Hinge over, soft elbows.",
            "Lift to the side and slightly back — let the rear delts work.",
        ],
        aliases: ["Bent-Over Reverse Fly"],
        primaryMuscles: [.rearDelts],
        secondaryMuscles: [.midBack, .traps],
        difficulty: .beginner
    )

    static let reversePecDeck = ExerciseDefinition(
        id: "reverse-pec-deck",
        name: "Reverse Pec Deck",
        pattern: .horizontalPull,
        primaryEquipment: .machine,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Chest into the pad, flare the arms back.",
            "Squeeze the rear delts at end range.",
        ],
        primaryMuscles: [.rearDelts],
        secondaryMuscles: [.midBack, .traps],
        difficulty: .beginner
    )

    // MARK: - Vertical pull (existing 2 + VOL-105 additions)

    static let pullUp = ExerciseDefinition(
        id: "pull-up",
        name: "Pull-Up",
        pattern: .verticalPull,
        primaryEquipment: .bodyweight,
        alternateEquipment: [.machine, .band],
        defaultRepRange: 5...12,
        defaultRPE: 8.0,
        isCompound: true,
        cues: ["Drive your elbows down to your ribs."],
        primaryMuscles: [.lats, .midBack],
        secondaryMuscles: [.biceps, .rearDelts, .forearms, .abs],
        difficulty: .intermediate
    )

    static let latPulldown = ExerciseDefinition(
        id: "lat-pulldown",
        name: "Lat Pulldown",
        pattern: .verticalPull,
        primaryEquipment: .cable,
        alternateEquipment: [.machine],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: ["Start with your lats, not your biceps."],
        primaryMuscles: [.lats],
        secondaryMuscles: [.biceps, .midBack, .rearDelts],
        difficulty: .beginner
    )

    static let chinUp = ExerciseDefinition(
        id: "chin-up",
        name: "Chin-Up",
        pattern: .verticalPull,
        primaryEquipment: .bodyweight,
        alternateEquipment: [.machine, .band],
        defaultRepRange: 5...12,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Underhand grip, hands shoulder-width.",
            "Pull the chest to the bar — biceps and lats together.",
        ],
        primaryMuscles: [.lats, .biceps],
        secondaryMuscles: [.midBack, .forearms, .abs],
        difficulty: .intermediate
    )

    static let neutralGripPullUp = ExerciseDefinition(
        id: "neutral-grip-pull-up",
        name: "Neutral-Grip Pull-Up",
        pattern: .verticalPull,
        primaryEquipment: .bodyweight,
        alternateEquipment: [.machine, .band],
        defaultRepRange: 5...12,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Palms facing each other — easiest on the shoulders.",
            "Drive elbows down and back.",
        ],
        primaryMuscles: [.lats, .midBack],
        secondaryMuscles: [.biceps, .brachialis, .forearms],
        difficulty: .intermediate
    )

    static let wideGripPullUp = ExerciseDefinition(
        id: "wide-grip-pull-up",
        name: "Wide-Grip Pull-Up",
        pattern: .verticalPull,
        primaryEquipment: .bodyweight,
        alternateEquipment: [.machine, .band],
        defaultRepRange: 5...10,
        defaultRPE: 8.5,
        isCompound: true,
        cues: [
            "Hands wider than shoulder — minimal arm contribution.",
            "Pull until the chin clears the bar.",
        ],
        primaryMuscles: [.lats],
        secondaryMuscles: [.midBack, .biceps, .rearDelts],
        difficulty: .advanced
    )

    static let assistedPullUp = ExerciseDefinition(
        id: "assisted-pull-up",
        name: "Assisted Pull-Up",
        pattern: .verticalPull,
        primaryEquipment: .machine,
        alternateEquipment: [.band, .bodyweight],
        defaultRepRange: 8...15,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Use the assist to control the eccentric, not skip the work.",
            "Same pull pattern — full ROM at every rep.",
        ],
        primaryMuscles: [.lats, .midBack],
        secondaryMuscles: [.biceps, .rearDelts],
        difficulty: .beginner
    )

    static let straightArmPulldown = ExerciseDefinition(
        id: "straight-arm-pulldown",
        name: "Straight-Arm Pulldown",
        pattern: .verticalPull,
        primaryEquipment: .cable,
        defaultRepRange: 12...15,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Soft elbows — keep the angle locked.",
            "Pull the bar to the thighs in a wide arc.",
        ],
        primaryMuscles: [.lats],
        secondaryMuscles: [.triceps, .abs],
        difficulty: .beginner
    )

    static let kneelingCablePulldown = ExerciseDefinition(
        id: "kneeling-cable-pulldown",
        name: "Kneeling Cable Pulldown",
        pattern: .verticalPull,
        primaryEquipment: .cable,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Kneel facing the cable column — line of pull stays vertical.",
            "Pull the bar to the chest, lats lead.",
        ],
        primaryMuscles: [.lats],
        secondaryMuscles: [.biceps, .midBack],
        difficulty: .intermediate
    )

    static let singleArmLatPulldown = ExerciseDefinition(
        id: "single-arm-lat-pulldown",
        name: "Single-Arm Lat Pulldown",
        pattern: .verticalPull,
        primaryEquipment: .cable,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Reach overhead at the top — full lat stretch.",
            "Pull the elbow to the hip, squeeze the lat.",
        ],
        primaryMuscles: [.lats],
        secondaryMuscles: [.biceps, .midBack],
        difficulty: .intermediate,
        unilateral: true,
        lengthenedPositionEmphasis: true
    )

    // MARK: - Isolation: arms, calves, forearms

    static let barbellCurl = ExerciseDefinition(
        id: "barbell-curl",
        name: "Barbell Curl",
        pattern: .isolation,
        primaryEquipment: .barbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Elbows pinned to your sides — no swinging.",
            "Squeeze the biceps at the top, controlled lower.",
        ],
        primaryMuscles: [.biceps],
        secondaryMuscles: [.brachialis, .forearms],
        difficulty: .beginner
    )

    static let dumbbellCurl = ExerciseDefinition(
        id: "dumbbell-curl",
        name: "Dumbbell Curl",
        pattern: .isolation,
        primaryEquipment: .dumbbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Supinate as you curl — palm rotates up.",
            "Strict elbows, no swinging.",
        ],
        aliases: ["DB Curl"],
        primaryMuscles: [.biceps],
        secondaryMuscles: [.brachialis, .forearms],
        difficulty: .beginner
    )

    static let inclineDumbbellCurl = ExerciseDefinition(
        id: "incline-db-curl",
        name: "Incline Dumbbell Curl",
        pattern: .isolation,
        primaryEquipment: .dumbbell,
        defaultRepRange: 10...12,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Bench at 60° — dumbbells hang behind the body for full stretch.",
            "Curl without swinging — slow eccentric.",
        ],
        aliases: ["Incline Curl"],
        primaryMuscles: [.biceps],
        secondaryMuscles: [.brachialis, .forearms],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let hammerCurl = ExerciseDefinition(
        id: "hammer-curl",
        name: "Hammer Curl",
        pattern: .isolation,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.cable],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Neutral grip — palms face each other the whole rep.",
            "Curl to shoulder height, brachialis does the work.",
        ],
        primaryMuscles: [.brachialis, .biceps],
        secondaryMuscles: [.forearms],
        difficulty: .beginner
    )

    static let preacherCurl = ExerciseDefinition(
        id: "preacher-curl",
        name: "Preacher Curl",
        pattern: .isolation,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell, .machine],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Armpits jammed against the pad.",
            "Full stretch at the bottom — that's where the bicep grows.",
        ],
        primaryMuscles: [.biceps],
        secondaryMuscles: [.brachialis, .forearms],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let cableCurl = ExerciseDefinition(
        id: "cable-curl",
        name: "Cable Curl",
        pattern: .isolation,
        primaryEquipment: .cable,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Elbows pinned — pure curl pattern.",
            "Constant tension — slow eccentric.",
        ],
        primaryMuscles: [.biceps],
        secondaryMuscles: [.brachialis, .forearms],
        difficulty: .beginner
    )

    static let tricepPushdown = ExerciseDefinition(
        id: "tricep-pushdown",
        name: "Tricep Pushdown",
        pattern: .isolation,
        primaryEquipment: .cable,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Elbows tucked at the sides.",
            "Push down and squeeze — lock out cleanly.",
        ],
        aliases: ["Pushdown"],
        primaryMuscles: [.triceps],
        secondaryMuscles: [],
        difficulty: .beginner
    )

    static let ropePushdown = ExerciseDefinition(
        id: "rope-pushdown",
        name: "Rope Tricep Pushdown",
        pattern: .isolation,
        primaryEquipment: .cable,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Spread the rope at the bottom.",
            "Squeeze the triceps hard at lockout.",
        ],
        primaryMuscles: [.triceps],
        secondaryMuscles: [],
        difficulty: .beginner
    )

    static let overheadTricepExtension = ExerciseDefinition(
        id: "overhead-tricep-extension",
        name: "Overhead Tricep Extension",
        pattern: .isolation,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.cable, .barbell],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Stretch the long head — elbows up, forearms drop behind the head.",
            "Pause at full stretch, then drive up.",
        ],
        aliases: ["Overhead Extension"],
        primaryMuscles: [.longHeadTriceps, .triceps],
        secondaryMuscles: [],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let skullcrusher = ExerciseDefinition(
        id: "skullcrusher",
        name: "Skullcrusher",
        pattern: .isolation,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell, .cable],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Lower behind the head, not to the forehead — full stretch.",
            "Elbows stay tucked — pure tricep work.",
        ],
        aliases: ["Lying Tricep Extension"],
        primaryMuscles: [.longHeadTriceps, .triceps],
        secondaryMuscles: [],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let pjrPullover = ExerciseDefinition(
        id: "pjr-pullover",
        name: "PJR Pullover",
        pattern: .isolation,
        primaryEquipment: .dumbbell,
        defaultRepRange: 8...12,
        defaultRPE: 8.0,
        isCompound: false,
        cues: [
            "Lower behind the head with a slight elbow bend.",
            "Drive the dumbbell back over the chest with the long head.",
        ],
        primaryMuscles: [.longHeadTriceps, .triceps],
        secondaryMuscles: [.lats],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let dumbbellPullover = ExerciseDefinition(
        id: "dumbbell-pullover",
        name: "Dumbbell Pullover",
        pattern: .isolation,
        primaryEquipment: .dumbbell,
        defaultRepRange: 10...15,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Soft elbows, deep stretch behind the head.",
            "Pull with the lats and chest together.",
        ],
        aliases: ["DB Pullover"],
        primaryMuscles: [.lats, .chest],
        secondaryMuscles: [.longHeadTriceps],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let cablePullover = ExerciseDefinition(
        id: "cable-pullover",
        name: "Cable Pullover",
        pattern: .isolation,
        primaryEquipment: .cable,
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Bent over with arms straight, pull the bar to your hips.",
            "Squeeze the lats at the bottom.",
        ],
        primaryMuscles: [.lats],
        secondaryMuscles: [.chest, .longHeadTriceps],
        difficulty: .intermediate
    )

    static let standingCalfRaise = ExerciseDefinition(
        id: "standing-calf-raise",
        name: "Standing Calf Raise",
        pattern: .isolation,
        primaryEquipment: .machine,
        alternateEquipment: [.dumbbell, .barbell],
        defaultRepRange: 10...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Full stretch at the bottom — drop the heels under.",
            "Squeeze hard at the top, full plantar flexion.",
        ],
        primaryMuscles: [.calves],
        secondaryMuscles: [],
        difficulty: .beginner,
        lengthenedPositionEmphasis: true
    )

    static let seatedCalfRaise = ExerciseDefinition(
        id: "seated-calf-raise",
        name: "Seated Calf Raise",
        pattern: .isolation,
        primaryEquipment: .machine,
        defaultRepRange: 12...20,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Bias the soleus — knees bent, slow tempo.",
            "Pause at the bottom — feel the deep stretch.",
        ],
        primaryMuscles: [.calves],
        secondaryMuscles: [],
        difficulty: .beginner,
        lengthenedPositionEmphasis: true
    )

    static let donkeyCalfRaise = ExerciseDefinition(
        id: "donkey-calf-raise",
        name: "Donkey Calf Raise",
        pattern: .isolation,
        primaryEquipment: .machine,
        alternateEquipment: [.bodyweight],
        defaultRepRange: 12...20,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Hinge at the hips — calves loaded under the load.",
            "Full stretch and full squeeze on every rep.",
        ],
        primaryMuscles: [.calves],
        secondaryMuscles: [.hamstrings],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    static let wristCurl = ExerciseDefinition(
        id: "wrist-curl",
        name: "Wrist Curl",
        pattern: .isolation,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.barbell, .cable],
        defaultRepRange: 12...20,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Forearms on the bench, palms up.",
            "Let the weight stretch the wrist down, then curl up.",
        ],
        primaryMuscles: [.forearms],
        secondaryMuscles: [],
        difficulty: .beginner
    )

    static let reverseCurl = ExerciseDefinition(
        id: "reverse-curl",
        name: "Reverse Curl",
        pattern: .isolation,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell, .cable],
        defaultRepRange: 10...15,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Pronated grip — knuckles up.",
            "Curl with strict form, no body english.",
        ],
        primaryMuscles: [.brachialis, .forearms],
        secondaryMuscles: [.biceps],
        difficulty: .beginner
    )

    // MARK: - Carry pattern

    static let farmersWalk = ExerciseDefinition(
        id: "farmers-walk",
        name: "Farmer's Walk",
        pattern: .carry,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.kettlebell, .barbell],
        defaultRepRange: 1...1,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Stand tall, shoulders packed.",
            "Short steps — don't let the load swing.",
        ],
        aliases: ["Farmer Carry"],
        primaryMuscles: [.forearms, .traps],
        secondaryMuscles: [.abs, .glutes, .quads, .calves],
        difficulty: .beginner
    )

    static let suitcaseCarry = ExerciseDefinition(
        id: "suitcase-carry",
        name: "Suitcase Carry",
        pattern: .carry,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.kettlebell],
        defaultRepRange: 1...1,
        defaultRPE: 7.5,
        isCompound: true,
        cues: [
            "Load on one side — fight the lean with the obliques.",
            "Stand tall, walk slow.",
        ],
        primaryMuscles: [.obliques, .abs],
        secondaryMuscles: [.forearms, .traps, .glutes],
        difficulty: .beginner,
        unilateral: true
    )

    // MARK: - Core pattern (VOL-105 new)

    static let plank = ExerciseDefinition(
        id: "plank",
        name: "Plank",
        pattern: .core,
        primaryEquipment: .bodyweight,
        defaultRepRange: 1...1,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Squeeze glutes, ribs down — flat plank from heels to head.",
            "Brace as if someone's about to punch you.",
        ],
        primaryMuscles: [.abs],
        secondaryMuscles: [.obliques, .glutes, .frontDelts],
        difficulty: .beginner
    )

    static let sidePlank = ExerciseDefinition(
        id: "side-plank",
        name: "Side Plank",
        pattern: .core,
        primaryEquipment: .bodyweight,
        defaultRepRange: 1...1,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Stack the hips, drive the bottom hip up.",
            "Hold a clean line — heels to head.",
        ],
        primaryMuscles: [.obliques],
        secondaryMuscles: [.abs, .frontDelts, .glutes],
        difficulty: .beginner,
        unilateral: true
    )

    static let hangingLegRaise = ExerciseDefinition(
        id: "hanging-leg-raise",
        name: "Hanging Leg Raise",
        pattern: .core,
        primaryEquipment: .bodyweight,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Hang from the bar — lats packed, no swinging.",
            "Curl the pelvis up, not just lift the legs.",
        ],
        aliases: ["Leg Raise"],
        primaryMuscles: [.abs],
        secondaryMuscles: [.obliques, .lats, .forearms],
        difficulty: .intermediate
    )

    static let cableCrunch = ExerciseDefinition(
        id: "cable-crunch",
        name: "Cable Crunch",
        pattern: .core,
        primaryEquipment: .cable,
        defaultRepRange: 12...15,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Hips locked — only the spine moves.",
            "Crunch with the abs, not pull with the arms.",
        ],
        primaryMuscles: [.abs],
        secondaryMuscles: [.obliques],
        difficulty: .beginner
    )

    static let abWheelRollout = ExerciseDefinition(
        id: "ab-wheel-rollout",
        name: "Ab Wheel Rollout",
        pattern: .core,
        primaryEquipment: .bodyweight,
        defaultRepRange: 6...12,
        defaultRPE: 7.5,
        isCompound: false,
        cues: [
            "Brace hard, no hip sag.",
            "Roll out only as far as you can hold the spine neutral.",
        ],
        primaryMuscles: [.abs],
        secondaryMuscles: [.obliques, .lats, .frontDelts],
        difficulty: .intermediate
    )

    static let pallofPress = ExerciseDefinition(
        id: "pallof-press",
        name: "Pallof Press",
        pattern: .core,
        primaryEquipment: .cable,
        alternateEquipment: [.band],
        defaultRepRange: 10...12,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Stand perpendicular to the cable — fight the rotation.",
            "Press straight out, hold, then return.",
        ],
        primaryMuscles: [.obliques, .abs],
        secondaryMuscles: [.glutes],
        difficulty: .beginner,
        unilateral: true
    )

    static let woodChop = ExerciseDefinition(
        id: "wood-chop",
        name: "Wood Chop",
        pattern: .core,
        primaryEquipment: .cable,
        alternateEquipment: [.band, .dumbbell],
        defaultRepRange: 10...12,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Drive with the trunk, not the arms.",
            "Pivot the back foot — full body rotation.",
        ],
        primaryMuscles: [.obliques],
        secondaryMuscles: [.abs, .frontDelts],
        difficulty: .beginner,
        unilateral: true
    )

    static let russianTwist = ExerciseDefinition(
        id: "russian-twist",
        name: "Russian Twist",
        pattern: .core,
        primaryEquipment: .bodyweight,
        alternateEquipment: [.dumbbell, .kettlebell],
        defaultRepRange: 12...20,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Lean back, feet light — engage the abs the whole time.",
            "Rotate from the trunk, not the arms.",
        ],
        primaryMuscles: [.obliques, .abs],
        secondaryMuscles: [],
        difficulty: .beginner
    )

    static let declineSitUp = ExerciseDefinition(
        id: "decline-sit-up",
        name: "Decline Sit-Up",
        pattern: .core,
        primaryEquipment: .bodyweight,
        alternateEquipment: [.dumbbell],
        defaultRepRange: 10...15,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Anchor the feet, full ROM sit-up.",
            "Curl up — don't yank with the neck.",
        ],
        primaryMuscles: [.abs],
        secondaryMuscles: [.obliques],
        difficulty: .beginner
    )

    // MARK: - Mobility pattern (VOL-105 new)

    static let tibialisRaise = ExerciseDefinition(
        id: "tibialis-raise",
        name: "Tibialis Raise",
        pattern: .mobility,
        primaryEquipment: .bodyweight,
        alternateEquipment: [.dumbbell, .band],
        defaultRepRange: 12...20,
        defaultRPE: 7.0,
        isCompound: false,
        cues: [
            "Heels at the base of the wall, toes lift up.",
            "Squeeze the shins hard, slow eccentric.",
        ],
        aliases: ["Tib Raise"],
        primaryMuscles: [.tibialis],
        secondaryMuscles: [],
        difficulty: .beginner
    )

    static let jeffersonCurl = ExerciseDefinition(
        id: "jefferson-curl",
        name: "Jefferson Curl",
        pattern: .mobility,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.barbell, .kettlebell],
        defaultRepRange: 6...10,
        defaultRPE: 6.5,
        isCompound: false,
        cues: [
            "Slow, segmented spinal flexion — chin tucks first.",
            "Light load — this is mobility, not strength.",
        ],
        primaryMuscles: [.lowerBack, .hamstrings],
        secondaryMuscles: [.midBack],
        difficulty: .intermediate,
        lengthenedPositionEmphasis: true
    )

    // MARK: - Conditioning

    static let burpee = ExerciseDefinition(
        id: "burpee",
        name: "Burpee",
        pattern: .conditioning,
        primaryEquipment: .bodyweight,
        defaultRepRange: 10...20,
        defaultRPE: 8.0,
        isCompound: true,
        cues: [
            "Drop, push-up, hop, jump.",
            "Find a sustainable pace — these crush you fast.",
        ],
        primaryMuscles: [.quads, .chest, .frontDelts],
        secondaryMuscles: [.glutes, .triceps, .abs, .calves],
        difficulty: .intermediate
    )

    static let jumpRope = ExerciseDefinition(
        id: "jump-rope",
        name: "Jump Rope",
        pattern: .conditioning,
        primaryEquipment: .bodyweight,
        defaultRepRange: 1...1,
        defaultRPE: 7.0,
        isCompound: true,
        cues: [
            "Stay light on the balls of the feet.",
            "Wrists do the work, not the shoulders.",
        ],
        primaryMuscles: [.calves],
        secondaryMuscles: [.forearms, .quads, .abs],
        difficulty: .beginner
    )

    /// All exercises in the catalog (VOL-105: 120+ entries).
    ///
    /// Order is grouped by movement pattern then by approximate
    /// programming priority within the pattern. Tests that assert the
    /// catalog size do so against a lower bound (`>= 120`) so adding a
    /// new entry doesn't churn the test.
    static let all: [ExerciseDefinition] = [
        // Squat
        backSquat, frontSquat, gobletSquat,
        lowBarSquat, highBarSquat, zercherSquat,
        boxSquat, pausedBackSquat, pinSquat,
        smithSquat, pendulumSquat, beltSquat,
        hackSquat, machineHackSquat, legPress, sissySquat,
        bulgarianSplitSquat, stepUp,

        // Hinge
        deadlift, romanianDeadlift, sumoDeadlift, trapBarDeadlift,
        deficitDeadlift, blockPulls, pausedDeadlift, stiffLegDeadlift,
        singleLegRDL, dumbbellRDL, kettlebellSwing,
        backExtension45, ghdBackExtension, goodMorning,
        barbellHipThrust, singleLegHipThrust, bStanceHipThrust, machineHipThrust,
        machineGluteKickback, cableGluteKickback,
        nordicHamCurl, sliderHamCurl, seatedLegCurl, lyingLegCurl,

        // Lunge
        walkingLunge, reverseLunge, forwardLunge, curtsyLunge, lateralLunge,

        // Horizontal push
        benchPress, dumbbellBenchPress,
        inclineBenchPress, inclineDumbbellPress, declineBenchPress,
        closeGripBenchPress, pausedBenchPress,
        machineChestPress, smithBenchPress,
        cableFly, machinePecDeck, dumbbellFly, inclineDumbbellFly,
        pushUp, deficitPushUp, divePushUp,

        // Vertical push
        overheadPress, seatedDumbbellPress, standingDumbbellPress,
        machineShoulderPress, arnoldPress, pushPress, zPress, landminePress,
        dumbbellLateralRaise, cableLateralRaise, leaningCableLateralRaise,
        machineLateralRaise, frontRaise, uprightRow,

        // Horizontal pull
        barbellRow, pendlayRow, yatesRow, tBarRow,
        meadowsRow, sealRow, chestSupportedRow,
        singleArmDumbbellRow, cableRow, invertedRow,
        facePull, cableRearDeltFly, dumbbellRearDeltFly, reversePecDeck,

        // Vertical pull
        pullUp, latPulldown, chinUp, neutralGripPullUp, wideGripPullUp,
        assistedPullUp, straightArmPulldown, kneelingCablePulldown,
        singleArmLatPulldown,

        // Isolation
        barbellCurl, dumbbellCurl, inclineDumbbellCurl, hammerCurl,
        preacherCurl, cableCurl,
        tricepPushdown, ropePushdown, overheadTricepExtension,
        skullcrusher, pjrPullover,
        dumbbellPullover, cablePullover,
        standingCalfRaise, seatedCalfRaise, donkeyCalfRaise,
        wristCurl, reverseCurl,

        // Carry
        farmersWalk, suitcaseCarry,

        // Core
        plank, sidePlank, hangingLegRaise, cableCrunch, abWheelRollout,
        pallofPress, woodChop, russianTwist, declineSitUp,

        // Mobility
        tibialisRaise, jeffersonCurl,

        // Conditioning
        burpee, jumpRope,
    ]
}

// swiftlint:enable file_length
