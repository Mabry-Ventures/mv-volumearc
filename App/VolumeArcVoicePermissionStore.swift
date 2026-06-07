import Foundation
import VolumeArcCore

#if canImport(AVFoundation) && canImport(Speech)
import AVFoundation
import Speech

actor VolumeArcVoicePermissionStore: VoicePermissionStore {
    func currentStatus() async -> VoicePermissionStatus {
        VoicePermissionStatus(
            microphone: microphoneStatus(),
            speechRecognition: speechStatus()
        )
    }

    func requestPermissions() async throws -> VoicePermissionStatus {
        let microphone = await requestMicrophone()
        let speech = await requestSpeechRecognition()
        return VoicePermissionStatus(microphone: microphone, speechRecognition: speech)
    }

    private func requestMicrophone() async -> FeaturePermissionStatus {
        let current = microphoneStatus()
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted ? .authorized : .denied)
            }
        }
    }

    private func requestSpeechRecognition() async -> FeaturePermissionStatus {
        let current = speechStatus()
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.mapSpeech(status))
            }
        }
    }

    private func microphoneStatus() -> FeaturePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .authorized
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .unavailable
        }
    }

    private func speechStatus() -> FeaturePermissionStatus {
        Self.mapSpeech(SFSpeechRecognizer.authorizationStatus())
    }

    private static func mapSpeech(_ status: SFSpeechRecognizerAuthorizationStatus) -> FeaturePermissionStatus {
        switch status {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unavailable
        }
    }
}
#endif

#if DEBUG
struct AuthorizedVoicePermissionFixtureStore: VoicePermissionStore {
    func currentStatus() async -> VoicePermissionStatus {
        VoicePermissionStatus(microphone: .authorized, speechRecognition: .authorized)
    }

    func requestPermissions() async throws -> VoicePermissionStatus {
        VoicePermissionStatus(microphone: .authorized, speechRecognition: .authorized)
    }
}
#endif
