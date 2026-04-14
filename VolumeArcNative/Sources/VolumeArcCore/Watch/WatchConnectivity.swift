import Foundation

public enum WatchPayloadKind: String, Sendable, Codable {
    case restTimer
    case liveState
    case startSession
    case endSession
    case coachCue
    case completedWorkout
}

public struct WatchPayload: Sendable, Codable {
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

    /// Encode the payload to a `[String: Any]` dictionary for WCSession message passing.
    public func asDictionary() -> [String: Any] {
        [
            "kind": kind.rawValue,
            "workoutID": workoutID,
            "createdAt": createdAt.timeIntervalSince1970,
            "body": body,
        ]
    }

    /// Decode a WCSession message dictionary into a WatchPayload.
    public init?(dictionary: [String: Any]) {
        guard let kindRaw = dictionary["kind"] as? String,
              let kind = WatchPayloadKind(rawValue: kindRaw),
              let workoutID = dictionary["workoutID"] as? String,
              let body = dictionary["body"] as? String
        else { return nil }
        let createdAt = (dictionary["createdAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? .now
        self.init(kind: kind, workoutID: workoutID, createdAt: createdAt, body: body)
    }
}

public enum WatchConnectivityNotifications {
    public static let payloadDidArrive = Notification.Name("VolumeArc.WatchConnectivity.payloadDidArrive")
    public static let payloadUserInfoKey = "watchPayload"
}

public struct WatchSessionSnapshot: Sendable, Codable {
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

public protocol WatchSessionTransport: Sendable {
    func activate() async
    func isReachable() async -> Bool
    func send(_ payload: WatchPayload) async throws
}

#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
import WatchConnectivity

/// Real WCSession-backed transport.
/// Activates the default session, sends messages via transferUserInfo for
/// reliability (guaranteed delivery even if the peer isn't reachable), and
/// posts received payloads via NotificationCenter so the app can respond.
public final class WatchConnectivitySessionTransport: NSObject, WatchSessionTransport, WCSessionDelegate, @unchecked Sendable {
    private let session: WCSession

    public override init() {
        self.session = WCSession.default
        super.init()
        session.delegate = self
    }

    public func activate() async {
        guard WCSession.isSupported() else { return }
        if session.activationState != .activated {
            session.activate()
        }
    }

    public func isReachable() async -> Bool {
        session.isReachable
    }

    public func send(_ payload: WatchPayload) async throws {
        guard session.activationState == .activated else {
            session.activate()
            throw WatchTransportError.notActivated
        }
        // transferUserInfo queues reliably — survives app restarts on both sides.
        session.transferUserInfo(payload.asDictionary())
    }

    // MARK: - WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let payload = WatchPayload(dictionary: userInfo) {
            NotificationCenter.default.post(
                name: WatchConnectivityNotifications.payloadDidArrive,
                object: nil,
                userInfo: [WatchConnectivityNotifications.payloadUserInfoKey: payload]
            )
        }
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let payload = WatchPayload(dictionary: message) {
            NotificationCenter.default.post(
                name: WatchConnectivityNotifications.payloadDidArrive,
                object: nil,
                userInfo: [WatchConnectivityNotifications.payloadUserInfoKey: payload]
            )
        }
    }
}
#endif

public enum WatchTransportError: Error, LocalizedError {
    case notActivated
    case notReachable

    public var errorDescription: String? {
        switch self {
        case .notActivated: return "Watch connectivity session is not activated."
        case .notReachable: return "Paired device is not reachable right now."
        }
    }
}

public struct UnavailableWatchSessionTransport: WatchSessionTransport {
    public init() {}
    public func activate() async {}
    public func isReachable() async -> Bool { false }
    public func send(_ payload: WatchPayload) async throws {
        throw WatchTransportError.notReachable
    }
}

// MARK: - Pending payload store

public protocol WatchPendingPayloadStore: Sendable {
    func enqueue(_ payload: WatchPayload) async
    func dequeueAll() async -> [WatchPayload]
    func count() async -> Int
}

public actor UserDefaultsWatchPendingPayloadStore: WatchPendingPayloadStore {
    private let defaults: UserDefaults
    private let key = "com.mabryventures.VolumeArc.watch.pendingPayloads"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func enqueue(_ payload: WatchPayload) async {
        var current = loadUnsafe()
        current.append(payload)
        save(current)
    }

    public func dequeueAll() async -> [WatchPayload] {
        let current = loadUnsafe()
        save([])
        return current
    }

    public func count() async -> Int {
        loadUnsafe().count
    }

    private func loadUnsafe() -> [WatchPayload] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WatchPayload].self, from: data)
        else { return [] }
        return decoded
    }

    private func save(_ payloads: [WatchPayload]) {
        if let data = try? JSONEncoder().encode(payloads) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - Session state store

public protocol WatchSessionStateStore: Sendable {
    func load() async -> WatchSessionSnapshot?
    func save(_ snapshot: WatchSessionSnapshot) async
    func clear() async
}

public final class UserDefaultsWatchSessionStateStore: WatchSessionStateStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "com.mabryventures.VolumeArc.watch.sessionSnapshot"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() async -> WatchSessionSnapshot? {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(WatchSessionSnapshot.self, from: data)
        else { return nil }
        return decoded
    }

    public func save(_ snapshot: WatchSessionSnapshot) async {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    public func clear() async {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Coordinator

public actor WatchConnectivityCoordinator {
    private let transport: WatchSessionTransport
    private let payloadStore: WatchPendingPayloadStore

    public init(transport: WatchSessionTransport, payloadStore: WatchPendingPayloadStore) {
        self.transport = transport
        self.payloadStore = payloadStore
        Task { await transport.activate() }
    }

    public func isReachable() async -> Bool {
        await transport.isReachable()
    }

    public func pendingPayloadCount() async -> Int {
        await payloadStore.count()
    }

    /// Send a payload. If the transport fails or the peer isn't reachable,
    /// enqueue the payload for replay on the next successful send.
    public func send(_ payload: WatchPayload) async throws {
        do {
            try await transport.send(payload)
        } catch {
            await payloadStore.enqueue(payload)
            throw error
        }
    }

    /// Flush any pending payloads if the peer is now reachable.
    public func flushPendingIfReachable() async throws {
        guard await transport.isReachable() else { return }
        let pending = await payloadStore.dequeueAll()
        for payload in pending {
            do {
                try await transport.send(payload)
            } catch {
                // Put it back in the queue if sending still fails.
                await payloadStore.enqueue(payload)
                throw error
            }
        }
    }
}
