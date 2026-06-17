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

/// PR #363 (Codex P1): refresh-independent record that first-run
/// onboarding has completed at least once. `RootDashboardView` derives
/// its launch gates from this (and `SafetyDisclaimerAcknowledgmentStore`)
/// rather than `WorkoutDashboardModel.hasLoadedInitialData`, so a failed
/// dashboard refresh can neither bypass the onboarding/safety gates nor
/// make an already-onboarded athlete re-onboard (which would overwrite
/// their profile via `updateProfile`). The model's `isOnboardingComplete`
/// seeds this on every observation, so existing users migrate on their
/// first launch after this ships.
public enum OnboardingCompletionStore {
    private static let completedKey = "com.mabryventures.VolumeArc.onboarding.completed"

    public static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    public static func markComplete() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: completedKey)
    }
}
