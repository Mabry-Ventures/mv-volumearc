import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Movement pattern taxonomy for exercise classification.
///
/// VOL-105: expanded 9 → 12 cases. The original nine cases (`squat`,
/// `hinge`, `horizontalPush`, `verticalPush`, `horizontalPull`,
/// `verticalPull`, `carry`, `isolation`, `conditioning`) keep their raw
/// values so any persisted strings continue to round-trip. Three new
/// cases — `lunge`, `core`, `mobility` — split out classes of work that
/// the existing taxonomy lumped into `isolation`/`conditioning` and
/// that the scaled-up catalog needs to address explicitly (Bulgarian
/// split squats, hard core work, tibialis raises).
public enum MovementPattern: String, Sendable, CaseIterable {
    case squat
    case hinge
    case horizontalPush = "horizontal_push"
    case verticalPush = "vertical_push"
    case horizontalPull = "horizontal_pull"
    case verticalPull = "vertical_pull"
    case carry
    case lunge
    case isolation
    case core
    case conditioning
    case mobility
}

public enum Equipment: String, Sendable, CaseIterable {
    case barbell
    case dumbbell
    case machine
    case bodyweight
    case cable
    case kettlebell
    case band
}

/// Hypertrophy-grade muscle taxonomy (VOL-105).
///
/// Splits five groups finer than the upstream free-exercise-db schema so
/// programming for stretch-bias work, overhead tricep emphasis, and
/// modern lateral-delt selection has the vocabulary it needs:
///
/// - `chest` + `upperChest` (incline-anything)
/// - `frontDelts`, `sideDelts`, `rearDelts` (rear-delt isolation work)
/// - `triceps`, `longHeadTriceps` (overhead/skullcrusher work)
/// - `biceps`, `brachialis` (hammer-curl variants)
/// - `calves`, `tibialis` (tibialis raise / shin work)
public enum MuscleGroup: String, Sendable, CaseIterable {
    case chest
    case upperChest
    case lats
    case midBack
    case lowerBack
    case traps
    case frontDelts
    case sideDelts
    case rearDelts
    case biceps
    case brachialis
    case triceps
    case longHeadTriceps
    case forearms
    case abs
    case obliques
    case glutes
    case hamstrings
    case quads
    case adductors
    case abductors
    case calves
    case tibialis
    case neck
}

/// Difficulty tier used for filtering recommendations and surfacing
/// "show me a beginner-friendly version" affordances. Distinct from
/// `AdvancementLevel` (which describes the athlete) so that an
/// intermediate athlete can opt into an advanced movement explicitly.
///
/// Cases are declared in ascending difficulty order; the synthesized
/// `Comparable` conformance lets the progression engine clamp
/// recommendations to "this athlete's tier or easier" with a simple
/// `candidate.difficulty <= cap` check.
public enum DifficultyTier: String, Sendable, CaseIterable, Comparable {
    case beginner
    case intermediate
    case advanced

    public static func < (lhs: DifficultyTier, rhs: DifficultyTier) -> Bool {
        let order: [DifficultyTier] = [.beginner, .intermediate, .advanced]
        // Force unwrap is safe — both values are guaranteed members of
        // the static `order` array since the enum is exhaustive.
        // swiftlint:disable:next force_unwrapping
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Maps an exercise to one of three Apple Fitness analytics buckets.
///
/// VOL-105 / Decision 4: Apple's Fitness app analytics buckets all
/// "lifting" into traditional vs functional vs core regardless of how
/// fine-grained we get on our side, so finer mappings (HIIT,
/// mixedCardio, etc.) are intentionally out of scope here.
///
/// The enum compiles on every platform (watchOS, simulator). Only the
/// `toHKActivityType()` converter is HealthKit-gated so the type itself
/// remains a pure Swift value the rest of the pipeline can use.
public enum HKActivityTypeMapping: String, Sendable, CaseIterable {
    case traditional
    case functional
    case core

    #if canImport(HealthKit)
    /// Translates the catalog's HK mapping into the concrete
    /// `HKWorkoutActivityType` HealthKit expects when starting a workout
    /// session for this exercise.
    public func toHKActivityType() -> HKWorkoutActivityType {
        switch self {
        case .traditional: return .traditionalStrengthTraining
        case .functional:  return .functionalStrengthTraining
        case .core:        return .coreTraining
        }
    }
    #endif
}

/// A single exercise with its biomechanical and programming properties.
///
/// VOL-105 added six fields: `aliases`, `primaryMuscles`,
/// `secondaryMuscles`, `difficulty`, `unilateral`,
/// `lengthenedPositionEmphasis`, plus an opt-in
/// `healthKitActivityType` override (auto-derived when omitted). All
/// new fields default in `init` so the existing 11 entries kept
/// compiling unchanged before they were backfilled.
public struct ExerciseDefinition: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let pattern: MovementPattern
    public let primaryEquipment: Equipment
    public let alternateEquipment: [Equipment]
    public let defaultRepRange: ClosedRange<Int>
    public let defaultRPE: Double
    public let isCompound: Bool
    public let cues: [String]

    // VOL-105 additive fields
    public let aliases: [String]
    public let primaryMuscles: [MuscleGroup]
    public let secondaryMuscles: [MuscleGroup]
    public let difficulty: DifficultyTier
    public let unilateral: Bool
    public let lengthenedPositionEmphasis: Bool
    public let healthKitActivityType: HKActivityTypeMapping

    public init(
        id: String,
        name: String,
        pattern: MovementPattern,
        primaryEquipment: Equipment,
        alternateEquipment: [Equipment] = [],
        defaultRepRange: ClosedRange<Int>,
        defaultRPE: Double,
        isCompound: Bool,
        cues: [String],
        aliases: [String] = [],
        primaryMuscles: [MuscleGroup] = [],
        secondaryMuscles: [MuscleGroup] = [],
        difficulty: DifficultyTier = .intermediate,
        unilateral: Bool = false,
        lengthenedPositionEmphasis: Bool = false,
        healthKitActivityType: HKActivityTypeMapping? = nil
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.primaryEquipment = primaryEquipment
        self.alternateEquipment = alternateEquipment
        self.defaultRepRange = defaultRepRange
        self.defaultRPE = defaultRPE
        self.isCompound = isCompound
        self.cues = cues
        self.aliases = aliases
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.difficulty = difficulty
        self.unilateral = unilateral
        self.lengthenedPositionEmphasis = lengthenedPositionEmphasis
        self.healthKitActivityType = healthKitActivityType
            ?? Self.defaultHKType(pattern: pattern, primaryEquipment: primaryEquipment)
    }

    /// Default HealthKit activity-type mapping for an exercise.
    ///
    /// Used as the resolved value when callers don't provide an
    /// override. Core work always maps to `.core`; conditioning and
    /// mobility map to `.functional`; everything else picks
    /// traditional vs functional based on whether the implement is a
    /// loaded plate-and-pin tool (`.barbell`, `.dumbbell`, `.machine`,
    /// `.cable`) or an unloaded/rotational tool (`.bodyweight`,
    /// `.kettlebell`, `.band`).
    public static func defaultHKType(
        pattern: MovementPattern,
        primaryEquipment: Equipment
    ) -> HKActivityTypeMapping {
        switch pattern {
        case .core:
            return .core
        case .conditioning, .mobility:
            return .functional
        default:
            switch primaryEquipment {
            case .barbell, .dumbbell, .machine, .cable:
                return .traditional
            case .bodyweight, .kettlebell, .band:
                return .functional
            }
        }
    }
}

/// Expanded exercise catalog covering the major compound and isolation
/// lifts plus the modern hypertrophy-emphasis movements introduced in
/// VOL-105.
///
/// The static-let entries themselves live in
/// `ExerciseCatalog+Entries.swift` so this file stays under the
/// `file_length` warning threshold while keeping the canonical type +
/// helpers + `all` aggregation co-located.
public enum VolumeArcExerciseCatalog {

    /// Find an exercise by its ID.
    public static func exercise(withID id: String) -> ExerciseDefinition? {
        all.first { $0.id == id }
    }

    /// Find alternates for a given exercise based on available equipment.
    /// Returns exercises with the same movement pattern that can be performed
    /// with the user's available equipment.
    public static func alternatives(
        for exercise: ExerciseDefinition,
        availableEquipment: Set<Equipment>
    ) -> [ExerciseDefinition] {
        all.filter { candidate in
            candidate.id != exercise.id
            && candidate.pattern == exercise.pattern
            && (availableEquipment.contains(candidate.primaryEquipment)
                || !candidate.alternateEquipment.filter(availableEquipment.contains).isEmpty)
        }
    }
}
