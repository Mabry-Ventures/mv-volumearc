import Foundation

public enum TrainingProgramDifficulty: String, Codable, Sendable, CaseIterable {
    case novice
    case intermediate
    case advanced

    public var displayName: String {
        switch self {
        case .novice:
            return String(localized: "Novice", comment: "Training program difficulty for beginner lifters")
        case .intermediate:
            return String(localized: "Intermediate", comment: "Training program difficulty for experienced lifters")
        case .advanced:
            return String(localized: "Advanced", comment: "Training program difficulty for advanced lifters")
        }
    }
}

public enum TrainingProgramEquipmentRequirement: String, Codable, Sendable, CaseIterable {
    case barbell
    case barbellAndBodyweight = "barbell_bodyweight"
    case fullGym = "full_gym"

    public var displayName: String {
        switch self {
        case .barbell:
            return String(localized: "Barbell", comment: "Training program equipment requirement")
        case .barbellAndBodyweight:
            return String(localized: "Barbell + bodyweight", comment: "Training program equipment requirement")
        case .fullGym:
            return String(localized: "Full gym", comment: "Training program equipment requirement")
        }
    }
}

public struct TrainingProgramSessionTemplate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let dayOfWeek: Int
    public let title: String
    public let focus: String
    public let exerciseNames: [String]
    public let prescription: String

    public init(
        id: String,
        dayOfWeek: Int,
        title: String,
        focus: String,
        exerciseNames: [String],
        prescription: String
    ) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.title = title
        self.focus = focus
        self.exerciseNames = exerciseNames
        self.prescription = prescription
    }
}

public struct TrainingProgramDefinition: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let author: String
    public let weeks: Int
    public let sessionsPerWeek: Int
    public let advancementCriteria: String
    public let difficulty: TrainingProgramDifficulty
    public let equipmentRequirement: TrainingProgramEquipmentRequirement
    public let sessions: [TrainingProgramSessionTemplate]

    public init(
        id: String,
        name: String,
        author: String,
        weeks: Int,
        sessionsPerWeek: Int? = nil,
        advancementCriteria: String,
        difficulty: TrainingProgramDifficulty,
        equipmentRequirement: TrainingProgramEquipmentRequirement,
        sessions: [TrainingProgramSessionTemplate]
    ) {
        let resolvedSessionsPerWeek = sessionsPerWeek ?? sessions.count
        precondition(weeks > 0, "Training program weeks must be greater than zero")
        precondition((1...7).contains(resolvedSessionsPerWeek), "Training program sessionsPerWeek must be 1...7")
        precondition(sessions.count == resolvedSessionsPerWeek, "Training program sessions must match sessionsPerWeek")
        precondition(sessions.allSatisfy { (1...7).contains($0.dayOfWeek) }, "Training program days must be 1...7")
        precondition(
            Set(sessions.map(\.dayOfWeek)).count == sessions.count,
            "Training program sessions must have unique days"
        )
        self.id = id
        self.name = name
        self.author = author
        self.weeks = weeks
        self.sessionsPerWeek = resolvedSessionsPerWeek
        self.advancementCriteria = advancementCriteria
        self.difficulty = difficulty
        self.equipmentRequirement = equipmentRequirement
        self.sessions = sessions.sorted { $0.dayOfWeek < $1.dayOfWeek }
    }

    static func isValid(weeks: Int, sessionsPerWeek: Int, sessions: [TrainingProgramSessionTemplate]) -> Bool {
        weeks > 0
            && (1...7).contains(sessionsPerWeek)
            && sessions.count == sessionsPerWeek
            && sessions.allSatisfy { (1...7).contains($0.dayOfWeek) }
            && Set(sessions.map(\.dayOfWeek)).count == sessions.count
    }

    public func weeklyWorkouts(startingOn startDate: Date = .now, calendar: Calendar = .current) -> [WeeklyWorkout] {
        let startWeekday = WeeklyWorkout.trainingWeekday(for: startDate, calendar: calendar)
        return sessions.map { session in
            WeeklyWorkout(
                dayOfWeek: shiftedWeekday(for: session, startWeekday: startWeekday),
                title: session.title
            )
        }
        .sorted { $0.dayOfWeek < $1.dayOfWeek }
    }

    public func scheduledSession(
        on date: Date = .now,
        assignedAt: Date,
        calendar: Calendar = .current
    ) -> ActiveTrainingProgramContext? {
        guard sessions.isEmpty == false else { return nil }

        let startDay = calendar.startOfDay(for: assignedAt)
        let targetDay = calendar.startOfDay(for: date)
        let elapsedDays = max(0, calendar.dateComponents([.day], from: startDay, to: targetDay).day ?? 0)
        let startWeekday = WeeklyWorkout.trainingWeekday(for: assignedAt, calendar: calendar)
        let todayWeekday = WeeklyWorkout.trainingWeekday(for: date, calendar: calendar)

        let shiftedSessions = sessions.enumerated().map { index, session in
            ShiftedSession(
                session: session,
                dayNumber: index + 1,
                shiftedWeekday: shiftedWeekday(for: session, startWeekday: startWeekday)
            )
        }
        .sorted { $0.shiftedWeekday < $1.shiftedWeekday }

        guard let next = shiftedSessions.first(where: { $0.shiftedWeekday >= todayWeekday })
            ?? shiftedSessions.first
        else {
            return nil
        }

        let baseWeek = (elapsedDays / 7) + 1
        let rollsIntoNextWeek = next.dayNumber == 1 && elapsedDays % 7 != 0
        let rawWeek = baseWeek + (rollsIntoNextWeek ? 1 : 0)
        let weekNumber = min(max(1, rawWeek), max(1, weeks))

        return ActiveTrainingProgramContext(
            programID: id,
            programName: name,
            author: author,
            weekNumber: weekNumber,
            totalWeeks: weeks,
            dayNumber: next.dayNumber,
            sessionsPerWeek: sessionsPerWeek,
            sessionTitle: next.session.title,
            sessionFocus: next.session.focus,
            prescription: next.session.prescription,
            advancementCriteria: advancementCriteria
        )
    }

    private func shiftedWeekday(for session: TrainingProgramSessionTemplate, startWeekday: Int) -> Int {
        guard let firstDefaultWeekday = sessions.first?.dayOfWeek else {
            return session.dayOfWeek
        }
        let offset = (session.dayOfWeek - firstDefaultWeekday + 7) % 7
        return ((startWeekday - 1 + offset) % 7) + 1
    }

    private struct ShiftedSession {
        let session: TrainingProgramSessionTemplate
        let dayNumber: Int
        let shiftedWeekday: Int
    }
}

public struct ActiveTrainingProgramContext: Sendable, Equatable {
    public let programID: String
    public let programName: String
    public let author: String
    public let weekNumber: Int
    public let totalWeeks: Int
    public let dayNumber: Int
    public let sessionsPerWeek: Int
    public let sessionTitle: String
    public let sessionFocus: String
    public let prescription: String
    public let advancementCriteria: String

    public init(
        programID: String,
        programName: String,
        author: String,
        weekNumber: Int,
        totalWeeks: Int,
        dayNumber: Int,
        sessionsPerWeek: Int,
        sessionTitle: String,
        sessionFocus: String,
        prescription: String,
        advancementCriteria: String
    ) {
        self.programID = programID
        self.programName = programName
        self.author = author
        self.weekNumber = weekNumber
        self.totalWeeks = totalWeeks
        self.dayNumber = dayNumber
        self.sessionsPerWeek = sessionsPerWeek
        self.sessionTitle = sessionTitle
        self.sessionFocus = sessionFocus
        self.prescription = prescription
        self.advancementCriteria = advancementCriteria
    }

    public var promptFragment: String {
        """
        ## Active program
        - Program: \(programName) by \(author)
        - Position: Week \(weekNumber) / \(totalWeeks), Day \(dayNumber) / \(sessionsPerWeek)
        - Session: \(sessionTitle) (\(sessionFocus))
        - Today's prescription: \(prescription)
        - Advancement: \(advancementCriteria)
        """
    }
}

public enum TrainingProgramCatalog {
    private static func localizedCatalogText(
        _ value: String.LocalizationValue,
        comment: StaticString
    ) -> String {
        String(localized: value, comment: comment)
    }

    public static let curated: [TrainingProgramDefinition] = [
        startingStrength,
        strongLifts5x5,
        fiveThreeOneBBB,
        pushPullLegs6Day,
        upperLower4Day,
        hypertrophySpecificTraining,
    ]

    public static func program(id: String) -> TrainingProgramDefinition? {
        curated.first { $0.id == id }
    }

    public static let startingStrength = TrainingProgramDefinition(
        id: "starting-strength",
        name: localizedCatalogText("Starting Strength", comment: "Training program name"),
        author: localizedCatalogText("Mark Rippetoe", comment: "Training program author"),
        weeks: 12,
        advancementCriteria: localizedCatalogText(
            "Add 5 lb to upper-body lifts and 10 lb to squat/deadlift when all prescribed reps are completed.",
            comment: "Training program progression rule"
        ),
        difficulty: .novice,
        equipmentRequirement: .barbell,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "starting-strength-a",
                dayOfWeek: 1,
                title: localizedCatalogText("Starting Strength A", comment: "Training program session title"),
                focus: localizedCatalogText("Squat, press, deadlift", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Back Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Bench Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Deadlift", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Squat 3x5, bench press 3x5, deadlift 1x5",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "starting-strength-b",
                dayOfWeek: 3,
                title: localizedCatalogText("Starting Strength B", comment: "Training program session title"),
                focus: localizedCatalogText("Squat, press, power pull", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Back Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Overhead Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Power Clean", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Squat 3x5, overhead press 3x5, power clean 5x3",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "starting-strength-a2",
                dayOfWeek: 5,
                title: localizedCatalogText("Starting Strength A", comment: "Training program session title"),
                focus: localizedCatalogText("Squat, press, deadlift", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Back Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Bench Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Deadlift", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Repeat Workout A and alternate A/B each session",
                    comment: "Training program prescription"
                )
            ),
        ]
    )

    public static let strongLifts5x5 = TrainingProgramDefinition(
        id: "stronglifts-5x5",
        name: localizedCatalogText("StrongLifts 5x5", comment: "Training program name"),
        author: localizedCatalogText("Mehdi Hadim", comment: "Training program author"),
        weeks: 12,
        advancementCriteria: localizedCatalogText(
            "Add 5 lb next time when every 5x5 set is completed; deload after repeated misses.",
            comment: "Training program progression rule"
        ),
        difficulty: .novice,
        equipmentRequirement: .barbell,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "stronglifts-a",
                dayOfWeek: 1,
                title: localizedCatalogText("StrongLifts A", comment: "Training program session title"),
                focus: localizedCatalogText("Squat, bench, row", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Back Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Bench Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Barbell Row", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Squat 5x5, bench press 5x5, barbell row 5x5",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "stronglifts-b",
                dayOfWeek: 3,
                title: localizedCatalogText("StrongLifts B", comment: "Training program session title"),
                focus: localizedCatalogText("Squat, press, deadlift", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Back Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Overhead Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Deadlift", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Squat 5x5, overhead press 5x5, deadlift 1x5",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "stronglifts-a2",
                dayOfWeek: 5,
                title: localizedCatalogText("StrongLifts A", comment: "Training program session title"),
                focus: localizedCatalogText("Squat, bench, row", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Back Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Bench Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Barbell Row", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Repeat Workout A and alternate A/B each session",
                    comment: "Training program prescription"
                )
            ),
        ]
    )

    public static let fiveThreeOneBBB = TrainingProgramDefinition(
        id: "531-bbb",
        name: localizedCatalogText("5/3/1 BBB", comment: "Training program name"),
        author: localizedCatalogText("Jim Wendler", comment: "Training program author"),
        weeks: 16,
        advancementCriteria: localizedCatalogText(
            "Advance training maxes after each 4-week wave: +5 lb upper body, +10 lb lower body.",
            comment: "Training program progression rule"
        ),
        difficulty: .intermediate,
        equipmentRequirement: .barbell,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "531-press",
                dayOfWeek: 1,
                title: localizedCatalogText("5/3/1 Press", comment: "Training program session title"),
                focus: localizedCatalogText("Press plus BBB volume", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Overhead Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Pull-Up", comment: "Exercise name in training program"),
                    localizedCatalogText("Dumbbell Row", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "5/3/1 overhead press, 5x10 press at BBB load, 50-100 pulls",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "531-deadlift",
                dayOfWeek: 2,
                title: localizedCatalogText("5/3/1 Deadlift", comment: "Training program session title"),
                focus: localizedCatalogText("Deadlift plus posterior chain", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Deadlift", comment: "Exercise name in training program"),
                    localizedCatalogText("Romanian Deadlift", comment: "Exercise name in training program"),
                    localizedCatalogText("Hanging Leg Raise", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "5/3/1 deadlift, 5x10 deadlift at BBB load, trunk work",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "531-bench",
                dayOfWeek: 4,
                title: localizedCatalogText("5/3/1 Bench", comment: "Training program session title"),
                focus: localizedCatalogText("Bench plus upper volume", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Bench Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Dumbbell Bench Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Barbell Row", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "5/3/1 bench, 5x10 bench at BBB load, 50-100 rows",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "531-squat",
                dayOfWeek: 5,
                title: localizedCatalogText("5/3/1 Squat", comment: "Training program session title"),
                focus: localizedCatalogText("Squat plus lower volume", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Back Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Front Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Back Extension", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "5/3/1 squat, 5x10 squat at BBB load, single-leg or trunk assistance",
                    comment: "Training program prescription"
                )
            ),
        ]
    )

    public static let pushPullLegs6Day = TrainingProgramDefinition(
        id: "ppl-6-day",
        name: localizedCatalogText("PPL 6-day", comment: "Training program name"),
        author: localizedCatalogText("VolumeArc", comment: "Training program author"),
        weeks: 10,
        advancementCriteria: localizedCatalogText(
            "Add load when all sets land in the top half of the rep target at RPE 8 or lower.",
            comment: "Training program progression rule"
        ),
        difficulty: .intermediate,
        equipmentRequirement: .fullGym,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "ppl-push-a",
                dayOfWeek: 1,
                title: localizedCatalogText("Push A", comment: "Training program session title"),
                focus: localizedCatalogText("Chest, shoulders, triceps", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Bench Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Overhead Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Cable Fly", comment: "Exercise name in training program"),
                    localizedCatalogText("Triceps Pushdown", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Bench 4x6-8, overhead press 3x6-8, fly 3x10-15, triceps 3x10-15",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "ppl-pull-a",
                dayOfWeek: 2,
                title: localizedCatalogText("Pull A", comment: "Training program session title"),
                focus: localizedCatalogText("Back, rear delts, biceps", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Barbell Row", comment: "Exercise name in training program"),
                    localizedCatalogText("Pull-Up", comment: "Exercise name in training program"),
                    localizedCatalogText("Rear Delt Fly", comment: "Exercise name in training program"),
                    localizedCatalogText("Barbell Curl", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Row 4x6-8, pull-up 4x6-10, rear delt 3x12-20, curls 3x8-12",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "ppl-legs-a",
                dayOfWeek: 3,
                title: localizedCatalogText("Legs A", comment: "Training program session title"),
                focus: localizedCatalogText("Squat emphasis", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Back Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Romanian Deadlift", comment: "Exercise name in training program"),
                    localizedCatalogText("Leg Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Calf Raise", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Squat 4x5-8, RDL 3x8-10, leg press 3x10-15, calves 4x8-15",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "ppl-push-b",
                dayOfWeek: 4,
                title: localizedCatalogText("Push B", comment: "Training program session title"),
                focus: localizedCatalogText("Incline and delts", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Incline Dumbbell Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Lateral Raise", comment: "Exercise name in training program"),
                    localizedCatalogText("Machine Chest Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Skullcrusher", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Incline press 4x8-10, laterals 4x12-20, machine press 3x10-12, skullcrusher 3x10-15",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "ppl-pull-b",
                dayOfWeek: 5,
                title: localizedCatalogText("Pull B", comment: "Training program session title"),
                focus: localizedCatalogText("Vertical pull and arms", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Lat Pulldown", comment: "Exercise name in training program"),
                    localizedCatalogText("Seated Cable Row", comment: "Exercise name in training program"),
                    localizedCatalogText("Face Pull", comment: "Exercise name in training program"),
                    localizedCatalogText("Hammer Curl", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Pulldown 4x8-12, cable row 3x8-12, face pull 3x12-20, hammer curl 3x10-15",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "ppl-legs-b",
                dayOfWeek: 6,
                title: localizedCatalogText("Legs B", comment: "Training program session title"),
                focus: localizedCatalogText("Hinge and quad volume", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Deadlift", comment: "Exercise name in training program"),
                    localizedCatalogText("Front Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Leg Curl", comment: "Exercise name in training program"),
                    localizedCatalogText("Calf Raise", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Deadlift 3x3-5, front squat 3x6-8, leg curl 4x10-15, calves 4x10-15",
                    comment: "Training program prescription"
                )
            ),
        ]
    )

    public static let upperLower4Day = TrainingProgramDefinition(
        id: "upper-lower-4-day",
        name: localizedCatalogText("Upper/Lower 4-day", comment: "Training program name"),
        author: localizedCatalogText("VolumeArc", comment: "Training program author"),
        weeks: 12,
        advancementCriteria: localizedCatalogText(
            "Progress compounds weekly when top sets stay under RPE 8.5; progress isolation work by reps first.",
            comment: "Training program progression rule"
        ),
        difficulty: .intermediate,
        equipmentRequirement: .fullGym,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "upper-lower-upper-strength",
                dayOfWeek: 1,
                title: localizedCatalogText("Upper Strength", comment: "Training program session title"),
                focus: localizedCatalogText("Heavy press and pull", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Bench Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Barbell Row", comment: "Exercise name in training program"),
                    localizedCatalogText("Overhead Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Pull-Up", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Bench 4x4-6, row 4x5-8, press 3x5-8, pull-up 3x6-10",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "upper-lower-lower-strength",
                dayOfWeek: 2,
                title: localizedCatalogText("Lower Strength", comment: "Training program session title"),
                focus: localizedCatalogText("Squat and hinge strength", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Back Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Deadlift", comment: "Exercise name in training program"),
                    localizedCatalogText("Bulgarian Split Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Calf Raise", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Squat 4x4-6, deadlift 3x3-5, split squat 3x8-10, calves 4x8-12",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "upper-lower-upper-volume",
                dayOfWeek: 4,
                title: localizedCatalogText("Upper Volume", comment: "Training program session title"),
                focus: localizedCatalogText("Hypertrophy press and pull", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Incline Dumbbell Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Lat Pulldown", comment: "Exercise name in training program"),
                    localizedCatalogText("Lateral Raise", comment: "Exercise name in training program"),
                    localizedCatalogText("Cable Curl", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Incline 4x8-12, pulldown 4x8-12, laterals 4x12-20, curls 3x10-15",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "upper-lower-lower-volume",
                dayOfWeek: 5,
                title: localizedCatalogText("Lower Volume", comment: "Training program session title"),
                focus: localizedCatalogText("Leg volume", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Front Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Romanian Deadlift", comment: "Exercise name in training program"),
                    localizedCatalogText("Leg Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Leg Curl", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Front squat 4x6-10, RDL 3x8-12, leg press 3x10-15, leg curl 3x10-15",
                    comment: "Training program prescription"
                )
            ),
        ]
    )

    public static let hypertrophySpecificTraining = TrainingProgramDefinition(
        id: "hst",
        name: localizedCatalogText("Hypertrophy Specific Training", comment: "Training program name"),
        author: localizedCatalogText("Bryan Haycock", comment: "Training program author"),
        weeks: 8,
        advancementCriteria: localizedCatalogText(
            "Wave loads across 15s, 10s, and 5s; increase load every session while preserving full-body frequency.",
            comment: "Training program progression rule"
        ),
        difficulty: .advanced,
        equipmentRequirement: .fullGym,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "hst-a",
                dayOfWeek: 1,
                title: localizedCatalogText("HST Full Body A", comment: "Training program session title"),
                focus: localizedCatalogText("Full-body 15s/10s/5s wave", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Back Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Bench Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Barbell Row", comment: "Exercise name in training program"),
                    localizedCatalogText("Romanian Deadlift", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Full body 1-2 sets each: squat, bench, row, hinge; wave reps by block",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "hst-b",
                dayOfWeek: 3,
                title: localizedCatalogText("HST Full Body B", comment: "Training program session title"),
                focus: localizedCatalogText("Full-body alternate angles", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Front Squat", comment: "Exercise name in training program"),
                    localizedCatalogText("Incline Dumbbell Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Lat Pulldown", comment: "Exercise name in training program"),
                    localizedCatalogText("Leg Curl", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Full body 1-2 sets each: quad, incline press, vertical pull, hamstring curl",
                    comment: "Training program prescription"
                )
            ),
            TrainingProgramSessionTemplate(
                id: "hst-c",
                dayOfWeek: 5,
                title: localizedCatalogText("HST Full Body C", comment: "Training program session title"),
                focus: localizedCatalogText("Full-body pump and progression", comment: "Training program session focus"),
                exerciseNames: [
                    localizedCatalogText("Leg Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Machine Chest Press", comment: "Exercise name in training program"),
                    localizedCatalogText("Seated Cable Row", comment: "Exercise name in training program"),
                    localizedCatalogText("Lateral Raise", comment: "Exercise name in training program"),
                ],
                prescription: localizedCatalogText(
                    "Full body 1-2 sets each: leg press, chest press, row, delts; keep load moving upward",
                    comment: "Training program prescription"
                )
            ),
        ]
    )
}
