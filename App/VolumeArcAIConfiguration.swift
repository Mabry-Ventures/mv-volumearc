import Foundation
import VolumeArcCore

enum VolumeArcAIConfiguration {
    private static let secureStore = VolumeArcSecureStore()
    private static let baseURLKey = "ai.relay.baseURL"

    static func bootstrapRelaySecretsIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        let baseURLString = environment["VOLUMEARC_OPENAI_BASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "VolumeArcOpenAIBaseURL") as? String

        if let baseURLString, baseURLString.isEmpty == false {
            try? secureStore.save(baseURLString, for: baseURLKey)
        }
    }

    static var relayConfiguration: OpenAIRelayConfiguration? {
        let baseURLString = (try? secureStore.load(baseURLKey))
            ?? ProcessInfo.processInfo.environment["VOLUMEARC_OPENAI_BASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "VolumeArcOpenAIBaseURL") as? String

        guard let baseURLString, let baseURL = URL(string: baseURLString) else {
            return nil
        }

        return OpenAIRelayConfiguration(baseURL: baseURL, bearerToken: "session-managed")
    }

    static var startupWarning: String? {
        relayConfiguration == nil
            ? "OpenAI relay base URL is not configured, so cloud AI and live voice are unavailable on this build."
            : nil
    }
}
