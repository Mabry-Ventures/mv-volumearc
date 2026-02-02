// WatchConnectivityManager.swift
// BeastModeWatch
// Manages WatchConnectivity for syncing workout data with iPhone

import Foundation
import WatchConnectivity
import Combine

/// Manages WatchConnectivity for bidirectional data sync between Watch and iPhone
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = WatchConnectivityManager()

    // MARK: - Published Properties

    @Published var isReachable: Bool = false
    @Published var isPaired: Bool = false
    @Published var isWatchAppInstalled: Bool = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    // MARK: - Private Properties

    private var session: WCSession?
    private let syncQueue = DispatchQueue(label: "com.beastmode.watch.sync")

    // MARK: - Initialization

    private override init() {
        super.init()
        setupSession()
    }

    // MARK: - Session Setup

    private func setupSession() {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Sync Operations

    /// Sync all pending workouts to iPhone
    func syncPendingWorkouts() async {
        guard let session, session.isReachable else {
            // Store for later sync via background transfer
            await transferWorkoutsInBackground()
            return
        }

        let workouts = await WatchWorkoutManager.shared.getWorkoutsForSync()

        guard !workouts.isEmpty else {
            print("No workouts to sync")
            return
        }

        do {
            let transferData = WorkoutTransferData(workouts: workouts)
            let encodedData = try JSONEncoder().encode(transferData)

            let message: [String: Any] = [
                "type": WatchMessageType.workoutCompleted.rawValue,
                "payload": encodedData,
                "timestamp": Date().timeIntervalSince1970
            ]

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.sendMessage(message, replyHandler: { reply in
                    // Mark workouts as synced
                    if let success = reply["success"] as? Bool, success {
                        Task { @MainActor in
                            let syncedIds = workouts.map { $0.id }
                            await WatchWorkoutManager.shared.markWorkoutsAsSynced(syncedIds)
                            self.lastSyncDate = Date()
                            self.syncError = nil
                        }
                        continuation.resume()
                    } else {
                        let error = NSError(
                            domain: "WatchSync",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Sync not acknowledged"]
                        )
                        continuation.resume(throwing: error)
                    }
                }, errorHandler: { error in
                    continuation.resume(throwing: error)
                })
            }
        } catch {
            syncError = error.localizedDescription
            print("Failed to sync workouts: \(error)")
            // Fallback to background transfer
            await transferWorkoutsInBackground()
        }
    }

    /// Transfer workouts via background transfer (when iPhone not immediately reachable)
    private func transferWorkoutsInBackground() async {
        guard let session else { return }

        let workouts = await WatchWorkoutManager.shared.getWorkoutsForSync()

        guard !workouts.isEmpty else { return }

        do {
            let transferData = WorkoutTransferData(workouts: workouts)
            let encodedData = try JSONEncoder().encode(transferData)

            // Use userInfo transfer for guaranteed delivery
            let userInfo: [String: Any] = [
                "type": WatchMessageType.workoutCompleted.rawValue,
                "payload": encodedData,
                "timestamp": Date().timeIntervalSince1970
            ]

            session.transferUserInfo(userInfo)
            print("Workouts queued for background transfer")
        } catch {
            print("Failed to queue background transfer: \(error)")
        }
    }

    /// Request full sync from iPhone
    func requestFullSync() {
        guard let session, session.isReachable else {
            print("iPhone not reachable for sync request")
            return
        }

        let message: [String: Any] = [
            "type": WatchMessageType.requestSync.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: nil, errorHandler: { error in
            print("Failed to request sync: \(error)")
        })
    }

    /// Update application context (for complication data etc.)
    func updateApplicationContext(_ context: [String: Any]) {
        guard let session else { return }

        do {
            try session.updateApplicationContext(context)
        } catch {
            print("Failed to update application context: \(error)")
        }
    }

    // MARK: - Connection Status

    func refreshConnectionStatus() {
        guard let session else { return }

        isReachable = session.isReachable

        #if os(iOS)
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        #endif
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                print("WCSession activation failed: \(error)")
                self.syncError = error.localizedDescription
            } else {
                print("WCSession activated with state: \(activationState.rawValue)")
                self.refreshConnectionStatus()
            }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        // Reactivate for switching watches
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshConnectionStatus()
        }
    }
    #endif

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if session.isReachable {
                // Attempt to sync pending workouts when connection established
                await self.syncPendingWorkouts()
            }
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
        guard let typeString = message["type"] as? String,
              let messageType = WatchMessageType(rawValue: typeString) else {
            replyHandler?(["success": false, "error": "Invalid message type"])
            return
        }

        Task { @MainActor in
            switch messageType {
            case .exerciseTemplatesUpdate:
                handleTemplatesUpdate(message, replyHandler: replyHandler)

            case .syncAcknowledged:
                handleSyncAcknowledged(message)
                replyHandler?(["success": true])

            case .userDataSync:
                handleUserDataSync(message, replyHandler: replyHandler)

            case .workoutCompleted:
                // This is handled on iPhone side
                replyHandler?(["success": true])

            case .requestSync:
                // Handle sync request from iPhone
                await syncPendingWorkouts()
                replyHandler?(["success": true])
            }
        }
    }

    @MainActor
    private func handleTemplatesUpdate(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        guard let payload = message["payload"] as? Data else {
            replyHandler?(["success": false, "error": "Invalid payload"])
            return
        }

        do {
            let templates = try JSONDecoder().decode([QuickExerciseTemplate].self, from: payload)
            WatchWorkoutManager.shared.updateExerciseTemplates(templates)
            replyHandler?(["success": true])
        } catch {
            replyHandler?(["success": false, "error": error.localizedDescription])
        }
    }

    @MainActor
    private func handleSyncAcknowledged(_ message: [String: Any]) {
        guard let workoutIdsData = message["workoutIds"] as? Data,
              let workoutIds = try? JSONDecoder().decode([UUID].self, from: workoutIdsData) else {
            return
        }

        WatchWorkoutManager.shared.markWorkoutsAsSynced(workoutIds)
        lastSyncDate = Date()
        syncError = nil
    }

    @MainActor
    private func handleUserDataSync(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        // Handle user data sync from iPhone (e.g., last weights, templates, settings)
        if let payload = message["payload"] as? Data {
            // Process user data as needed
            print("Received user data sync: \(payload.count) bytes")
        }
        replyHandler?(["success": true])
    }

    // MARK: - User Info Transfer (Background)

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleIncomingMessage(userInfo, replyHandler: nil)
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        if let error {
            print("User info transfer failed: \(error)")
        } else {
            print("User info transfer completed successfully")
            // Mark workouts as synced if this was a workout transfer
            Task { @MainActor in
                if let typeString = userInfoTransfer.userInfo["type"] as? String,
                   typeString == WatchMessageType.workoutCompleted.rawValue {
                    // Will be confirmed by iPhone acknowledgment
                }
            }
        }
    }

    // MARK: - Application Context

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            // Handle application context updates (e.g., complication data)
            if let complicationData = applicationContext["complicationData"] as? Data {
                // Update complication data manager
                if let data = try? JSONDecoder().decode(ComplicationData.self, from: complicationData) {
                    ComplicationDataManager.shared.saveData(data)
                }
            }
        }
    }
}
