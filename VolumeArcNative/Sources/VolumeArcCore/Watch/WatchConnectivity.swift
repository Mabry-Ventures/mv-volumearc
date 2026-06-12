import Foundation

public enum WatchPayloadKind: String, Sendable, Codable {
    case restTimer
    case liveState
    case startSession
    case endSession
    case coachCue
    case completedWorkout
    case voiceCoachToggle
    case formCheckStart
    case formCheckStop
    case formCheckResult
    case formCheckStopped
    case scheduledPlan
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

/// VOL-275: a co-designed plan scheduled on the phone, mirrored to the
/// watch so the upcoming session is visible at a glance. The exercises
/// carry the post-clamp prescription — this payload is built AFTER the
/// coach-source safety backstop has bounded the plan, never from raw
/// extraction output.
public struct WatchScheduledPlanPayload: Sendable, Codable, Equatable {
    public struct Exercise: Sendable, Codable, Equatable {
        public let name: String
        public let sets: Int
        public let reps: Int
        public let weight: Int

        public init(name: String, sets: Int, reps: Int, weight: Int) {
            self.name = name
            self.sets = sets
            self.reps = reps
            self.weight = weight
        }
    }

    public let title: String
    public let dayOfWeek: Int
    /// Concrete date the plan is scheduled for. The watch derives its
    /// chip label (Today / Tomorrow / weekday) from this — a plan
    /// scheduled for today must never render as "Tomorrow"
    /// (PR #363 review, Codex P2).
    public let scheduledFor: Date
    public let durationMinutes: Int?
    public let targetRPE: Int?
    public let exercises: [Exercise]

    public init(
        title: String,
        dayOfWeek: Int,
        scheduledFor: Date,
        durationMinutes: Int?,
        targetRPE: Int?,
        exercises: [Exercise]
    ) {
        self.title = title
        self.dayOfWeek = dayOfWeek
        self.scheduledFor = scheduledFor
        self.durationMinutes = durationMinutes
        self.targetRPE = targetRPE
        self.exercises = exercises
    }

    public static func encode(_ payload: WatchScheduledPlanPayload) -> String {
        SyncPayloadCodec.encode(payload) ?? "{}"
    }

    public static func decode(from body: String) -> WatchScheduledPlanPayload? {
        SyncPayloadCodec.decode(WatchScheduledPlanPayload.self, from: body)
    }
}

public struct WatchFormCheckStartPayload: Sendable, Codable, Equatable, Identifiable {
    public let sessionID: String
    public let exerciseID: String
    public let exerciseName: String
    public let setNumber: Int

    public var id: String { sessionID }

    public init(
        sessionID: String,
        exerciseID: String,
        exerciseName: String,
        setNumber: Int
    ) {
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.setNumber = setNumber
    }

    public var exercise: FormCheckExercise? {
        FormCheckExercise.infer(exerciseID: exerciseID, name: exerciseName)
    }

    public static func encode(_ payload: WatchFormCheckStartPayload) -> String {
        SyncPayloadCodec.encode(payload) ?? "{}"
    }

    public static func decode(from body: String) -> WatchFormCheckStartPayload? {
        SyncPayloadCodec.decode(WatchFormCheckStartPayload.self, from: body)
    }
}

public struct WatchFormCheckStopPayload: Sendable, Codable, Equatable {
    public let sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }

    public static func encode(_ payload: WatchFormCheckStopPayload) -> String {
        SyncPayloadCodec.encode(payload) ?? "{}"
    }

    public static func decode(from body: String) -> WatchFormCheckStopPayload? {
        SyncPayloadCodec.decode(WatchFormCheckStopPayload.self, from: body)
    }
}

public struct WatchFormCheckResultPayload: Sendable, Codable, Equatable {
    public let sessionID: String
    public let exercise: FormCheckExercise
    public let verdict: FormCheckVerdict
    public let cueText: String
    public let hapticCode: FormCheckHapticCode
    public let repCount: Int
    public let duration: TimeInterval
    public let analyzedAt: Date

    public init(
        sessionID: String,
        exercise: FormCheckExercise,
        verdict: FormCheckVerdict,
        cueText: String,
        hapticCode: FormCheckHapticCode,
        repCount: Int,
        duration: TimeInterval,
        analyzedAt: Date = .now
    ) {
        self.sessionID = sessionID
        self.exercise = exercise
        self.verdict = verdict
        self.cueText = cueText
        self.hapticCode = hapticCode
        self.repCount = repCount
        self.duration = duration
        self.analyzedAt = analyzedAt
    }

    public init(sessionID: String, analysis: FormCheckAnalysis) {
        self.init(
            sessionID: sessionID,
            exercise: analysis.exercise,
            verdict: analysis.verdict,
            cueText: analysis.cueText,
            hapticCode: analysis.hapticCode,
            repCount: analysis.repCount,
            duration: analysis.duration,
            analyzedAt: analysis.capturedAt
        )
    }

    public var shortSummary: String {
        switch verdict {
        case .solid:
            return String(localized: "Form solid", comment: "Watch form-check solid result")
        case .review:
            return String(localized: "Review form", comment: "Watch form-check review result")
        case .inconclusive:
            return String(localized: "Try again", comment: "Watch form-check inconclusive result")
        }
    }

    public static func encode(_ payload: WatchFormCheckResultPayload) -> String {
        SyncPayloadCodec.encode(payload) ?? "{}"
    }

    public static func decode(from body: String) -> WatchFormCheckResultPayload? {
        SyncPayloadCodec.decode(WatchFormCheckResultPayload.self, from: body)
    }
}

public enum WatchFormCheckStopReason: String, Sendable, Codable, Equatable {
    case userDismissed
    case unavailable
}

public struct WatchFormCheckStoppedPayload: Sendable, Codable, Equatable {
    public let sessionID: String
    public let reason: WatchFormCheckStopReason
    public let message: String

    public init(sessionID: String, reason: WatchFormCheckStopReason, message: String) {
        self.sessionID = sessionID
        self.reason = reason
        self.message = message
    }

    public static func encode(_ payload: WatchFormCheckStoppedPayload) -> String {
        SyncPayloadCodec.encode(payload) ?? "{}"
    }

    public static func decode(from body: String) -> WatchFormCheckStoppedPayload? {
        SyncPayloadCodec.decode(WatchFormCheckStoppedPayload.self, from: body)
    }
}

public struct WatchSessionSnapshot: Sendable, Codable {
    public let workoutID: String
    public let selectedAction: WorkoutAction
    public let restEndsAt: Date
    public let coachPrompt: String
    public let sessionActive: Bool
    public let statusMessage: String
    public let loggedSetCount: Int
    /// VOL-275: encoded `WatchScheduledPlanPayload` body for tomorrow's
    /// co-designed plan, so the watch keeps showing it across relaunches.
    /// Optional + defaulted so pre-VOL-275 snapshots keep decoding.
    public let scheduledPlanBody: String?

    public init(
        workoutID: String = "active-strength-session",
        selectedAction: WorkoutAction,
        restEndsAt: Date,
        coachPrompt: String,
        sessionActive: Bool,
        statusMessage: String,
        loggedSetCount: Int = 0,
        scheduledPlanBody: String? = nil
    ) {
        self.workoutID = workoutID
        self.selectedAction = selectedAction
        self.restEndsAt = restEndsAt
        self.coachPrompt = coachPrompt
        self.sessionActive = sessionActive
        self.statusMessage = statusMessage
        self.loggedSetCount = loggedSetCount
        self.scheduledPlanBody = scheduledPlanBody
    }

    private enum CodingKeys: String, CodingKey {
        case workoutID
        case selectedAction
        case restEndsAt
        case coachPrompt
        case sessionActive
        case statusMessage
        case loggedSetCount
        case scheduledPlanBody
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.workoutID = try container.decodeIfPresent(String.self, forKey: .workoutID) ?? "active-strength-session"
        self.selectedAction = try container.decode(WorkoutAction.self, forKey: .selectedAction)
        self.restEndsAt = try container.decode(Date.self, forKey: .restEndsAt)
        self.coachPrompt = try container.decode(String.self, forKey: .coachPrompt)
        self.sessionActive = try container.decode(Bool.self, forKey: .sessionActive)
        self.statusMessage = try container.decode(String.self, forKey: .statusMessage)
        self.loggedSetCount = try container.decodeIfPresent(Int.self, forKey: .loggedSetCount) ?? 0
        self.scheduledPlanBody = try container.decodeIfPresent(String.self, forKey: .scheduledPlanBody)
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

    override public init() {
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
    func enqueueFront(_ payload: WatchPayload) async
    func dequeueAll() async -> [WatchPayload]
    func count() async -> Int
}

public actor UserDefaultsWatchPendingPayloadStore: WatchPendingPayloadStore {
    private let defaults: UserDefaults
    private let key = "com.mabryventures.VolumeArc.watch.pendingPayloads"

    // VOL-138: `sending` lets non-isolated callers (XCTest methods,
    // app launch wiring) pass a `UserDefaults` instance across the
    // actor boundary without Swift 6 "risks causing data races"
    // diagnostics. `UserDefaults` is not marked `Sendable` in the
    // current Foundation SDKs, but ownership transfer at init time
    // is sound — once stored inside the actor, all reads/writes are
    // serialized by actor isolation. Same fix pattern is used in
    // Foundation's own Swift 6 transition.
    public init(defaults: sending UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func enqueue(_ payload: WatchPayload) async {
        var current = loadUnsafe()
        current.append(payload)
        save(current)
    }

    public func enqueueFront(_ payload: WatchPayload) async {
        var current = loadUnsafe()
        current.insert(payload, at: 0)
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
    private let telemetrySink: (any TelemetrySink)?

    public init(
        transport: WatchSessionTransport,
        payloadStore: WatchPendingPayloadStore,
        telemetrySink: (any TelemetrySink)? = nil
    ) {
        self.transport = transport
        self.payloadStore = payloadStore
        self.telemetrySink = telemetrySink
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
            recordPayloadQueued(payload, reason: "send_failed")
            throw error
        }
    }

    /// Flush any pending payloads if the peer is now reachable.
    public func flushPendingIfReachable() async throws {
        guard await transport.isReachable() else { return }
        let pending = await payloadStore.dequeueAll()
        for (index, payload) in pending.enumerated() {
            do {
                try await transport.send(payload)
                recordPayloadReplayed(payload)
            } catch {
                // Put the failed payload and every untouched payload back in
                // original order so a partial replay cannot drop work.
                for payloadToRequeue in pending[index...].reversed() {
                    await payloadStore.enqueueFront(payloadToRequeue)
                    recordPayloadQueued(payloadToRequeue, reason: "replay_failed")
                }
                throw error
            }
        }
    }

    private func recordPayloadQueued(_ payload: WatchPayload, reason: String) {
        telemetrySink?.record(TelemetryEvent(
            category: "watch",
            name: "payload.queued",
            severity: .info,
            message: "Watch payload queued for replay.",
            metadata: [
                "kind": payload.kind.rawValue,
                "reason": reason,
            ]
        ))
    }

    private func recordPayloadReplayed(_ payload: WatchPayload) {
        telemetrySink?.record(TelemetryEvent(
            category: "watch",
            name: "payload.replayed",
            severity: .info,
            message: "Watch payload replayed after reconnect.",
            metadata: [
                "kind": payload.kind.rawValue,
            ]
        ))
    }
}
