#if canImport(Combine)
import Foundation

@_spi(Testing) public struct WorkoutDashboardSnapshotState: Sendable {
    public var readiness: ReadinessAssessment
    public var autopilot: WorkoutAutopilotState?
    public var recentSessions: [RecentSession]
    public var athlete: AthleteProfile
    public var nextWorkout: WeeklyWorkout?
    public var weeklyPlan: [WeeklyWorkout]
    public var trainingPrograms: [TrainingProgramDefinition]
    public var activeProgram: ActiveTrainingProgramContext?
    public var coachMemory: CoachMemory
    public var coachMessages: [CoachMessage]
    public var isSessionActive: Bool
    public var activeWorkoutID: String?
    public var activeWorkoutTitle: String?
    public var loggedSetCountThisSession: Int
    public var activeSessionPlan: WorkoutSessionPlan?
    public var activeSessionExerciseIndex: Int
    public var loggedSetCountForActiveExercise: Int
    public var isOnboardingComplete: Bool
    public var isNetworkReachable: Bool
    public var isHealthAuthorized: Bool
    public var recovery: RecoveryContext
    public var startupNotice: String?
    public var startupNoticeSeverity: TelemetrySeverity?
    public var operationalSignals: [OperationalSignalSummary]

    public init(
        readiness: ReadinessAssessment,
        autopilot: WorkoutAutopilotState?,
        recentSessions: [RecentSession],
        athlete: AthleteProfile,
        nextWorkout: WeeklyWorkout?,
        weeklyPlan: [WeeklyWorkout],
        trainingPrograms: [TrainingProgramDefinition] = TrainingProgramCatalog.curated,
        activeProgram: ActiveTrainingProgramContext? = nil,
        coachMemory: CoachMemory = CoachMemory(),
        coachMessages: [CoachMessage] = [],
        isSessionActive: Bool = false,
        activeWorkoutID: String? = nil,
        activeWorkoutTitle: String? = nil,
        loggedSetCountThisSession: Int = 0,
        activeSessionPlan: WorkoutSessionPlan? = nil,
        activeSessionExerciseIndex: Int = 0,
        loggedSetCountForActiveExercise: Int = 0,
        isOnboardingComplete: Bool = true,
        isNetworkReachable: Bool = true,
        isHealthAuthorized: Bool = false,
        recovery: RecoveryContext = RecoveryContext(),
        startupNotice: String? = nil,
        startupNoticeSeverity: TelemetrySeverity? = nil,
        operationalSignals: [OperationalSignalSummary] = []
    ) {
        self.readiness = readiness
        self.autopilot = autopilot
        self.recentSessions = recentSessions
        self.athlete = athlete
        self.nextWorkout = nextWorkout
        self.weeklyPlan = weeklyPlan
        self.trainingPrograms = trainingPrograms
        self.activeProgram = activeProgram
        self.coachMemory = coachMemory
        self.coachMessages = coachMessages
        self.isSessionActive = isSessionActive
        self.activeWorkoutID = activeWorkoutID
        self.activeWorkoutTitle = activeWorkoutTitle
        self.loggedSetCountThisSession = loggedSetCountThisSession
        self.activeSessionPlan = activeSessionPlan
        self.activeSessionExerciseIndex = activeSessionExerciseIndex
        self.loggedSetCountForActiveExercise = loggedSetCountForActiveExercise
        self.isOnboardingComplete = isOnboardingComplete
        self.isNetworkReachable = isNetworkReachable
        self.isHealthAuthorized = isHealthAuthorized
        self.recovery = recovery
        self.startupNotice = startupNotice
        self.startupNoticeSeverity = startupNoticeSeverity
        self.operationalSignals = operationalSignals
    }
}

#endif
