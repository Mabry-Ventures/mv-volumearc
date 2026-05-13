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

/// Launch argument flags the app respects at startup. XCUITests set these
/// to produce deterministic state.
enum VolumeArcLaunchArguments {
    private static func flagEnabled(_ flag: String) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }

        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return true }

        let rawValue = arguments[nextIndex]
        guard rawValue.hasPrefix("-") == false else { return true }
        return rawValue != "0"
    }

    /// `-UITestMode 1` — disables analytics, skips permission prompts, seeds
    /// deterministic state, and exposes accessibility identifiers on UI.
    static var isUITestMode: Bool {
        flagEnabled("-UITestMode")
    }

    /// `-SkipOnboarding 1` — skips the onboarding flow and seeds defaults.
    static var skipOnboarding: Bool {
        flagEnabled("-SkipOnboarding")
    }

    /// `-SeedFixtures 1` — seeds the persistence layer with demo fixture data.
    static var seedFixtures: Bool {
        flagEnabled("-SeedFixtures")
    }

    /// `-PerfTestMode 1` — VOL-99. Seeds a 50-session history and enables
    /// the full recent-sessions list on the Today tab so the scroll
    /// performance test (`VolumeArcPerfTests.testTodayScrollPerformance`)
    /// has real rows to scroll through. Implies `-SeedFixtures 1` and
    /// `-SkipOnboarding 1` via the bootstrapper.
    static var isPerfTestMode: Bool {
        flagEnabled("-PerfTestMode")
    }

    /// `-SimulatePermissionPrompts 1` — VOL-109. Re-enables system
    /// permission prompts (HealthKit, Notifications) inside
    /// `-UITestMode 1` so XCUITests can drive the prompt path via
    /// `addUIInterruptionMonitor`. Without this flag,
    /// `VolumeArcRuntimeFlags.isDeterministicMode` short-circuits every
    /// prompt site so existing journey tests don't trip on the system
    /// dialog. The pair `-UITestMode 1 -SimulatePermissionPrompts 1` is
    /// the signature for permission-flow XCUITests.
    static var simulatePermissionPrompts: Bool {
        flagEnabled("-SimulatePermissionPrompts")
    }

    /// `-PostFakeWatchPayload <kind>` — VOL-112. Tells the app to post a
    /// simulated `WatchPayload` notification at launch, as if a paired
    /// Apple Watch had sent the named kind. Used by
    /// `VolumeArcWatchSimulationJourneyTests` to exercise the iPhone
    /// dashboard's watch-payload arrival path without spinning up a
    /// paired-simulator session (full pairing coverage lives in VOL-94's
    /// real-device canary).
    ///
    /// `<kind>` is a `WatchPayloadKind` rawValue: `restTimer`,
    /// `liveState`, `startSession`, `endSession`, `coachCue`, or
    /// `completedWorkout`. The flag is gated on `-UITestMode 1` —
    /// production app launches ignore it even if accidentally set.
    static var postFakeWatchPayloadKind: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PostFakeWatchPayload") else { return nil }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return nil }
        let value = arguments[nextIndex]
        guard value.hasPrefix("-") == false else { return nil }
        return value
    }
}

@main
struct VolumeArcApp: App {
    @StateObject private var navigation = DashboardNavigationModel()
    // VOL-149: deterministic-mode-only telemetry probe. In release
    // builds the probe never installs its NotificationCenter observer
    // (gated inside its init), so this object is effectively inert
    // and the `debug.telemetry.events` overlay shows the empty
    // placeholder. Lifecycle is owned by the App so it survives
    // navigation churn — XCUITests need a stable reader across the
    // whole journey.
    @StateObject private var telemetryDebugProbe = VolumeArcTelemetryDebugProbe()
    private let dashboardModel: WorkoutDashboardModel
    private let widgetController = VolumeArcWidgetController()
    #if canImport(ActivityKit)
    private let liveActivityController: VolumeArcLiveActivityController
    #endif
    #if canImport(SwiftData)
    private let persistence = VolumeArcPersistenceController.shared
    #endif

    // VOL-87 follow-up: the 205-line init currently exceeds the
    // function_body_length error threshold (200). Scheduled for the full
    // @main → Bootstrap + Factories split under a follow-up ticket; for
    // now we disable the rule on this single initializer so CI can stay
    // green. Every new dependency added here should push toward moving
    // that subsystem into a dedicated factory instead of growing this
    // initializer further.
    // swiftlint:disable:next function_body_length
    init() {
        VolumeArcRuntimeFlags.isDeterministicMode = VolumeArcLaunchArguments.isUITestMode
        // VOL-99: mirror `-PerfTestMode` onto the runtime flag so
        // `VolumeArcCore` and `VolumeArcUI` can adapt fetch limits and
        // list caps without taking a new dependency on the launch
        // argument layer.
        VolumeArcRuntimeFlags.isPerformanceTestMode = VolumeArcLaunchArguments.isPerfTestMode
        // VOL-109: mirror `-SimulatePermissionPrompts` so the prompt
        // sites can re-enable the system dialog inside `-UITestMode 1`
        // for the permission-flow XCUITests.
        VolumeArcRuntimeFlags.simulatePermissionPrompts = VolumeArcLaunchArguments.simulatePermissionPrompts
        #if canImport(Sentry)
        VolumeArcSentryConfiguration.bootstrapIfNeeded()
        #endif
        VolumeArcAIConfiguration.bootstrapRelaySecretsIfNeeded()
        #if canImport(BackgroundTasks) && !os(watchOS)
        // Must happen before the app finishes launching. The model holder
        // is populated below once the dashboardModel is constructed.
        VolumeArcBackgroundTasks.registerHandlers()
        #endif
        #if canImport(SwiftData)
        let persistence = VolumeArcPersistenceController.shared
        if let container = persistence.container {
            do {
                try VolumeArcLaunchBootstrapper.applyLaunchArguments(
                    to: container,
                    isUITestMode: VolumeArcLaunchArguments.isUITestMode,
                    skipOnboarding: VolumeArcLaunchArguments.skipOnboarding,
                    seedFixtures: VolumeArcLaunchArguments.seedFixtures,
                    isPerfTestMode: VolumeArcLaunchArguments.isPerfTestMode
                )
            } catch {
                // Surface bootstrap failure rather than silently swallowing
                // it with `try?`. A broken deterministic-mode seed will
                // otherwise cause flaky, non-reproducible test behavior and
                // hide the root cause.
                NSLog(
                    "[VolumeArc] Launch bootstrap failed: %@ (isUITestMode=%@, skipOnboarding=%@, seedFixtures=%@, isPerfTestMode=%@)",
                    error.localizedDescription,
                    String(describing: VolumeArcLaunchArguments.isUITestMode),
                    String(describing: VolumeArcLaunchArguments.skipOnboarding),
                    String(describing: VolumeArcLaunchArguments.seedFixtures),
                    String(describing: VolumeArcLaunchArguments.isPerfTestMode)
                )
                assertionFailure("Launch bootstrap failed: \(error)")
            }
        }
        #endif
        let healthStore = Self.makeHealthStore()
        let voicePermissionStore = Self.makeVoicePermissionStore()
        let accountSessionStore = Self.makeAccountSessionStore()
        let notificationStore = Self.makeNotificationStore()
        #if canImport(SwiftData)
        let telemetrySink = Self.makeTelemetrySink(initialEvents: persistence.bootstrapTelemetryEvents)
        #else
        let telemetrySink = Self.makeTelemetrySink()
        #endif
        // VOL-61: single `FeatureFlagProvider` + `FlagGateTelemetry`
        // constructed once and threaded by explicit DI into every gating
        // surface — the runtime factory (voice + Foundation Models), the
        // cloud-sync coordinator, the live-activity controller, and the
        // dashboard model. No global singleton: the dashboard still
        // exposes its own reference so UI / diagnostics can read / write
        // overrides through the same store.
        //
        // VOL-91: shared `PremiumGateTelemetry` is threaded alongside the
        // flag gate so the runtime factory can record a single `.info`
        // event per premium-gated feature (coach_tier, live_voice) per
        // launch. Instantiated before `subscriptionStore` (which is
        // conditional on StoreKit) so the gate lifecycle is identical on
        // both StoreKit-enabled and StoreKit-less builds.
        let featureFlags: FeatureFlagProvider = LocalFeatureFlagProvider()
        let flagGate = FlagGateTelemetry(flags: featureFlags, telemetry: telemetrySink)
        let premiumGate = PremiumGateTelemetry(telemetry: telemetrySink)
        #if canImport(ActivityKit)
        self.liveActivityController = VolumeArcLiveActivityController(flagGate: flagGate)
        #endif
        let surfaceStore = UserDefaultsPlatformSurfaceStateStore()
        #if canImport(StoreKit)
        let syncStateStore = FileSyncStateStore(url: Self.syncStateStoreURL())
        let syncTransport = Self.makeSyncTransport()
        // VOL-142: pass the shared telemetry sink so entitlement
        // transitions (granted / revoked / purchase_pending) are
        // visible alongside the rest of the platform's diagnostics.
        // The store emits at most one event per state change, never
        // per refresh, so this stays low-volume in production.
        let subscriptionStore = StoreKitSubscriptionStore(
            productIDs: VolumeArcPremiumCatalog.subscriptionProductIDs,
            telemetry: telemetrySink
        )
        // VOL-91: construct AI runtime AFTER the subscription store so the
        // factory can gate coach tier + voice transport on the user's
        // premium entitlement. Order of the factory calls matters — the
        // first one emits the `coach_tier` telemetry event; the second
        // reuses the dedupe guard in `PremiumGateTelemetry`.
        let aiProvider = VolumeArcAIRuntimeFactory.makeCoachProvider(
            flagGate: flagGate,
            subscriptionStore: subscriptionStore,
            premiumGate: premiumGate
        )
        let voiceCoach = VolumeArcAIRuntimeFactory.makeVoiceCoach(
            flagGate: flagGate,
            subscriptionStore: subscriptionStore,
            premiumGate: premiumGate
        )
        #if canImport(SwiftData)
        let startupSignals = Self.startupSignals(
            persistenceStatus: persistence.bootstrapStatus,
            telemetrySink: telemetrySink
        )
        #else
        let startupSignals = Self.startupSignals(telemetrySink: telemetrySink)
        #endif
        #if canImport(SwiftData)
        if let container = persistence.container {
            // VOL-67 Codex P1 (fixup #28): gate the entire outbound
            // sync pipeline on `.cloudSynced` storage mode. Fallback
            // containers (`.localFallback`, `.inMemoryFallback`) are a
            // DIFFERENT SQLite file than the cloud-backed store — they
            // start empty, get populated by `seedIfNeeded`, and must
            // NEVER push to CloudKit. Otherwise a transient fallback
            // launch on a device that previously synced successfully
            // would use its persisted cursor to push seeded/default
            // fallback state up to CloudKit, overwriting authoritative
            // cloud data another device wrote.
            //
            // Fixup #22 gated the backfill on this same mode, but the
            // sync engine + repository outbound queue were still wired
            // through the real transport whenever a container existed,
            // so every repository mutation in fallback mode could still
            // enqueue outbound rows and those rows could reach CloudKit
            // on the next sync cycle. This fixup closes the remaining
            // leak by using `NoOpOutboundSyncQueue` + `UnavailableCloudSyncTransport`
            // in fallback modes, so local writes stay local and the
            // coordinator reports `isAvailable == false` for pulls.
            let isCloudSynced = persistence.bootstrapStatus.storageMode == .cloudSynced
            let outboundQueue: any OutboundSyncQueue
            let effectiveTransport: CloudSyncTransport
            if isCloudSynced {
                outboundQueue = SwiftDataOutboundSyncQueue(container: container)
                effectiveTransport = syncTransport
            } else {
                outboundQueue = NoOpOutboundSyncQueue()
                let storageMode = persistence.bootstrapStatus.storageMode.rawValue
                effectiveTransport = UnavailableCloudSyncTransport(
                    reason: """
                        Storage mode is \(storageMode); outbound sync is \
                        disabled until cloud-backed persistence is available.
                        """
                )
            }
            let repository = SwiftDataWorkoutRepository(container: container, outboundQueue: outboundQueue)
            let coachMemoryRepository = SwiftDataCoachMemoryRepository(
                container: container,
                outboundQueue: outboundQueue,
                telemetrySink: telemetrySink
            )
            // VOL-79: one-shot retention sweep at launch to clean up
            // pre-policy rows on existing installs. Non-blocking so we
            // don't delay first frame on devices with large coach-memory
            // backlogs. `try?` because prune failures are already
            // surfaced to the telemetry sink inside the repository and
            // MUST NOT surface as a launch crash.
            Task { @MainActor in
                try? coachMemoryRepository.pruneLegacyRows()
            }
            let userProfileRepository = SwiftDataUserProfileRepository(container: container, outboundQueue: outboundQueue)
            let trainingPlanRepository = SwiftDataTrainingPlanRepository(container: container, outboundQueue: outboundQueue)
            let syncApplier = DefaultSyncPayloadApplier(
                workoutRepository: repository,
                coachMemoryRepository: coachMemoryRepository,
                userProfileRepository: userProfileRepository,
                trainingPlanRepository: trainingPlanRepository,
                telemetrySink: telemetrySink,
                outboundQueue: outboundQueue
            )
            // VOL-67 Copilot fixup #13: pass `telemetrySink` so the
            // outbound-queue quarantine path (see `CloudSyncCoordinator.push`)
            // can emit `sync.outbound_row_quarantined` events. Without
            // wiring the sink here, those warnings are silently dropped
            // in production and unparseable queue rows look like they
            // vanished into the void.
            let syncEngine = CloudSyncCoordinator(
                transport: effectiveTransport,
                payloadApplier: syncApplier,
                stateStore: syncStateStore,
                outboundQueue: outboundQueue,
                telemetrySink: telemetrySink,
                flagGate: flagGate
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
                voiceCoach: voiceCoach,
                featureFlags: featureFlags
            )
        } else {
            let syncEngine = CloudSyncCoordinator(
                transport: syncTransport,
                stateStore: syncStateStore,
                telemetrySink: telemetrySink,
                flagGate: flagGate
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
                voiceCoach: voiceCoach,
                featureFlags: featureFlags
            )
        }
        #else
        let syncEngine = CloudSyncCoordinator(
            transport: syncTransport,
            stateStore: syncStateStore,
            flagGate: flagGate
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
            voiceCoach: voiceCoach,
            featureFlags: featureFlags
        )
        #endif
        #else
        // VOL-91: without StoreKit, premium entitlement is always false —
        // factory falls back to flash-lite + Unavailable voice transport.
        // Still thread `premiumGate` so the one-shot telemetry event
        // fires with `premium=false`, which is the correct state for
        // non-StoreKit builds (macOS previews, Linux-style CI).
        let aiProvider = VolumeArcAIRuntimeFactory.makeCoachProvider(
            flagGate: flagGate,
            subscriptionStore: nil,
            premiumGate: premiumGate
        )
        let voiceCoach = VolumeArcAIRuntimeFactory.makeVoiceCoach(
            flagGate: flagGate,
            subscriptionStore: nil,
            premiumGate: premiumGate
        )
        self.dashboardModel = WorkoutDashboardModel(
            aiProvider: aiProvider,
            accountSessionStore: accountSessionStore,
            voicePermissionStore: voicePermissionStore,
            healthStore: healthStore,
            notificationStore: notificationStore,
            telemetrySink: telemetrySink,
            surfaceStore: surfaceStore,
            voiceCoach: voiceCoach,
            featureFlags: featureFlags
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
                if !VolumeArcRuntimeFlags.isDeterministicMode {
                    _ = await scheduler.requestPermissionIfNeeded()
                }
                #endif
                #if canImport(Network)
                Self.startNetworkReachabilityMonitor()
                #endif
                #if canImport(BackgroundTasks) && !os(watchOS)
                // Publish the model to the BG task handler holder and
                // schedule the next refresh/processing opportunity.
                VolumeArcBackgroundTasks.sharedModel = dashboardModel
                VolumeArcBackgroundTasks.scheduleAll()
                #endif

                // VOL-112: when launched with `-PostFakeWatchPayload <kind>`
                // and `-UITestMode 1`, post a simulated `WatchPayload` so
                // the iPhone dashboard exercises its watch-arrival path
                // without needing a paired-simulator session. The full
                // pairing path is covered by VOL-94's real-device canary.
                Self.postSimulatedWatchPayloadIfRequested()
            }
            // VOL-112: hidden test-only overlay surfacing the most-recent
            // received Watch payload kind. Gated on deterministic mode so
            // production builds neither render the overlay nor add it to
            // the accessibility tree. XCUITests
            // (`VolumeArcWatchSimulationJourneyTests`) assert on this
            // identifier to confirm the payload arrival path executed.
            .overlay(alignment: .topLeading) {
                if VolumeArcRuntimeFlags.isDeterministicMode {
                    Text(verbatim: dashboardModel.lastWatchPayloadKindForTesting ?? "")
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("debug.watch.last-payload-kind")
                        .accessibilityLabel(Text(verbatim: dashboardModel.lastWatchPayloadKindForTesting ?? ""))
                        .allowsHitTesting(false)
                        .opacity(0.001)
                }
            }
            // VOL-149: hidden test-only overlay carrying a JSON-encoded
            // snapshot of recent telemetry events. XCUITests use the
            // `assertTelemetryFired(category:name:within:)` helper
            // (`VolumeArcAppUITestSupport`) to poll the label and
            // assert that a specific (category, name) pair fired during
            // a journey. Same deterministic-mode gating + opacity
            // hiding as the watch-payload overlay above.
            .overlay(alignment: .topLeading) {
                if VolumeArcRuntimeFlags.isDeterministicMode {
                    Text(verbatim: telemetryDebugProbe.recentEventsJSON)
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("debug.telemetry.events")
                        .accessibilityLabel(Text(verbatim: telemetryDebugProbe.recentEventsJSON))
                        .allowsHitTesting(false)
                        .opacity(0.001)
                }
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
}
