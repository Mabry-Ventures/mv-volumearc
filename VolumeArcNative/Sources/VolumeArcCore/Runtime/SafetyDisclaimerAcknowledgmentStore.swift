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

/// PR #363 (Codex P2): pure decision for the root launch gates, so the
/// `.task` and the `onChange` mirror in `RootDashboardView` stay provably
/// consistent and the migration-safety invariant is unit-testable.
///
/// The hazard: an athlete who onboarded on a build BEFORE
/// `OnboardingCompletionStore` shipped has the store empty until a
/// successful refresh reads `model.isOnboardingComplete` and seeds it. If
/// that first post-upgrade refresh FAILS, `isOnboardingComplete` stays at
/// its default `false`. Treating that as a fresh install re-presents
/// onboarding, and completing it writes default fields through
/// `updateProfile`, overwriting the existing profile. So onboarding is
/// shown ONLY for a CONFIRMED fresh install — a successful load that found
/// no onboarded profile. A failed/again-pending refresh is treated as a
/// returning athlete (safety gate, never onboarding) to protect their data.
public enum LaunchGate {
    public struct Decision: Equatable, Sendable {
        public let showOnboarding: Bool
        public let showSafetyAcknowledgment: Bool

        public init(showOnboarding: Bool, showSafetyAcknowledgment: Bool) {
            self.showOnboarding = showOnboarding
            self.showSafetyAcknowledgment = showSafetyAcknowledgment
        }
    }

    /// - Parameters:
    ///   - refreshSucceeded: whether the initial dashboard load completed
    ///     (i.e. `model.isOnboardingComplete` reflects persisted truth).
    ///   - modelOnboardingComplete: the freshly loaded onboarding flag.
    ///   - onboardingStoreComplete: the refresh-independent persisted flag.
    ///   - safetyAccepted: whether the current safety disclaimer is accepted.
    public static func decide(
        refreshSucceeded: Bool,
        modelOnboardingComplete: Bool,
        onboardingStoreComplete: Bool,
        safetyAccepted: Bool
    ) -> Decision {
        let isOnboarded = onboardingStoreComplete || modelOnboardingComplete
        let confirmedFreshInstall = refreshSucceeded && !isOnboarded
        return Decision(
            showOnboarding: confirmedFreshInstall,
            showSafetyAcknowledgment: !confirmedFreshInstall && !safetyAccepted
        )
    }
}
