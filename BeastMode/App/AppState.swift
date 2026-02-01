import SwiftUI
import Combine

/// Observable app-wide state management
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published Properties

    @Published var selectedTab: BeastModeTab = .log
    @Published var isWorkoutActive: Bool = false
    @Published var currentWorkoutStartTime: Date?
    @Published var showingOnboarding: Bool = false

    // MARK: - User Preferences

    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("preferredUnits") var preferredUnits: String = WeightUnit.pounds.rawValue
    @AppStorage("defaultRestTimer") var defaultRestTimer: TimeInterval = 90

    // MARK: - Computed Properties

    var weightUnit: WeightUnit {
        WeightUnit(rawValue: preferredUnits) ?? .pounds
    }

    // MARK: - Initialization

    init() {
        showingOnboarding = !hasCompletedOnboarding
    }

    // MARK: - Workout Session Management

    func startWorkout() {
        isWorkoutActive = true
        currentWorkoutStartTime = Date()
    }

    func endWorkout() {
        isWorkoutActive = false
        currentWorkoutStartTime = nil
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        showingOnboarding = false
    }
}

// MARK: - Tab Definition

enum BeastModeTab: String, CaseIterable, Identifiable {
    case plan = "Plan"
    case log = "Log"
    case progress = "Progress"
    case coach = "Coach"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .plan: return "calendar.badge.clock"
        case .log: return "figure.strengthtraining.traditional"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .coach: return "sparkles"
        }
    }

    var title: String { rawValue }
}
