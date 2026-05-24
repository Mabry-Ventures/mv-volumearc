#if canImport(SwiftData)
import Foundation
import SwiftData
#if canImport(OSLog)
import OSLog
#endif

/// Sendable snapshot of all repository-derived dashboard state.
///
/// `WorkoutDashboardModel` is `@MainActor` because SwiftUI observes it.
/// This loader keeps the SwiftData read/projection path off that actor:
/// it creates its own `ModelContext`, turns managed records into value
/// projections inside the actor, and returns only Sendable structs for
/// the model to publish.
public struct DashboardRefreshSnapshot: Sendable {
    public struct ActiveWorkout: Sendable {
        public let identifier: String
        public let title: String
        public let completedSetCount: Int

        public init(identifier: String, title: String, completedSetCount: Int) {
            self.identifier = identifier
            self.title = title
            self.completedSetCount = completedSetCount
        }
    }

    public let athlete: AthleteProfile
    public let recentSessions: [RecentSession]
    public let readiness: ReadinessAssessment
    public let autopilot: WorkoutAutopilotState
    public let nextWorkout: WeeklyWorkout?
    public let trainingPrograms: [TrainingProgramDefinition]
    public let activeProgram: ActiveTrainingProgramContext?
    public let activeWorkout: ActiveWorkout?
    public let coachMemory: CoachMemory
    public let isOnboardingComplete: Bool

    public init(
        athlete: AthleteProfile,
        recentSessions: [RecentSession],
        readiness: ReadinessAssessment,
        autopilot: WorkoutAutopilotState,
        nextWorkout: WeeklyWorkout?,
        trainingPrograms: [TrainingProgramDefinition],
        activeProgram: ActiveTrainingProgramContext?,
        activeWorkout: ActiveWorkout?,
        coachMemory: CoachMemory,
        isOnboardingComplete: Bool
    ) {
        self.athlete = athlete
        self.recentSessions = recentSessions
        self.readiness = readiness
        self.autopilot = autopilot
        self.nextWorkout = nextWorkout
        self.trainingPrograms = trainingPrograms
        self.activeProgram = activeProgram
        self.activeWorkout = activeWorkout
        self.coachMemory = coachMemory
        self.isOnboardingComplete = isOnboardingComplete
    }
}

public actor DashboardRefreshLoader {
    private let container: ModelContainer
    private let progressionEngine: ProgressionEngine
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "com.mabryventures.VolumeArc", category: "dashboard-refresh")
    #endif

    public init(
        container: ModelContainer,
        progressionEngine: ProgressionEngine = ProgressionEngine()
    ) {
        self.container = container
        self.progressionEngine = progressionEngine
    }

    public func load(sessionFetchLimit: Int) throws -> DashboardRefreshSnapshot {
        let context = ModelContext(container)
        let profile = try loadProfile(in: context)
        let athlete = loadAthleteProfile(from: profile)
        let recentSessions = try loadRecentSessions(limit: sessionFetchLimit, in: context)
        let readiness = progressionEngine.evaluateReadiness(from: recentSessions, athlete: athlete)

        let primaryExercise = VolumeArcExerciseCatalog.backSquat
        let history = try loadHistory(forExercise: primaryExercise.id, limit: 20, in: context)
        let memory = try loadCoachMemory(in: context)
        let autopilot = progressionEngine.buildAutopilotState(
            for: history,
            athlete: athlete,
            goal: VolumeArcProductDefaults.strengthGoal,
            recentSessions: recentSessions,
            memory: memory
        )

        return DashboardRefreshSnapshot(
            athlete: athlete,
            recentSessions: recentSessions,
            readiness: readiness,
            autopilot: autopilot,
            nextWorkout: try loadNextWorkout(in: context),
            trainingPrograms: try loadTrainingPrograms(in: context),
            activeProgram: try loadActiveProgramContext(in: context),
            activeWorkout: try loadActiveWorkout(in: context),
            coachMemory: memory,
            isOnboardingComplete: profile?.onboardingCompleted ?? false
        )
    }

    private func loadProfile(in context: ModelContext) throws -> UserProfileRecord? {
        var descriptor = FetchDescriptor<UserProfileRecord>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func loadAthleteProfile(from record: UserProfileRecord?) -> AthleteProfile {
        guard let record else {
            return VolumeArcProductDefaults.athleteProfile
        }

        let equipment = Set(
            record.availableEquipmentCSV.split(separator: ",")
                .compactMap { Equipment(rawValue: String($0)) }
        )

        return AthleteProfile(
            name: record.name,
            coachingStyle: CoachingStyle(rawValue: record.coachingStyle) ?? .motivational,
            privacyMode: PrivacyMode(rawValue: record.privacyMode) ?? .standard,
            advancementLevel: AdvancementLevel(rawValue: record.advancementLevel) ?? .intermediate,
            availableEquipment: equipment.isEmpty ? [.barbell, .dumbbell, .machine, .bodyweight] : equipment,
            sessionTimeBudgetMinutes: record.sessionTimeBudgetMinutes,
            weeklyTrainingDays: record.weeklyTrainingDays,
            preferredRepRange: record.preferredRepRangeLower...record.preferredRepRangeUpper
        )
    }

    private func loadCompletedWorkouts(limit: Int, in context: ModelContext) throws -> [WorkoutRecord] {
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.completedAt != nil
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    private func loadRecentSessions(limit: Int, in context: ModelContext) throws -> [RecentSession] {
        try loadCompletedWorkouts(limit: limit, in: context)
            .map(Self.recentSession(from:))
    }

    private func loadHistory(
        forExercise exerciseID: String,
        limit: Int,
        in context: ModelContext
    ) throws -> ExerciseHistory {
        let workouts = try loadCompletedWorkouts(limit: 200, in: context)
        let sessions = workouts.compactMap { workout -> ExerciseSession? in
            guard let data = workout.setsJSON.data(using: .utf8) else { return nil }
            let logged: [RefreshLoggedSet]
            do {
                logged = try JSONDecoder().decode([RefreshLoggedSet].self, from: data)
            } catch {
                logHistoryDecodeFailure(workout: workout, error: error)
                return nil
            }

            let sets = logged.filter { $0.exerciseID == exerciseID }.map(\.set)
            guard !sets.isEmpty else { return nil }
            return ExerciseSession(date: workout.completedAt ?? workout.startedAt, sets: sets)
        }
        return ExerciseHistory(exerciseID: exerciseID, sessions: Array(sessions.prefix(limit)))
    }

    private func logHistoryDecodeFailure(workout: WorkoutRecord, error: Error) {
        #if canImport(OSLog)
        logger.warning(
            """
            Failed to decode workout history for \(workout.identifier, privacy: .public): \
            \(String(describing: error), privacy: .public)
            """
        )
        #endif
    }

    private func loadCoachMemory(in context: ModelContext) throws -> CoachMemory {
        var descriptor = FetchDescriptor<CoachMemoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        let entries = try context.fetch(descriptor).map {
            CoachMemory.Entry(
                createdAt: $0.createdAt,
                summary: $0.content,
                theme: $0.theme.isEmpty ? nil : $0.theme
            )
        }
        return CoachMemory(entries: entries)
    }

    private func loadNextWorkout(in context: ModelContext) throws -> WeeklyWorkout? {
        var descriptor = FetchDescriptor<TrainingPlanRecord>()
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first,
              let data = record.workoutsJSON.data(using: .utf8)
        else {
            return nil
        }

        let workouts: [WeeklyWorkout]
        do {
            workouts = try JSONDecoder().decode([WeeklyWorkout].self, from: data)
        } catch {
            logTrainingPlanDecodeFailure(error: error)
            return nil
        }

        let sortedWorkouts = workouts.sorted { $0.dayOfWeek < $1.dayOfWeek }
        guard !sortedWorkouts.isEmpty else { return nil }
        let todayWeekday = WeeklyWorkout.trainingWeekday(for: .now)
        return sortedWorkouts.first { $0.dayOfWeek >= todayWeekday } ?? sortedWorkouts.first
    }

    private func loadTrainingPrograms(in context: ModelContext) throws -> [TrainingProgramDefinition] {
        let records = try context.fetch(FetchDescriptor<TrainingProgramRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
        var persistedByID: [String: TrainingProgramDefinition] = [:]
        for definition in records.compactMap(TrainingProgramDefinition.init(record:)) where persistedByID[definition.id] == nil {
            persistedByID[definition.id] = definition
        }

        let curatedIDs = Set(TrainingProgramCatalog.curated.map(\.id))
        let curatedAndPersisted = TrainingProgramCatalog.curated.map { curated in
            persistedByID[curated.id] ?? curated
        }
        let persistedOnly = persistedByID.values
            .filter { !curatedIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return curatedAndPersisted + persistedOnly
    }

    private func loadActiveProgramContext(in context: ModelContext) throws -> ActiveTrainingProgramContext? {
        var descriptor = FetchDescriptor<TrainingProgramRecord>(
            predicate: #Predicate<TrainingProgramRecord> { program in
                program.isActive
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first,
              let definition = TrainingProgramDefinition(record: record)
        else {
            return nil
        }
        return definition.scheduledSession(on: .now, assignedAt: record.assignedAt ?? record.updatedAt)
    }

    private func logTrainingPlanDecodeFailure(error: Error) {
        #if canImport(OSLog)
        logger.error(
            "Failed to decode training plan JSON for dashboard refresh: \(String(describing: error), privacy: .public)"
        )
        #endif
    }

    private func loadActiveWorkout(in context: ModelContext) throws -> DashboardRefreshSnapshot.ActiveWorkout? {
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.completedAt == nil
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let active = try context.fetch(descriptor).first else { return nil }
        return DashboardRefreshSnapshot.ActiveWorkout(
            identifier: active.identifier,
            title: active.title,
            completedSetCount: active.completedSetCount
        )
    }

    private static func recentSession(from workout: WorkoutRecord) -> RecentSession {
        RecentSession(
            date: workout.completedAt ?? workout.startedAt,
            durationMinutes: workout.durationMinutes,
            exerciseIDs: workout.exerciseIDsCSV.split(separator: ",").map(String.init),
            totalVolumeLoad: workout.totalVolumeLoad,
            averageRPE: workout.averageRPE,
            completedSetCount: workout.completedSetCount
        )
    }
}

private struct RefreshLoggedSet: Codable {
    let exerciseID: String
    let set: WorkoutSetPerformance
}
#endif
