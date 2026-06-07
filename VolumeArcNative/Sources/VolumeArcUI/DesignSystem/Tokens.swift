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
                                          dark: Color(red: 0.90, green: 0.54, blue: 0.32))

        /// Deep brand color — used for gradient endpoints and pressed states.
        public static let primaryDeep = Color(light: Color(red: 0.82, green: 0.31, blue: 0.11),
                                              dark: Color(red: 0.77, green: 0.41, blue: 0.22))

        /// Sunrise hero gradient start.
        public static let sunriseA = Color(light: Color(red: 1.0, green: 0.70, blue: 0.48),
                                           dark: Color(red: 1.0, green: 0.66, blue: 0.44))

        /// Sunrise hero gradient midpoint.
        public static let sunriseB = Color(light: Color(red: 0.95, green: 0.42, blue: 0.20),
                                           dark: Color(red: 0.90, green: 0.42, blue: 0.23))

        /// Sunrise hero gradient finish.
        public static let sunriseC = Color(light: Color(red: 0.78, green: 0.29, blue: 0.43),
                                           dark: Color(red: 0.70, green: 0.24, blue: 0.40))

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
        public static let surfaceGrouped = Color(.systemGroupedBackground)
        public static let cameraSurface = Color.black
        public static let cameraForeground = Color.white

        // Text
        public static let textPrimary = Color(.label)
        public static let textSecondary = Color(.secondaryLabel)
        public static let textTertiary = Color(.tertiaryLabel)
        public static let textOnPrimary = Color.white
    }

    // MARK: - Gradients

    public enum Gradients {
        public static let sunriseHero = LinearGradient(
            colors: [VA.Colors.sunriseA, VA.Colors.sunriseB, VA.Colors.sunriseC],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Typography
    //
    // All tokens use `Font.system(size:weight:design:)` paired with an implicit
    // relative text style via `Font.system(_:design:weight:)` so Dynamic Type
    // scaling works out of the box. The `relativeTo:` initializer lets the OS
    // scale each token against a paired text style while preserving our
    // rounded/default/monospaced design choice.

    public enum Typography {
        /// Hero numbers (readiness score, weight). Scales with .largeTitle.
        public static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)

        /// Screen titles. Scales with .title.
        public static let title = Font.system(.title, design: .rounded, weight: .bold)

        /// Section titles, card headers. Scales with .title2.
        public static let title2 = Font.system(.title2, design: .rounded, weight: .semibold)

        /// Card titles, prominent labels. Scales with .headline.
        public static let headline = Font.system(.headline, design: .default, weight: .semibold)

        /// Body text, descriptions. Scales with .body.
        public static let body = Font.system(.body, design: .default, weight: .regular)

        /// Buttons, interactive labels. Scales with .subheadline.
        public static let button = Font.system(.subheadline, design: .default, weight: .semibold)

        /// Supporting text, metadata. Scales with .footnote.
        public static let footnote = Font.system(.footnote, design: .default, weight: .medium)

        /// Captions, badges, timestamps. Scales with .caption2.
        public static let caption = Font.system(.caption2, design: .default, weight: .semibold)

        /// Larger caption (headline companion). Scales with .caption.
        public static let captionLarge = Font.system(.caption, design: .default, weight: .regular)

        /// Monospaced variant for numbers that should align vertically. Scales with .body.
        public static let monoDigit = Font.system(.body, design: .monospaced).monospacedDigit()

        /// Display with monospaced digits for rest timer. Scales with .largeTitle.
        public static let timerDisplay = Font.system(.largeTitle, design: .rounded, weight: .bold)
            .monospacedDigit()

        /// Large onboarding glyphs. Fixed by design so SF Symbols keep a stable visual anchor.
        public static let onboardingIcon = Font.system(size: 88, weight: .semibold)

        /// Compact camera chrome glyphs.
        public static let cameraChromeIcon = Font.system(size: 15, weight: .semibold)

        /// Large camera unavailable glyph.
        public static let cameraUnavailableIcon = Font.system(size: 44, weight: .semibold)

        /// Compact glyph inside primary buttons.
        public static let buttonIcon = Font.system(size: 15, weight: .semibold)

        /// Small trend glyph in metric cards.
        public static let metricTrendIcon = Font.system(size: 13, weight: .bold)

        /// Large empty-state glyph.
        public static let emptyStateIcon = Font.system(size: 48, weight: .light)

        /// Large error-state glyph.
        public static let errorStateIcon = Font.system(size: 44, weight: .medium)

        /// Compact coach avatar glyph.
        public static let coachAvatarIcon = Font.system(size: 14, weight: .semibold)

        /// Toast leading glyph.
        public static let toastIcon = Font.system(size: 20, weight: .semibold)

        // MARK: Widget / Live Activity scale
        //
        // Widget surfaces intentionally use fixed point sizes rather than
        // Dynamic Type — the WidgetKit layout budget is fixed and Dynamic
        // Type scaling would overflow the small/medium/large bounds. These
        // tokens codify the exact sizes we ship so no widget view has to
        // reach for `.system(size:)` directly.

        /// Widget display number (readiness score, small/medium layouts).
        public static let widgetScoreLarge = Font.system(size: 36, weight: .bold, design: .rounded)

        /// Widget display number (readiness score, medium ring).
        public static let widgetScoreMedium = Font.system(size: 28, weight: .bold, design: .rounded)

        /// Widget display number (readiness score, accessory / ring center).
        public static let widgetScoreSmall = Font.system(size: 22, weight: .bold, design: .rounded)

        /// Live Activity rest-timer display (monospaced for digit alignment).
        public static let widgetTimerDisplay = Font.system(size: 22, weight: .bold, design: .rounded)
            .monospacedDigit()

        /// Active exercise title in Live Activity banner.
        public static let widgetActivityTitle = Font.system(size: 17, weight: .bold, design: .rounded)

        /// Primary headline in widget medium/large layouts.
        public static let widgetHeadline = Font.system(size: 18, weight: .bold, design: .rounded)

        /// Secondary headline in widget medium layouts.
        public static let widgetHeadlineCompact = Font.system(size: 16, weight: .semibold, design: .rounded)

        /// Body in widget / accessory rectangular copy.
        public static let widgetBody = Font.system(size: 13, weight: .semibold)

        /// Medium-weight supporting copy in widgets.
        public static let widgetBodyMedium = Font.system(size: 12, weight: .medium)

        /// Coach prompt copy in widget large layout.
        public static let widgetCoachBody = Font.system(size: 12, weight: .regular)

        /// Supporting copy in widgets (next-lift forecast, status).
        public static let widgetFootnote = Font.system(size: 13, weight: .semibold)

        /// Supporting copy at small size (streak count, meta labels).
        public static let widgetFootnoteSmall = Font.system(size: 12, weight: .semibold)

        /// Small meta copy in widget large layout (row icons + labels).
        public static let widgetMeta = Font.system(size: 11, weight: .semibold)

        /// Chip/meta copy at compact widget small layout.
        public static let widgetMetaCompact = Font.system(size: 10, weight: .semibold)

        /// Accessory small body (dynamic island etc.).
        public static let widgetMicro = Font.system(size: 9, weight: .semibold)

        /// Streak count number.
        public static let widgetStreakNumber = Font.system(size: 11, weight: .bold, design: .rounded)

        /// Streak icon sizing.
        public static let widgetStreakIcon = Font.system(size: 9, weight: .bold)

        /// Tracking-style hero label ("VOLUMEARC", "READY").
        public static let widgetHeroBadgeLarge = Font.system(size: 11, weight: .semibold, design: .rounded)

        /// Tracking-style hero label at medium size.
        public static let widgetHeroBadge = Font.system(size: 10, weight: .semibold, design: .rounded)

        /// Micro ALL-CAPS badges ("READY", "REST", "NEXT").
        public static let widgetMicroBadge = Font.system(size: 10, weight: .semibold)

        /// Micro ALL-CAPS badges at smallest family.
        public static let widgetMicroBadgeXS = Font.system(size: 9, weight: .semibold)

        /// Accessory circular score inset label.
        public static let widgetAccessoryLabel = Font.system(size: 8, weight: .semibold)

        /// Accessory circular score glyph.
        public static let widgetAccessoryScore = Font.system(size: 20, weight: .bold, design: .rounded)

        /// Accessory circular score glyph (watchOS complication scale).
        public static let complicationScore = Font.system(size: 22, weight: .bold, design: .rounded)

        /// Dynamic Island prominent countdown / GO label (monospaced-friendly).
        public static let dynamicIslandTitle = Font.title3.bold()

        /// Dynamic Island compact trailing label (rest seconds / GO).
        public static let dynamicIslandCompact = Font.caption.bold()

        /// Letter spacing for ALL-CAPS eyebrow labels.
        public static let eyebrowTracking: CGFloat = 0.6

        /// Minimum scale for compact Dynamic Island title copy.
        public static let dynamicIslandTitleMinimumScale: CGFloat = 0.8

        /// Minimum scale for compact Dynamic Island subtitle copy.
        public static let dynamicIslandSubtitleMinimumScale: CGFloat = 0.82
    }

    // MARK: - Opacity

    public enum Opacity {
        /// Subtle decorative glow on tinted hero cards.
        public static let heroGlow: Double = 0.26

        /// Muted copy on primary/gradient surfaces.
        public static let textMutedOnPrimary: Double = 0.78

        /// Supporting copy on primary/gradient surfaces.
        public static let textSecondaryOnPrimary: Double = 0.88

        /// Elevated light chip fill on primary/gradient surfaces.
        public static let elevatedSurfaceOnPrimary: Double = 0.96

        /// Hairline stroke on primary/gradient surfaces.
        public static let strokeOnPrimary: Double = 0.28

        /// Tinted icon panel primary stop.
        public static let iconPanelPrimary: Double = 0.18

        /// Tinted icon panel accent stop.
        public static let iconPanelAccent: Double = 0.14

        /// Subtle separators on neutral surfaces.
        public static let subtleSeparator: Double = 0.16

        /// Subtle tinted fills.
        public static let subtleFill: Double = 0.12

        /// Prominent accent fills.
        public static let prominentFill: Double = 0.86

        /// Paywall hero-to-surface background wash.
        public static let paywallBackgroundStart: Double = 0.18

        /// Dark camera chrome backing.
        public static let cameraChrome: Double = 0.42

        /// Camera panel surface over live preview.
        public static let cameraPanel: Double = 0.94

        /// Camera panel hairline stroke.
        public static let cameraPanelStroke: Double = 0.14

        /// Skeleton line opacity over camera preview.
        public static let cameraSkeleton: Double = 0.72

        /// Primary camera overlay copy.
        public static let cameraTextPrimary: Double = 0.84

        /// Secondary camera overlay copy.
        public static let cameraTextSecondary: Double = 0.78
    }

    // MARK: - Spacing (4pt grid)

    public enum Space {
        public static let zero: CGFloat = 0
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
        public static let onboardingMaxWidth: CGFloat = 320

        /// Standard avatar control size.
        public static let avatar: CGFloat = 40

        /// Decorative hero glow diameter.
        public static let heroGlowSize: CGFloat = 220

        /// Decorative hero glow blur radius.
        public static let heroGlowBlur: CGFloat = 10

        /// Decorative hero glow horizontal offset.
        public static let heroGlowOffsetX: CGFloat = 72

        /// Decorative hero glow vertical offset.
        public static let heroGlowOffsetY: CGFloat = -78

        /// Fixed media rail in split action cards.
        public static let actionMediaRail: CGFloat = 88

        /// Minimum height for prominent action cards.
        public static let actionCardMinHeight: CGFloat = 92

        /// Compact icon badge dimension.
        public static let iconBadge: CGFloat = 30

        /// Large illustration tile dimension used in CTA cards.
        public static let ctaIllustration: CGFloat = 58

        /// Minimum height for exercise illustration heroes.
        public static let exerciseIllustrationMinHeight: CGFloat = 180

        /// Single-point border stroke.
        public static let border: CGFloat = 1

        /// Half-point hairline stroke.
        public static let hairline: CGFloat = 0.5

        /// Camera overlay close button and title pill height.
        public static let cameraChromeControl: CGFloat = 38

        /// Camera pose skeleton line width.
        public static let cameraSkeletonStroke: CGFloat = 3

        /// Camera pose joint marker diameter.
        public static let cameraJointMarker: CGFloat = 8

        // MARK: Widget scale
        //
        // Widgets have their own spacing rhythm because container budgets
        // are tight. These tokens are off-grid by design so we can hold
        // the shipping layout exactly while still routing through VA.Space.

        /// Streak badge inner gap (icon-to-number).
        public static let widgetHairline: CGFloat = 3

        /// Widget body rhythm (small layout gaps).
        public static let widgetTight: CGFloat = 6

        /// Widget row gap (medium/large ring-to-copy).
        public static let widgetRow: CGFloat = 10

        /// Widget hstack gap (dynamic island / live activity stacks).
        public static let widgetStack: CGFloat = 14

        /// Widget outer padding (live activity banner).
        public static let widgetOuter: CGFloat = 14
    }

    // MARK: - Widget layout (fixed-size chrome)
    //
    // WidgetKit enforces fixed bounds on every family; we codify the ring
    // dimensions and pill sizes so no widget view has to reach for a raw
    // CGFloat. Stroke widths mirror the ring radii rhythm.

    public enum Widget {
        /// Readiness ring size on system medium layout.
        public static let ringSizeMedium: CGFloat = 72

        /// Readiness ring size on system large layout.
        public static let ringSizeLarge: CGFloat = 92

        /// Readiness pill (Live Activity leading accessory).
        public static let activityPill: CGFloat = 52

        /// Apple Watch supplemental Live Activity countdown pill.
        public static let watchLiveActivityPill: CGFloat = 48

        /// Minimum scale for lock screen Live Activity set-progress copy.
        public static let liveActivitySetLineMinimumScale: CGFloat = 0.82

        /// Minimum scale for Apple Watch supplemental Live Activity set-progress copy.
        public static let watchLiveActivitySetLineMinimumScale: CGFloat = 0.78

        /// Minimum scale for Live Activity countdown glyphs inside circular pills.
        public static let liveActivityTimerMinimumScale: CGFloat = 0.72

        /// Ring stroke width on system medium layout.
        public static let ringStrokeMedium: CGFloat = 8

        /// Ring stroke width on system large layout.
        public static let ringStrokeLarge: CGFloat = 10

        /// Tracking applied to ALL-CAPS micro labels ("READY", "NEXT").
        public static let microTracking: CGFloat = 0.5

        /// Background-tint opacity used for ring backs and pill fills.
        public static let backgroundTint: Double = 0.12

        /// Ring-back stroke opacity.
        public static let ringBackOpacity: Double = 0.15
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

    /// Standard VA card styling with Liquid Glass material and shadow.
    /// Glass falls back to a solid surface fill when the user has
    /// `accessibilityReduceTransparency` enabled — see `VA.Materials`.
    func vaCardStyle(elevation: VA.Shadow = .sm, cornerRadius: CGFloat = VA.Radius.lg) -> some View {
        self
            .vaGlassBackground(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .vaShadow(elevation)
    }
}
#endif
