#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

public struct RootDashboardView: View {
    @ObservedObject private var navigation: DashboardNavigationModel
    @ObservedObject private var model: WorkoutDashboardModel
    @StateObject private var toastPresenter = VAToastPresenter()

    /// VOL-176: App-layer feedback submission hook. Propagated to the
    /// Profile tab so it can present the feedback sheet and forward
    /// the user's input to the Sentry/telemetry adapter the App
    /// constructs in `VolumeArcAppFactories`.
    private let onSendFeedback: ((FeedbackBundle.Category, String) -> Void)?

    public init(
        navigation: DashboardNavigationModel,
        model: WorkoutDashboardModel,
        onSendFeedback: ((FeedbackBundle.Category, String) -> Void)? = nil
    ) {
        self.navigation = navigation
        self.model = model
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
                WorkoutsView(model: model)
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
                ProfileView(model: model, onSendFeedback: onSendFeedback)
            }
            .tabItem {
                Label(DashboardTab.profile.title, systemImage: DashboardTab.profile.systemImage)
                    .accessibilityIdentifier("tab.profile")
            }
            .tag(DashboardTab.profile)
            .accessibilityIdentifier("tab.profile")
        }
        .tint(VA.Colors.primary)
        .accessibilityIdentifier("root.dashboard")
        .environmentObject(toastPresenter)
        .vaToastOverlay(toastPresenter)
        .task {
            let shouldOpenProfileOnLaunch = Self.shouldOpenProfileOnLaunch
            if shouldOpenProfileOnLaunch {
                navigation.openProfile()
            }

            await model.refresh()
            navigation.showOnboarding = model.hasLoadedInitialData && !model.isOnboardingComplete
            // XCUITest affordance: open the Profile surface directly so
            // tests that target Profile-only rows do not depend on
            // simulator-specific TabView hit testing.
            if shouldOpenProfileOnLaunch, navigation.showOnboarding == false {
                navigation.openProfile()
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
        .onChange(of: model.isOnboardingComplete) { _, isComplete in
            guard model.hasLoadedInitialData else { return }
            navigation.showOnboarding = !isComplete
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            VAHaptics.selection()
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
}
#endif
