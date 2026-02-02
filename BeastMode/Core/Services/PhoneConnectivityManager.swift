// PhoneConnectivityManager.swift
// BeastMode
// Manages WatchConnectivity on iPhone side for receiving workout data from Apple Watch

import Foundation
import WatchConnectivity
import Combine
import SwiftData

/// Manages WatchConnectivity on iPhone to receive workout data from Apple Watch
@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = PhoneConnectivityManager()

    // MARK: - Published Properties

    @Published var isReachable: Bool = false
    @Published var isPaired: Bool = false
    @Published var isWatchAppInstalled: Bool = false
    @Published var pendingWorkoutsCount: Int = 0
    @Published var lastReceivedWorkout: Date?

    // MARK: - Private Properties

    private var session: WCSession?
    private var modelContext: ModelContext?

    // MARK: - Callbacks

    var onWorkoutReceived: ((WatchWorkoutTransfer) -> Void)?

    // MARK: - Initialization

    private override init() {
        super.init()
        setupSession()
    }

    // MARK: - Configuration

    /// Configure with SwiftData model context for saving workouts
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Session Setup

    private func setupSession() {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported on this device")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Send to Watch

    /// Send exercise templates to Watch
    func sendExerciseTemplates(_ templates: [WatchExerciseTemplate]) {
        guard let session, session.isReachable else {
            // Queue for later
            queueTemplatesForTransfer(templates)
            return
        }

        do {
            let encodedData = try JSONEncoder().encode(templates)
            let message: [String: Any] = [
                "type": "exercise_templates_update",
                "payload": encodedData,
                "timestamp": Date().timeIntervalSince1970
            ]

            session.sendMessage(message, replyHandler: { reply in
                print("Templates sent successfully: \(reply)")
            }, errorHandler: { error in
                print("Failed to send templates: \(error)")
                self.queueTemplatesForTransfer(templates)
            })
        } catch {
            print("Failed to encode templates: \(error)")
        }
    }

    /// Request sync from Watch
    func requestWatchSync() {
        guard let session, session.isReachable else {
            print("Watch not reachable")
            return
        }

        let message: [String: Any] = [
            "type": "request_sync",
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: nil, errorHandler: { error in
            print("Failed to request sync: \(error)")
        })
    }

    /// Send acknowledgment for received workouts
    func acknowledgeWorkouts(_ workoutIds: [UUID]) {
        guard let session else { return }

        do {
            let idsData = try JSONEncoder().encode(workoutIds)
            let message: [String: Any] = [
                "type": "sync_acknowledged",
                "workoutIds": idsData,
                "timestamp": Date().timeIntervalSince1970
            ]

            if session.isReachable {
                session.sendMessage(message, replyHandler: nil, errorHandler: { error in
                    print("Failed to send acknowledgment: \(error)")
                })
            } else {
                session.transferUserInfo(message)
            }
        } catch {
            print("Failed to encode workout IDs: \(error)")
        }
    }

    /// Update application context for Watch (complication data, etc.)
    func updateWatchContext(_ context: [String: Any]) {
        guard let session else { return }

        do {
            try session.updateApplicationContext(context)
        } catch {
            print("Failed to update watch context: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func queueTemplatesForTransfer(_ templates: [WatchExerciseTemplate]) {
        guard let session else { return }

        do {
            let encodedData = try JSONEncoder().encode(templates)
            let userInfo: [String: Any] = [
                "type": "exercise_templates_update",
                "payload": encodedData,
                "timestamp": Date().timeIntervalSince1970
            ]
            session.transferUserInfo(userInfo)
        } catch {
            print("Failed to queue templates: \(error)")
        }
    }

    // MARK: - Connection Status

    func refreshConnectionStatus() {
        guard let session else { return }

        isReachable = session.isReachable
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                print("WCSession activation failed: \(error)")
            } else {
                print("WCSession activated: \(activationState.rawValue)")
                self.refreshConnectionStatus()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshConnectionStatus()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    // MARK: - Message Handling

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingMessage(message, replyHandler: nil)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleIncomingMessage(message, replyHandler: replyHandler)
    }

    private nonisolated func handleIncomingMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?
    ) {
        guard let typeString = message["type"] as? String else {
            replyHandler?(["success": false, "error": "Invalid message type"])
            return
        }

        Task { @MainActor in
            switch typeString {
            case "workout_completed":
                handleWorkoutCompleted(message, replyHandler: replyHandler)

            case "request_sync":
                // Watch is requesting data
                replyHandler?(["success": true])

            default:
                replyHandler?(["success": false, "error": "Unknown message type"])
            }
        }
    }

    @MainActor
    private func handleWorkoutCompleted(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        guard let payload = message["payload"] as? Data else {
            replyHandler?(["success": false, "error": "Invalid payload"])
            return
        }

        do {
            let transferData = try JSONDecoder().decode(WatchWorkoutTransferData.self, from: payload)

            // Process each workout
            var processedIds: [UUID] = []
            for watchWorkout in transferData.workouts {
                processWatchWorkout(watchWorkout)
                processedIds.append(watchWorkout.id)
            }

            // Send acknowledgment
            acknowledgeWorkouts(processedIds)

            lastReceivedWorkout = Date()
            replyHandler?(["success": true])

            // Notify observers
            for workout in transferData.workouts {
                let transfer = WatchWorkoutTransfer(
                    id: workout.id,
                    name: workout.name,
                    startedAt: workout.startedAt,
                    completedAt: workout.completedAt,
                    exercises: workout.exercises.map { ex in
                        WatchExerciseTransfer(
                            name: ex.name,
                            category: ex.category,
                            sets: ex.sets.map { set in
                                WatchSetTransfer(
                                    setNumber: set.setNumber,
                                    weight: set.weight,
                                    reps: set.reps
                                )
                            }
                        )
                    }
                )
                onWorkoutReceived?(transfer)
            }
        } catch {
            print("Failed to decode workout data: \(error)")
            replyHandler?(["success": false, "error": error.localizedDescription])
        }
    }

    @MainActor
    private func processWatchWorkout(_ watchWorkout: WatchWorkoutSession) {
        guard let modelContext else {
            print("Model context not configured")
            return
        }

        // Create Workout from watch data
        // Note: This requires a userId which should come from the current user
        // For now, we'll store it and let the app handle the conversion

        print("Received workout from Watch: \(watchWorkout.name)")
        print("  - Exercises: \(watchWorkout.exercises.count)")
        print("  - Total sets: \(watchWorkout.totalSets)")
        print("  - Volume: \(watchWorkout.totalVolume) lbs")

        // TODO: Convert to Workout model and save to SwiftData
        // This would integrate with the main app's data model
    }

    // MARK: - User Info Transfer

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleIncomingMessage(userInfo, replyHandler: nil)
    }

    // MARK: - Application Context

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            // Handle any context updates from Watch
            print("Received application context from Watch")
        }
    }
}

// MARK: - Transfer Models (iPhone side)

/// Workout data received from Watch
struct WatchWorkoutTransfer: Identifiable {
    let id: UUID
    let name: String
    let startedAt: Date
    let completedAt: Date?
    let exercises: [WatchExerciseTransfer]
}

struct WatchExerciseTransfer {
    let name: String
    let category: String
    let sets: [WatchSetTransfer]
}

struct WatchSetTransfer {
    let setNumber: Int
    let weight: Double
    let reps: Int
}

/// Exercise template to send to Watch
struct WatchExerciseTemplate: Codable {
    let id: UUID
    let name: String
    let category: String
    let defaultWeight: Double
    let defaultReps: Int
}

// MARK: - Codable Transfer Data (matches Watch models)

private struct WatchWorkoutTransferData: Codable {
    let workouts: [WatchWorkoutSession]
    let transferredAt: Date
}

private struct WatchWorkoutSession: Codable {
    let id: UUID
    let name: String
    let startedAt: Date
    let completedAt: Date?
    let exercises: [WatchExerciseLog]
    let syncStatus: String

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var totalVolume: Double {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { setTotal, set in
                setTotal + (set.weight * Double(set.reps))
            }
        }
    }
}

private struct WatchExerciseLog: Codable {
    let id: UUID
    let name: String
    let category: String
    let sets: [WatchSetLog]
    let order: Int
}

private struct WatchSetLog: Codable {
    let id: UUID
    let setNumber: Int
    let weight: Double
    let reps: Int
    let completedAt: Date
}
