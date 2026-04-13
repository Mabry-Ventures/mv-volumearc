import Foundation
import VolumeArcCore

// MARK: - AI

final class MockAICoachProvider: AICoachProvider, @unchecked Sendable {
    var responses: [String] = ["Hold the current load and focus on rep quality."]
    var callCount = 0

    func coachResponse(for prompt: String, context: String) async throws -> String {
        callCount += 1
        return responses.indices.contains(callCount - 1) ? responses[callCount - 1] : responses.last ?? ""
    }
}

// MARK: - Cloud Sync

struct MockCloudSyncTransport: CloudSyncTransport {}

// MARK: - Health

struct MockHealthStore: HealthStore {}

// MARK: - Telemetry

final class MockTelemetrySink: TelemetrySink, @unchecked Sendable {
    var recordedEvents: [TelemetryEvent] = []

    func record(_ event: TelemetryEvent) {
        recordedEvents.append(event)
    }
}

// MARK: - Notifications

struct MockNotificationStore: NotificationStore {}

// MARK: - Voice

actor MockVoicePermissionStore: VoicePermissionStore {
    var statusToReturn = VoicePermissionStatus(microphone: .authorized, speechRecognition: .authorized)

    func currentStatus() async -> VoicePermissionStatus { statusToReturn }
    func requestPermissions() async throws -> VoicePermissionStatus { statusToReturn }
}

// MARK: - Account

struct MockAccountSessionStore: AccountSessionStore {}

// MARK: - Voice Transport

actor MockRealtimeVoiceTransport: RealtimeVoiceTransport {
    var connected = false

    func connect(model: AIModelIdentifier, policy: VoiceSessionPolicy) async throws {
        connected = true
    }

    func send(context: String, userText: String) async throws -> String { "" }
    func interrupt() async { connected = false }
    func disconnect() async { connected = false }
}
