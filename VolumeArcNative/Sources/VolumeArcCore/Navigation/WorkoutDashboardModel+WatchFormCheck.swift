#if canImport(SwiftUI)
import Foundation

extension WorkoutDashboardModel {
    public func handleWatchPayload(_ payload: WatchPayload) async {
        telemetrySink.record(TelemetryEvent(
            category: "watch",
            name: "payload_received",
            severity: .info,
            message: "Watch payload: \(payload.kind.rawValue)"
        ))
        lastWatchPayloadKindForTesting = payload.kind.rawValue

        if payload.kind == .voiceCoachToggle,
           let settings = WatchVoiceCoach.decodeSettingsPayload(from: payload.body) {
            await watchVoiceSettingsStore.setWatchVoiceEnabled(settings.isEnabled)
        }
        if payload.kind == .formCheckStart,
           let request = WatchFormCheckStartPayload.decode(from: payload.body) {
            receiveWatchFormCheckStart(request)
            return
        }
        if payload.kind == .formCheckStop,
           let stop = WatchFormCheckStopPayload.decode(from: payload.body) {
            receiveWatchFormCheckStop(stop)
            return
        }
        await refresh()
    }

    public func completeWatchFormCheck(_ analysis: FormCheckAnalysis, sessionID: String) async {
        defer {
            clearWatchFormCheckRequest(sessionID: sessionID)
        }
        guard completedWatchFormCheckSessionIDs.insert(sessionID).inserted else { return }
        recordFormCheckAnalysis(analysis)

        let result = WatchFormCheckResultPayload(sessionID: sessionID, analysis: analysis)
        let payload = WatchPayload(
            kind: .formCheckResult,
            workoutID: activeWorkoutID ?? sessionID,
            body: WatchFormCheckResultPayload.encode(result)
        )
        await sendWatchFormCheckPayload(payload, eventName: "result_sent")
    }

    public func dismissWatchFormCheckRequest(sessionID: String) async {
        await stopWatchFormCheckRequest(
            sessionID: sessionID,
            reason: .userDismissed,
            message: String(localized: "Capture stopped on iPhone.", comment: "Watch form-check stopped message")
        )
    }

    public func rejectWatchFormCheckRequest(sessionID: String, message: String) async {
        await stopWatchFormCheckRequest(
            sessionID: sessionID,
            reason: .unavailable,
            message: message
        )
    }

    private func stopWatchFormCheckRequest(
        sessionID: String,
        reason: WatchFormCheckStopReason,
        message: String
    ) async {
        defer {
            clearWatchFormCheckRequest(sessionID: sessionID)
        }
        guard completedWatchFormCheckSessionIDs.contains(sessionID) == false else { return }
        let stopped = WatchFormCheckStoppedPayload(
            sessionID: sessionID,
            reason: reason,
            message: message
        )
        let payload = WatchPayload(
            kind: .formCheckStopped,
            workoutID: activeWorkoutID ?? sessionID,
            body: WatchFormCheckStoppedPayload.encode(stopped)
        )
        await sendWatchFormCheckPayload(payload, eventName: "stopped_sent")
    }

    private func receiveWatchFormCheckStart(_ request: WatchFormCheckStartPayload) {
        activeWatchFormCheckRequest = request
        completedWatchFormCheckSessionIDs.remove(request.sessionID)
        watchFormCheckStopToken = nil
        telemetrySink.record(TelemetryEvent(
            category: "watch.form_check",
            name: "start_received",
            severity: .info,
            message: "Watch requested form-check capture.",
            metadata: [
                "exercise": request.exerciseName,
                "set": "\(request.setNumber)",
            ]
        ))
    }

    private func receiveWatchFormCheckStop(_ stop: WatchFormCheckStopPayload) {
        if activeWatchFormCheckRequest?.sessionID == stop.sessionID {
            watchFormCheckStopToken = "\(stop.sessionID)-\(UUID().uuidString)"
        }
        telemetrySink.record(TelemetryEvent(
            category: "watch.form_check",
            name: "stop_received",
            severity: .info,
            message: "Watch requested form-check analysis.",
            metadata: ["sessionID": stop.sessionID]
        ))
    }

    private func clearWatchFormCheckRequest(sessionID: String) {
        if activeWatchFormCheckRequest?.sessionID == sessionID {
            activeWatchFormCheckRequest = nil
            watchFormCheckStopToken = nil
        }
    }

    private func sendWatchFormCheckPayload(_ payload: WatchPayload, eventName: String) async {
        guard let watchConnectivityCoordinator else {
            telemetrySink.record(TelemetryEvent(
                category: "watch.form_check",
                name: "\(eventName)_unavailable",
                severity: .warning,
                message: "Watch form-check response could not be sent because WatchConnectivity is unavailable."
            ))
            return
        }

        do {
            try await watchConnectivityCoordinator.send(payload)
            telemetrySink.record(TelemetryEvent(
                category: "watch.form_check",
                name: eventName,
                severity: .info,
                message: "Watch form-check response sent.",
                metadata: ["kind": payload.kind.rawValue]
            ))
        } catch {
            let pending = await watchConnectivityCoordinator.pendingPayloadCount()
            publishWatchConnectivityQueuedNotice(pending: pending)
            telemetrySink.record(TelemetryEvent(
                category: "watch.form_check",
                name: "\(eventName)_queued",
                severity: .warning,
                message: "Watch form-check response queued until reconnect.",
                metadata: [
                    "kind": payload.kind.rawValue,
                    "pending": "\(pending)",
                ]
            ))
        }
    }
}
#endif
