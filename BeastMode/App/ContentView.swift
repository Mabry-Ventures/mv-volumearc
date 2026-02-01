import SwiftUI
import SwiftData

/// Main content view with tab navigation
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: BeastModeTab = .log

    var body: some View {
        TabView(selection: $selectedTab) {
            WeeklyPlanView()
                .tabItem {
                    Label(BeastModeTab.plan.title, systemImage: BeastModeTab.plan.icon)
                }
                .tag(BeastModeTab.plan)

            DailyLogView()
                .tabItem {
                    Label(BeastModeTab.log.title, systemImage: BeastModeTab.log.icon)
                }
                .tag(BeastModeTab.log)

            ProgressView()
                .tabItem {
                    Label(BeastModeTab.progress.title, systemImage: BeastModeTab.progress.icon)
                }
                .tag(BeastModeTab.progress)

            AICoachView()
                .tabItem {
                    Label(BeastModeTab.coach.title, systemImage: BeastModeTab.coach.icon)
                }
                .tag(BeastModeTab.coach)
        }
        .tint(.beastPrimary)
        .onAppear {
            configureServices()
        }
        .onChange(of: selectedTab) { _, newTab in
            AnalyticsService.shared.track(.tabSelected(tab: newTab.rawValue))
        }
        .sheet(isPresented: $appState.showingOnboarding) {
            OnboardingView()
        }
    }

    private func configureServices() {
        DataService.shared.configure(with: modelContext)
    }
}

/// Simple onboarding view
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var currentPage = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $currentPage) {
                OnboardingPage(
                    icon: "figure.strengthtraining.traditional",
                    title: "Welcome to Beast Mode",
                    description: "Your AI-powered progressive overload tracker for serious strength gains."
                )
                .tag(0)

                OnboardingPage(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Track Your Progress",
                    description: "Log every set, track personal records, and visualize your strength journey."
                )
                .tag(1)

                OnboardingPage(
                    icon: "sparkles",
                    title: "AI Coaching",
                    description: "Get personalized form tips, exercise alternatives, and weekly insights."
                )
                .tag(2)

                OnboardingPage(
                    icon: "applewatch",
                    title: "Wrist-First Logging",
                    description: "Log sets directly from your Apple Watch during workouts."
                )
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        AnalyticsService.shared.track(.onboardingSkipped)
                        appState.completeOnboarding()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if currentPage == 3 {
                    TintedGlassButton("Get Started", icon: "arrow.right") {
                        AnalyticsService.shared.track(.onboardingCompleted)
                        appState.completeOnboarding()
                    }
                    .padding()
                }
            }
        }
    }
}

struct OnboardingPage: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundStyle(.beastPrimary)
                .padding(.bottom, 20)

            Text(title)
                .font(.beastTitle)
                .multilineTextAlignment(.center)

            Text(description)
                .font(.beastBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
        .modelContainer(for: [
            UserProfile.self,
            WorkoutPlan.self,
            PlannedDay.self,
            PlannedExercise.self,
            DailyLog.self,
            ExerciseLog.self,
            SetLog.self,
            PersonalRecord.self
        ], inMemory: true)
}
