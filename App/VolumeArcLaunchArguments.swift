import Foundation

/// Launch argument flags the app respects at startup. XCUITests set these
/// to produce deterministic state.
enum VolumeArcLaunchArguments {
    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag) else { return nil }

        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return nil }
        let value = arguments[nextIndex]
        guard value.hasPrefix("-") == false else { return nil }
        return value
    }

    private static func flagEnabled(_ flag: String) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }

        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return true }

        let rawValue = arguments[nextIndex]
        guard rawValue.hasPrefix("-") == false else { return true }
        return rawValue != "0"
    }

    /// `-UITestMode 1` — disables analytics, skips permission prompts, seeds
    /// deterministic state, and exposes accessibility identifiers on UI.
    static var isUITestMode: Bool {
        flagEnabled("-UITestMode")
    }

    /// `-SkipOnboarding 1` — skips the onboarding flow and seeds defaults.
    static var skipOnboarding: Bool {
        flagEnabled("-SkipOnboarding")
    }

    /// `-SeedFixtures 1` — seeds the persistence layer with demo fixture data.
    static var seedFixtures: Bool {
        flagEnabled("-SeedFixtures")
    }

    /// `-UseScreenshotStoreKitFixtures 1` — Debug-only screenshot hook.
    /// Renders submitted subscription prices without depending on the
    /// simulator StoreKit daemon, which can return an empty product list
    /// even when the local `.storekit` catalog is attached.
    static var useScreenshotStoreKitFixtures: Bool {
        isUITestMode && flagEnabled("-UseScreenshotStoreKitFixtures")
    }

    /// `-UsePremiumEntitlementFixture 1` — Debug-only UI-test hook layered
    /// on top of screenshot StoreKit fixtures. Grants one submitted
    /// subscription product locally so Profile can render the premium
    /// management path without a live StoreKit purchase.
    static var usePremiumEntitlementFixture: Bool {
        isUITestMode && flagEnabled("-UsePremiumEntitlementFixture")
    }

    /// `-SuppressSubscriptionManageExternalURL 1` — deterministic UI-test
    /// hook that lets Profile record the manage-subscription telemetry
    /// without leaving the app for Apple's subscription-management URL.
    static var suppressSubscriptionManageExternalURL: Bool {
        isUITestMode && flagEnabled("-SuppressSubscriptionManageExternalURL")
    }

    /// `-RestTimerDurationSeconds <seconds>` — deterministic UI-test hook that
    /// shortens the active-session rest timer for the expiry journey.
    static var restTimerDurationOverride: TimeInterval? {
        guard isUITestMode,
              let rawValue = value(after: "-RestTimerDurationSeconds"),
              let value = TimeInterval(rawValue),
              value > 0
        else { return nil }
        return value
    }

    /// `-VoicePromptTranscriptFixture <text>` — deterministic UI-test hook
    /// that supplies the transcript a speech-recognition pass would produce.
    static var voicePromptTranscriptFixture: String? {
        guard isUITestMode else { return nil }
        return value(after: "-VoicePromptTranscriptFixture")
    }

    /// `-PreserveUITestPersistence 1` — deterministic relaunch hook for
    /// resilience journeys. Honored only with `-UITestMode 1` and without
    /// fixture seeding, so normal UI tests still start clean.
    static var preserveUITestPersistence: Bool {
        isUITestMode && flagEnabled("-PreserveUITestPersistence")
    }

    /// `-PerfTestMode 1` — seeds a 50-session history and enables the full
    /// recent-sessions list on Today for scroll-performance tests.
    static var isPerfTestMode: Bool {
        flagEnabled("-PerfTestMode")
    }

    /// `-SimulatePermissionPrompts 1` — re-enables system permission prompts
    /// inside `-UITestMode 1` so XCUITests can drive the prompt path.
    static var simulatePermissionPrompts: Bool {
        flagEnabled("-SimulatePermissionPrompts")
    }

    /// `-StrictPrivacyMode 1` — deterministic-mode-only hook used by coach
    /// privacy journey tests to seed the profile in strict mode.
    static var strictPrivacyMode: Bool {
        isUITestMode && flagEnabled("-StrictPrivacyMode")
    }

    /// `-PostFakeWatchPayload <kind>` — posts a simulated `WatchPayload`
    /// notification at launch as if a paired Watch had sent the named kind.
    static var postFakeWatchPayloadKind: String? {
        value(after: "-PostFakeWatchPayload")
    }

    /// `-OpenDeepLinkOnLaunch <url>` — deterministic-mode-only XCUITest hook.
    static var openDeepLinkURL: URL? {
        guard isUITestMode, let rawValue = value(after: "-OpenDeepLinkOnLaunch") else { return nil }
        return URL(string: rawValue)
    }

    /// `-OpenNotificationOnLaunch <url>` — deterministic-mode-only XCUITest
    /// hook that simulates tapping a notification with a VolumeArc deep link.
    static var openNotificationURL: URL? {
        guard isUITestMode, let rawValue = value(after: "-OpenNotificationOnLaunch") else { return nil }
        return URL(string: rawValue)
    }
}
