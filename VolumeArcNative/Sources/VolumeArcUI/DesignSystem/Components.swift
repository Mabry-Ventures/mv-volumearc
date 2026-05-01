#if canImport(SwiftUI)
import SwiftUI

// MARK: - VACard

public struct VACard<Content: View>: View {
    public enum Style {
        case flat
        case elevated
        case glass
        case accent
    }

    private let style: Style
    private let content: Content

    public init(style: Style = .glass, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    public var body: some View {
        // The glass case routes through `.vaGlassBackground(...)` so it uses
        // the real iOS 26 Liquid Glass APIs (and respects
        // `accessibilityReduceTransparency`). Other cases use a flat fill
        // background painted into the same shape.
        Group {
            if style == .glass {
                content
                    .padding(VA.Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vaGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
            } else {
                content
                    .padding(VA.Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(nonGlassBackground)
                    .clipShape(RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
            }
        }
        .vaShadow(shadow)
    }

    @ViewBuilder
    private var nonGlassBackground: some View {
        switch style {
        case .flat:
            VA.Colors.surfaceSecondary
        case .elevated:
            VA.Colors.surfacePrimary
        case .glass:
            // Unreachable — handled above by `vaGlassBackground`.
            Color.clear
        case .accent:
            LinearGradient(
                colors: [
                    VA.Colors.sunriseA.opacity(0.22),
                    VA.Colors.sunriseB.opacity(0.12),
                    VA.Colors.sunriseC.opacity(0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var shadow: VA.Shadow {
        switch style {
        case .flat: return .none
        case .elevated: return .md
        case .glass: return .sm
        case .accent: return .sm
        }
    }
}

// MARK: - VAButton

public struct VAButton: View {
    public enum Style {
        case primary
        case secondary
        case destructive
        case ghost
    }

    private let title: String
    private let icon: String?
    private let style: Style
    private let isLoading: Bool
    private let accessibilityHintText: String?
    private let accessibilityIdentifierValue: String?
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primary,
        isLoading: Bool = false,
        accessibilityHint: String? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isLoading = isLoading
        self.accessibilityHintText = accessibilityHint
        self.accessibilityIdentifierValue = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        // VOL-114: previous implementation tracked press state via
        // `.simultaneousGesture(DragGesture(...))` and applied the
        // visual scale/opacity effects on the wrapping View. That
        // gesture wrapper absorbed `.accessibilityIdentifier(...)`
        // modifiers attached AFTER it — XCUITest queries against
        // `app.buttons[id]` would fail because the identifier landed
        // on the gesture container, not the Button itself.
        //
        // The fix moves press-feedback into a custom ButtonStyle so the
        // Button stays the outermost accessibility element. Identifier,
        // label, and hint modifiers attach directly to it and propagate
        // cleanly. No more gesture-container interception.
        Button(action: action) {
            HStack(spacing: VA.Space.sm) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foregroundColor)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(VA.Typography.button)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .padding(.horizontal, VA.Space.lg)
            .modifier(VAButtonBackgroundModifier(style: style))
        }
        .buttonStyle(VAButtonPressStyle())
        .disabled(isLoading || !isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
        .accessibilityLabel(isLoading ? "\(title), loading" : title)
        .accessibilityHint(accessibilityHintText ?? "")
        .modifier(VAButtonIdentifierModifier(identifier: accessibilityIdentifierValue))
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive: return VA.Colors.textOnPrimary
        case .secondary: return VA.Colors.textPrimary
        case .ghost: return VA.Colors.primary
        }
    }
}

/// VOL-114: replaces the old `.simultaneousGesture(DragGesture(...))` +
/// `.scaleEffect(isPressed)` press-feedback approach. A custom ButtonStyle
/// reads `configuration.isPressed` natively, so we don't need a gesture
/// wrapper that would absorb downstream `.accessibilityIdentifier(...)`.
/// VAButton stays a clean Button at the accessibility layer.
private struct VAButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Attaches an accessibility identifier to the wrapped Button when one is
/// supplied. Skipping the modifier entirely when the identifier is nil
/// avoids clobbering call-site-applied identifiers on VAButtons that opt
/// out of threading one through the initializer.
private struct VAButtonIdentifierModifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

/// Paints the right background for a `VAButton`. The `.secondary` style uses
/// the real iOS 26 interactive Liquid Glass via `.vaInteractiveGlassBackground`;
/// other styles use a flat fill or gradient clipped to the button shape.
private struct VAButtonBackgroundModifier: ViewModifier {
    let style: VAButton.Style

    func body(content: Content) -> some View {
        switch style {
        case .secondary:
            content.vaInteractiveGlassBackground(
                in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
            )
        case .primary:
            content
                .background(
                    LinearGradient(
                        colors: [VA.Colors.primary, VA.Colors.primaryDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        case .destructive:
            content
                .background(VA.Colors.error)
                .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        case .ghost:
            content
                .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        }
    }
}

// MARK: - VAMetricDisplay

public struct VAMetricDisplay: View {
    public enum TrendDirection {
        case up, down, flat, none
    }

    private let label: String
    private let value: String
    private let unit: String?
    private let trend: TrendDirection
    private let style: Style

    public enum Style {
        case compact
        case standard
        case hero
    }

    public init(
        label: String,
        value: String,
        unit: String? = nil,
        trend: TrendDirection = .none,
        style: Style = .standard
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.trend = trend
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(label)
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(alignment: .firstTextBaseline, spacing: VA.Space.xs) {
                Text(value)
                    .font(valueFont)
                    .foregroundStyle(VA.Colors.textPrimary)
                if let unit {
                    Text(unit)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                if trend != .none {
                    Image(systemName: trendIcon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(trendColor)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit ?? "")")
    }

    private var valueFont: Font {
        switch style {
        case .compact: return VA.Typography.headline
        case .standard: return VA.Typography.title2
        case .hero: return VA.Typography.display
        }
    }

    private var trendIcon: String {
        switch trend {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        case .none: return ""
        }
    }

    private var trendColor: Color {
        switch trend {
        case .up: return VA.Colors.success
        case .down: return VA.Colors.error
        case .flat: return VA.Colors.textSecondary
        case .none: return .clear
        }
    }
}

// MARK: - VAProgressRing

public struct VAProgressRing: View {
    private let progress: Double
    private let lineWidth: CGFloat
    private let color: Color
    private let backgroundColor: Color

    public init(
        progress: Double,
        lineWidth: CGFloat = 8,
        color: Color = VA.Colors.primary,
        backgroundColor: Color? = nil
    ) {
        self.progress = max(0, min(1, progress))
        self.lineWidth = lineWidth
        self.color = color
        self.backgroundColor = backgroundColor ?? color.opacity(0.15)
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(backgroundColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
        }
    }
}

// MARK: - VASectionHeader

public struct VASectionHeader: View {
    private let title: String
    private let subtitle: String?
    private let action: (label: String, handler: () -> Void)?

    public init(
        _ title: String,
        subtitle: String? = nil,
        action: (label: String, handler: () -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VA.Typography.title2)
                    .foregroundStyle(VA.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
            }
            Spacer()
            if let action {
                Button(action.label, action: action.handler)
                    .font(VA.Typography.button)
                    .foregroundStyle(VA.Colors.primary)
            }
        }
    }
}

// MARK: - VAEmptyState

public struct VAEmptyState: View {
    private let icon: String
    private let title: String
    private let message: String
    private let action: (label: String, handler: () -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        action: (label: String, handler: () -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
    }

    public var body: some View {
        VStack(spacing: VA.Space.lg) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(VA.Colors.textTertiary)

            VStack(spacing: VA.Space.sm) {
                Text(title)
                    .font(VA.Typography.title2)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(message)
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if let action {
                VAButton(action.label, style: .primary, action: action.handler)
                    .frame(maxWidth: 240)
                    .padding(.top, VA.Space.md)
            }
        }
        .padding(VA.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - VALoadingState

public struct VALoadingState: View {
    private let message: String?

    public init(message: String? = nil) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: VA.Space.md) {
            ProgressView()
                .controlSize(.large)
            if let message {
                Text(message)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - VAErrorState

public struct VAErrorState: View {
    private let title: String
    private let message: String
    private let retry: (() -> Void)?

    public init(title: String, message: String, retry: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: VA.Space.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(VA.Colors.warning)

            VStack(spacing: VA.Space.sm) {
                Text(title)
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(message)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if let retry {
                VAButton("Try Again", icon: "arrow.clockwise", style: .secondary, action: retry)
                    .frame(maxWidth: 200)
            }
        }
        .padding(VA.Space.xl)
    }
}

// MARK: - VACoachBubble

public struct VACoachBubble: View {
    public enum Sender {
        case user
        case coach
    }

    private let sender: Sender
    private let content: String
    private let isStreaming: Bool

    public init(sender: Sender, content: String, isStreaming: Bool = false) {
        self.sender = sender
        self.content = content
        self.isStreaming = isStreaming
    }

    public var body: some View {
        HStack(alignment: .top, spacing: VA.Space.sm) {
            if sender == .coach {
                coachAvatar
            } else {
                Spacer(minLength: 60)
            }

            bubbleContent

            if sender == .user {
                Spacer().frame(width: 0)
            } else {
                Spacer(minLength: 40)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        let stack = VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(content)
                .font(VA.Typography.body)
                .foregroundStyle(sender == .user ? VA.Colors.textOnPrimary : VA.Colors.textPrimary)
                .multilineTextAlignment(.leading)

            if isStreaming {
                typingIndicator
            }
        }
        .padding(.horizontal, VA.Space.md)
        .padding(.vertical, VA.Space.md)

        if sender == .user {
            stack
                .background(VA.Colors.primary)
                .clipShape(RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
        } else {
            // Coach bubble uses real iOS 26 Liquid Glass.
            stack
                .vaGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
        }
    }

    private var accessibilityLabelText: String {
        let prefix = sender == .user ? "You said" : "Coach said"
        let suffix = isStreaming ? ", still typing" : ""
        return "\(prefix): \(content)\(suffix)"
    }

    private var coachAvatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [VA.Colors.primary, VA.Colors.primary.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 32, height: 32)
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(VA.Colors.textSecondary)
                    .frame(width: 5, height: 5)
                    .opacity(0.6)
            }
        }
        .padding(.top, 2)
    }
}
#endif
