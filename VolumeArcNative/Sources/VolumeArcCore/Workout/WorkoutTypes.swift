import Foundation

public enum WorkoutAction: String, Sendable, CaseIterable, Codable {
    case increase
    case hold
    case decrease
}

public enum AdvancementLevel: String, Sendable, CaseIterable, Codable {
    case beginner
    case intermediate
    case advanced
}

public enum CoachingStyle: String, Sendable, CaseIterable, Codable {
    case motivational
    case analytical
    case minimal
}

public enum PrivacyMode: String, Sendable, CaseIterable, Codable {
    case standard
    case strict
}

public struct WorkoutTarget: Sendable, Equatable {
    public let weight: Double
    public let unit: String
    public let repRange: ClosedRange<Int>
    public let targetRPE: Double

    public init(weight: Double, unit: String, repRange: ClosedRange<Int>, targetRPE: Double) {
        self.weight = weight
        self.unit = unit
        self.repRange = repRange
        self.targetRPE = targetRPE
    }
}

public struct WorkoutAutopilotState: Sendable {
    public let nextExerciseID: String
    public let nextExerciseName: String
    public let nextTarget: WorkoutTarget
    public let bestCue: String
    public let recommendationReason: String
    public let suggestedAction: WorkoutAction

    public init(
        nextExerciseID: String,
        nextExerciseName: String,
        nextTarget: WorkoutTarget,
        bestCue: String,
        recommendationReason: String,
        suggestedAction: WorkoutAction = .hold
    ) {
        self.nextExerciseID = nextExerciseID
        self.nextExerciseName = nextExerciseName
        self.nextTarget = nextTarget
        self.bestCue = bestCue
        self.recommendationReason = recommendationReason
        self.suggestedAction = suggestedAction
    }
}

/// How a workout plan reached a persistence or session-start chokepoint.
/// The `.coach` case gates the VOL-284 prescription-clamp backstop, so
/// this is deliberately an enum (PR #363 review) — a string-literal typo
/// at a call site would otherwise silently skip a safety branch. The raw
/// value feeds telemetry metadata.
public enum WorkoutPlanSource: String, Sendable, Equatable {
    case manual
    case coach
    case workoutsBuilder = "workouts_builder"
}

public enum CoachWorkoutPlanExtractor {
    public static func plan(from response: String, title: String) -> WorkoutSessionPlan? {
        let exercises = response
            .split(whereSeparator: \.isNewline)
            .compactMap { exercise(from: String($0), response: response) }
            .prefix(8)
        guard !exercises.isEmpty else { return nil }

        let exerciseList = Array(exercises)
        let targetRPE = conservativeResponse(response) ? 6 : 7
        return WorkoutSessionPlan(
            title: title,
            durationMinutes: min(75, max(20, exerciseList.count * 10)),
            targetRPE: targetRPE,
            exercises: exerciseList
        )
    }

    private static func exercise(from line: String, response: String) -> WeeklyWorkoutExercise? {
        let trimmed = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-* "))
        let normalizedLine = lineWithoutListMarker(trimmed)
        let seconds = firstInt(matching: #"(\d+)\s*seconds?"#, in: normalizedLine)
        let setRep = setRepPair(in: normalizedLine)
        guard trimmed.range(of: "rep", options: .caseInsensitive) != nil
                || seconds != nil
                || setRep != nil
        else { return nil }

        guard let name = exerciseName(from: normalizedLine),
              !name.isEmpty,
              // "Rest 90 seconds between sets" is an instruction, not a
              // movement — a bogus "Rest" exercise must never reach a
              // schedule or template (PR #363 review, Codex P2). Prefix
              // match: "Rest for", "Warm-up", "Cool down" all qualify.
              !isRestInstructionName(name),
              let sets = firstInt(matching: #"(\d+)\s*sets?"#, in: normalizedLine)
                ?? setRep?.sets
                ?? (seconds == nil ? nil : 1)
        else { return nil }

        let reps = firstInt(matching: #"(\d+)\s*reps?"#, in: normalizedLine)
            ?? setRep?.reps
            ?? seconds
            ?? 1
        let targetRPE = conservativeResponse(response) ? 6 : 7
        let weight = firstInt(matching: #"(\d+)\s*(?:lb|lbs|pounds?)"#, in: normalizedLine)
            ?? defaultWeight(for: name, response: response)
        return WeeklyWorkoutExercise(
            name: name,
            sets: max(1, min(sets, 8)),
            reps: max(1, min(reps, 50)),
            weight: max(0, weight),
            targetRPE: targetRPE,
            restSeconds: targetRPE <= 6 ? 75 : 120
        )
    }

    private static func lineWithoutListMarker(_ line: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"^\s*(?:\d+[\.)]|[A-Za-z][\.)])\s+"#,
            options: []
        ) else { return line }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex
            .stringByReplacingMatches(in: line, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func exerciseName(from line: String) -> String? {
        let delimiterRanges = [
            line.range(of: ":"),
            line.range(of: " - "),
            line.range(of: " -- "),
            line.range(of: " \u{2013} "),
            line.range(of: " \u{2014} "),
        ].compactMap { $0 }
        let rawName: Substring
        if let delimiter = delimiterRanges.min(by: { $0.lowerBound < $1.lowerBound }) {
            rawName = line[..<delimiter.lowerBound]
        } else if let prescriptionRange = firstPrescriptionRange(in: line) {
            rawName = line[..<prescriptionRange.lowerBound]
        } else {
            return nil
        }
        let name = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.localizedCaseInsensitiveContains("sample workout") else { return nil }
        guard !name.localizedCaseInsensitiveContains("workout plan") else { return nil }
        return name
    }

    private static func firstPrescriptionRange(in text: String) -> Range<String.Index>? {
        let patterns = [
            #"(\d+)\s*(?:x|×)\s*\d+"#,
            #"\d+\s*sets?"#,
            #"\d+\s*seconds?"#,
        ]
        return patterns
            .compactMap { firstMatchRange(matching: $0, in: text) }
            .min(by: { $0.lowerBound < $1.lowerBound })
    }

    private static func firstMatchRange(matching pattern: String, in text: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return Range(match.range, in: text)
    }

    private static func firstInt(matching pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[matchRange])
    }

    private static func isRestInstructionName(_ name: String) -> Bool {
        // Instruction-shaped only: the rest word ends the name or leads
        // into instruction phrasing. "Rest-Pause Bench Press" is a real
        // movement and must keep parsing (PR #363 review).
        name.range(
            of: #"^(?:rest|cool[\s-]?down|warm[\s-]?up)(?:$|\s+(?:for|period|between|\d))"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func setRepPair(in text: String) -> (sets: Int, reps: Int)? {
        // PR #363 review (Codex P2): the two forms need different
        // out-of-range policies. A bare "3x315" is usually load-by-rep
        // confusion, so the strict guard rejects the whole pair. But
        // "10 sets of 3" is unambiguous — discarding it made the caller
        // fall back to firstInt("sets") with reps defaulting to 1
        // (8x1 instead of the intended capped 8x3), silently changing
        // the workout volume. The worded form clamps sets and keeps the
        // captured reps instead.
        let patterns: [(pattern: String, clampsSets: Bool)] = [
            (#"(\d+)\s*(?:x|×)\s*(\d+)"#, false),
            (#"(\d+)\s*sets?\s*(?:of|x|×)?\s*(\d+)"#, true),
        ]
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for (pattern, clampsSets) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: range)
            else { continue }
            guard match.numberOfRanges > 2,
                  let setsRange = Range(match.range(at: 1), in: text),
                  let repsRange = Range(match.range(at: 2), in: text),
                  let sets = Int(text[setsRange]),
                  let reps = Int(text[repsRange])
            else { continue }
            guard (1...100).contains(reps) else { continue }
            if clampsSets {
                guard sets >= 1 else { continue }
                return (min(sets, 8), reps)
            }
            guard (1...8).contains(sets) else { continue }
            return (sets, reps)
        }
        return nil
    }

    private static func conservativeResponse(_ response: String) -> Bool {
        let lowered = response.lowercased()
        return lowered.contains("light")
            || lowered.contains("easy")
            || lowered.contains("sick")
            || lowered.contains("sore")
            || lowered.contains("pain")
            || lowered.contains("tight")
            || lowered.contains("run down")
            || lowered.contains("rpe 6")
    }

    private static func defaultWeight(for name: String, response: String) -> Int {
        let loweredName = name.lowercased()
        let isConservative = conservativeResponse(response)
        if loweredName.contains("dumbbell") {
            return isConservative ? 20 : 35
        }
        if loweredName.contains("barbell")
            || loweredName.contains("squat")
            || loweredName.contains("deadlift")
            || loweredName.contains("bench") {
            return isConservative ? 45 : 95
        }
        return 0
    }
}

public struct ReadinessAssessment: Sendable {
    public let score: Int
    public let brief: String
    public let factors: [Factor]

    public struct Factor: Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let impact: Int  // -100 to +100
        public let detail: String

        public init(name: String, impact: Int, detail: String) {
            self.name = name
            self.impact = impact
            self.detail = detail
        }
    }

    public init(score: Int, brief: String, factors: [Factor] = []) {
        self.score = score
        self.brief = brief
        self.factors = factors
    }
}

public struct WorkoutSetPerformance: Codable, Sendable, Equatable {
    public let weight: Double
    public let reps: Int
    public let rpe: Double
    public let completedAt: Date

    public init(weight: Double, reps: Int, rpe: Double, completedAt: Date) {
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.completedAt = completedAt
    }
}

public struct WatchWorkoutSyncPayload: Codable, Sendable {
    public let workoutID: String
    public let receivedAt: Date
    public let title: String
    public let exerciseID: String
    public let exerciseName: String
    public let set: WorkoutSetPerformance
    public let recommendedAction: String
    public let durationMinutes: Int
    public let completionRate: Double
    public let summary: String

    public init(
        workoutID: String, receivedAt: Date, title: String,
        exerciseID: String, exerciseName: String,
        set: WorkoutSetPerformance, recommendedAction: WorkoutAction,
        durationMinutes: Int, completionRate: Double, summary: String
    ) {
        self.workoutID = workoutID
        self.receivedAt = receivedAt
        self.title = title
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.set = set
        self.recommendedAction = recommendedAction.rawValue
        self.durationMinutes = durationMinutes
        self.completionRate = completionRate
        self.summary = summary
    }
}

public struct AthleteProfile: Sendable {
    public let name: String
    public let coachingStyle: CoachingStyle
    public let privacyMode: PrivacyMode
    public let advancementLevel: AdvancementLevel
    public let availableEquipment: Set<Equipment>
    public let sessionTimeBudgetMinutes: Int
    public let weeklyTrainingDays: Int
    public let preferredRepRange: ClosedRange<Int>

    public init(
        name: String,
        coachingStyle: CoachingStyle = .motivational,
        privacyMode: PrivacyMode = .standard,
        advancementLevel: AdvancementLevel = .intermediate,
        availableEquipment: Set<Equipment> = [.barbell, .dumbbell, .machine, .bodyweight],
        sessionTimeBudgetMinutes: Int = 60,
        weeklyTrainingDays: Int = 4,
        preferredRepRange: ClosedRange<Int> = 5...8
    ) {
        self.name = name
        self.coachingStyle = coachingStyle
        self.privacyMode = privacyMode
        self.advancementLevel = advancementLevel
        self.availableEquipment = availableEquipment
        self.sessionTimeBudgetMinutes = sessionTimeBudgetMinutes
        self.weeklyTrainingDays = weeklyTrainingDays
        self.preferredRepRange = preferredRepRange
    }
}

public extension AthleteProfile {
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        if parts.isEmpty { return "VA" }
        return parts.compactMap(\.first).map(String.init).joined()
    }
}

/// A completed training session.
public struct RecentSession: Sendable {
    public let identifier: String?
    public let title: String?
    public let sourceName: String?
    public let date: Date
    public let durationMinutes: Int
    public let exerciseIDs: [String]
    public let totalVolumeLoad: Double  // Sum of weight × reps × sets
    public let averageRPE: Double
    public let completedSetCount: Int

    public init(
        identifier: String? = nil,
        title: String? = nil,
        sourceName: String? = nil,
        date: Date,
        durationMinutes: Int = 60,
        exerciseIDs: [String] = [],
        totalVolumeLoad: Double = 0,
        averageRPE: Double = 7.0,
        completedSetCount: Int = 0
    ) {
        self.identifier = identifier
        self.title = title
        self.sourceName = sourceName
        self.date = date
        self.durationMinutes = durationMinutes
        self.exerciseIDs = exerciseIDs
        self.totalVolumeLoad = totalVolumeLoad
        self.averageRPE = averageRPE
        self.completedSetCount = completedSetCount
    }

    public var isExternalHealthSession: Bool {
        completedSetCount == 0 && exerciseIDs.contains { $0.hasPrefix("healthkit-") }
    }

    public var isUserDeletable: Bool {
        identifier != nil && !isExternalHealthSession
    }
}

/// Historical performance for a single exercise.
public struct ExerciseHistory: Sendable {
    public let exerciseID: String
    public let sessions: [ExerciseSession]

    public init(exerciseID: String, sessions: [ExerciseSession] = []) {
        self.exerciseID = exerciseID
        self.sessions = sessions
    }

    /// The most recent session, if any.
    public var lastSession: ExerciseSession? {
        sessions.max(by: { $0.date < $1.date })
    }

    /// The top working weight across all recorded sessions.
    public var topWeight: Double {
        sessions.flatMap(\.sets).map(\.weight).max() ?? 0
    }

    public var isEmpty: Bool { sessions.isEmpty }
}

public struct ExerciseSession: Sendable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let sets: [WorkoutSetPerformance]

    public init(date: Date, sets: [WorkoutSetPerformance]) {
        self.date = date
        self.sets = sets
    }

    public var totalVolumeLoad: Double {
        sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    public var topSetWeight: Double {
        sets.map(\.weight).max() ?? 0
    }

    public var averageRPE: Double {
        guard !sets.isEmpty else { return 0 }
        return sets.map(\.rpe).reduce(0, +) / Double(sets.count)
    }
}

public enum StrengthGoal: String, Sendable, CaseIterable {
    case generalStrength = "general-strength"
    case hypertrophy
    case powerlifting
    case weightLoss = "weight-loss"
}

public struct CoachMemory: Sendable {
    public struct Entry: Sendable, Identifiable {
        public var id: Date { createdAt }
        public let createdAt: Date
        public let summary: String
        public let theme: String?

        public init(createdAt: Date, summary: String, theme: String? = nil) {
            self.createdAt = createdAt
            self.summary = summary
            self.theme = theme
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }

    public var mostRecent: [Entry] {
        entries.sorted { $0.createdAt > $1.createdAt }.prefix(5).map { $0 }
    }
}
