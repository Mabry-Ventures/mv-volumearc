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
        .onChange(of: model.isOnboardingComplete) { _, isComplete in
            guard model.hasLoadedInitialData else { return }
            navigation.showOnboarding = !isComplete
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            VAHaptics.selection()
        }
    }
}
#endif
