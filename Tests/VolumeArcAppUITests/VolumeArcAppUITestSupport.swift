import XCTest

/// VOL-93: shared XCUITest helpers for the VolumeArc iOS app.
///
/// Centralizes the launch-argument configurations used by both the
/// original smoke tests (`VolumeArcAppUITests`) and the journey suite
/// (`VolumeArcAppJourneyTests`). Keeping one definition per flag
/// combination keeps the tests aligned if we ever rename or add a new
/// bootstrap flag.
enum VolumeArcAppUITestSupport {
    /// Fully-seeded dashboard: onboarding pre-completed, deterministic
    /// fixtures installed. Used by any test whose starting point is the
    /// home dashboard.
    static func makeSeededApp(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMode", "1",
            "-SkipOnboarding", "1",
            "-SeedFixtures", "1",
        ]
        app.launchArguments += extra
        return app
    }

    /// First-launch experience: the app boots into the onboarding cover
    /// because no user profile has been persisted yet. Used by the
    /// onboarding gate smoke test and the onboarding journey.
    static func makeOnboardingApp(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UITestMode", "1",
        ]
        app.launchArguments += extra
        return app
    }
}
