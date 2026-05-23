import Foundation

public enum TrainingProgramDifficulty: String, Codable, Sendable, CaseIterable {
    case novice
    case intermediate
    case advanced

    public var displayName: String {
        switch self {
        case .novice: return "Novice"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }
}

public enum TrainingProgramEquipmentRequirement: String, Codable, Sendable, CaseIterable {
    case barbell
    case barbellAndBodyweight = "barbell_bodyweight"
    case fullGym = "full_gym"

    public var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .barbellAndBodyweight: return "Barbell + bodyweight"
        case .fullGym: return "Full gym"
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
        self.id = id
        self.name = name
        self.author = author
        self.weeks = weeks
        self.sessionsPerWeek = sessionsPerWeek ?? sessions.count
        self.advancementCriteria = advancementCriteria
        self.difficulty = difficulty
        self.equipmentRequirement = equipmentRequirement
        self.sessions = sessions.sorted { $0.dayOfWeek < $1.dayOfWeek }
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
        guard let firstSession = sessions.first else { return nil }

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

        let rollsIntoNextWeek = next.shiftedWeekday < todayWeekday
        let rawWeek = (elapsedDays / 7) + 1 + (rollsIntoNextWeek ? 1 : 0)
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
        name: "Starting Strength",
        author: "Mark Rippetoe",
        weeks: 12,
        advancementCriteria: "Add 5 lb to upper-body lifts and 10 lb to squat/deadlift when all prescribed reps are completed.",
        difficulty: .novice,
        equipmentRequirement: .barbell,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "starting-strength-a",
                dayOfWeek: 1,
                title: "Starting Strength A",
                focus: "Squat, press, deadlift",
                exerciseNames: ["Back Squat", "Bench Press", "Deadlift"],
                prescription: "Squat 3x5, bench press 3x5, deadlift 1x5"
            ),
            TrainingProgramSessionTemplate(
                id: "starting-strength-b",
                dayOfWeek: 3,
                title: "Starting Strength B",
                focus: "Squat, press, power pull",
                exerciseNames: ["Back Squat", "Overhead Press", "Power Clean"],
                prescription: "Squat 3x5, overhead press 3x5, power clean 5x3"
            ),
            TrainingProgramSessionTemplate(
                id: "starting-strength-a2",
                dayOfWeek: 5,
                title: "Starting Strength A",
                focus: "Squat, press, deadlift",
                exerciseNames: ["Back Squat", "Bench Press", "Deadlift"],
                prescription: "Repeat Workout A and alternate A/B each session"
            ),
        ]
    )

    public static let strongLifts5x5 = TrainingProgramDefinition(
        id: "stronglifts-5x5",
        name: "StrongLifts 5x5",
        author: "Mehdi Hadim",
        weeks: 12,
        advancementCriteria: "Add 5 lb next time when every 5x5 set is completed; deload after repeated misses.",
        difficulty: .novice,
        equipmentRequirement: .barbell,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "stronglifts-a",
                dayOfWeek: 1,
                title: "StrongLifts A",
                focus: "Squat, bench, row",
                exerciseNames: ["Back Squat", "Bench Press", "Barbell Row"],
                prescription: "Squat 5x5, bench press 5x5, barbell row 5x5"
            ),
            TrainingProgramSessionTemplate(
                id: "stronglifts-b",
                dayOfWeek: 3,
                title: "StrongLifts B",
                focus: "Squat, press, deadlift",
                exerciseNames: ["Back Squat", "Overhead Press", "Deadlift"],
                prescription: "Squat 5x5, overhead press 5x5, deadlift 1x5"
            ),
            TrainingProgramSessionTemplate(
                id: "stronglifts-a2",
                dayOfWeek: 5,
                title: "StrongLifts A",
                focus: "Squat, bench, row",
                exerciseNames: ["Back Squat", "Bench Press", "Barbell Row"],
                prescription: "Repeat Workout A and alternate A/B each session"
            ),
        ]
    )

    public static let fiveThreeOneBBB = TrainingProgramDefinition(
        id: "531-bbb",
        name: "5/3/1 BBB",
        author: "Jim Wendler",
        weeks: 16,
        advancementCriteria: "Advance training maxes after each 4-week wave: +5 lb upper body, +10 lb lower body.",
        difficulty: .intermediate,
        equipmentRequirement: .barbell,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "531-press",
                dayOfWeek: 1,
                title: "5/3/1 Press",
                focus: "Press plus BBB volume",
                exerciseNames: ["Overhead Press", "Pull-Up", "Dumbbell Row"],
                prescription: "5/3/1 overhead press, 5x10 press at BBB load, 50-100 pulls"
            ),
            TrainingProgramSessionTemplate(
                id: "531-deadlift",
                dayOfWeek: 2,
                title: "5/3/1 Deadlift",
                focus: "Deadlift plus posterior chain",
                exerciseNames: ["Deadlift", "Romanian Deadlift", "Hanging Leg Raise"],
                prescription: "5/3/1 deadlift, 5x10 deadlift at BBB load, trunk work"
            ),
            TrainingProgramSessionTemplate(
                id: "531-bench",
                dayOfWeek: 4,
                title: "5/3/1 Bench",
                focus: "Bench plus upper volume",
                exerciseNames: ["Bench Press", "Dumbbell Bench Press", "Barbell Row"],
                prescription: "5/3/1 bench, 5x10 bench at BBB load, 50-100 rows"
            ),
            TrainingProgramSessionTemplate(
                id: "531-squat",
                dayOfWeek: 5,
                title: "5/3/1 Squat",
                focus: "Squat plus lower volume",
                exerciseNames: ["Back Squat", "Front Squat", "Back Extension"],
                prescription: "5/3/1 squat, 5x10 squat at BBB load, single-leg or trunk assistance"
            ),
        ]
    )

    public static let pushPullLegs6Day = TrainingProgramDefinition(
        id: "ppl-6-day",
        name: "PPL 6-day",
        author: "VolumeArc",
        weeks: 10,
        advancementCriteria: "Add load when all sets land in the top half of the rep target at RPE 8 or lower.",
        difficulty: .intermediate,
        equipmentRequirement: .fullGym,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "ppl-push-a",
                dayOfWeek: 1,
                title: "Push A",
                focus: "Chest, shoulders, triceps",
                exerciseNames: ["Bench Press", "Overhead Press", "Cable Fly", "Triceps Pushdown"],
                prescription: "Bench 4x6-8, overhead press 3x6-8, fly 3x10-15, triceps 3x10-15"
            ),
            TrainingProgramSessionTemplate(
                id: "ppl-pull-a",
                dayOfWeek: 2,
                title: "Pull A",
                focus: "Back, rear delts, biceps",
                exerciseNames: ["Barbell Row", "Pull-Up", "Rear Delt Fly", "Barbell Curl"],
                prescription: "Row 4x6-8, pull-up 4x6-10, rear delt 3x12-20, curls 3x8-12"
            ),
            TrainingProgramSessionTemplate(
                id: "ppl-legs-a",
                dayOfWeek: 3,
                title: "Legs A",
                focus: "Squat emphasis",
                exerciseNames: ["Back Squat", "Romanian Deadlift", "Leg Press", "Calf Raise"],
                prescription: "Squat 4x5-8, RDL 3x8-10, leg press 3x10-15, calves 4x8-15"
            ),
            TrainingProgramSessionTemplate(
                id: "ppl-push-b",
                dayOfWeek: 4,
                title: "Push B",
                focus: "Incline and delts",
                exerciseNames: ["Incline Dumbbell Press", "Lateral Raise", "Machine Chest Press", "Skullcrusher"],
                prescription: "Incline press 4x8-10, laterals 4x12-20, machine press 3x10-12, skullcrusher 3x10-15"
            ),
            TrainingProgramSessionTemplate(
                id: "ppl-pull-b",
                dayOfWeek: 5,
                title: "Pull B",
                focus: "Vertical pull and arms",
                exerciseNames: ["Lat Pulldown", "Seated Cable Row", "Face Pull", "Hammer Curl"],
                prescription: "Pulldown 4x8-12, cable row 3x8-12, face pull 3x12-20, hammer curl 3x10-15"
            ),
            TrainingProgramSessionTemplate(
                id: "ppl-legs-b",
                dayOfWeek: 6,
                title: "Legs B",
                focus: "Hinge and quad volume",
                exerciseNames: ["Deadlift", "Front Squat", "Leg Curl", "Calf Raise"],
                prescription: "Deadlift 3x3-5, front squat 3x6-8, leg curl 4x10-15, calves 4x10-15"
            ),
        ]
    )

    public static let upperLower4Day = TrainingProgramDefinition(
        id: "upper-lower-4-day",
        name: "Upper/Lower 4-day",
        author: "VolumeArc",
        weeks: 12,
        advancementCriteria: "Progress compounds weekly when top sets stay under RPE 8.5; progress isolation work by reps first.",
        difficulty: .intermediate,
        equipmentRequirement: .fullGym,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "upper-lower-upper-strength",
                dayOfWeek: 1,
                title: "Upper Strength",
                focus: "Heavy press and pull",
                exerciseNames: ["Bench Press", "Barbell Row", "Overhead Press", "Pull-Up"],
                prescription: "Bench 4x4-6, row 4x5-8, press 3x5-8, pull-up 3x6-10"
            ),
            TrainingProgramSessionTemplate(
                id: "upper-lower-lower-strength",
                dayOfWeek: 2,
                title: "Lower Strength",
                focus: "Squat and hinge strength",
                exerciseNames: ["Back Squat", "Deadlift", "Bulgarian Split Squat", "Calf Raise"],
                prescription: "Squat 4x4-6, deadlift 3x3-5, split squat 3x8-10, calves 4x8-12"
            ),
            TrainingProgramSessionTemplate(
                id: "upper-lower-upper-volume",
                dayOfWeek: 4,
                title: "Upper Volume",
                focus: "Hypertrophy press and pull",
                exerciseNames: ["Incline Dumbbell Press", "Lat Pulldown", "Lateral Raise", "Cable Curl"],
                prescription: "Incline 4x8-12, pulldown 4x8-12, laterals 4x12-20, curls 3x10-15"
            ),
            TrainingProgramSessionTemplate(
                id: "upper-lower-lower-volume",
                dayOfWeek: 5,
                title: "Lower Volume",
                focus: "Leg volume",
                exerciseNames: ["Front Squat", "Romanian Deadlift", "Leg Press", "Leg Curl"],
                prescription: "Front squat 4x6-10, RDL 3x8-12, leg press 3x10-15, leg curl 3x10-15"
            ),
        ]
    )

    public static let hypertrophySpecificTraining = TrainingProgramDefinition(
        id: "hst",
        name: "Hypertrophy Specific Training",
        author: "Bryan Haycock",
        weeks: 8,
        advancementCriteria: "Wave loads across 15s, 10s, and 5s; increase load every session while preserving full-body frequency.",
        difficulty: .advanced,
        equipmentRequirement: .fullGym,
        sessions: [
            TrainingProgramSessionTemplate(
                id: "hst-a",
                dayOfWeek: 1,
                title: "HST Full Body A",
                focus: "Full-body 15s/10s/5s wave",
                exerciseNames: ["Back Squat", "Bench Press", "Barbell Row", "Romanian Deadlift"],
                prescription: "Full body 1-2 sets each: squat, bench, row, hinge; wave reps by block"
            ),
            TrainingProgramSessionTemplate(
                id: "hst-b",
                dayOfWeek: 3,
                title: "HST Full Body B",
                focus: "Full-body alternate angles",
                exerciseNames: ["Front Squat", "Incline Dumbbell Press", "Lat Pulldown", "Leg Curl"],
                prescription: "Full body 1-2 sets each: quad, incline press, vertical pull, hamstring curl"
            ),
            TrainingProgramSessionTemplate(
                id: "hst-c",
                dayOfWeek: 5,
                title: "HST Full Body C",
                focus: "Full-body pump and progression",
                exerciseNames: ["Leg Press", "Machine Chest Press", "Seated Cable Row", "Lateral Raise"],
                prescription: "Full body 1-2 sets each: leg press, chest press, row, delts; keep load moving upward"
            ),
        ]
    )
}
