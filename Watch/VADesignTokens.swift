#if canImport(SwiftUI)
import SwiftUI

/// Design tokens for the VolumeArc watchOS app.
///
/// Mirrors the canonical `VA` namespace in
/// `VolumeArcNative/Sources/VolumeArcUI/DesignSystem/Tokens.swift` — because
/// the watchOS target does not (and cannot) depend on `VolumeArcUI` (the UI
/// package relies on iOS-only Liquid Glass APIs), we re-declare the subset of
/// tokens the watch surfaces reach for. Keep this file in sync with the
/// canonical source; never introduce a watch-only raw value here.
///
/// If you need a new watch-specific spacing, weight, or colour, add it here
/// first and mirror the addition upstream when the design-system relocation
/// audit lands.
public enum VA {
    // MARK: - Colors

    public enum Colors {
        /// Primary brand colour — CTAs, active states, accent lines.
        public static let primary = Color(red: 1.0, green: 0.50, blue: 0.24)

        /// Secondary accent — highlights, secondary actions.
        public static let secondary = Color(red: 0.35, green: 0.58, blue: 0.95)

        /// Success state — completions, confirmations.
        public static let success = Color(red: 0.30, green: 0.80, blue: 0.50)

        /// Warning state — deloads, non-blocking alerts.
        public static let warning = Color(red: 1.0, green: 0.78, blue: 0.20)

        /// Error state — failures, destructive actions.
        public static let error = Color(red: 0.98, green: 0.35, blue: 0.35)

        /// Neutral chrome — muted action tints.
        public static let neutral = Color.gray

        /// Text on primary surfaces.
        public static let textPrimary = Color.primary

        /// Muted text — metadata, hints, captions.
        public static let textSecondary = Color.secondary
    }

    // MARK: - Typography

    /// Watch-scaled typography tokens. Each token maps to a SwiftUI text style
    /// that Dynamic Type scales for us, then layers weight so we don't lose
    /// scaling when applying emphasis inline.
    public enum Typography {
        /// Hero number display (rest timer, readiness score).
        public static let display = Font.title2.bold()

        /// Screen headers and the current exercise title.
        public static let title = Font.title3.bold()

        /// Card-level prominent label (target weight, rep range).
        public static let headline = Font.headline

        /// Body copy — decision summary, coach text, status.
        public static let body = Font.footnote

        /// Supporting text — section headings, counts.
        public static let footnote = Font.footnote.weight(.semibold)

        /// Section label or micro-badge.
        public static let caption = Font.caption2.weight(.semibold)
    }

    // MARK: - Spacing (watch 2pt grid)

    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
        public static let xl: CGFloat = 16
    }

    // MARK: - Corner radius

    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
    }
}
#endif
