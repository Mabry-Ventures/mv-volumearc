import Foundation

/// VOL-287: persisted acknowledgment of the onboarding safety disclaimer.
///
/// The disclaimer is shown once during onboarding; the acknowledgment is
/// versioned so a future material change to the safety copy can re-prompt
/// by bumping `currentVersion`. The minimum-age value is product policy —
/// changing it requires Jared's sign-off (mirrors the VOL-284 clamp
/// constants contract).
public enum SafetyDisclaimerAcknowledgmentStore {
    private static let versionKey = "com.mabryventures.VolumeArc.safety.disclaimerAcceptedVersion"
    private static let acceptedAtKey = "com.mabryventures.VolumeArc.safety.disclaimerAcceptedAt"

    /// Bump when the disclaimer copy changes materially enough that prior
    /// acceptance should not carry over.
    public static let currentVersion = 1

    /// Product policy (VOL-287 sign-off): minimum age to train with
    /// VolumeArc without guardian approval.
    public static let minimumAgeYears = 16

    public static var isAccepted: Bool {
        UserDefaults.standard.integer(forKey: versionKey) >= currentVersion
    }

    public static func recordAccepted(at date: Date = .now) {
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: acceptedAtKey)
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: versionKey)
        UserDefaults.standard.removeObject(forKey: acceptedAtKey)
    }
}
