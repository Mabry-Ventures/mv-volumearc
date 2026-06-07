import Foundation

public enum FeaturePermissionStatus: String, Sendable {
    case authorized
    case denied
    case notDetermined
    case unavailable
}

public struct VoicePermissionStatus: Sendable, Equatable {
    public let microphone: FeaturePermissionStatus
    public let speechRecognition: FeaturePermissionStatus

    public init(microphone: FeaturePermissionStatus, speechRecognition: FeaturePermissionStatus) {
        self.microphone = microphone
        self.speechRecognition = speechRecognition
    }

    public var isAuthorized: Bool {
        microphone == .authorized && speechRecognition == .authorized
    }

    public var isDeniedOrUnavailable: Bool {
        [microphone, speechRecognition].contains { status in
            status == .denied || status == .unavailable
        }
    }
}

public protocol VoicePermissionStore: Sendable {
    func currentStatus() async -> VoicePermissionStatus
    func requestPermissions() async throws -> VoicePermissionStatus
}

public struct UnavailableVoicePermissionStore: VoicePermissionStore {
    public init() {}

    public func currentStatus() async -> VoicePermissionStatus {
        VoicePermissionStatus(microphone: .unavailable, speechRecognition: .unavailable)
    }

    public func requestPermissions() async throws -> VoicePermissionStatus {
        VoicePermissionStatus(microphone: .unavailable, speechRecognition: .unavailable)
    }
}
