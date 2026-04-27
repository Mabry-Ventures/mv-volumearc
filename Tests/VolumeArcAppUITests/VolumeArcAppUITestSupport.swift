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

    // MARK: - VOL-111: Dynamic Type + pseudo-locale launch helpers

    /// `accessibility5` Dynamic Type — the absolute largest content-size
    /// category iOS exposes. Catches truncation, button-row collapse, and
    /// scrollable content that doesn't actually scroll under stress.
    ///
    /// The raw string is the platform constant Apple's launch-argument
    /// parser recognizes; using the constant directly via
    /// `UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue`
    /// would couple this helper to UIKit, which the test target doesn't
    /// import directly.
    static let accessibility5SizeCategoryArgument =
        "UICTContentSizeCategoryAccessibilityXXXL"

    /// Re-decorate any launcher with Dynamic Type set to `.accessibility5`.
    /// Compose with `makeOnboardingApp` / `makeSeededApp` by passing the
    /// returned `[String]` as `extra:`.
    static var dynamicTypeAccessibility5LaunchArgs: [String] {
        [
            "-UIPreferredContentSizeCategoryName",
            accessibility5SizeCategoryArgument,
        ]
    }

    /// Apple's `-NSDoubleLocalizedStrings YES` pseudo-locale: every
    /// localized string is doubled in length at runtime, surfacing layout
    /// breaks that only happen with longer translations (German, Russian,
    /// French — the realistic target locales VolumeArc will ship to).
    static var pseudoLocaleDoubleLengthLaunchArgs: [String] {
        [
            "-NSDoubleLocalizedStrings", "YES",
            // Force the bundle to load via a non-en-US development region
            // so the doubled strings actually resolve through the
            // localization path. `en` is fine — the doubling middleware
            // catches the resolved value regardless of locale.
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
    }

    /// One-stop helper for the "extreme stress" combination: largest
    /// Dynamic Type + double-length pseudo-locale at the same time. Use
    /// this for the worst-case smoke test; individual axis tests use the
    /// per-axis launch-arg arrays above.
    static var dynamicTypeAndPseudoLocaleStressLaunchArgs: [String] {
        dynamicTypeAccessibility5LaunchArgs + pseudoLocaleDoubleLengthLaunchArgs
    }
}
