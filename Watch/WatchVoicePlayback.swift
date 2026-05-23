import VolumeArcCore

#if canImport(AVFoundation)
@preconcurrency import AVFoundation

actor AVFoundationWatchVoicePlayback: WatchVoicePlayback {
    private let synthesizer = AVSpeechSynthesizer()
    private let speechDelegate = WatchSpeechDelegate()

    init() {
        speechDelegate.onSpeechEnded = {
            Self.deactivateAudioSession()
        }
        synthesizer.delegate = speechDelegate
    }

    func prewarm() async {
        _ = synthesizer.isSpeaking
    }

    func speak(_ utterance: WatchVoiceUtterance) async throws {
        try configureAudioSession()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let speech = AVSpeechUtterance(string: utterance.text)
        speech.prefersAssistiveTechnologySettings = true
        speech.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(speech)
    }

    func stop() async {
        synthesizer.stopSpeaking(at: .immediate)
        Self.deactivateAudioSession()
    }

    private func configureAudioSession() throws {
        #if os(watchOS) || os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: [])
        #endif
    }

    private static func deactivateAudioSession() {
        #if os(watchOS) || os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}

private final class WatchSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onSpeechEnded: (@Sendable () -> Void)?

    private func handleSpeechEnded(_ synthesizer: AVSpeechSynthesizer) {
        guard synthesizer.isSpeaking == false else { return }
        onSpeechEnded?()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        _ = utterance
        handleSpeechEnded(synthesizer)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        _ = utterance
        handleSpeechEnded(synthesizer)
    }
}
#endif
