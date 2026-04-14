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
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            VAHaptics.selection()
        }
    }
}
#endif
