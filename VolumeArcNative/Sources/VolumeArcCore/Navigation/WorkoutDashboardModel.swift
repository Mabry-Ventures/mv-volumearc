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

    @Published public var activeWorkoutTitle: String?
    @Published public private(set) var isSessionActive: Bool = false
    @Published public private(set) var loggedSetCountThisSession: Int = 0

    @Published public var startupNotice: String?
    @Published public var startupNoticeSeverity: TelemetrySeverity?
    @Published public private(set) var operationalSignals: [OperationalSignalSummary] = []

    @Published public var coachMessages: [CoachMessage] = []
    @Published public private(set) var isCoachStreaming: Bool = false

    @Published public var isOnboardingComplete: Bool = false
    @Published public private(set) var isNetworkReachable: Bool = true
    @Published public private(set) var hasLoadedInitialData: Bool = false

    /// VOL-112: most-recent `WatchPayloadKind.rawValue` observed by
    /// `handleWatchPayload`. Surfaced as observable state so XCUITests
    /// (and only XCUITests, via the deterministic-mode debug overlay in
    /// `VolumeArcApp`) can assert the watch-payload arrival path
    /// actually fired without scraping telemetry events. In production
    /// this is set as a side effect of every received payload but no UI
    /// reads it — the runtime cost is one optional-string assignment per
    /// payload arrival, which is negligible vs the existing telemetry
    /// `record` + `refresh()` work in the same handler.
    @Published public private(set) var lastWatchPayloadKindForTesting: String?

    // MARK: - Dependencies

    private let aiProvider: AICoachProvider
    private let voiceCoach: LiveVoiceCoachOrchestrator
    private let telemetrySink: TelemetrySink
    private let progressionEngine = ProgressionEngine()
    public let featureFlags: FeatureFlagProvider

    #if canImport(SwiftData)
    private let workoutRepository: SwiftDataWorkoutRepository?
    private let coachMemoryRepository: SwiftDataCoachMemoryRepository?
    private let userProfileRepository: SwiftDataUserProfileRepository?
    private let trainingPlanRepository: SwiftDataTrainingPlanRepository?
    #endif

    #if canImport(StoreKit)
    private let syncEngine: CloudSyncCoordinator?
    public let subscriptionStore: StoreKitSubscriptionStore?
    #endif

    private var activeWorkoutID: String?

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
        featureFlags: FeatureFlagProvider? = nil
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
        self.telemetrySink = telemetrySink
        self.featureFlags = featureFlags ?? LocalFeatureFlagProvider()
        self.workoutRepository = repository
        self.coachMemoryRepository = coachMemoryRepository
        self.userProfileRepository = userProfileRepository
        self.trainingPlanRepository = trainingPlanRepository
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
        featureFlags: FeatureFlagProvider? = nil
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
        self.telemetrySink = telemetrySink
        self.featureFlags = featureFlags ?? LocalFeatureFlagProvider()
        #if canImport(SwiftData)
        self.workoutRepository = nil
        self.coachMemoryRepository = nil
        self.userProfileRepository = nil
        self.trainingPlanRepository = nil
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
        featureFlags: FeatureFlagProvider? = nil
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
        self.telemetrySink = telemetrySink
        self.featureFlags = featureFlags ?? LocalFeatureFlagProvider()
        #if canImport(SwiftData)
        self.workoutRepository = nil
        self.coachMemoryRepository = nil
        self.userProfileRepository = nil
        self.trainingPlanRepository = nil
        #endif
        #if canImport(StoreKit)
        self.syncEngine = nil
        self.subscriptionStore = nil
        #endif
        Task { await refresh() }
    }

    // MARK: - Refresh

    /// Reload all published state from repositories. Called at launch and after writes.
    public func refresh() async {
        #if canImport(SwiftData)
        guard let workoutRepository,
              let userProfileRepository,
              let coachMemoryRepository,
              let trainingPlanRepository else {
            return
        }

        do {
            let profile = try userProfileRepository.athleteProfile()
            self.athlete = profile

            // VOL-99: the perf suite seeds a larger history pool and
            // asserts scroll performance on the Today tab. Bump the fetch
            // limit when `-PerfTestMode 1` is active so the rows exist in
            // memory for XCTest to scroll past.
            let sessionFetchLimit = VolumeArcRuntimeFlags.isPerformanceTestMode ? 60 : 20
            let sessions = try workoutRepository.recentSessions(limit: sessionFetchLimit)
            self.recentSessions = sessions

            self.readiness = progressionEngine.evaluateReadiness(from: sessions, athlete: profile)

            // Find the primary exercise to build autopilot state for.
            let primary = VolumeArcExerciseCatalog.backSquat
            let history = try workoutRepository.history(forExercise: primary.id)
            let memory = try coachMemoryRepository.coachMemory()

            self.autopilot = progressionEngine.buildAutopilotState(
                for: history,
                athlete: profile,
                goal: VolumeArcProductDefaults.strengthGoal,
                recentSessions: sessions,
                memory: memory
            )

            self.nextWorkout = try trainingPlanRepository.nextWorkout()

            // Check active workout state
            if let active = try workoutRepository.activeWorkout() {
                self.activeWorkoutID = active.identifier
                self.activeWorkoutTitle = active.title
                self.isSessionActive = true
                self.loggedSetCountThisSession = active.completedSetCount
            } else {
                self.activeWorkoutID = nil
                self.activeWorkoutTitle = nil
                self.isSessionActive = false
                self.loggedSetCountThisSession = 0
            }

            self.isOnboardingComplete = try userProfileRepository.isOnboardingComplete()
            self.hasLoadedInitialData = true

            // Publish a widget snapshot derived from the freshly loaded state.
            publishWidgetSnapshot()

            telemetrySink.record(TelemetryEvent(
                category: "dashboard",
                name: "refresh",
                severity: .info,
                message: "Dashboard refreshed",
                metadata: ["sessionCount": "\(sessions.count)", "readiness": "\(readiness.score)"]
            ))
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "dashboard",
                name: "refresh_failed",
                severity: .error,
                message: "Failed to refresh dashboard: \(error.localizedDescription)"
            ))
        }
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

    /// Log the currently recommended set from autopilot state.
    public func logRecommendedSet() async {
        #if canImport(SwiftData)
        guard let workoutRepository, let autopilot else { return }

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
        do {
            try userProfileRepository.upsertProfile(defaults)
            try userProfileRepository.markOnboardingComplete()
            telemetrySink.record(TelemetryEvent(
                category: "profile",
                name: "profile_updated",
                severity: .info,
                message: "Profile updated for \(defaults.name.isEmpty ? "athlete" : defaults.name)"
            ))
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

    // MARK: - Coach

    /// Send a prompt to the AI coach and stream the response into `coachMessages` token-by-token.
    public func askCoach(_ prompt: String) async {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let userMessage = CoachMessage(id: UUID(), sender: .user, content: prompt)
        coachMessages.append(userMessage)

        isCoachStreaming = true
        defer { isCoachStreaming = false }

        let context = buildCoachContext()

        // Create a placeholder message we'll append tokens to as they arrive.
        let streamingID = UUID()
        coachMessages.append(CoachMessage(id: streamingID, sender: .coach, content: ""))

        var accumulated = ""
        do {
            let stream = aiProvider.streamCoachResponse(for: prompt, context: context)
            for try await chunk in stream {
                accumulated += chunk
                if let index = coachMessages.firstIndex(where: { $0.id == streamingID }) {
                    coachMessages[index] = CoachMessage(
                        id: streamingID,
                        sender: .coach,
                        content: accumulated,
                        timestamp: coachMessages[index].timestamp
                    )
                }
            }

            // Persist the full response as a coach memory for future prompt grounding.
            #if canImport(SwiftData)
            if !accumulated.isEmpty {
                try? coachMemoryRepository?.append(
                    content: "User asked: \(prompt)\nCoach said: \(accumulated)",
                    theme: inferTheme(from: prompt)
                )
            }
            #endif

            telemetrySink.record(TelemetryEvent(
                category: "coach",
                name: "ask_complete",
                severity: .info,
                message: "Coach responded (\(accumulated.count) chars)"
            ))
        } catch {
            // Replace the placeholder with a user-visible error and keep the conversation alive.
            if let index = coachMessages.firstIndex(where: { $0.id == streamingID }) {
                coachMessages[index] = CoachMessage(
                    id: streamingID,
                    sender: .coach,
                    content: "I'm having trouble reaching my knowledge base. Try again in a moment."
                )
            }

            telemetrySink.record(TelemetryEvent(
                category: "coach",
                name: "ask_failed",
                severity: .warning,
                message: error.localizedDescription
            ))
        }
    }

    /// Build the grounded context block for coach prompts using real dashboard state and
    /// recent coach memories for continuity across conversations.
    private func buildCoachContext() -> String {
        let athleteName = athlete.name.isEmpty ? "the athlete" : athlete.name
        let avgRPE = recentSessions.isEmpty
            ? 0
            : recentSessions.map(\.averageRPE).reduce(0, +) / Double(recentSessions.count)

        let lastSessionSummary: String? = recentSessions
            .max(by: { $0.date < $1.date })
            .map { session in
                let volume = Int(session.totalVolumeLoad)
                let rpe = String(format: "%.1f", session.averageRPE)
                return "\(session.completedSetCount) sets, \(volume)lb total, RPE \(rpe)"
            }

        var memories: [String] = []
        #if canImport(SwiftData)
        if let coachMemoryRepository, let memory = try? coachMemoryRepository.coachMemory() {
            memories = memory.mostRecent.map(\.summary)
        }
        #endif

        let nextExercise = autopilot?.nextExerciseName
        let nextTarget: String? = autopilot.map { state in
            let weight = Int(state.nextTarget.weight)
            let reps = state.nextTarget.repRange
            return "\(weight)lb × \(reps.lowerBound)-\(reps.upperBound)"
        }

        let context = CoachContext(
            athleteName: athleteName,
            advancementLevel: athlete.advancementLevel.rawValue,
            readinessScore: readiness.score,
            readinessBrief: readiness.brief,
            nextExercise: nextExercise,
            nextTarget: nextTarget,
            recentSessionCount: recentSessions.count,
            averageRPE: avgRPE,
            lastSessionSummary: lastSessionSummary,
            recentMemories: memories
        )

        return context.asPromptBlock(privacyMode: athlete.privacyMode)
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

    public func handleWatchPayload(_ payload: WatchPayload) async {
        telemetrySink.record(TelemetryEvent(
            category: "watch",
            name: "payload_received",
            severity: .info,
            message: "Watch payload: \(payload.kind.rawValue)"
        ))
        // VOL-112: pin the most-recent kind for the test-only debug
        // overlay. Done before refresh so a slow refresh doesn't delay
        // the visible signal — XCUITests wait on this string and
        // shouldn't have to wait for the full repository round-trip.
        lastWatchPayloadKindForTesting = payload.kind.rawValue
        await refresh()
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

    #if canImport(SwiftData)
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
    #endif
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
