#if canImport(SwiftUI)
import Foundation
import SwiftUI
#if canImport(SwiftData)
import SwiftData
#endif

@MainActor
public final class WorkoutDashboardModel: ObservableObject {
    private let aiProvider: AICoachProvider
    private let voiceCoach: LiveVoiceCoachOrchestrator

    @Published public var startupNotice: String?
    @Published public var startupNoticeSeverity: TelemetrySeverity?

    // Full initializer (with repositories, sync, subscriptions, signals)
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
        voiceCoach: LiveVoiceCoachOrchestrator
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
        self.startupNotice = startupNotice
        self.startupNoticeSeverity = startupNoticeSeverity
    }
    #endif

    // Without repositories (degraded persistence)
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
        voiceCoach: LiveVoiceCoachOrchestrator
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
        self.startupNotice = startupNotice
        self.startupNoticeSeverity = startupNoticeSeverity
    }
    #endif

    // Minimal (no StoreKit, no SwiftData)
    public init(
        aiProvider: AICoachProvider,
        accountSessionStore: AccountSessionStore,
        voicePermissionStore: VoicePermissionStore,
        healthStore: HealthStore,
        notificationStore: NotificationStore,
        telemetrySink: TelemetrySink,
        surfaceStore: PlatformSurfaceStateStore,
        voiceCoach: LiveVoiceCoachOrchestrator
    ) {
        self.aiProvider = aiProvider
        self.voiceCoach = voiceCoach
    }

    public func handleWatchPayload(_ payload: WatchPayload) async {}
    public func handleHealthBackgroundUpdate(_ update: HealthBackgroundUpdate) async {}
    public func startWorkoutSession() async {}
    public func logRecommendedSet() async {}
    public func syncNow() async {}
}
#endif
