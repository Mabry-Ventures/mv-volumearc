#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

public struct RootDashboardView: View {
    @ObservedObject private var navigation: DashboardNavigationModel
    @ObservedObject private var model: WorkoutDashboardModel
    @StateObject private var toastPresenter = VAToastPresenter()
    @AppStorage(VolumeArcAppearancePreference.storageKey)
    private var appearancePreferenceRawValue = VolumeArcAppearancePreference.system.rawValue

    /// VOL-176: App-layer feedback submission hook. Propagated to the
    /// Profile tab so it can present the feedback surface and forward
    /// the user's input to the Sentry/telemetry adapter constructed by
    /// `VolumeArcApp`.
    private let onSendFeedback: ((FeedbackBundle.Category, String) -> Void)?
    private let onRequestNotifications: (() async -> Bool)?

    public init(
        navigation: DashboardNavigationModel,
        model: WorkoutDashboardModel,
        onRequestNotifications: (() async -> Bool)? = nil,
        onSendFeedback: ((FeedbackBundle.Category, String) -> Void)? = nil
    ) {
        self.navigation = navigation
        self.model = model
        self.onRequestNotifications = onRequestNotifications
        self.onSendFeedback = onSendFeedback
    }

    public var body: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationStack {
                TodayView(model: model, navigation: navigation)
            }
            .tabItem {
                Label(DashboardTab.today.title, systemImage: DashboardTab.today.systemImage)
                    .accessibilityIdentifier("tab.today")
            }
            .tag(DashboardTab.today)
            .accessibilityIdentifier("tab.today")

            NavigationStack {
                WorkoutsView(model: model, navigation: navigation)
            }
            .tabItem {
                Label(DashboardTab.workouts.title, systemImage: DashboardTab.workouts.systemImage)
                    .accessibilityIdentifier("tab.workouts")
            }
            .tag(DashboardTab.workouts)
            .accessibilityIdentifier("tab.workouts")

            NavigationStack {
                CoachView(model: model, navigation: navigation)
            }
            .tabItem {
                Label(DashboardTab.coach.title, systemImage: DashboardTab.coach.systemImage)
                    .accessibilityIdentifier("tab.coach")
            }
            .tag(DashboardTab.coach)
            .accessibilityIdentifier("tab.coach")

            NavigationStack {
                SignalsView(model: model)
            }
            .tabItem {
                Label(DashboardTab.signals.title, systemImage: DashboardTab.signals.systemImage)
                    .accessibilityIdentifier("tab.signals")
            }
            .tag(DashboardTab.signals)
            .accessibilityIdentifier("tab.signals")

            NavigationStack {
                ProfileView(
                    model: model,
                    onRequestNotifications: onRequestNotifications,
                    onSendFeedback: onSendFeedback
                )
            }
            .tabItem {
                Label(DashboardTab.profile.title, systemImage: DashboardTab.profile.systemImage)
                    .accessibilityIdentifier("tab.profile")
            }
            .tag(DashboardTab.profile)
            .accessibilityIdentifier("tab.profile")
        }
        .tint(VA.Colors.primary)
        .preferredColorScheme(appearancePreference.preferredColorScheme)
        .accessibilityIdentifier("root.dashboard")
        .environmentObject(toastPresenter)
        .vaToastOverlay(toastPresenter)
        .task {
            let shouldOpenProfileOnLaunch = Self.shouldOpenProfileOnLaunch
            let shouldOpenWorkoutsOnLaunch = Self.shouldOpenWorkoutsOnLaunch
            let shouldOpenCoachOnLaunch = Self.shouldOpenCoachOnLaunch
            let shouldOpenSignalsOnLaunch = Self.shouldOpenSignalsOnLaunch
            let shouldSeedCoachWorkoutHandoff = Self.shouldSeedCoachWorkoutHandoffOnLaunch
            if shouldOpenProfileOnLaunch {
                navigation.openProfile()
            }
            if shouldOpenWorkoutsOnLaunch {
                navigation.openWorkouts()
            }
            if shouldOpenCoachOnLaunch {
                navigation.openCoach(prompt: "")
            }
            if shouldOpenSignalsOnLaunch {
                navigation.openSignals()
            }

            await model.refresh()
            if shouldSeedCoachWorkoutHandoff {
                model.coachMessages = Self.seededCoachWorkoutHandoffMessages
            }
            navigation.showOnboarding = model.hasLoadedInitialData && !model.isOnboardingComplete
            // XCUITest affordance: open the Profile surface directly so
            // tests that target Profile-only rows do not depend on
            // simulator-specific TabView hit testing.
            if shouldOpenProfileOnLaunch, navigation.showOnboarding == false {
                navigation.openProfile()
            }
            // VOL-141: stable entry point for Workouts-tab journeys.
            if shouldOpenWorkoutsOnLaunch, navigation.showOnboarding == false {
                navigation.openWorkouts()
            }
            // VOL-200 P2: same affordance for Coach-tab journeys.
            if shouldOpenCoachOnLaunch, navigation.showOnboarding == false {
                navigation.openCoach(prompt: "")
            }
            // VOL-200 P5: same affordance for Signals-tab journeys.
            if shouldOpenSignalsOnLaunch, navigation.showOnboarding == false {
                navigation.openSignals()
            }
            // VOL-93: `-ShowPaywallOnLaunch 1` asks the dashboard to
            // present the paywall as soon as the app boots. This is an
            // XCUITest affordance so journey tests can exercise the
            // paywall surface without driving the user all the way to
            // the profile tab. Intentionally read directly from
            // `ProcessInfo` here to avoid threading a new dependency
            // through `VolumeArcApp` while VOL-87 is splitting that
            // file. Fires only on first launch while the flag is set;
            // the sheet below drives dismissal.
            if Self.shouldShowPaywallOnLaunch, navigation.showOnboarding == false {
                navigation.showPaywall = true
            }
        }
        .fullScreenCover(isPresented: $navigation.showOnboarding) {
            OnboardingView(
                isPresented: $navigation.showOnboarding,
                onComplete: { result in
                    Task {
                        // VOL-57 fixup: only `updateProfile` here; the
                        // `.onChange(of: model.isOnboardingComplete)` below is
                        // the single source of truth for dismissing the cover.
                        // If `updateProfile` silently fails (SwiftData save
                        // error), `isOnboardingComplete` stays false, the cover
                        // stays up, and the user can retry. Unconditionally
                        // dismissing here let users bypass the first-run gate
                        // whenever the profile save happened to fail.
                        await model.updateProfile(result.toDefaults())
                    }
                },
                // VOL-109: route the permissions-step "Connect Apple Health"
                // tap through the dashboard model, which gates on
                // `VolumeArcRuntimeFlags.shouldSurfacePermissionPrompts` so
                // existing journey tests never see the system sheet, but
                // permission-flow XCUITests with
                // `-SimulatePermissionPrompts 1` do.
                onRequestHealthAuthorization: {
                    await model.requestHealthKitAuthorization()
                },
                onRequestNotificationAuthorization: onRequestNotifications,
                onConnectAppleAccount: { account in
                    await model.connectAppleAccount(
                        userID: account.userID,
                        displayName: account.displayName,
                        email: account.email
                    )
                },
                onResumeFromSavedProgress: { stepRaw in
                    model.recordOnboardingResumed(stepRaw: stepRaw)
                }
            )
        }
        // VOL-93: paywall sheet attached at the root so it can be triggered
        // from launch arguments (`-ShowPaywallOnLaunch`) as well as from
        // `ProfileView` (which continues to present its own sheet for the
        // normal upgrade flow). Only presents when `subscriptionStore` is
        // available; otherwise the sheet quietly collapses to an empty
        // container so non-StoreKit builds (e.g., Linux-style CI) do not
        // crash on launch.
        .sheet(isPresented: $navigation.showPaywall) {
            paywallSheet
        }
        .fullScreenCover(item: watchFormCheckRequestBinding) { request in
            watchFormCheckSheet(for: request)
        }
        .onChange(of: model.isOnboardingComplete) { _, isComplete in
            guard model.hasLoadedInitialData else { return }
            if isComplete {
                OnboardingProgressStore.clear()
            }
            navigation.showOnboarding = !isComplete
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            VAHaptics.selection()
        }
        .onChange(of: model.watchConnectivityNotice) { _, notice in
            guard let notice else { return }
            toastPresenter.show(VAToast(
                kind: toastKind(for: notice.severity),
                title: notice.title,
                message: notice.message,
                duration: 5
            ))
        }
    }

    @ViewBuilder
    private var paywallSheet: some View {
        #if canImport(StoreKit)
        if let subscriptionStore = model.subscriptionStore {
            PaywallView(
                subscriptionStore: subscriptionStore,
                isPresented: $navigation.showPaywall
            )
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }

    private var watchFormCheckRequestBinding: Binding<WatchFormCheckStartPayload?> {
        Binding(
            get: { model.activeWatchFormCheckRequest },
            set: { newValue in
                guard newValue == nil, let request = model.activeWatchFormCheckRequest else { return }
                Task {
                    await model.dismissWatchFormCheckRequest(sessionID: request.sessionID)
                }
            }
        )
    }

    @ViewBuilder
    private func watchFormCheckSheet(for request: WatchFormCheckStartPayload) -> some View {
        #if os(iOS)
        if let exercise = request.exercise {
            FormCheckCaptureView(
                exercise: exercise,
                exerciseName: request.exerciseName,
                startsAutomatically: true,
                automaticallyUsesResult: true,
                externalStopToken: model.watchFormCheckStopToken
            ) { analysis in
                await model.completeWatchFormCheck(analysis, sessionID: request.sessionID)
            }
        } else {
            VStack(spacing: VA.Space.md) {
                Text(String(localized: "Form check unavailable", comment: "Unsupported watch form check title"))
                    .font(VA.Typography.title2)
                Text(String(localized: "This lift is not supported for camera form check yet.", comment: "Unsupported watch form check message"))
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(VA.Space.xl)
            .task {
                await model.rejectWatchFormCheckRequest(
                    sessionID: request.sessionID,
                    message: String(
                        localized: "This lift is not supported for camera form check yet.",
                        comment: "Unsupported watch form-check stopped message"
                    )
                )
            }
        }
        #else
        EmptyView()
        #endif
    }

    private func toastKind(for severity: TelemetrySeverity) -> VAToast.Kind {
        switch severity {
        case .error:
            return .error
        case .warning:
            return .warning
        case .info:
            return .info
        }
    }

    /// VOL-93: XCUITest helper — presents the paywall as soon as the
    /// dashboard finishes its initial refresh when this flag is set.
    /// Passing `-ShowPaywallOnLaunch 0` or leaving the flag off keeps
    /// the previous behavior (paywall only opens from the Profile tab).
    private static var shouldShowPaywallOnLaunch: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShowPaywallOnLaunch") else {
            return false
        }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return true }
        let rawValue = arguments[nextIndex]
        guard rawValue.hasPrefix("-") == false else { return true }
        return rawValue != "0"
    }

    /// XCUITest helper for journeys that need a stable Profile entry point.
    private static var shouldOpenProfileOnLaunch: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-OpenProfileOnLaunch") else {
            return false
        }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return true }
        let rawValue = arguments[nextIndex]
        guard rawValue.hasPrefix("-") == false else { return true }
        return rawValue != "0"
    }

    /// VOL-141: XCUITest helper that opens the Workouts tab on launch
    /// so Workouts-only journeys do not depend on TabView hit testing.
    fileprivate static var shouldOpenWorkoutsOnLaunch: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-OpenWorkoutsOnLaunch") else {
            return false
        }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return true }
        let rawValue = arguments[nextIndex]
        guard rawValue.hasPrefix("-") == false else { return true }
        return rawValue != "0"
    }

    /// VOL-200 Phase 2: XCUITest helper that opens the Coach tab on
    /// launch so coach-journey tests don't depend on simulator-specific
    /// TabView hit testing. Same shape as `shouldOpenProfileOnLaunch`;
    /// add similar helpers for Signals / Workouts as Phase 2+ journey
    /// PRs need stable tab entry points.
    fileprivate static var shouldOpenCoachOnLaunch: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-OpenCoachOnLaunch") else {
            return false
        }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return true }
        let rawValue = arguments[nextIndex]
        guard rawValue.hasPrefix("-") == false else { return true }
        return rawValue != "0"
    }

    /// VOL-200 Phase 5: XCUITest helper that opens the Signals tab on
    /// launch so signals-journey tests don't depend on simulator-specific
    /// TabView hit testing. Same shape as `shouldOpenCoachOnLaunch`.
    fileprivate static var shouldOpenSignalsOnLaunch: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-OpenSignalsOnLaunch") else {
            return false
        }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return true }
        let rawValue = arguments[nextIndex]
        guard rawValue.hasPrefix("-") == false else { return true }
        return rawValue != "0"
    }

    /// XCUITest helper that seeds a parseable Coach workout recommendation so
    /// the one-tap Coach -> Workouts handoff can be exercised without live AI.
    fileprivate static var shouldSeedCoachWorkoutHandoffOnLaunch: Bool {
        guard VolumeArcRuntimeFlags.isDeterministicMode else { return false }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-SeedCoachWorkoutHandoff") else {
            return false
        }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return true }
        let rawValue = arguments[nextIndex]
        guard rawValue.hasPrefix("-") == false else { return true }
        return rawValue != "0"
    }

    fileprivate static var seededCoachWorkoutHandoffMessages: [CoachMessage] {
        [
            CoachMessage(
                sender: .user,
                content: String(
                    localized: "Build me a light workout I can start now.",
                    comment: "Seeded user message for Coach workout handoff UI tests"
                )
            ),
            CoachMessage(
                sender: .coach,
                content: String(
                    localized: """
                    Keep this light and focused on clean movement.

                    - Dumbbell rows: 3 sets of 10 reps
                    - Light lunges: 3 sets of 10 reps
                    - Light planks: 3 sets of 30 seconds
                    """,
                    comment: "Seeded parseable Coach workout recommendation for UI tests"
                )
            ),
        ]
    }

    private var appearancePreference: VolumeArcAppearancePreference {
        VolumeArcAppearancePreference(rawValue: appearancePreferenceRawValue) ?? .system
    }
}

public enum VolumeArcAppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark
    case warm

    public static let storageKey = "volumearc.appearancePreference"
    public static let userSelectableCases: [VolumeArcAppearancePreference] = [.system, .light, .dark]

    public var id: String { rawValue }

    public var displayName: String {
        LocalizedLabels.appearancePreferenceDisplayName(self)
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light, .warm:
            return .light
        case .dark:
            return .dark
        }
    }
}
#endif
