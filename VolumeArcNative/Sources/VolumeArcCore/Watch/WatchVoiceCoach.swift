import Foundation

public enum WatchVoiceDelivery: String, Sendable, Equatable {
    case textToSpeech
}

public struct WatchVoiceUtterance: Sendable, Equatable {
    public let text: String
    public let delivery: WatchVoiceDelivery

    public init(
        text: String,
        delivery: WatchVoiceDelivery = .textToSpeech
    ) {
        self.text = text
        self.delivery = delivery
    }
}

public enum WatchVoiceEvent: Sendable, Equatable {
    case setComplete(restSeconds: Int)
    case nextSet(exerciseName: String, target: WorkoutTarget)
    case restRemaining(seconds: Int)
    case coachCue(String)
}

public struct WatchVoiceSettingsPayload: Codable, Sendable, Equatable {
    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}

public enum WatchVoiceCoach {
    public static func encodeSettingsPayload(isEnabled: Bool) -> String {
        SyncPayloadCodec.encode(WatchVoiceSettingsPayload(isEnabled: isEnabled)) ?? "{\"isEnabled\":\(isEnabled)}"
    }

    public static func decodeSettingsPayload(from body: String) -> WatchVoiceSettingsPayload? {
        SyncPayloadCodec.decode(WatchVoiceSettingsPayload.self, from: body)
    }

    public static func utterance(for event: WatchVoiceEvent) -> WatchVoiceUtterance {
        switch event {
        case let .setComplete(restSeconds):
            let seconds = max(0, restSeconds)
            return WatchVoiceUtterance(
                text: String(
                    localized: "Set complete, rest \(localizedSecondCount(seconds))",
                    comment: "Watch voice cue when a set is complete; includes rest duration in seconds"
                )
            )
        case let .nextSet(_, target):
            let reps = target.repRange.lowerBound
            return WatchVoiceUtterance(
                text: String(
                    localized: "Next set: \(localizedRepCount(reps)) at \(Int(target.weight.rounded()))",
                    comment: "Watch voice cue for the next set target"
                )
            )
        case let .restRemaining(seconds):
            let remaining = max(0, seconds)
            return WatchVoiceUtterance(
                text: String(
                    localized: "\(localizedSecondCount(remaining)) remaining",
                    comment: "Watch voice cue for rest time remaining"
                )
            )
        case let .coachCue(cue):
            return WatchVoiceUtterance(text: cue)
        }
    }

    private static func localizedSecondCount(_ seconds: Int) -> String {
        // watchOS 26.5 produced "30 second remaining" from inline inflection.
        if seconds == 1 {
            return String(localized: "1 second", comment: "Singular watch voice duration in seconds")
        }
        return String(
            localized: "\(seconds) seconds",
            comment: "Plural watch voice duration in seconds; placeholder is the number of seconds"
        )
    }

    private static func localizedRepCount(_ reps: Int) -> String {
        // Keep this explicit for the same watchOS 26.5 inline inflection behavior as seconds.
        if reps == 1 {
            return String(localized: "1 rep", comment: "Singular watch voice rep count")
        }
        return String(
            localized: "\(reps) reps",
            comment: "Plural watch voice rep count; placeholder is the number of reps"
        )
    }
}

public protocol WatchVoicePlayback: Sendable {
    func prewarm() async
    func speak(_ utterance: WatchVoiceUtterance) async throws
    func stop() async
}

public extension WatchVoicePlayback {
    func prewarm() async {}
    func stop() async {}
}

public struct UnavailableWatchVoicePlayback: WatchVoicePlayback {
    public init() {}

    public func speak(_ utterance: WatchVoiceUtterance) async throws {
        _ = utterance
    }
}

public protocol WatchVoiceSettingsStore: Sendable {
    func isWatchVoiceEnabled() async -> Bool
    func setWatchVoiceEnabled(_ enabled: Bool) async
}

public actor UserDefaultsWatchVoiceSettingsStore: WatchVoiceSettingsStore {
    private let defaults: UserDefaults
    private let key = "com.mabryventures.VolumeArc.watch.voiceCoach.enabled"

    public init(defaults: sending UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isWatchVoiceEnabled() async -> Bool {
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    public func setWatchVoiceEnabled(_ enabled: Bool) async {
        defaults.set(enabled, forKey: key)
    }
}
