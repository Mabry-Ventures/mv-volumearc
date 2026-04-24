#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

public struct RootDashboardView: View {
    @ObservedObject private var navigation: DashboardNavigationModel
    @ObservedObject private var model: WorkoutDashboardModel
    @StateObject private var toastPresenter = VAToastPresenter()

    public init(navigation: DashboardNavigationModel, model: WorkoutDashboardModel) {
        self.navigation = navigation
        self.model = model
    }

    public var body: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationStack {
                TodayView(model: model, navigation: navigation)
            }
            .tabItem {
                Label(DashboardTab.today.title, systemImage: DashboardTab.today.systemImage)
            }
            .tag(DashboardTab.today)
            .accessibilityIdentifier("tab.today")

            NavigationStack {
                WorkoutsView(model: model)
            }
            .tabItem {
                Label(DashboardTab.workouts.title, systemImage: DashboardTab.workouts.systemImage)
            }
            .tag(DashboardTab.workouts)
            .accessibilityIdentifier("tab.workouts")

            NavigationStack {
                CoachView(model: model, navigation: navigation)
            }
            .tabItem {
                Label(DashboardTab.coach.title, systemImage: DashboardTab.coach.systemImage)
            }
            .tag(DashboardTab.coach)
            .accessibilityIdentifier("tab.coach")

            NavigationStack {
                SignalsView(model: model)
            }
            .tabItem {
                Label(DashboardTab.signals.title, systemImage: DashboardTab.signals.systemImage)
            }
            .tag(DashboardTab.signals)
            .accessibilityIdentifier("tab.signals")

            NavigationStack {
                ProfileView(model: model)
            }
            .tabItem {
                Label(DashboardTab.profile.title, systemImage: DashboardTab.profile.systemImage)
            }
            .tag(DashboardTab.profile)
            .accessibilityIdentifier("tab.profile")
        }
        .tint(VA.Colors.primary)
        .accessibilityIdentifier("root.dashboard")
        .environmentObject(toastPresenter)
        .vaToastOverlay(toastPresenter)
        .task {
            await model.refresh()
            navigation.showOnboarding = model.hasLoadedInitialData && !model.isOnboardingComplete
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
            OnboardingView(isPresented: $navigation.showOnboarding) { result in
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
            }
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
}
#endif
