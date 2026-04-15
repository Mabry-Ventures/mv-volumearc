import Foundation
#if canImport(SwiftUI)
import SwiftUI

public enum DashboardTab: String, Sendable, Hashable, CaseIterable {
    case today
    case workouts
    case coach
    case signals
    case profile

    public var title: String {
        switch self {
        case .today: return "Today"
        case .workouts: return "Workouts"
        case .coach: return "Coach"
        case .signals: return "Signals"
        case .profile: return "Profile"
        }
    }

    public var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .workouts: return "figure.strengthtraining.traditional"
        case .coach: return "waveform.and.mic"
        case .signals: return "chart.line.uptrend.xyaxis"
        case .profile: return "person.crop.circle"
        }
    }
}

@MainActor
public final class DashboardNavigationModel: ObservableObject {
    @Published public var selectedTab: DashboardTab = .today
    @Published public var coachPrompt: String?
    @Published public var showOnboarding: Bool = false

    public init() {}

    public func openToday() {
        selectedTab = .today
    }

    public func openCoach(prompt: String) {
        selectedTab = .coach
        coachPrompt = prompt
    }

    public func openSignals() {
        selectedTab = .signals
    }

    public func openProfile() {
        selectedTab = .profile
    }

    public func clearCoachPrompt() {
        coachPrompt = nil
    }
}
#endif

public enum VolumeArcDeepLink {
    public enum Destination: Sendable {
        case today
        case nextWorkout
        case coach(prompt: String)
        case signals
        case action(Action)

        public enum Action: String, Sendable {
            case startWorkoutSession
            case logRecommendedSet
            case syncNow
        }
    }

    public static func destination(for url: URL) -> Destination? {
        guard url.scheme == "volumearc" else { return nil }
        let host = url.host ?? ""
        switch host {
        case "today": return .today
        case "nextWorkout", "next-workout": return .nextWorkout
        case "coach":
            let prompt = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "prompt" })?.value ?? ""
            return .coach(prompt: prompt)
        case "signals": return .signals
        case "action":
            guard let actionName = url.pathComponents.dropFirst().first,
                  let action = Destination.Action(rawValue: actionName) else { return nil }
            return .action(action)
        default: return nil
        }
    }

    public static func url(for destination: Destination) -> URL {
        switch destination {
        case .today: return URL(string: "volumearc://today")!
        case .nextWorkout: return URL(string: "volumearc://nextWorkout")!
        case let .coach(prompt):
            var components = URLComponents(string: "volumearc://coach")!
            components.queryItems = [URLQueryItem(name: "prompt", value: prompt)]
            return components.url!
        case .signals: return URL(string: "volumearc://signals")!
        case let .action(action): return URL(string: "volumearc://action/\(action.rawValue)")!
        }
    }
}
