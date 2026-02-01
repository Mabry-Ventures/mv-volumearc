import Foundation
import WatchConnectivity

/// Service for communicating between iPhone and Apple Watch
final class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    @Published var isReachable = false
    @Published var isWatchAppInstalled = false
    @Published var lastReceivedSetLog: SetLogTransfer?
    @Published var lastReceivedWorkout: WorkoutTransfer?

    private var session: WCSession?

    private override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Session State

    var isSupported: Bool {
        WCSession.isSupported()
    }

    var isPaired: Bool {
        session?.isPaired ?? false
    }

    // MARK: - Send Data to Watch

    /// Send the current workout plan to the watch
    func sendWorkoutPlan(_ plan: WorkoutPlanTransfer) {
        guard let session = session, session.activationState == .activated else { return }

        do {
            let data = try JSONEncoder().encode(plan)
            let message = ["type": "workoutPlan", "data": data] as [String: Any]

            if session.isReachable {
                session.sendMessage(message, replyHandler: nil)
            } else {
                try session.updateApplicationContext(message)
            }
        } catch {
            print("Failed to send workout plan: \(error)")
        }
    }

    /// Send today's exercises to the watch
    func sendTodayExercises(_ exercises: [ExerciseTransfer]) {
        guard let session = session, session.activationState == .activated else { return }

        do {
            let data = try JSONEncoder().encode(exercises)
            let message = ["type": "todayExercises", "data": data] as [String: Any]

            if session.isReachable {
                session.sendMessage(message, replyHandler: nil)
            } else {
                try session.updateApplicationContext(message)
            }
        } catch {
            print("Failed to send exercises: \(error)")
        }
    }

    /// Send user preferences to the watch
    func sendUserPreferences(restTimerDuration: TimeInterval, weightUnit: String) {
        guard let session = session, session.activationState == .activated else { return }

        let message: [String: Any] = [
            "type": "preferences",
            "restTimerDuration": restTimerDuration,
            "weightUnit": weightUnit
        ]

        do {
            try session.updateApplicationContext(message)
        } catch {
            print("Failed to send preferences: \(error)")
        }
    }

    // MARK: - Request Data from Watch

    /// Request the current workout status from the watch
    func requestWorkoutStatus(completion: @escaping (WorkoutStatusResponse?) -> Void) {
        guard let session = session, session.isReachable else {
            completion(nil)
            return
        }

        session.sendMessage(["type": "requestStatus"], replyHandler: { reply in
            if let data = reply["data"] as? Data,
               let status = try? JSONDecoder().decode(WorkoutStatusResponse.self, from: data) {
                completion(status)
            } else {
                completion(nil)
            }
        })
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            #if os(iOS)
            self.isWatchAppInstalled = session.isWatchAppInstalled
            #endif
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleReceivedMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleReceivedMessage(message)
        replyHandler(["status": "received"])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleReceivedMessage(applicationContext)
    }

    private func handleReceivedMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        DispatchQueue.main.async {
            switch type {
            case "setLog":
                if let data = message["data"] as? Data,
                   let setLog = try? JSONDecoder().decode(SetLogTransfer.self, from: data) {
                    self.lastReceivedSetLog = setLog
                    NotificationCenter.default.post(
                        name: .watchSetLogReceived,
                        object: nil,
                        userInfo: ["setLog": setLog]
                    )
                }

            case "workoutComplete":
                if let data = message["data"] as? Data,
                   let workout = try? JSONDecoder().decode(WorkoutTransfer.self, from: data) {
                    self.lastReceivedWorkout = workout
                    NotificationCenter.default.post(
                        name: .watchWorkoutCompleted,
                        object: nil,
                        userInfo: ["workout": workout]
                    )
                }

            default:
                break
            }
        }
    }
}

// MARK: - Transfer Models

struct WorkoutPlanTransfer: Codable {
    let name: String
    let days: [DayTransfer]

    struct DayTransfer: Codable {
        let weekday: Int
        let focusArea: String
        let exercises: [ExerciseTransfer]
    }
}

struct ExerciseTransfer: Codable, Identifiable {
    let id: String
    let name: String
    let targetSets: Int
    let targetRepsMin: Int
    let targetRepsMax: Int
}

struct SetLogTransfer: Codable {
    let exerciseId: String
    let exerciseName: String
    let setNumber: Int
    let weight: Double?
    let reps: Int?
    let duration: TimeInterval?
    let timestamp: Date
}

struct WorkoutTransfer: Codable {
    let startTime: Date
    let endTime: Date
    let focusArea: String
    let exerciseLogs: [ExerciseLogTransfer]

    struct ExerciseLogTransfer: Codable {
        let exerciseName: String
        let sets: [SetLogTransfer]
    }
}

struct WorkoutStatusResponse: Codable {
    let isActive: Bool
    let currentExercise: String?
    let currentSetNumber: Int?
    let elapsedTime: TimeInterval?
}

// MARK: - Notification Names

extension Notification.Name {
    static let watchSetLogReceived = Notification.Name("watchSetLogReceived")
    static let watchWorkoutCompleted = Notification.Name("watchWorkoutCompleted")
}
