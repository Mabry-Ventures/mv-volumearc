import Foundation

/// Canonical URLs for VolumeArc's user-facing legal pages.
///
/// These are referenced by the paywall and any other surface that needs to
/// point the user at Terms of Service or Privacy Policy. Keeping them in one
/// place means the real published URLs can be swapped in when the marketing
/// site is stood up closer to launch (VOL-71).
///
/// Note: the destinations are placeholder URLs on `volumearc.app` that may
/// return 404 until the marketing site ships. That's intentional — App Store
/// review requires these links to be wired up even before the pages are live
/// so reviewers can see intent.
public enum LegalLinks {
    // swiftlint:disable force_unwrapping
    // The URL literals below are static, valid https:// strings that cannot
    // fail at runtime; force-unwrapping is idiomatic for this pattern.

    /// Terms of Service landing page.
    public static let termsOfService = URL(string: "https://volumearc.app/terms")!

    /// Privacy Policy landing page.
    public static let privacyPolicy = URL(string: "https://volumearc.app/privacy")!
    // swiftlint:enable force_unwrapping
}
