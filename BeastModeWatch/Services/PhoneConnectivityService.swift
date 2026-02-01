import Foundation
import WatchConnectivity

/// Service for communicating with iPhone from Apple Watch
final class PhoneConnectivityService: NSObject, ObservableObject {
    static let shared = PhoneConnectivityService()

    @Published var isReachable = false
    @Published var receivedExercises: [ExerciseTransfer] = []
    @Published var restTimerDuration: TimeInterval = 90
    @Published var weightUnit: String = "lbs"

    private var session: WCSession?

    private override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Send Data to Phone

    func sendSetLog(_ setLog: SetLogTransfer) {
        guard let session = session, session.activationState == .activated else { return }

        do {
            let data = try JSONEncoder().encode(setLog)
            let message = ["type": "setLog", "data": data] as [String: Any]

            if session.isReachable {
                session.sendMessage(message, replyHandler: nil)
            } else {
                try session.updateApplicationContext(message)
            }
        } catch {
            print("Failed to send set log: \(error)")
        }
    }

    func sendWorkoutComplete(_ workout: WorkoutTransfer) {
        guard let session = session, session.activationState == .activated else { return }

        do {
            let data = try JSONEncoder().encode(workout)
            let message = ["type": "workoutComplete", "data": data] as [String: Any]

            if session.isReachable {
                session.sendMessage(message, replyHandler: nil)
            } else {
                try session.updateApplicationContext(message)
            }
        } catch {
            print("Failed to send workout complete: \(error)")
        }
    }

    func requestTodayExercises() {
        guard let session = session, session.isReachable else { return }

        session.sendMessage(["type": "requestExercises"], replyHandler: { [weak self] reply in
            if let data = reply["data"] as? Data,
               let exercises = try? JSONDecoder().decode([ExerciseTransfer].self, from: data) {
                DispatchQueue.main.async {
                    self?.receivedExercises = exercises
                }
            }
        })
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleReceivedMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleReceivedMessage(message)

        if let type = message["type"] as? String, type == "requestStatus" {
            // Send back current workout status
            let status = WorkoutStatusResponse(
                isActive: false,
                currentExercise: nil,
                currentSetNumber: nil,
                elapsedTime: nil
            )
            if let data = try? JSONEncoder().encode(status) {
                replyHandler(["data": data])
            } else {
                replyHandler([:])
            }
        } else {
            replyHandler(["status": "received"])
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleReceivedMessage(applicationContext)
    }

    private func handleReceivedMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }

        DispatchQueue.main.async {
            switch type {
            case "todayExercises":
                if let data = message["data"] as? Data,
                   let exercises = try? JSONDecoder().decode([ExerciseTransfer].self, from: data) {
                    self.receivedExercises = exercises
                }

            case "preferences":
                if let duration = message["restTimerDuration"] as? TimeInterval {
                    self.restTimerDuration = duration
                }
                if let unit = message["weightUnit"] as? String {
                    self.weightUnit = unit
                }

            default:
                break
            }
        }
    }
}
