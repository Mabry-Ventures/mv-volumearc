import Foundation

public enum WatchPayloadKind: String, Sendable {
    case restTimer
    case liveState
    case startSession
    case endSession
    case coachCue
    case completedWorkout
}

public struct WatchPayload: Sendable {
    public let kind: WatchPayloadKind
    public let workoutID: String
    public let createdAt: Date
    public let body: String

    public init(kind: WatchPayloadKind, workoutID: String, body: String) {
        self.kind = kind
        self.workoutID = workoutID
        self.createdAt = Date.now
        self.body = body
    }

    public init(kind: WatchPayloadKind, workoutID: String, createdAt: Date, body: String) {
        self.kind = kind
        self.workoutID = workoutID
        self.createdAt = createdAt
        self.body = body
    }
}

public enum WatchConnectivityNotifications {
    public static let payloadDidArrive = Notification.Name("VolumeArc.WatchConnectivity.payloadDidArrive")
    public static let payloadUserInfoKey = "watchPayload"
}

public struct WatchSessionSnapshot: Sendable {
    public let selectedAction: WorkoutAction
    public let restEndsAt: Date
    public let coachPrompt: String
    public let sessionActive: Bool
    public let statusMessage: String

    public init(selectedAction: WorkoutAction, restEndsAt: Date, coachPrompt: String, sessionActive: Bool, statusMessage: String) {
        self.selectedAction = selectedAction
        self.restEndsAt = restEndsAt
        self.coachPrompt = coachPrompt
        self.sessionActive = sessionActive
        self.statusMessage = statusMessage
    }
}

public protocol WatchSessionTransport: Sendable {}

#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
public struct WatchConnectivitySessionTransport: WatchSessionTransport {
    public init() {}
}
#endif

public struct UnavailableWatchSessionTransport: WatchSessionTransport {
    public init() {}
}

public protocol WatchPendingPayloadStore: Sendable {}

public struct UserDefaultsWatchPendingPayloadStore: WatchPendingPayloadStore {
    public init() {}
}

public protocol WatchSessionStateStore: Sendable {
    func load() async -> WatchSessionSnapshot?
    func save(_ snapshot: WatchSessionSnapshot) async
    func clear() async
}

public struct UserDefaultsWatchSessionStateStore: WatchSessionStateStore {
    public init() {}
    public func load() async -> WatchSessionSnapshot? { nil }
    public func save(_ snapshot: WatchSessionSnapshot) async {}
    public func clear() async {}
}

public struct WatchConnectivityCoordinator: Sendable {
    private let transport: WatchSessionTransport

    public init(transport: WatchSessionTransport, payloadStore: WatchPendingPayloadStore) {
        self.transport = transport
    }

    public func isReachable() async -> Bool { false }
    public func flushPendingIfReachable() async throws {}
    public func pendingPayloadCount() async -> Int { 0 }
    public func send(_ payload: WatchPayload) async throws {}
}
