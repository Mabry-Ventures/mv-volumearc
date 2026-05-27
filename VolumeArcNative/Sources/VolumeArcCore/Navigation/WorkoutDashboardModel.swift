// swiftlint:disable file_length
#if canImport(SwiftUI)
import Foundation
import SwiftUI
#if canImport(SwiftData)
import SwiftData
#endif

/// The central view model that drives every screen in the iOS app.
///
/// Responsibilities:
/// - Holds the current readiness assessment, autopilot state, and recent sessions
/// - Drives dashboard action methods (start session, log set, sync)
/// - Routes Watch Connectivity and Health background updates into the data layer
/// - Publishes streaming coach messages and startup signals to the UI
@MainActor
public final class WorkoutDashboardModel: ObservableObject {

    // MARK: - Published state
    @Published public private(set) var readiness: ReadinessAssessment = ReadinessAssessment(score: 85, brief: "Ready to train.", factors: [])
    @Published public private(set) var autopilot: WorkoutAutopilotState?
    @Published public private(set) var recentSessions: [RecentSession] = []
    @Published public private(set) var athlete: AthleteProfile = VolumeArcProductDefaults.athleteProfile
    @Published public private(set) var nextWorkout: WeeklyWorkout?
    @Published public private(set) var trainingPrograms: [TrainingProgramDefinition] = TrainingProgramCatalog.curated
    @Published public private(set) var activeProgram: ActiveTrainingProgramContext?
    @Published public private(set) var coachMemory: CoachMemory = CoachMemory()
    @Published public internal(set) var latestFormCheckAnalysis: FormCheckAnalysis?

    @Published public var activeWorkoutTitle: String?
    @Published public private(set) var isSessionActive: Bool = false
    @Published public private(set) var loggedSetCountThisSession: Int = 0

    @Published public var startupNotice: String?
    @Published public var startupNoticeSeverity: TelemetrySeverity?
    @Published public private(set) var operationalSignals: [OperationalSignalSummary] = []

    @Published public var coachMessages: [CoachMessage] = []
    @Published public private(set) var isCoachStreaming: Bool = false
    @Published public private(set) var coachFallbackNotice: String?

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

    // MARK: - Dependencies
    private let aiProvider: AICoachProvider
    private let voiceCoach: LiveVoiceCoachOrchestrator
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

    var activeWorkoutID: String?
    var completedWatchFormCheckSessionIDs: Set<String> = []

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
        watchConnectivityCoordinator: WatchConnectivityCoordinator? = nil
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
        self.telemetrySink = telemetrySink
        self.featureFlags = featureFlags ?? LocalFeatureFlagProvider()
        self.healthStore = healthStore
        self.recoveryReader = recoveryReader
        self.healthWorkoutImporter = healthWorkoutImporter
        self.watchVoiceSettingsStore = watchVoiceSettingsStore
        self.watchConnectivityCoordinator = watchConnectivityCoordinator
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
        watchConnectivityCoordinator: WatchConnectivityCoordinator? = nil
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
        self.telemetrySink = telemetrySink
        self.featureFlags = featureFlags ?? LocalFeatureFlagProvider()
        self.healthStore = healthStore
        self.recoveryReader = recoveryReader
        self.healthWorkoutImporter = healthWorkoutImporter
        self.watchVoiceSettingsStore = watchVoiceSettingsStore
        self.watchConnectivityCoordinator = watchConnectivityCoordinator
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

    public init(
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
        watchConnectivityCoordinator: WatchConnectivityCoordinator? = nil
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
        self.telemetrySink = telemetrySink
        self.featureFlags = featureFlags ?? LocalFeatureFlagProvider()
        self.healthStore = healthStore
        self.recoveryReader = recoveryReader
        self.healthWorkoutImporter = healthWorkoutImporter
        self.watchVoiceSettingsStore = watchVoiceSettingsStore
        self.watchConnectivityCoordinator = watchConnectivityCoordinator
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
        Task { await refresh() }
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
            self.trainingPrograms = snapshot.trainingPrograms
            self.activeProgram = snapshot.activeProgram
            self.coachMemory = snapshot.coachMemory

            if let active = snapshot.activeWorkout {
                // VOL-256: active-workout recovery contract. When the
                // model boots and finds a `WorkoutRecord` with
                // `completedAt == nil` (i.e., the user crashed / was
                // memory-killed mid-session), we silently restore the
                // session state — `isSessionActive = true`,
                // `activeWorkoutID` rehydrated, completed set count
                // preserved. The Today tab's `quickActionsRow` then
                // renders "Continue Session" instead of "Start
                // Workout" via the existing
                // `model.isSessionActive` gate. Silent restoration is
                // intentional: a strength athlete who crashes mid-set
                // wants their workout back, not a "Resume / Discard?"
                // prompt that risks accidental discard.
                //
                // Telemetry: emit one `.info` event per refresh that
                // restores a session that wasn't already active in
                // the model. The `wasActive` guard de-duplicates so
                // the periodic refresh loop doesn't fire the event
                // on every poll; only the "active appeared from
                // nowhere" transition counts as a recovery.
                let wasActive = self.isSessionActive
                self.activeWorkoutID = active.identifier
                self.activeWorkoutTitle = active.title
                self.isSessionActive = true
                self.loggedSetCountThisSession = active.completedSetCount
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
            } else {
                self.activeWorkoutID = nil
                self.activeWorkoutTitle = nil
                self.isSessionActive = false
                self.loggedSetCountThisSession = 0
            }

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

    // MARK: - Dashboard actions
    /// Start a new workout session.
    public func startWorkoutSession() async {
        #if canImport(SwiftData)
        guard let workoutRepository else { return }
        do {
            let title = nextWorkout?.title ?? "Strength Session"
            let workout = try workoutRepository.createWorkout(title: title)
            self.activeWorkoutID = workout.identifier
            self.activeWorkoutTitle = workout.title
            self.isSessionActive = true
            self.loggedSetCountThisSession = 0

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
        let snapshot = WidgetSummarySnapshot(
            nextWorkoutTitle: nextWorkout?.title ?? autopilot?.nextExerciseName ?? "Strength Session",
            readinessScore: "\(readiness.score)",
            primaryLiftForecast: autopilot.map { "\($0.nextExerciseName) @ \(Int($0.nextTarget.weight))lb" } ?? "Open to plan your session",
            nextActionTitle: isSessionActive ? "Continue" : "Start",
            syncSummary: isSessionActive ? "Session in progress" : "\(recentSessions.count) this week",
            streakDays: computeStreakDays(),
            coachPrompt: autopilot?.recommendationReason ?? "What should I do next?"
        )
        PlatformSurfaceDefaultsWriter.saveWidgetSnapshot(snapshot)

        if let autopilot, isSessionActive {
            let state = LiveActivityState(
                workoutTitle: activeWorkoutTitle ?? "Strength Session",
                activeExerciseName: autopilot.nextExerciseName,
                targetSummary: "\(Int(autopilot.nextTarget.weight))lb × \(autopilot.nextTarget.repRange.lowerBound)",
                setProgressSummary: autopilot.liveActivitySetProgressSummary(
                    loggedSetCount: loggedSetCountThisSession
                ),
                restSecondsRemaining: nil
            )
            PlatformSurfaceDefaultsWriter.saveLiveActivityState(state)
        } else if !isSessionActive {
            PlatformSurfaceDefaultsWriter.clearLiveActivityState()
        }
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
    func logRecommendedSet() async {
        #if canImport(SwiftData)
        guard let workoutRepository else { return }

        if autopilot == nil {
            await refresh()
        }
        guard let autopilot else { return }

        if activeWorkoutID == nil {
            await startWorkoutSession()
        }
        guard let workoutID = activeWorkoutID else { return }

        let set = WorkoutSetPerformance(
            weight: autopilot.nextTarget.weight,
            reps: autopilot.nextTarget.repRange.lowerBound,
            rpe: autopilot.nextTarget.targetRPE,
            completedAt: .now
        )

        do {
            try workoutRepository.appendSet(
                set,
                forExercise: autopilot.nextExerciseID,
                to: workoutID
            )
            loggedSetCountThisSession += 1

            telemetrySink.record(TelemetryEvent(
                category: "workout",
                name: "set_logged",
                severity: .info,
                message: "Logged \(Int(set.weight))lb x \(set.reps) on \(autopilot.nextExerciseName)"
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
            return result.canShareWorkouts && isHealthAuthorized
        } catch {
            isHealthAuthorized = await healthStore.isAuthorized
            telemetrySink.record(TelemetryEvent(
                category: "health",
                name: "auth_failed",
                severity: .warning,
                message: "HealthKit authorization request errored: \(error.localizedDescription)"
            ))
            return false
        }
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
        } catch {
            replaceCoachMessage(
                id: streamingID,
                content: String(
                    localized: "I'm having trouble reaching my knowledge base. Try again in a moment.",
                    comment: "Coach message shown when coach response fails and fallback content is unavailable"
                )
            )
            recordCoachAskFailure(error)
        }
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
        let stream = aiProvider.streamCoachResponse(for: prompt, context: context)
        for try await chunk in stream {
            accumulated += chunk
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
