import Foundation

/// Movement pattern taxonomy for exercise classification.
public enum MovementPattern: String, Sendable, CaseIterable {
    case squat
    case hinge
    case horizontalPush = "horizontal_push"
    case verticalPush = "vertical_push"
    case horizontalPull = "horizontal_pull"
    case verticalPull = "vertical_pull"
    case carry
    case isolation
    case conditioning
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

/// A single exercise with its biomechanical and programming properties.
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

    public init(
        id: String,
        name: String,
        pattern: MovementPattern,
        primaryEquipment: Equipment,
        alternateEquipment: [Equipment] = [],
        defaultRepRange: ClosedRange<Int>,
        defaultRPE: Double,
        isCompound: Bool,
        cues: [String]
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
    }
}

/// Expanded exercise catalog covering the major compound and isolation lifts.
public enum VolumeArcExerciseCatalog {

    // MARK: - Squat pattern
    public static let backSquat = ExerciseDefinition(
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
        ]
    )

    public static let frontSquat = ExerciseDefinition(
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
        ]
    )

    public static let gobletSquat = ExerciseDefinition(
        id: "goblet-squat",
        name: "Goblet Squat",
        pattern: .squat,
        primaryEquipment: .dumbbell,
        alternateEquipment: [.kettlebell],
        defaultRepRange: 8...12,
        defaultRPE: 7.0,
        isCompound: true,
        cues: ["Drive your elbows inside your knees at the bottom."]
    )

    // MARK: - Hinge pattern
    public static let deadlift = ExerciseDefinition(
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
        ]
    )

    public static let romanianDeadlift = ExerciseDefinition(
        id: "romanian-deadlift",
        name: "Romanian Deadlift",
        pattern: .hinge,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell],
        defaultRepRange: 6...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: ["Push your hips back, feel the stretch in the hamstrings."]
    )

    // MARK: - Horizontal push
    public static let benchPress = ExerciseDefinition(
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
        ]
    )

    public static let dumbbellBenchPress = ExerciseDefinition(
        id: "db-bench-press",
        name: "Dumbbell Bench Press",
        pattern: .horizontalPush,
        primaryEquipment: .dumbbell,
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: ["Stretch at the bottom, squeeze at the top."]
    )

    // MARK: - Vertical push
    public static let overheadPress = ExerciseDefinition(
        id: "overhead-press",
        name: "Overhead Press",
        pattern: .verticalPush,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell],
        defaultRepRange: 5...8,
        defaultRPE: 7.5,
        isCompound: true,
        cues: ["Squeeze your glutes, press the bar past your forehead."]
    )

    // MARK: - Horizontal pull
    public static let barbellRow = ExerciseDefinition(
        id: "barbell-row",
        name: "Barbell Row",
        pattern: .horizontalPull,
        primaryEquipment: .barbell,
        alternateEquipment: [.dumbbell, .cable],
        defaultRepRange: 6...10,
        defaultRPE: 7.5,
        isCompound: true,
        cues: ["Row to your lower chest, squeeze your back at the top."]
    )

    // MARK: - Vertical pull
    public static let pullUp = ExerciseDefinition(
        id: "pull-up",
        name: "Pull-Up",
        pattern: .verticalPull,
        primaryEquipment: .bodyweight,
        alternateEquipment: [.machine, .band],
        defaultRepRange: 5...12,
        defaultRPE: 8.0,
        isCompound: true,
        cues: ["Drive your elbows down to your ribs."]
    )

    public static let latPulldown = ExerciseDefinition(
        id: "lat-pulldown",
        name: "Lat Pulldown",
        pattern: .verticalPull,
        primaryEquipment: .cable,
        alternateEquipment: [.machine],
        defaultRepRange: 8...12,
        defaultRPE: 7.5,
        isCompound: true,
        cues: ["Start with your lats, not your biceps."]
    )

    /// All exercises in the catalog.
    public static let all: [ExerciseDefinition] = [
        backSquat, frontSquat, gobletSquat,
        deadlift, romanianDeadlift,
        benchPress, dumbbellBenchPress,
        overheadPress,
        barbellRow,
        pullUp, latPulldown,
    ]

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
