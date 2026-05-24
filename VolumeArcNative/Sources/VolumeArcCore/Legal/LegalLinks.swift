import Foundation

/// Canonical URLs for VolumeArc's user-facing legal pages.
///
/// These are referenced by the paywall and any other surface that needs to
/// point the user at Terms of Service or Privacy Policy. Keeping them in one
/// place means there is a single source of truth for the published URLs
/// (VOL-71 wired them; VOL-160 stood up the marketing site).
///
/// Both destinations are live: the marketing site shipped (VOL-160) and the
/// pages carry finalized legal copy (VOL-195/VOL-124). `marketing` CI runs
/// `check-legal-pages.mjs` to fail the build if either page regresses to
/// placeholder/draft content, so these links resolve to real Terms /
/// Privacy content for App Store review (Guideline 3.1.2).
/// The Privacy Policy also carries the VOL-155/VOL-242 camera form-check
/// disclosure: frames stay on-device even when the Watch starts/stops capture;
/// only derived form metrics can enter coach context.
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
