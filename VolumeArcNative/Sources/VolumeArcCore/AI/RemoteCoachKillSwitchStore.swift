import Foundation

/// VOL-286: cached remote kill switch for the on-device Foundation Models
/// coach path. The cloud path can be killed instantly at the relay
/// (`COACH_DISABLED=1` returns 503 and the app falls back on-device), but
/// the FM path never touches the relay during inference — this store is
/// how operations stops a misbehaving on-device brain without an app
/// update. The app refreshes it from `POST /v1/config` at launch; the
/// flag applies from the next coach turn and fails open to the last
/// cached value when the network is unavailable.
public enum RemoteCoachKillSwitchStore {
    private static let fmKilledKey = "com.mabryventures.VolumeArc.coach.remote.fmCoachKilled"

    public static var isFoundationModelCoachKilled: Bool {
        UserDefaults.standard.bool(forKey: fmKilledKey)
    }

    public static func update(foundationModelCoachKilled: Bool) {
        UserDefaults.standard.set(foundationModelCoachKilled, forKey: fmKilledKey)
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: fmKilledKey)
    }
}
