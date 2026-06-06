// swiftlint:disable file_length
#if canImport(SwiftUI)
import Foundation
import SwiftUI
#if canImport(SwiftData)
import SwiftData
#endif

public struct WatchConnectivityNotice: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case queued
        case replayed
    }

    public let id: UUID
    public let kind: Kind
    public let title: String
    public let message: String
    public let severity: TelemetrySeverity

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        message: String,
        severity: TelemetrySeverity
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.severity = severity
    }
}

/// The central view model that drives every screen in the iOS app.
///
/// Responsibilities:
/// - Holds the current readiness assessment, autopilot state, and recent sessions
/// - Drives dashboard action methods (start session, log set, sync)
/// - Routes Watch Connectivity and Health background updates into the data layer
/// - Publishes streaming coach messages and startup signals to the UI
@MainActor
// swiftlint:disable:next type_body_length
public final class WorkoutDashboardModel: ObservableObject {

    // MARK: - Published state
    @Published public private(set) var readiness: ReadinessAssessment = ReadinessAssessment(score: 85, brief: "Ready to train.", factors: [])
    @Published public private(set) var autopilot: WorkoutAutopilotState?
    @Published public private(set) var recentSessions: [RecentSession] = []
    @Published public private(set) var athlete: AthleteProfile = VolumeArcProductDefaults.athleteProfile
    @Published public private(set) var nextWorkout: WeeklyWorkout?
    @Published public private(set) var weeklyPlan: [WeeklyWorkout] = []
    @Published public private(set) var trainingPrograms: [TrainingProgramDefinition] = TrainingProgramCatalog.curated
    @Published public private(set) var activeProgram: ActiveTrainingProgramContext?
    @Published public private(set) var coachMemory: CoachMemory = CoachMemory()
    @Published public internal(set) var latestFormCheckAnalysis: FormCheckAnalysis?

    @Published public var activeWorkoutTitle: String?
    @Published public private(set) var isSessionActive: Bool = false
    @Published public private(set) var loggedSetCountThisSession: Int = 0
    @Published public private(set) var activeSessionPlan: WorkoutSessionPlan?
    @Published public private(set) var activeSessionExerciseIndex: Int = 0
    @Published public private(set) var loggedSetCountForActiveExercise: Int = 0

    @Published public var startupNotice: String?
    @Published public var startupNoticeSeverity: TelemetrySeverity?
    @Published public private(set) var operationalSignals: [OperationalSignalSummary] = []

    @Published public var coachMessages: [CoachMessage] = []
    @Published public private(set) var isCoachStreaming: Bool = false
    @Published public private(set) var coachFallbackNotice: String?
    @Published public private(set) var voicePermissionStatus = VoicePermissionStatus(
        microphone: .notDetermined,
        speechRecognition: .notDetermined
    )
    @Published public private(set) var isVoiceTurnActive: Bool = false
    @Published public private(set) var voiceNotice: String?

    @Published public var isOnboardingComplete: Bool = false
    @Published public private(set) var isNetworkReachable: Bool = true
    @Published public private(set) var hasLoadedInitialData: Bool = false
    @Published public private(set) var isHealthAuthorized: Bool = false
    /// VOL-181 Phase 1B: cached recovery snapshot (HRV, sleep debt,
    /// strength load) fed into the coach prompt's recovery section
    /// and surfaced as the Today-tab `VARecoveryChip`. Updated on
    /// `refresh()` via the injected `RecoveryReader`. Defaults to an
    /// empty context so views and the prompt block gracefully omit
    /// the recovery surface when HK is unavailable. `internal(set)`
    /// rather than `private(set)` so the extracted `+CoachContext`
    /// extension can update it on refresh — still effectively
    /// non-writeable from outside VolumeArcCore.
    @Published public internal(set) var recovery: RecoveryContext = RecoveryContext()

    /// VOL-112: most-recent Watch payload kind, surfaced for the
    /// deterministic-mode debug overlay so XCUITests can assert the
    /// watch-payload arrival path without scraping telemetry events.
    @Published public internal(set) var lastWatchPayloadKindForTesting: String?
    @Published public internal(set) var activeWatchFormCheckRequest: WatchFormCheckStartPayload?
    @Published public internal(set) var watchFormCheckStopToken: String?
    @Published public private(set) var watchConnectivityNotice: WatchConnectivityNotice?

    // MARK: - Dependencies
    private let aiProvider: AICoachProvider
    private let voiceCoach: LiveVoiceCoachOrchestrator
    private let voicePermissionStore: VoicePermissionStore
    // VOL-181: relaxed from `private` to internal so the extracted
    // coach-context extension (in WorkoutDashboardModel+CoachContext.swift)
    // can record recovery-read failures. Still effectively internal to
    // VolumeArcCore — no public API surface change.
    let telemetrySink: TelemetrySink
    private let progressionEngine = ProgressionEngine()
    public let featureFlags: FeatureFlagProvider
    /// VOL-109: HealthKit authorization gateway. Stored so onboarding +
    /// the Profile-tab "Apple Health" row can route auth requests
    /// through `requestHealthKitAuthorization()` rather than reaching
    /// into a global `HealthStore` singleton.
    private let healthStore: HealthStore
    /// VOL-181 Phase 1B: platform-agnostic seam that produces a
    /// `RecoveryContext` from HealthKit (App layer injects the real
    /// `HealthKitRecoveryReader`; tests and macOS hosts get the
    /// default `UnavailableRecoveryReader` which returns an empty
    /// context). Internal so the extracted coach-context extension
    /// can call `currentRecovery()`.
    let recoveryReader: RecoveryReader
    let healthWorkoutImporter: HealthWorkoutImporting
    let watchVoiceSettingsStore: WatchVoiceSettingsStore
    let watchConnectivityCoordinator: WatchConnectivityCoordinator?
    private let activeSessionStateStore: ActiveWorkoutSessionStateStore
    private let accountSessionStore: AccountSessionStore

    #if canImport(SwiftData)
    private let workoutRepository: SwiftDataWorkoutRepository?
    // VOL-181: relaxed to internal so the extracted coach-context
    // extension can pull memory.mostRecent into the prompt block.
    let coachMemoryRepository: SwiftDataCoachMemoryRepository?
    private let userProfileRepository: SwiftDataUserProfileRepository?
    // Internal so the extracted coach-context extension can include
    // the current weekly plan in planning prompts.
    let trainingPlanRepository: SwiftDataTrainingPlanRepository?
    let trainingProgramRepository: SwiftDataTrainingProgramRepository?
    private let refreshLoader: DashboardRefreshLoader?
    #endif

    #if canImport(StoreKit)
    private let syncEngine: CloudSyncCoordinator?
    public let subscriptionStore: StoreKitSubscriptionStore?
    #endif
    private var didRecordCloudSyncUnavailable = false
    private var publishedLiveActivityWorkoutID: String?

    // VOL-256: `public private(set)` so VolumeArcAppTests can read the
    // rehydrated workout ID across the crash-recovery integration tests
    // without `@testable import` (which the test target deliberately
    // avoids to keep production access modeled honestly), while still
    // forbidding outside-module mutation.
    public private(set) var activeWorkoutID: String?
    var completedWatchFormCheckSessionIDs: Set<String> = []
    @Published public private(set) var accountSession: AccountSession?

    public var activeSessionExercise: WeeklyWorkoutExercise? {
        activeSessionPlan?.exercise(at: activeSessionExerciseIndex)
    }

    public var nextActiveSessionExercise: WeeklyWorkoutExercise? {
        activeSessionPlan?.exercise(at: activeSessionExerciseIndex + 1)
    }

    public var activeSessionTotalSetCount: Int {
        activeSessionPlan?.totalSetCount ?? 0
    }

    public var activeSessionExerciseSetCount: Int {
        activeSessionExercise.map { max(1, $0.sets) } ?? 0
    }

    // MARK: - Initializers
    #if canImport(SwiftData) && canImport(StoreKit)
    public init(
        aiProvider: AICoachProvider,
        syncEngine: CloudSyncCoordinator,
        repository: SwiftDataWorkoutRepository,
        coachMemoryRepository: SwiftDataCoachMemoryRepository,
        userProfileRepository: SwiftDataUserProfileRepository,
        trainingPlanRepository: SwiftDataTrainingPlanRepository,
        accountSessionStore: AccountSessionStore,
        voicePermissionStore: VoicePermissionStore,
        healthStore: HealthStore,
        notificationStore: NotificationStore,
        telemetrySink: TelemetrySink,
        surfaceStore: PlatformSurfaceStateStore,
        startupNotice: String? = nil,
        startupNoticeSeverity: TelemetrySeverity? = nil,
        operationalSignals: [OperationalSignalSummary] = [],
        subscriptionStore: StoreKitSubscriptionStore,
        voiceCoach: LiveVoiceCoachOrchestrator,
        // VOL-61: optional so existing test sites keep compiling without
        // changes. App-level wiring now threads the same provider used by
        // the launch-scoped flag gate so the dashboard and the gating
        // surfaces read a consistent flag state.
        featureFlags: FeatureFlagProvider? = nil,
        // VOL-181 Phase 1B: defaults to `UnavailableRecoveryReader()`
        // so existing test sites (which don't care about recovery)
        // keep compiling unchanged. App-level wiring injects the real
        // `HealthKitRecoveryReader`.
        recoveryReader: RecoveryReader = UnavailableRecoveryReader(),
        healthWorkoutImporter: HealthWorkoutImporting = UnavailableHealthWorkoutImporter(),
        watchVoiceSettingsStore: WatchVoiceSettingsStore = UserDefaultsWatchVoiceSettingsStore(),
        watchConnectivityCoordinator: WatchConnectivityCoordinator? = nil,
        activeSessionStateStore: ActiveWorkoutSessionStateStore = UserDefaultsActiveSessionStateStore()
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
        self.voicePermissionStore = voicePermissionStore
        self.telemetrySink = telemetrySink
        self.featureFlags = featureFlags ?? LocalFeatureFlagProvider()
        self.healthStore = healthStore
        self.recoveryReader = recoveryReader
        self.healthWorkoutImporter = healthWorkoutImporter
        self.watchVoiceSettingsStore = watchVoiceSettingsStore
        self.watchConnectivityCoordinator = watchConnectivityCoordinator
        self.activeSessionStateStore = activeSessionStateStore
        self.accountSessionStore = accountSessionStore
        self.accountSession = accountSessionStore.load()
        self.workoutRepository = repository
        self.coachMemoryRepository = coachMemoryRepository
        self.userProfileRepository = userProfileRepository
        self.trainingPlanRepository = trainingPlanRepository
        self.trainingProgramRepository = SwiftDataTrainingProgramRepository(
            container: repository.container,
            trainingPlanRepository: trainingPlanRepository
        )
        self.refreshLoader = DashboardRefreshLoader(container: repository.container)
        self.syncEngine = syncEngine
        self.subscriptionStore = subscriptionStore
        self.startupNotice = startupNotice
        self.startupNoticeSeverity = startupNoticeSeverity
        self.operationalSignals = operationalSignals
        Task { await refresh() }
    }
    #endif

    #if canImport(StoreKit)
    public init(
        aiProvider: AICoachProvider,
        syncEngine: CloudSyncCoordinator,
        accountSessionStore: AccountSessionStore,
        voicePermissionStore: VoicePermissionStore,
        healthStore: HealthStore,
        notificationStore: NotificationStore,
        telemetrySink: TelemetrySink,
        surfaceStore: PlatformSurfaceStateStore,
        startupNotice: String? = nil,
        startupNoticeSeverity: TelemetrySeverity? = nil,
        operationalSignals: [OperationalSignalSummary] = [],
        subscriptionStore: StoreKitSubscriptionStore,
        voiceCoach: LiveVoiceCoachOrchestrator,
        featureFlags: FeatureFlagProvider? = nil,
        recoveryReader: RecoveryReader = UnavailableRecoveryReader(),
        healthWorkoutImporter: HealthWorkoutImporting = UnavailableHealthWorkoutImporter(),
        watchVoiceSettingsStore: WatchVoiceSettingsStore = UserDefaultsWatchVoiceSettingsStore(),
        watchConnectivityCoordinator: WatchConnectivityCoordinator? = nil,
        activeSessionStateStore: ActiveWorkoutSessionStateStore = UserDefaultsActiveSessionStateStore()
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
        self.voicePermissionStore = voicePermissionStore
        self.telemetrySink = telemetrySink
        self.featureFlags = featureFlags ?? LocalFeatureFlagProvider()
        self.healthStore = healthStore
        self.recoveryReader = recoveryReader
        self.healthWorkoutImporter = healthWorkoutImporter
        self.watchVoiceSettingsStore = watchVoiceSettingsStore
        self.watchConnectivityCoordinator = watchConnectivityCoordinator
        self.activeSessionStateStore = activeSessionStateStore
        self.accountSessionStore = accountSessionStore
        self.accountSession = accountSessionStore.load()
        #if canImport(SwiftData)
        self.workoutRepository = nil
        self.coachMemoryRepository = nil
        self.userProfileRepository = nil
        self.trainingPlanRepository = nil
        self.trainingProgramRepository = nil
        self.refreshLoader = nil
        #endif
        self.syncEngine = syncEngine
        self.subscriptionStore = subscriptionStore
        self.startupNotice = startupNotice
        self.startupNoticeSeverity = startupNoticeSeverity
        self.operationalSignals = operationalSignals
        Task { await refresh() }
    }
    #endif

    private init(
        aiProvider: AICoachProvider,
        accountSessionStore: AccountSessionStore,
        voicePermissionStore: VoicePermissionStore,
        healthStore: HealthStore,
        notificationStore: NotificationStore,
        telemetrySink: TelemetrySink,
        surfaceStore: PlatformSurfaceStateStore,
        voiceCoach: LiveVoiceCoachOrchestrator,
        featureFlags: FeatureFlagProvider? = nil,
        recoveryReader: RecoveryReader = UnavailableRecoveryReader(),
        healthWorkoutImporter: HealthWorkoutImporting = UnavailableHealthWorkoutImporter(),
        watchVoiceSettingsStore: WatchVoiceSettingsStore = UserDefaultsWatchVoiceSettingsStore(),
        watchConnectivityCoordinator: WatchConnectivityCoordinator? = nil,
        activeSessionStateStore: ActiveWorkoutSessionStateStore = InMemoryActiveWorkoutSessionStateStore(),
        autoRefresh: Bool
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
        self.voicePermissionStore = voicePermissionStore
        self.telemetrySink = telemetrySink
        self.featureFlags = featureFlags ?? LocalFeatureFlagProvider()
        self.healthStore = healthStore
        self.recoveryReader = recoveryReader
        self.healthWorkoutImporter = healthWorkoutImporter
        self.watchVoiceSettingsStore = watchVoiceSettingsStore
        self.watchConnectivityCoordinator = watchConnectivityCoordinator
        self.activeSessionStateStore = activeSessionStateStore
        self.accountSessionStore = accountSessionStore
        self.accountSession = accountSessionStore.load()
        #if canImport(SwiftData)
        self.workoutRepository = nil
        self.coachMemoryRepository = nil
        self.userProfileRepository = nil
        self.trainingPlanRepository = nil
        self.trainingProgramRepository = nil
        self.refreshLoader = nil
        #endif
        #if canImport(StoreKit)
        self.syncEngine = nil
        self.subscriptionStore = nil
        #endif
        if autoRefresh {
            Task { await refresh() }
        }
    }

    public convenience init(
        aiProvider: AICoachProvider,
        accountSessionStore: AccountSessionStore,
        voicePermissionStore: VoicePermissionStore,
        healthStore: HealthStore,
        notificationStore: NotificationStore,
        telemetrySink: TelemetrySink,
        surfaceStore: PlatformSurfaceStateStore,
        voiceCoach: LiveVoiceCoachOrchestrator,
        featureFlags: FeatureFlagProvider? = nil,
        recoveryReader: RecoveryReader = UnavailableRecoveryReader(),
        healthWorkoutImporter: HealthWorkoutImporting = UnavailableHealthWorkoutImporter(),
        watchVoiceSettingsStore: WatchVoiceSettingsStore = UserDefaultsWatchVoiceSettingsStore(),
        watchConnectivityCoordinator: WatchConnectivityCoordinator? = nil,
        activeSessionStateStore: ActiveWorkoutSessionStateStore = InMemoryActiveWorkoutSessionStateStore()
    ) {
        self.init(
            aiProvider: aiProvider,
            accountSessionStore: accountSessionStore,
            voicePermissionStore: voicePermissionStore,
            healthStore: healthStore,
            notificationStore: notificationStore,
            telemetrySink: telemetrySink,
            surfaceStore: surfaceStore,
            voiceCoach: voiceCoach,
            featureFlags: featureFlags,
            recoveryReader: recoveryReader,
            healthWorkoutImporter: healthWorkoutImporter,
            watchVoiceSettingsStore: watchVoiceSettingsStore,
            watchConnectivityCoordinator: watchConnectivityCoordinator,
            activeSessionStateStore: activeSessionStateStore,
            autoRefresh: true
        )
    }

    @_spi(Testing) public convenience init(
        snapshotState state: WorkoutDashboardSnapshotState,
        telemetrySink: any TelemetrySink = InMemoryTelemetrySink(),
        featureFlags: (any FeatureFlagProvider)? = nil
    ) {
        let coachProvider = LocalHeuristicAICoachProvider(
            coachingStyle: state.athlete.coachingStyle
        )
        self.init(
            aiProvider: coachProvider,
            accountSessionStore: UserDefaultsAccountSessionStore(),
            voicePermissionStore: UnavailableVoicePermissionStore(),
            healthStore: UnavailableHealthStore(),
            notificationStore: InMemoryNotificationStore(),
            telemetrySink: telemetrySink,
            surfaceStore: UserDefaultsPlatformSurfaceStateStore(),
            voiceCoach: LiveVoiceCoachOrchestrator(
                transport: AIRelayVoiceTransport(provider: coachProvider)
            ),
            featureFlags: featureFlags,
            recoveryReader: UnavailableRecoveryReader(),
            healthWorkoutImporter: UnavailableHealthWorkoutImporter(),
            watchVoiceSettingsStore: UserDefaultsWatchVoiceSettingsStore(),
            watchConnectivityCoordinator: nil,
            activeSessionStateStore: InMemoryActiveWorkoutSessionStateStore(),
            autoRefresh: false
        )

        readiness = state.readiness
        autopilot = state.autopilot
        recentSessions = state.recentSessions
        athlete = state.athlete
        nextWorkout = state.nextWorkout
        weeklyPlan = state.weeklyPlan
        trainingPrograms = state.trainingPrograms
        activeProgram = state.activeProgram
        coachMemory = state.coachMemory
        coachMessages = state.coachMessages
        isCoachStreaming = false
        coachFallbackNotice = nil
        activeWorkoutID = state.activeWorkoutID
        activeWorkoutTitle = state.activeWorkoutTitle
        isSessionActive = state.isSessionActive
        loggedSetCountThisSession = state.loggedSetCountThisSession
        activeSessionPlan = state.activeSessionPlan
        activeSessionExerciseIndex = state.activeSessionExerciseIndex
        loggedSetCountForActiveExercise = state.loggedSetCountForActiveExercise
        isOnboardingComplete = state.isOnboardingComplete
        isNetworkReachable = state.isNetworkReachable
        isHealthAuthorized = state.isHealthAuthorized
        hasLoadedInitialData = true
        recovery = state.recovery
        startupNotice = state.startupNotice
        startupNoticeSeverity = state.startupNoticeSeverity
        operationalSignals = state.operationalSignals
    }

    // MARK: - Refresh
    /// Reload all published state from repositories. Called at launch and after writes.
    @discardableResult
    public func refresh() async -> Bool {
        self.isHealthAuthorized = await healthStore.isAuthorized
        await refreshRecovery()

        #if canImport(SwiftData)
        guard let refreshLoader else {
            return true
        }

        do {
            // VOL-99: the perf suite seeds a larger history pool and
            // asserts scroll performance on the Today tab. Bump the fetch
            // limit when `-PerfTestMode 1` is active so the rows exist in
            // memory for XCTest to scroll past.
            let sessionFetchLimit = VolumeArcRuntimeFlags.isPerformanceTestMode ? 60 : 20
            let externalHealthSessions = await externalHealthWorkoutSessions(limit: sessionFetchLimit)
            let snapshot = try await refreshLoader.load(
                sessionFetchLimit: sessionFetchLimit,
                externalSessions: externalHealthSessions
            )

            self.athlete = snapshot.athlete
            self.recentSessions = snapshot.recentSessions
            self.readiness = snapshot.readiness
            self.autopilot = snapshot.autopilot
            self.nextWorkout = snapshot.nextWorkout
            self.weeklyPlan = snapshot.weeklyPlan
            self.trainingPrograms = snapshot.trainingPrograms
            self.activeProgram = snapshot.activeProgram
            self.coachMemory = snapshot.coachMemory

            applyActiveWorkoutRecoverySnapshot(snapshot.activeWorkout)

            self.isOnboardingComplete = snapshot.isOnboardingComplete
            self.hasLoadedInitialData = true

            // Publish a widget snapshot derived from the freshly loaded state.
            publishWidgetSnapshot()

            telemetrySink.record(TelemetryEvent(
                category: "dashboard",
                name: "refresh",
                severity: .info,
                message: "Dashboard refreshed",
                metadata: ["sessionCount": "\(snapshot.recentSessions.count)", "readiness": "\(readiness.score)"]
            ))
            return true
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "dashboard",
                name: "refresh_failed",
                severity: .error,
                message: "Failed to refresh dashboard: \(error.localizedDescription)"
            ))
            return false
        }
        #else
        return true
        #endif
    }

    #if canImport(SwiftData)
    /// VOL-256: active-workout recovery contract. When the dashboard
    /// boots and finds a `WorkoutRecord` with `completedAt == nil` (the
    /// user crashed / was memory-killed mid-session), silently restore
    /// the session state. The Today tab's `quickActionsRow` then renders
    /// "Continue Session" via the existing `model.isSessionActive` gate.
    /// Silent restoration is intentional — a strength athlete who lost
    /// a set to a crash wants the workout back, not a "Resume / Discard?"
    /// prompt that risks accidental discard.
    ///
    /// Emits a single `workout.active_session.recovered` `.info` event
    /// on the `wasActive == false → true` transition. The guard
    /// deduplicates against the polling refresh loop so only a real
    /// recovery counts.
    private func applyActiveWorkoutRecoverySnapshot(_ active: DashboardRefreshSnapshot.ActiveWorkout?) {
        guard let active else {
            let previousWorkoutID = self.activeWorkoutID
            self.activeWorkoutID = nil
            self.activeWorkoutTitle = nil
            self.isSessionActive = false
            self.loggedSetCountThisSession = 0
            clearActiveSessionPlan(persistedWorkoutID: previousWorkoutID)
            return
        }
        let wasActive = self.isSessionActive
        let previousWorkoutID = self.activeWorkoutID
        self.activeWorkoutID = active.identifier
        self.activeWorkoutTitle = active.title
        self.isSessionActive = true
        self.loggedSetCountThisSession = active.completedSetCount
        if !wasActive || previousWorkoutID != active.identifier || activeSessionPlan == nil {
            restoreActiveSessionStateIfPossible(for: active.identifier)
            self.loggedSetCountThisSession = active.completedSetCount
        }
        if wasActive == false {
            telemetrySink.record(TelemetryEvent(
                category: "workout",
                name: "active_session.recovered",
                severity: .info,
                message: "Restored an in-progress workout session from persistence on dashboard refresh.",
                metadata: [
                    "workout_id": active.identifier,
                    "completed_sets": String(active.completedSetCount)
                ]
            ))
        }
    }
    #endif

    private func activeSessionPlanCandidate(from explicitPlan: WorkoutSessionPlan?) -> WorkoutSessionPlan? {
        if let explicitPlan, !explicitPlan.isEmpty {
            return explicitPlan
        }
        if let nextWorkout, !nextWorkout.exercises.isEmpty {
            return WorkoutSessionPlan(workout: nextWorkout)
        }
        return nil
    }

    private func workoutTitle(overrideTitle: String?, plan: WorkoutSessionPlan?) -> String {
        let trimmedOverride = overrideTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedOverride.isEmpty {
            return trimmedOverride
        }
        let trimmedPlanTitle = plan?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedPlanTitle.isEmpty {
            return trimmedPlanTitle
        }
        return nextWorkout?.title ?? "Strength Session"
    }

    private func clearActiveSessionPlan() {
        activeSessionPlan = nil
        activeSessionExerciseIndex = 0
        loggedSetCountForActiveExercise = 0
    }

    private func clearActiveSessionPlan(persistedWorkoutID: String?) {
        clearActiveSessionPlan()
        if let persistedWorkoutID {
            activeSessionStateStore.clear(workoutID: persistedWorkoutID)
        }
    }

    private func persistActiveSessionStateIfNeeded() {
        guard let activeWorkoutID,
              let activeSessionPlan,
              activeSessionPlan.isEmpty == false
        else { return }

        activeSessionStateStore.save(ActiveWorkoutSessionState(
            workoutID: activeWorkoutID,
            plan: activeSessionPlan,
            activeExerciseIndex: activeSessionExerciseIndex,
            loggedSetCountForActiveExercise: loggedSetCountForActiveExercise
        ))
    }

    private func restoreActiveSessionStateIfPossible(for workoutID: String) {
        guard let state = activeSessionStateStore.load(workoutID: workoutID),
              state.plan.isEmpty == false
        else {
            clearActiveSessionPlan()
            return
        }

        activeSessionPlan = state.plan
        let maxIndex = max(0, state.plan.exercises.count - 1)
        activeSessionExerciseIndex = min(max(0, state.activeExerciseIndex), maxIndex)
        let activeSetCount = state.plan.exercise(at: activeSessionExerciseIndex).map { max(1, $0.sets) } ?? 1
        loggedSetCountForActiveExercise = min(
            max(0, state.loggedSetCountForActiveExercise),
            activeSetCount
        )
    }

    private func advanceActiveSessionPlanAfterLoggedSet() {
        guard let activeSessionPlan,
              activeSessionPlan.exercises.indices.contains(activeSessionExerciseIndex)
        else { return }

        let targetSets = max(1, activeSessionPlan.exercises[activeSessionExerciseIndex].sets)
        loggedSetCountForActiveExercise += 1
        guard loggedSetCountForActiveExercise >= targetSets else { return }

        if activeSessionExerciseIndex < activeSessionPlan.exercises.count - 1 {
            activeSessionExerciseIndex += 1
            loggedSetCountForActiveExercise = 0
        } else {
            loggedSetCountForActiveExercise = targetSets
        }
    }

    private static func exerciseIdentifier(named name: String) -> String {
        let normalized = normalizeExerciseName(name)
        if let match = VolumeArcExerciseCatalog.all.first(where: { exercise in
            normalizeExerciseName(exercise.name) == normalized
                || exercise.aliases.contains(where: { normalizeExerciseName($0) == normalized })
        }) {
            return match.id
        }
        return normalized
            .split(separator: " ")
            .joined(separator: "-")
    }

    private static func normalizeExerciseName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    // MARK: - Dashboard actions
    /// Start a new workout session.
    public func startWorkoutSession(title overrideTitle: String? = nil, plan: WorkoutSessionPlan? = nil) async {
        #if canImport(SwiftData)
        guard let workoutRepository else { return }
        do {
            let resolvedPlan = activeSessionPlanCandidate(from: plan)
            let title = workoutTitle(overrideTitle: overrideTitle, plan: resolvedPlan)
            let workout = try workoutRepository.createWorkout(title: title)
            self.activeWorkoutID = workout.identifier
            self.activeWorkoutTitle = workout.title
            self.isSessionActive = true
            self.loggedSetCountThisSession = 0
            self.activeSessionPlan = resolvedPlan
            self.activeSessionExerciseIndex = 0
            self.loggedSetCountForActiveExercise = 0
            persistActiveSessionStateIfNeeded()

            publishWidgetSnapshot()

            telemetrySink.record(TelemetryEvent(
                category: "workout",
                name: "session_started",
                severity: .info,
                message: "Started session: \(title)"
            ))
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "workout",
                name: "session_start_failed",
                severity: .error,
                message: error.localizedDescription
            ))
        }
        #endif
    }

    public func replaceActiveSessionExercise(with replacement: WeeklyWorkoutExercise) {
        guard let activeSessionPlan,
              activeSessionPlan.exercises.indices.contains(activeSessionExerciseIndex)
        else { return }

        var exercises = activeSessionPlan.exercises
        exercises[activeSessionExerciseIndex] = replacement
        self.activeSessionPlan = WorkoutSessionPlan(
            title: activeSessionPlan.title,
            durationMinutes: activeSessionPlan.durationMinutes,
            targetRPE: activeSessionPlan.targetRPE,
            exercises: exercises
        )
        self.loggedSetCountForActiveExercise = 0
        persistActiveSessionStateIfNeeded()
        telemetrySink.record(TelemetryEvent(
            category: "workout",
            name: "exercise_replaced",
            severity: .info,
            message: "Replaced current exercise with \(replacement.name).",
            metadata: ["exercise": replacement.name]
        ))
        publishWidgetSnapshot()
    }

    @discardableResult
    public func deferActiveSessionExercise() -> (deferredExercise: String, nextExercise: String)? {
        guard let activeSessionPlan,
              activeSessionPlan.exercises.indices.contains(activeSessionExerciseIndex),
              activeSessionExerciseIndex < activeSessionPlan.exercises.count - 1
        else { return nil }

        var exercises = activeSessionPlan.exercises
        let deferredExercise = exercises.remove(at: activeSessionExerciseIndex)
        exercises.append(deferredExercise)
        guard exercises.indices.contains(activeSessionExerciseIndex) else { return nil }

        self.activeSessionPlan = WorkoutSessionPlan(
            title: activeSessionPlan.title,
            durationMinutes: activeSessionPlan.durationMinutes,
            targetRPE: activeSessionPlan.targetRPE,
            exercises: exercises
        )
        self.loggedSetCountForActiveExercise = 0
        persistActiveSessionStateIfNeeded()
        let nextExercise = exercises[activeSessionExerciseIndex]
        telemetrySink.record(TelemetryEvent(
            category: "workout",
            name: "exercise_deferred",
            severity: .info,
            message: "Deferred \(deferredExercise.name) and loaded \(nextExercise.name).",
            metadata: [
                "deferred_exercise": deferredExercise.name,
                "next_exercise": nextExercise.name,
            ]
        ))
        publishWidgetSnapshot()
        return (deferredExercise.name, nextExercise.name)
    }

    public func moveActiveSession(toExerciseAt index: Int) {
        guard let activeSessionPlan,
              activeSessionPlan.exercises.indices.contains(index),
              index != activeSessionExerciseIndex
        else { return }

        let previousExercise = activeSessionPlan.exercises[activeSessionExerciseIndex]
        let nextExercise = activeSessionPlan.exercises[index]
        activeSessionExerciseIndex = index
        loggedSetCountForActiveExercise = 0
        persistActiveSessionStateIfNeeded()
        telemetrySink.record(TelemetryEvent(
            category: "workout",
            name: "exercise_selected",
            severity: .info,
            message: "Moved active session from \(previousExercise.name) to \(nextExercise.name).",
            metadata: [
                "from_exercise": previousExercise.name,
                "to_exercise": nextExercise.name,
            ]
        ))
        publishWidgetSnapshot()
    }

    public func skipActiveSessionExercise() {
        guard let activeSessionPlan,
              activeSessionPlan.exercises.indices.contains(activeSessionExerciseIndex)
        else { return }

        let skippedExercise = activeSessionPlan.exercises[activeSessionExerciseIndex]
        if activeSessionExerciseIndex < activeSessionPlan.exercises.count - 1 {
            activeSessionExerciseIndex += 1
            loggedSetCountForActiveExercise = 0
        } else {
            loggedSetCountForActiveExercise = max(1, skippedExercise.sets)
        }
        persistActiveSessionStateIfNeeded()
        telemetrySink.record(TelemetryEvent(
            category: "workout",
            name: "exercise_skipped",
            severity: .info,
            message: "Skipped \(skippedExercise.name) during an active session.",
            metadata: ["exercise": skippedExercise.name]
        ))
        publishWidgetSnapshot()
    }

    /// Discard the in-progress workout without creating a completed history row.
    @discardableResult
    public func discardActiveWorkoutSession() async -> Bool {
        #if canImport(SwiftData)
        guard let workoutRepository, let workoutID = activeWorkoutID else { return false }
        do {
            try workoutRepository.deleteWorkout(identifier: workoutID)
            self.activeWorkoutID = nil
            self.activeWorkoutTitle = nil
            self.isSessionActive = false
            self.loggedSetCountThisSession = 0
            clearActiveSessionPlan(persistedWorkoutID: workoutID)
            telemetrySink.record(TelemetryEvent(
                category: "workout",
                name: "session_discarded",
                severity: .warning,
                message: "Discarded in-progress workout session.",
                metadata: ["workout_id": workoutID]
            ))
            await refresh()
            return true
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "workout",
                name: "session_discard_failed",
                severity: .error,
                message: error.localizedDescription,
                metadata: ["workout_id": workoutID]
            ))
            return false
        }
        #else
        return false
        #endif
    }

    /// End the currently active workout session.
    @discardableResult
    public func completeWorkoutSession() async -> RecentSession? {
        #if canImport(SwiftData)
        guard let workoutRepository, let workoutID = activeWorkoutID else { return nil }

        // VOL-57 fixup: `completeWorkout` succeeds as a discrete step.
        // Previously the snapshot fetch was inside the same do-block, so
        // any SwiftData fetch error on the read thrown after the write
        // routed through the catch and skipped teardown — leaving the
        // UI in an "active session" state for a workout that was already
        // persisted as complete, and surfacing a false failure event.
        // Split the two: a failed write is a real completion failure;
        // a failed read is best-effort and must not block teardown.
        do {
            try workoutRepository.completeWorkout(identifier: workoutID)
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "workout",
                name: "session_complete_failed",
                severity: .error,
                message: error.localizedDescription
            ))
            return nil
        }

        // Completion has persisted — tear down the session state
        // unconditionally so the UI reflects reality even if the
        // snapshot read below fails.
        self.activeWorkoutID = nil
        self.activeWorkoutTitle = nil
        self.isSessionActive = false
        self.loggedSetCountThisSession = 0
        clearActiveSessionPlan(persistedWorkoutID: workoutID)

        telemetrySink.record(TelemetryEvent(
            category: "workout",
            name: "session_completed",
            severity: .info,
            message: "Completed workout"
        ))

        // Best-effort snapshot read for the return value. Completion
        // already succeeded and teardown already ran, so a fetch error
        // here is not a failure of the operation — just a missing
        // return payload.
        let completedSession = (try? workoutRepository.workout(withIdentifier: workoutID))
            .flatMap { $0 }
            .map(Self.recentSession)

        await refresh()
        return completedSession
        #else
        return nil
        #endif
    }

    /// Delete a completed local workout session from history.
    @discardableResult
    public func deleteWorkoutSession(_ session: RecentSession) async -> Bool {
        #if canImport(SwiftData)
        guard let workoutRepository,
              let identifier = session.identifier,
              session.isUserDeletable
        else { return false }

        do {
            try workoutRepository.deleteWorkout(identifier: identifier)
            telemetrySink.record(TelemetryEvent(
                category: "workout",
                name: "deleted",
                severity: .info,
                message: "Deleted workout session from history.",
                metadata: [
                    "workout_id": identifier,
                    "title": session.title ?? "",
                ]
            ))
            await refresh()
            return true
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "workout",
                name: "delete_failed",
                severity: .error,
                message: error.localizedDescription,
                metadata: ["workout_id": identifier]
            ))
            return false
        }
        #else
        return false
        #endif
    }

    /// Record the active rest timer finishing. The timer itself is owned
    /// by the Workouts surface so the one-second display can re-render
    /// locally; telemetry belongs on the dashboard model with the rest
    /// of the workout events.
    public func recordRestTimerExpired(duration: TimeInterval) {
        telemetrySink.record(TelemetryEvent(
            category: "workout",
            name: "rest_timer.expired",
            severity: .info,
            message: "Rest timer expired.",
            metadata: [
                "duration_seconds": String(Int(max(0, duration).rounded())),
                "active_workout_id": activeWorkoutID ?? "",
            ]
        ))
    }

    public func recordOnboardingResumed(stepRaw: Int) {
        telemetrySink.record(TelemetryEvent(
            category: "onboarding",
            name: "resumed",
            severity: .info,
            message: "Onboarding resumed from saved progress.",
            metadata: ["step": String(stepRaw)]
        ))
    }

    public func recordCloudSyncUnavailableIfNeeded() async {
        guard !didRecordCloudSyncUnavailable else { return }
        #if canImport(StoreKit)
        guard let syncEngine else {
            didRecordCloudSyncUnavailable = true
            telemetrySink.record(TelemetryEvent(
                category: "cloudsync",
                name: "unavailable",
                severity: .warning,
                message: "Cloud sync engine is not configured for this launch."
            ))
            return
        }
        let isAvailable = await syncEngine.isAvailable
        guard !isAvailable else { return }
        didRecordCloudSyncUnavailable = true
        telemetrySink.record(TelemetryEvent(
            category: "cloudsync",
            name: "unavailable",
            severity: .warning,
            message: "Cloud sync is unavailable for this launch."
        ))
        #endif
    }

    public func recordAbortedCoachStreamIfNeeded() {
        guard CoachStreamRecoveryStore.consumeAbortedStream() else { return }
        telemetrySink.record(TelemetryEvent(
            category: "coach",
            name: "stream.aborted",
            severity: .warning,
            message: "Previous coach stream was interrupted before completion."
        ))
    }

    public func flushWatchConnectivityPendingPayloads() async {
        guard let watchConnectivityCoordinator else { return }
        let pendingBefore = await watchConnectivityCoordinator.pendingPayloadCount()
        guard pendingBefore > 0 else { return }

        do {
            try await watchConnectivityCoordinator.flushPendingIfReachable()
        } catch {
            let pendingAfterFailure = await watchConnectivityCoordinator.pendingPayloadCount()
            publishWatchConnectivityQueuedNotice(pending: pendingAfterFailure)
            return
        }

        let pendingAfter = await watchConnectivityCoordinator.pendingPayloadCount()
        if pendingAfter == 0 {
            publishWatchConnectivityReplayedNotice(replayed: pendingBefore)
        } else {
            publishWatchConnectivityQueuedNotice(pending: pendingAfter)
        }
    }

    func publishWatchConnectivityQueuedNotice(pending: Int) {
        watchConnectivityNotice = WatchConnectivityNotice(
            kind: .queued,
            title: String(localized: "Watch update queued", comment: "Toast title when WatchConnectivity payloads are queued"),
            message: String(
                localized: "We'll replay ^[\(pending) update](inflect: true) when your Watch reconnects.",
                comment: "Toast message when WatchConnectivity payloads are queued; placeholder is pending payload count"
            ),
            severity: .warning
        )
    }

    private func publishWatchConnectivityReplayedNotice(replayed: Int) {
        watchConnectivityNotice = WatchConnectivityNotice(
            kind: .replayed,
            title: String(localized: "Watch back in sync", comment: "Toast title when queued WatchConnectivity payloads replay"),
            message: String(
                localized: "Replayed ^[\(replayed) queued update](inflect: true).",
                comment: "Toast message when WatchConnectivity payloads replay; placeholder is replayed payload count"
            ),
            severity: .info
        )
    }

    public func connectAppleAccount(userID: String, displayName: String, email: String?) async {
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedUserID.isEmpty == false else {
            telemetrySink.record(TelemetryEvent(
                category: "account",
                name: "apple_sign_in_missing_user",
                severity: .warning,
                message: "Apple sign-in returned no stable user identifier."
            ))
            return
        }

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = AccountSession(
            provider: "apple",
            userID: trimmedUserID,
            displayName: trimmedDisplayName,
            email: trimmedEmail?.isEmpty == false ? trimmedEmail : nil
        )
        accountSessionStore.save(session)
        accountSession = session
        telemetrySink.record(TelemetryEvent(
            category: "account",
            name: "apple_sign_in_connected",
            severity: .info,
            message: "Apple account connected for profile sync."
        ))

        let currentName = athlete.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentName.isEmpty, trimmedDisplayName.isEmpty == false {
            await updateProfile(UserProfileDefaults(
                name: trimmedDisplayName,
                coachingStyle: athlete.coachingStyle,
                privacyMode: athlete.privacyMode,
                advancementLevel: athlete.advancementLevel,
                availableEquipment: Array(athlete.availableEquipment),
                preferredRepRangeLower: athlete.preferredRepRange.lowerBound,
                preferredRepRangeUpper: athlete.preferredRepRange.upperBound,
                sessionTimeBudgetMinutes: athlete.sessionTimeBudgetMinutes,
                weeklyTrainingDays: athlete.weeklyTrainingDays
            ))
        }
    }

    public func clearAccountSession() {
        accountSessionStore.clear()
        accountSession = nil
        telemetrySink.record(TelemetryEvent(
            category: "account",
            name: "session_cleared",
            severity: .info,
            message: "Account session cleared."
        ))
    }

    /// Persist profile updates from the edit screen or onboarding.
    public func updateProfile(_ defaults: UserProfileDefaults) async {
        #if canImport(SwiftData)
        guard let userProfileRepository else { return }
        let previousCoachingStyle = athlete.coachingStyle
        let previousPrivacyMode = athlete.privacyMode
        do {
            try userProfileRepository.upsertProfile(defaults)
            try userProfileRepository.markOnboardingComplete()
            telemetrySink.record(TelemetryEvent(
                category: "profile",
                name: "profile_updated",
                severity: .info,
                message: "Profile updated for \(defaults.name.isEmpty ? "athlete" : defaults.name)"
            ))
            recordProfilePreferenceTelemetry(
                previousCoachingStyle: previousCoachingStyle,
                previousPrivacyMode: previousPrivacyMode,
                defaults: defaults
            )
            await refresh()
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "profile",
                name: "profile_update_failed",
                severity: .error,
                message: error.localizedDescription
            ))
        }
        #endif
    }

    @discardableResult
    public func appendCoachMemory(content: String, theme: String = "manual") async -> Bool {
        #if canImport(SwiftData)
        guard let coachMemoryRepository else { return false }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTheme = theme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return false }

        do {
            let resolvedTheme = trimmedTheme.isEmpty ? "manual" : trimmedTheme
            try coachMemoryRepository.append(content: trimmedContent, theme: resolvedTheme)
            telemetrySink.record(TelemetryEvent(
                category: "coach.memory",
                name: "manual_saved",
                severity: .info,
                message: "Saved coach memory entry",
                metadata: ["theme": resolvedTheme]
            ))
            await refresh()
            return true
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "coach.memory",
                name: "manual_save_failed",
                severity: .error,
                message: error.localizedDescription
            ))
            return false
        }
        #else
        return false
        #endif
    }

    /// Trigger a cloud sync cycle.
    public func syncNow() async {
        telemetrySink.record(TelemetryEvent(
            category: "sync",
            name: "sync_requested",
            severity: .info,
            message: "Manual sync requested"
        ))

        #if canImport(StoreKit)
        if let syncEngine {
            do {
                let recordCount = try await syncEngine.syncCycle()
                telemetrySink.record(TelemetryEvent(
                    category: "sync",
                    name: "sync_complete",
                    severity: .info,
                    message: "Synced \(recordCount) records"
                ))
            } catch {
                telemetrySink.record(TelemetryEvent(
                    category: "sync",
                    name: "sync_failed",
                    severity: .warning,
                    message: error.localizedDescription
                ))
            }
        }
        #endif

        await refresh()
    }

    /// Pattern-match the user's prompt to infer a memory theme for organization.
    private func inferTheme(from prompt: String) -> String {
        let lowered = prompt.lowercased()
        if lowered.contains("squat") { return "squat" }
        if lowered.contains("bench") { return "bench" }
        if lowered.contains("dead") { return "deadlift" }
        if lowered.contains("press") { return "overhead_press" }
        if lowered.contains("ready") || lowered.contains("recovery") { return "readiness" }
        if lowered.contains("deload") || lowered.contains("back off") { return "deload" }
        if lowered.contains("form") || lowered.contains("technique") { return "form" }
        return "general"
    }

    // MARK: - Watch & Health handlers

    // MARK: - Widget / Live Activity state publishing

    private func publishWidgetSnapshot() {
        let liveExerciseName = activeSessionExercise?.name ?? autopilot?.nextExerciseName
        let liveWeight = activeSessionExercise.map { Double($0.weight) } ?? autopilot?.nextTarget.weight
        let liveReps = activeSessionExercise?.reps ?? autopilot?.nextTarget.repRange.lowerBound
        let snapshot = WidgetSummarySnapshot(
            nextWorkoutTitle: nextWorkout?.title ?? liveExerciseName ?? "Strength Session",
            readinessScore: "\(readiness.score)",
            primaryLiftForecast: liveExerciseName.map { name in
                if let liveWeight {
                    return "\(name) @ \(Int(liveWeight))lb"
                }
                return name
            } ?? "Open to plan your session",
            nextActionTitle: isSessionActive ? "Continue" : "Start",
            syncSummary: isSessionActive ? "Session in progress" : "\(recentSessions.count) this week",
            streakDays: computeStreakDays(),
            coachPrompt: autopilot?.recommendationReason ?? "What should I do next?"
        )
        PlatformSurfaceDefaultsWriter.saveWidgetSnapshot(snapshot)

        if isSessionActive, let liveExerciseName {
            let state = LiveActivityState(
                workoutTitle: activeWorkoutTitle ?? "Strength Session",
                activeExerciseName: liveExerciseName,
                targetSummary: "\(Int(liveWeight ?? 0))lb × \(liveReps ?? 1)",
                setProgressSummary: liveActivitySetProgressSummary(),
                restSecondsRemaining: nil
            )
            PlatformSurfaceDefaultsWriter.saveLiveActivityState(state)
            if publishedLiveActivityWorkoutID != activeWorkoutID {
                publishedLiveActivityWorkoutID = activeWorkoutID
                telemetrySink.record(TelemetryEvent(
                    category: "liveactivity",
                    name: "started",
                    severity: .info,
                    message: "Published active workout state for Live Activity.",
                    metadata: [
                        "workout_id": activeWorkoutID ?? "",
                        "workout": state.workoutTitle,
                        "exercise": state.activeExerciseName
                    ]
                ))
            }
        } else if !isSessionActive {
            PlatformSurfaceDefaultsWriter.clearLiveActivityState()
            if let workoutID = publishedLiveActivityWorkoutID {
                publishedLiveActivityWorkoutID = nil
                telemetrySink.record(TelemetryEvent(
                    category: "liveactivity",
                    name: "ended",
                    severity: .info,
                    message: "Cleared active workout Live Activity state.",
                    metadata: ["workout_id": workoutID]
                ))
            }
        }
    }

    private func liveActivitySetProgressSummary() -> String {
        if activeSessionExerciseSetCount > 0 {
            let current = min(loggedSetCountForActiveExercise + 1, activeSessionExerciseSetCount)
            return "Set \(current) of \(activeSessionExerciseSetCount)"
        }
        return autopilot?.liveActivitySetProgressSummary(loggedSetCount: loggedSetCountThisSession) ?? "Set 1 of 1"
    }

    private func computeStreakDays() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var cursor = Date.now
        let sortedSessions = recentSessions.sorted { $0.date > $1.date }
        for session in sortedSessions {
            if calendar.isDate(session.date, inSameDayAs: cursor) {
                streak += 1
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            } else if session.date < cursor {
                break
            }
        }
        return streak
    }

    public func handleHealthBackgroundUpdate(_ update: HealthBackgroundUpdate) async {
        telemetrySink.record(TelemetryEvent(
            category: "health",
            name: "background_update",
            severity: .info,
            message: "Background health update for \(update.workoutID)"
        ))
        await refresh()
    }
}

public extension WorkoutDashboardModel {
    /// Log the currently recommended set from autopilot state.
    func logRecommendedSet(
        weightOverride: Double? = nil,
        repsOverride: Int? = nil,
        rpeOverride: Double? = nil,
        exerciseIDOverride: String? = nil,
        exerciseNameOverride: String? = nil
    ) async {
        #if canImport(SwiftData)
        guard let workoutRepository else { return }

        if autopilot == nil && activeSessionExercise == nil {
            await refresh()
        }
        guard autopilot != nil || activeSessionExercise != nil else { return }

        if activeWorkoutID == nil {
            await startWorkoutSession()
        }
        guard let workoutID = activeWorkoutID else { return }

        let plannedExercise = activeSessionExercise
        let exerciseName = exerciseNameOverride
            ?? plannedExercise?.name
            ?? autopilot?.nextExerciseName
            ?? "Current exercise"
        let exerciseID = exerciseIDOverride
            ?? plannedExercise.map { Self.exerciseIdentifier(named: $0.name) }
            ?? autopilot?.nextExerciseID
            ?? Self.exerciseIdentifier(named: exerciseName)
        let set = WorkoutSetPerformance(
            weight: weightOverride ?? plannedExercise.map { Double($0.weight) } ?? autopilot?.nextTarget.weight ?? 0,
            reps: repsOverride ?? plannedExercise?.reps ?? autopilot?.nextTarget.repRange.lowerBound ?? 1,
            rpe: rpeOverride ?? plannedExercise.map { Double($0.targetRPE) } ?? autopilot?.nextTarget.targetRPE ?? 7,
            completedAt: .now
        )

        do {
            try workoutRepository.appendSet(
                set,
                forExercise: exerciseID,
                to: workoutID
            )
            loggedSetCountThisSession += 1
            advanceActiveSessionPlanAfterLoggedSet()
            persistActiveSessionStateIfNeeded()

            telemetrySink.record(TelemetryEvent(
                category: "workout",
                name: "set_logged",
                severity: .info,
                message: "Logged \(Int(set.weight))lb x \(set.reps) on \(exerciseName)"
            ))

            await refresh()
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "workout",
                name: "set_log_failed",
                severity: .error,
                message: error.localizedDescription
            ))
        }
        #endif
    }

    /// VOL-110: BGTask app-refresh entry point with bracketing telemetry.
    @discardableResult
    func performBackgroundRefresh() async -> Bool {
        recordBackgroundTaskWake(kind: "app_refresh")
        telemetrySink.record(TelemetryEvent(
            category: "background",
            name: "refresh_started",
            severity: .info,
            message: "BGTask app-refresh handler entered."
        ))
        let success = await refresh()
        telemetrySink.record(TelemetryEvent(
            category: "background",
            name: success ? "refresh_completed" : "refresh_failed",
            severity: success ? .info : .error,
            message: success
                ? "BGTask app-refresh handler completed."
                : "BGTask app-refresh handler failed."
        ))
        return success
    }

    /// BGProcessing entry point with the same observability contract as app refresh.
    func performBackgroundProcessing() async {
        recordBackgroundTaskWake(kind: "app_processing")
        telemetrySink.record(TelemetryEvent(
            category: "background",
            name: "processing_started",
            severity: .info,
            message: "BGTask app-processing handler entered."
        ))
        await syncNow()
        telemetrySink.record(TelemetryEvent(
            category: "background",
            name: "processing_completed",
            severity: .info,
            message: "BGTask app-processing handler completed."
        ))
    }

    private func recordBackgroundTaskWake(kind: String) {
        telemetrySink.record(TelemetryEvent(
            category: "bgtask",
            name: "fired",
            severity: .info,
            message: "BGTask wake fired.",
            metadata: ["kind": kind]
        ))
    }

    /// VOL-109: request Apple Health authorization through the runtime prompt gate.
    @discardableResult
    func requestHealthKitAuthorization() async -> Bool {
        guard VolumeArcRuntimeFlags.shouldSurfacePermissionPrompts else {
            isHealthAuthorized = await healthStore.isAuthorized
            telemetrySink.record(TelemetryEvent(
                category: "health",
                name: "auth_skipped",
                severity: .info,
                message: "HealthKit prompt skipped under deterministic mode without simulation flag."
            ))
            return false
        }

        do {
            let result = try await healthStore.requestAuthorization()
            isHealthAuthorized = await healthStore.isAuthorized
            telemetrySink.record(TelemetryEvent(
                category: "health",
                name: "auth_requested",
                severity: .info,
                message: "HealthKit authorization request returned canShareWorkouts=\(result.canShareWorkouts)."
            ))
            if result.canShareWorkouts && isHealthAuthorized {
                recordHealthKitPermissionOutcome(
                    name: "authorized",
                    severity: .info,
                    message: "Apple Health authorization granted."
                )
            } else {
                recordHealthKitPermissionOutcome(
                    name: "denied",
                    severity: .warning,
                    message: "Apple Health authorization was denied or incomplete."
                )
            }
            return result.canShareWorkouts && isHealthAuthorized
        } catch {
            isHealthAuthorized = await healthStore.isAuthorized
            telemetrySink.record(TelemetryEvent(
                category: "health",
                name: "auth_failed",
                severity: .warning,
                message: "HealthKit authorization request errored: \(error.localizedDescription)"
            ))
            if error.localizedDescription.localizedCaseInsensitiveContains("denied") {
                recordHealthKitPermissionOutcome(
                    name: "denied",
                    severity: .warning,
                    message: "Apple Health authorization was denied."
                )
            }
            return false
        }
    }

    private func recordHealthKitPermissionOutcome(
        name: String,
        severity: TelemetrySeverity,
        message: String
    ) {
        telemetrySink.record(TelemetryEvent(
            category: "healthkit",
            name: name,
            severity: severity,
            message: message
        ))
    }
}

// MARK: - Coach

extension WorkoutDashboardModel {
    /// Send a prompt to the AI coach and stream the response into `coachMessages` token-by-token.
    public func askCoach(_ prompt: String) async {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        coachMessages.append(CoachMessage(id: UUID(), sender: .user, content: prompt))
        coachFallbackNotice = nil
        isCoachStreaming = true
        CoachStreamRecoveryStore.markInFlight()
        let fallbackObserver = makeCoachFallbackObserver()
        defer {
            NotificationCenter.default.removeObserver(fallbackObserver)
            isCoachStreaming = false
        }

        let context = buildCoachContext()
        let outboundPrompt = PromptPrivacyRedactor.redactQuestion(prompt, privacyMode: athlete.privacyMode)
        let streamingID = appendEmptyCoachMessage()

        do {
            let accumulated = try await streamCoachResponse(
                prompt: outboundPrompt,
                context: context,
                streamingID: streamingID
            )
            persistCoachMemory(prompt: prompt, response: accumulated)
            recordCoachAskComplete(characterCount: accumulated.count)
            CoachStreamRecoveryStore.clear()
        } catch is CancellationError {
            // Leave the in-flight marker intact. If the process is killed
            // mid-stream, the next launch consumes it and records
            // `coach.stream.aborted`; clearing here would hide the recovery
            // signal exactly when the user lost the turn.
        } catch {
            replaceCoachMessage(
                id: streamingID,
                content: String(
                    localized: "I'm having trouble reaching my knowledge base. Try again in a moment.",
                    comment: "Coach message shown when coach response fails and fallback content is unavailable"
                )
            )
            recordCoachAskFailure(error)
            CoachStreamRecoveryStore.clear()
        }
    }

    @discardableResult
    public func requestVoicePermissions() async -> Bool {
        do {
            let current = await voicePermissionStore.currentStatus()
            if current.isAuthorized {
                voicePermissionStatus = current
                recordVoiceEnabled(status: current)
                voiceNotice = nil
                return true
            }

            guard VolumeArcRuntimeFlags.shouldSurfacePermissionPrompts else {
                voicePermissionStatus = current
                publishVoicePermissionNotice(status: current)
                return false
            }

            let requested = try await voicePermissionStore.requestPermissions()
            voicePermissionStatus = requested
            guard requested.isAuthorized else {
                publishVoicePermissionNotice(status: requested)
                return false
            }

            recordVoiceEnabled(status: requested)
            voiceNotice = nil
            return true
        } catch {
            voiceNotice = String(
                localized: "Voice setup could not start. Check microphone and speech permissions.",
                comment: "Coach voice setup failure notice"
            )
            telemetrySink.record(TelemetryEvent(
                category: "voice",
                name: "permission_failed",
                severity: .warning,
                message: error.localizedDescription
            ))
            return false
        }
    }

    @discardableResult
    public func askCoachByVoice(_ prompt: String) async -> Bool {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !isCoachStreaming, !isVoiceTurnActive else { return false }
        guard await requestVoicePermissions() else { return false }

        coachMessages.append(CoachMessage(id: UUID(), sender: .user, content: trimmedPrompt))
        coachFallbackNotice = nil
        voiceNotice = nil
        isVoiceTurnActive = true
        isCoachStreaming = true
        let streamingID = appendEmptyCoachMessage()
        let context = buildCoachContext()
        let outboundPrompt = PromptPrivacyRedactor.redactQuestion(trimmedPrompt, privacyMode: athlete.privacyMode)
        recordVoiceSessionStarted(promptLength: trimmedPrompt.count)

        defer {
            isVoiceTurnActive = false
            isCoachStreaming = false
        }

        do {
            let response = try await voiceCoach.speak(prompt: outboundPrompt, context: context)
            replaceCoachMessage(id: streamingID, content: response)
            persistCoachMemory(prompt: trimmedPrompt, response: response)
            recordCoachAskComplete(characterCount: response.count)
            recordVoiceSessionCompleted(characterCount: response.count)
            return true
        } catch {
            replaceCoachMessage(
                id: streamingID,
                content: String(
                    localized: "Voice coach is unavailable right now. Type your question and send it instead.",
                    comment: "Coach message shown when a voice coach turn cannot complete"
                )
            )
            voiceNotice = String(
                localized: "Voice is unavailable. Text coach still works.",
                comment: "Coach voice unavailable banner message"
            )
            recordVoiceSessionFailed(error)
            return false
        }
    }

    private func publishVoicePermissionNotice(status: VoicePermissionStatus) {
        let message: String
        if status.isDeniedOrUnavailable {
            message = String(
                localized: "Enable microphone and speech access in Settings to use voice.",
                comment: "Coach voice permission denied or unavailable notice"
            )
        } else {
            message = String(
                localized: "Voice needs microphone and speech access before it can start.",
                comment: "Coach voice permission not yet determined notice"
            )
        }
        voiceNotice = message
        telemetrySink.record(TelemetryEvent(
            category: "voice",
            name: "permission_blocked",
            severity: .warning,
            message: message,
            metadata: [
                "microphone": status.microphone.rawValue,
                "speech": status.speechRecognition.rawValue,
            ]
        ))
    }

    private func recordVoiceEnabled(status: VoicePermissionStatus) {
        telemetrySink.record(TelemetryEvent(
            category: "voice",
            name: "enabled",
            severity: .info,
            message: "Voice permissions are enabled.",
            metadata: [
                "microphone": status.microphone.rawValue,
                "speech": status.speechRecognition.rawValue,
            ]
        ))
    }

    private func recordVoiceSessionStarted(promptLength: Int) {
        telemetrySink.record(TelemetryEvent(
            category: "voice",
            name: "session_started",
            severity: .info,
            message: "Voice coach turn started.",
            metadata: ["prompt_length": String(promptLength)]
        ))
    }

    private func recordVoiceSessionCompleted(characterCount: Int) {
        telemetrySink.record(TelemetryEvent(
            category: "voice",
            name: "session_completed",
            severity: .info,
            message: "Voice coach turn completed.",
            metadata: ["character_count": String(characterCount)]
        ))
    }

    private func recordVoiceSessionFailed(_ error: Error) {
        telemetrySink.record(TelemetryEvent(
            category: "voice",
            name: "session_failed",
            severity: .warning,
            message: error.localizedDescription
        ))
    }

    private func makeCoachFallbackObserver() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .coachFallbackUsed,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showTemporaryCoachFallbackNotice(String(
                    localized: "Coach is offline — quick local recommendation.",
                    comment: "Coach banner shown when relay response falls back to local heuristic"
                ))
            }
        }
    }

    private func showTemporaryCoachFallbackNotice(_ notice: String) {
        coachFallbackNotice = notice
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard self?.coachFallbackNotice == notice else { return }
            self?.coachFallbackNotice = nil
        }
    }

    private func appendEmptyCoachMessage() -> UUID {
        let streamingID = UUID()
        coachMessages.append(CoachMessage(id: streamingID, sender: .coach, content: ""))
        return streamingID
    }

    private func streamCoachResponse(prompt: String, context: String, streamingID: UUID) async throws -> String {
        var accumulated = ""
        accumulated.reserveCapacity(4_096)
        var accumulatedCharacterCount = 0
        var didRecordFirstToken = false
        var lastPublishedCharacterCount = 0
        let publishCharacterStride = 64
        let stream = aiProvider.streamCoachResponse(for: prompt, context: context)
        for try await chunk in stream {
            accumulated += chunk
            // Avoid calling String.count on the full accumulated response for every streamed chunk.
            accumulatedCharacterCount += chunk.count

            if !didRecordFirstToken,
               !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                didRecordFirstToken = true
                recordCoachFirstToken()
                replaceCoachMessage(id: streamingID, content: accumulated)
                lastPublishedCharacterCount = accumulatedCharacterCount
                continue
            }

            if accumulatedCharacterCount - lastPublishedCharacterCount >= publishCharacterStride {
                replaceCoachMessage(id: streamingID, content: accumulated)
                lastPublishedCharacterCount = accumulatedCharacterCount
            }
        }
        if accumulatedCharacterCount != lastPublishedCharacterCount {
            replaceCoachMessage(id: streamingID, content: accumulated)
        }
        return accumulated
    }

    private func replaceCoachMessage(id: UUID, content: String) {
        guard let index = coachMessages.firstIndex(where: { $0.id == id }) else { return }
        coachMessages[index] = CoachMessage(
            id: id,
            sender: .coach,
            content: content,
            timestamp: coachMessages[index].timestamp
        )
    }

    private func persistCoachMemory(prompt: String, response: String) {
        #if canImport(SwiftData)
        guard !response.isEmpty else { return }
        try? coachMemoryRepository?.append(
            content: "User asked: \(prompt)\nCoach said: \(response)",
            theme: inferTheme(from: prompt)
        )
        #endif
    }

    private func recordCoachAskComplete(characterCount: Int) {
        telemetrySink.record(TelemetryEvent(
            category: "coach",
            name: "ask_complete",
            severity: .info,
            message: "Coach responded (\(characterCount) chars)"
        ))
    }

    private func recordCoachFirstToken() {
        telemetrySink.record(TelemetryEvent(
            category: "coach",
            name: "first_token_received",
            severity: .info,
            message: "Coach response began streaming."
        ))
    }

    private func recordCoachAskFailure(_ error: Error) {
        telemetrySink.record(TelemetryEvent(
            category: "coach",
            name: "ask_failed",
            severity: .warning,
            message: error.localizedDescription
        ))
    }
}

// MARK: - Coach message model

public struct CoachMessage: Sendable, Identifiable, Equatable {
    public enum Sender: Sendable {
        case user
        case coach
    }

    public let id: UUID
    public let sender: Sender
    public let content: String
    public let timestamp: Date

    public init(id: UUID = UUID(), sender: Sender, content: String, timestamp: Date = .now) {
        self.id = id
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
    }
}
#endif
