#if canImport(SwiftUI)
import SwiftUI

/// Design tokens for VolumeArc.
/// All colors, typography, spacing, and visual constants live here.
/// Every view in the app should reference these — never hardcoded values.
public enum VA {
    // MARK: - Colors

    public enum Colors {
        /// Primary brand color — used for CTAs, active states, accent lines.
        public static let primary = Color(light: Color(red: 0.95, green: 0.42, blue: 0.20),
                                          dark: Color(red: 1.0, green: 0.50, blue: 0.24))

        /// Secondary accent — used for highlights, secondary actions.
        public static let secondary = Color(light: Color(red: 0.20, green: 0.45, blue: 0.85),
                                            dark: Color(red: 0.35, green: 0.58, blue: 0.95))

        /// Success state — completions, confirmations, green metrics.
        public static let success = Color(light: Color(red: 0.20, green: 0.70, blue: 0.40),
                                          dark: Color(red: 0.30, green: 0.80, blue: 0.50))

        /// Warning state — deload recommendations, non-blocking alerts.
        public static let warning = Color(light: Color(red: 0.95, green: 0.70, blue: 0.15),
                                          dark: Color(red: 1.0, green: 0.78, blue: 0.20))

        /// Error state — failures, destructive actions.
        public static let error = Color(light: Color(red: 0.90, green: 0.25, blue: 0.25),
                                        dark: Color(red: 0.98, green: 0.35, blue: 0.35))

        /// Info state — tips, neutral notices.
        public static let info = Color(light: Color(red: 0.30, green: 0.55, blue: 0.75),
                                       dark: Color(red: 0.45, green: 0.68, blue: 0.88))

        // Surface hierarchy
        public static let surfacePrimary = Color(.systemBackground)
        public static let surfaceSecondary = Color(.secondarySystemBackground)
        public static let surfaceTertiary = Color(.tertiarySystemBackground)

        // Text
        public static let textPrimary = Color(.label)
        public static let textSecondary = Color(.secondaryLabel)
        public static let textTertiary = Color(.tertiaryLabel)
        public static let textOnPrimary = Color.white
    }

    // MARK: - Typography

    public enum Typography {
        /// 34pt bold — hero numbers (readiness score, weight)
        public static let display = Font.system(size: 34, weight: .bold, design: .rounded)

        /// 28pt bold — screen titles
        public static let title = Font.system(size: 28, weight: .bold, design: .rounded)

        /// 22pt semibold — section titles, card headers
        public static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)

        /// 17pt semibold — card titles, prominent labels
        public static let headline = Font.system(size: 17, weight: .semibold, design: .default)

        /// 17pt regular — body text, descriptions
        public static let body = Font.system(size: 17, weight: .regular, design: .default)

        /// 15pt medium — buttons, interactive labels
        public static let button = Font.system(size: 15, weight: .semibold, design: .default)

        /// 13pt medium — supporting text, metadata
        public static let footnote = Font.system(size: 13, weight: .medium, design: .default)

        /// 11pt semibold — captions, badges, timestamps
        public static let caption = Font.system(size: 11, weight: .semibold, design: .default)

        /// Monospaced variant for numbers that should align vertically
        public static let monoDigit = Font.system(.body, design: .monospaced).monospacedDigit()

        /// Display with monospaced digits for rest timer
        public static let timerDisplay = Font.system(size: 44, weight: .bold, design: .rounded).monospacedDigit()
    }

    // MARK: - Spacing (4pt grid)

    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
    }

    // MARK: - Corner radius

    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let full: CGFloat = 9999
    }

    // MARK: - Shadow / Elevation

    public struct Shadow: Sendable {
        public let opacity: Double
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat

        public var color: Color {
            Color.black.opacity(opacity)
        }

        public static let none = Shadow(opacity: 0, radius: 0, x: 0, y: 0)
        public static let sm = Shadow(opacity: 0.08, radius: 4, x: 0, y: 2)
        public static let md = Shadow(opacity: 0.12, radius: 12, x: 0, y: 4)
        public static let lg = Shadow(opacity: 0.18, radius: 24, x: 0, y: 8)
    }
}

// MARK: - Color convenience

private extension Color {
    /// Create a dynamic color that adapts to light/dark mode.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #else
        self = light
        #endif
    }
}

// MARK: - View modifiers

public extension View {
    /// Apply a VA shadow token.
    func vaShadow(_ shadow: VA.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }

    /// Standard VA card styling with glass material and shadow.
    func vaCardStyle(elevation: VA.Shadow = .sm, cornerRadius: CGFloat = VA.Radius.lg) -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .vaShadow(elevation)
    }
}
#endif
