import SwiftUI
#if canImport(SwiftData)
import SwiftData
#endif
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(Network)
import Network
#endif
import VolumeArcCore
import VolumeArcUI

extension Notification.Name {
    static let volumeArcReachabilityChanged = Notification.Name("VolumeArc.ReachabilityChanged")
}

@main
struct VolumeArcApp: App {
    @StateObject private var navigation = DashboardNavigationModel()
    private let dashboardModel: WorkoutDashboardModel
    private let widgetController = VolumeArcWidgetController()
    #if canImport(ActivityKit)
    private let liveActivityController = VolumeArcLiveActivityController()
    #endif
    #if canImport(SwiftData)
    private let persistence = VolumeArcPersistenceController.shared
    #endif

    init() {
        #if canImport(Sentry)
        VolumeArcSentryConfiguration.bootstrapIfNeeded()
        #endif
        VolumeArcAIConfiguration.bootstrapRelaySecretsIfNeeded()
        #if canImport(SwiftData)
        let persistence = VolumeArcPersistenceController.shared
        #endif
        let aiProvider = VolumeArcAIRuntimeFactory.makeCoachProvider()
        let voiceCoach = VolumeArcAIRuntimeFactory.makeVoiceCoach()
        let healthStore = Self.makeHealthStore()
        let voicePermissionStore = Self.makeVoicePermissionStore()
        let accountSessionStore = Self.makeAccountSessionStore()
        let notificationStore = Self.makeNotificationStore()
        #if canImport(SwiftData)
        let telemetrySink = Self.makeTelemetrySink(initialEvents: persistence.bootstrapTelemetryEvents)
        #else
        let telemetrySink = Self.makeTelemetrySink()
        #endif
        let surfaceStore = UserDefaultsPlatformSurfaceStateStore()
        #if canImport(StoreKit)
        let syncStateStore = FileSyncStateStore(url: Self.syncStateStoreURL())
        let syncTransport = Self.makeSyncTransport()
        let subscriptionStore = StoreKitSubscriptionStore(
            productIDs: VolumeArcPremiumCatalog.subscriptionProductIDs
        )
        #if canImport(SwiftData)
        let startupSignals = Self.startupSignals(persistenceStatus: persistence.bootstrapStatus)
        #else
        let startupSignals = Self.startupSignals()
        #endif
        #if canImport(SwiftData)
        if let container = persistence.container {
            let repository = SwiftDataWorkoutRepository(container: container)
            let coachMemoryRepository = SwiftDataCoachMemoryRepository(container: container)
            let userProfileRepository = SwiftDataUserProfileRepository(container: container)
            let trainingPlanRepository = SwiftDataTrainingPlanRepository(container: container)
            let syncApplier = DefaultSyncPayloadApplier(
                workoutRepository: repository,
                coachMemoryRepository: coachMemoryRepository,
                userProfileRepository: userProfileRepository,
                trainingPlanRepository: trainingPlanRepository
            )
            let syncEngine = CloudSyncCoordinator(
                transport: syncTransport,
                payloadApplier: syncApplier,
                stateStore: syncStateStore
            )
            self.dashboardModel = WorkoutDashboardModel(
                aiProvider: aiProvider,
                syncEngine: syncEngine,
                repository: repository,
                coachMemoryRepository: coachMemoryRepository,
                userProfileRepository: userProfileRepository,
                trainingPlanRepository: trainingPlanRepository,
                accountSessionStore: accountSessionStore,
                voicePermissionStore: voicePermissionStore,
                healthStore: healthStore,
                notificationStore: notificationStore,
                telemetrySink: telemetrySink,
                surfaceStore: surfaceStore,
                startupNotice: Self.combinedStartupNotice(from: startupSignals),
                startupNoticeSeverity: Self.highestSeverity(in: startupSignals),
                operationalSignals: startupSignals,
                subscriptionStore: subscriptionStore,
                voiceCoach: voiceCoach
            )
        } else {
            let syncEngine = CloudSyncCoordinator(
                transport: syncTransport,
                stateStore: syncStateStore
            )
            self.dashboardModel = WorkoutDashboardModel(
                aiProvider: aiProvider,
                syncEngine: syncEngine,
                accountSessionStore: accountSessionStore,
                voicePermissionStore: voicePermissionStore,
                healthStore: healthStore,
                notificationStore: notificationStore,
                telemetrySink: telemetrySink,
                surfaceStore: surfaceStore,
                startupNotice: Self.combinedStartupNotice(from: startupSignals),
                startupNoticeSeverity: Self.highestSeverity(in: startupSignals),
                operationalSignals: startupSignals,
                subscriptionStore: subscriptionStore,
                voiceCoach: voiceCoach
            )
        }
        #else
        let syncEngine = CloudSyncCoordinator(
            transport: syncTransport,
            stateStore: syncStateStore
        )
        self.dashboardModel = WorkoutDashboardModel(
            aiProvider: aiProvider,
            syncEngine: syncEngine,
            accountSessionStore: accountSessionStore,
            voicePermissionStore: voicePermissionStore,
            healthStore: healthStore,
            notificationStore: notificationStore,
            telemetrySink: telemetrySink,
            surfaceStore: surfaceStore,
            subscriptionStore: subscriptionStore,
            voiceCoach: voiceCoach
        )
        #endif
        #else
        self.dashboardModel = WorkoutDashboardModel(
            aiProvider: aiProvider,
            accountSessionStore: accountSessionStore,
            voicePermissionStore: voicePermissionStore,
            healthStore: healthStore,
            notificationStore: notificationStore,
            telemetrySink: telemetrySink,
            surfaceStore: surfaceStore,
            voiceCoach: voiceCoach
        )
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootContent
        }
    }

    private var rootContent: some View {
        RootDashboardView(navigation: navigation, model: dashboardModel)
            .task {
                #if canImport(ActivityKit)
                await liveActivityController.restoreStoredStateIfAvailable()
                #endif
                #if canImport(UserNotifications)
                let scheduler = VolumeArcNotificationScheduler()
                scheduler.registerCategories()
                _ = await scheduler.requestPermissionIfNeeded()
                #endif
                #if canImport(Network)
                Self.startNetworkReachabilityMonitor()
                #endif
            }
            .onOpenURL { url in
                handle(url: url)
            }
            .onReceive(NotificationCenter.default.publisher(for: WatchConnectivityNotifications.payloadDidArrive)) { notification in
                guard let payload = notification.userInfo?[WatchConnectivityNotifications.payloadUserInfoKey] as? WatchPayload else {
                    return
                }

                Task {
                    await dashboardModel.handleWatchPayload(payload)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: HealthNotifications.backgroundWorkoutDidArrive)) { notification in
                guard let update = notification.userInfo?[HealthNotifications.backgroundWorkoutUserInfoKey] as? HealthBackgroundUpdate else {
                    return
                }

                Task {
                    await dashboardModel.handleHealthBackgroundUpdate(update)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: PlatformSurfaceNotifications.widgetSnapshotDidChange)) { _ in
                widgetController.reloadTimelines()
            }
            .onReceive(NotificationCenter.default.publisher(for: PlatformSurfaceNotifications.liveActivityDidChange)) { notification in
                #if canImport(ActivityKit)
                guard let state = notification.userInfo?[PlatformSurfaceNotifications.liveActivityUserInfoKey] as? LiveActivityState else {
                    return
                }

                Task {
                    await liveActivityController.startOrUpdate(from: state)
                }
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: PlatformSurfaceNotifications.liveActivityDidEnd)) { _ in
                #if canImport(ActivityKit)
                Task {
                    await liveActivityController.end()
                }
                #endif
            }
    }

    private func handle(url: URL) {
        guard let destination = VolumeArcDeepLink.destination(for: url) else { return }

        switch destination {
        case .today, .nextWorkout:
            navigation.openToday()
        case let .coach(prompt):
            navigation.openCoach(prompt: prompt)
        case .signals:
            navigation.openSignals()
        case let .action(action):
            switch action {
            case .startWorkoutSession:
                navigation.openToday()
                Task {
                    await dashboardModel.startWorkoutSession()
                }
            case .logRecommendedSet:
                navigation.openToday()
                Task {
                    await dashboardModel.logRecommendedSet()
                }
            case .syncNow:
                navigation.openSignals()
                Task {
                    await dashboardModel.syncNow()
                }
            }
        }
    }

    private static func makeHealthStore() -> HealthStore {
        #if canImport(HealthKit)
        HealthKitRuntimeStore()
        #else
        UnavailableHealthStore()
        #endif
    }

    private static func makeVoicePermissionStore() -> VoicePermissionStore {
        #if canImport(AVFoundation) && canImport(Speech)
        VolumeArcVoicePermissionStore()
        #else
        UnavailableVoicePermissionStore()
        #endif
    }

    private static func makeAccountSessionStore() -> AccountSessionStore {
        UserDefaultsAccountSessionStore()
    }

    #if canImport(Network)
    private static let reachabilityMonitor = NetworkReachabilityMonitor()

    private static func startNetworkReachabilityMonitor() {
        reachabilityMonitor.start { path in
            // Post a notification so observers can react to connectivity changes.
            NotificationCenter.default.post(
                name: .volumeArcReachabilityChanged,
                object: nil,
                userInfo: ["isReachable": path.status == .satisfied]
            )
        }
    }
    #endif

    private static func makeSyncTransport() -> CloudSyncTransport {
        let containerIdentifier = VolumeArcCloudConfiguration.containerIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let containerIdentifier, containerIdentifier.isEmpty == false else {
            return UnavailableCloudSyncTransport(
                reason: VolumeArcCloudConfiguration.startupWarning
                    ?? "Cloud sync is unavailable on this build."
            )
        }

        return CloudKitSyncTransport(
            containerIdentifier: containerIdentifier,
            zoneName: VolumeArcCloudConfiguration.syncZoneName
        )
    }

    #if canImport(SwiftData)
    private static func startupSignals(
        persistenceStatus: VolumeArcPersistenceController.BootstrapStatus
    ) -> [OperationalSignalSummary] {
        var signals: [OperationalSignalSummary] = []

        if persistenceStatus.isDegraded {
            signals.append(
                OperationalSignalSummary(
                    id: "persistence-bootstrap",
                    title: "Storage",
                    message: persistenceStatus.message,
                    severity: persistenceStatus.severity
                )
            )
        }

        if let relayWarning = VolumeArcAIConfiguration.startupWarning {
            signals.append(
                OperationalSignalSummary(
                    id: "ai-relay",
                    title: "AI Relay",
                    message: relayWarning,
                    severity: .warning
                )
            )
        }

        if let cloudWarning = VolumeArcCloudConfiguration.startupWarning {
            signals.append(
                OperationalSignalSummary(
                    id: "cloudkit-config",
                    title: "Cloud Sync",
                    message: cloudWarning,
                    severity: .warning
                )
            )
        }

        #if canImport(Sentry)
        if let sentryWarning = VolumeArcSentryConfiguration.startupWarning {
            signals.append(
                OperationalSignalSummary(
                    id: "sentry-config",
                    title: "Crash Reporting",
                    message: sentryWarning,
                    severity: .warning
                )
            )
        }
        #endif
        return signals
    }
    #else
    private static func startupSignals() -> [OperationalSignalSummary] {
        var signals: [OperationalSignalSummary] = []

        if let relayWarning = VolumeArcAIConfiguration.startupWarning {
            signals.append(
                OperationalSignalSummary(
                    id: "ai-relay",
                    title: "AI Relay",
                    message: relayWarning,
                    severity: .warning
                )
            )
        }

        if let cloudWarning = VolumeArcCloudConfiguration.startupWarning {
            signals.append(
                OperationalSignalSummary(
                    id: "cloudkit-config",
                    title: "Cloud Sync",
                    message: cloudWarning,
                    severity: .warning
                )
            )
        }

        #if canImport(Sentry)
        if let sentryWarning = VolumeArcSentryConfiguration.startupWarning {
            signals.append(
                OperationalSignalSummary(
                    id: "sentry-config",
                    title: "Crash Reporting",
                    message: sentryWarning,
                    severity: .warning
                )
            )
        }
        #endif
        return signals
    }
    #endif

    private static func combinedStartupNotice(from signals: [OperationalSignalSummary]) -> String? {
        guard signals.isEmpty == false else { return nil }
        return signals.map(\.message).joined(separator: " ")
    }

    private static func highestSeverity(in signals: [OperationalSignalSummary]) -> TelemetrySeverity? {
        signals
            .map(\.severity)
            .max(by: { severityRank($0) < severityRank($1) })
    }

    private static func severityRank(_ severity: TelemetrySeverity) -> Int {
        switch severity {
        case .info:
            return 0
        case .warning:
            return 1
        case .error:
            return 2
        }
    }

    private static func syncStateStoreURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return applicationSupport
            .appendingPathComponent("VolumeArc", isDirectory: true)
            .appendingPathComponent("sync-state.json", isDirectory: false)
    }

    private static func makeNotificationStore() -> NotificationStore {
        #if canImport(UserNotifications)
        UserNotificationCenterStore()
        #else
        InMemoryNotificationStore()
        #endif
    }

    private static func makeTelemetrySink(initialEvents: [TelemetryEvent] = []) -> TelemetrySink {
        let persistent = UserDefaultsTelemetrySink()
        var sinks: [TelemetrySink] = []
        if initialEvents.isEmpty == false {
            sinks.append(InMemoryTelemetrySink(events: initialEvents))
        }
        sinks.append(persistent)
        #if canImport(OSLog)
        sinks.append(OSLogTelemetrySink())
        #endif
        #if canImport(Sentry)
        if VolumeArcSentryConfiguration.isConfigured {
            sinks.append(SentryTelemetrySink())
        }
        #endif
        return sinks.count == 1 ? persistent : FanoutTelemetrySink(sinks: sinks)
    }
}
