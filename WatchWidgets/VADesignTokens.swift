#if canImport(SwiftUI) && os(watchOS)
import SwiftUI

/// Design tokens for the VolumeArc watchOS widget / complication extension.
///
/// Mirrors the canonical `VA` namespace in
/// `VolumeArcNative/Sources/VolumeArcUI/DesignSystem/Tokens.swift` — because
/// the watch widget extension does not depend on `VolumeArcUI`, we re-declare
/// the subset of tokens the complication surfaces reach for. Keep this file
/// in sync with the canonical source; never introduce a watch-only raw value
/// here.
public enum VA {
    // MARK: - Colors

    public enum Colors {
        /// Primary brand colour — CTAs, active states, accent lines.
        public static let primary = Color(red: 1.0, green: 0.50, blue: 0.24)

        /// Muted text — metadata, hints, captions.
        public static let textSecondary = Color.secondary
    }

    // MARK: - Typography (complication scale)

    /// Complication typography. Weights and sizes are tuned for watchOS
    /// accessory families; do not downgrade to literal `.system(size:)` —
    /// add a new token here instead.
    public enum Typography {
        /// Readiness score display — accessoryCircular center glyph.
        public static let scoreDisplay = Font.system(.title, design: .rounded, weight: .bold).monospacedDigit()

        /// Prominent number in accessoryCorner tiles.
        public static let scoreCompact = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()

        /// Ready-state micro label ("READY").
        public static let microLabel = Font.caption2.weight(.semibold)

        /// Headline in accessoryRectangular.
        public static let rectHeadline = Font.headline.monospacedDigit()

        /// Secondary line in accessoryRectangular.
        public static let rectCaption = Font.caption

        /// Tertiary line in accessoryRectangular.
        public static let rectFootnote = Font.caption2
    }

    // MARK: - Spacing

    public enum Space {
        public static let xxs: CGFloat = 0
        public static let xs: CGFloat = 2
        public static let sm: CGFloat = 4
    }

    // MARK: - Typographic tracking

    public enum Tracking {
        /// Wide-letter-spacing used on micro labels (e.g. "READY").
        public static let microLabel: CGFloat = 0.5
    }
}
#endif
