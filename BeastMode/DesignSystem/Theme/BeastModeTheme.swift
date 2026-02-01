import SwiftUI

/// Beast Mode theme configuration
struct BeastModeTheme {
    // MARK: - Spacing

    struct Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let full: CGFloat = .infinity
    }

    // MARK: - Shadows

    struct Shadow {
        static let small = ShadowStyle(
            color: .black.opacity(0.05),
            radius: 4,
            x: 0,
            y: 2
        )

        static let medium = ShadowStyle(
            color: .black.opacity(0.1),
            radius: 10,
            x: 0,
            y: 5
        )

        static let large = ShadowStyle(
            color: .black.opacity(0.15),
            radius: 20,
            x: 0,
            y: 10
        )

        static let glow = { (color: Color) in
            ShadowStyle(
                color: color.opacity(0.4),
                radius: 12,
                x: 0,
                y: 6
            )
        }
    }

    // MARK: - Animation

    struct Animation {
        static let quick = SwiftUI.Animation.snappy(duration: 0.2)
        static let standard = SwiftUI.Animation.snappy(duration: 0.3)
        static let slow = SwiftUI.Animation.snappy(duration: 0.5)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let bounce = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.6)
    }

    // MARK: - Icon Sizes

    struct IconSize {
        static let xs: CGFloat = 12
        static let sm: CGFloat = 16
        static let md: CGFloat = 20
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
}

/// Shadow style definition
struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Shadow Modifier

extension View {
    func beastShadow(_ style: ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

// MARK: - Theme Environment Key

struct ThemeKey: EnvironmentKey {
    static let defaultValue = BeastModeTheme.self
}

extension EnvironmentValues {
    var theme: BeastModeTheme.Type {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Haptic Feedback

enum HapticFeedback {
    case light
    case medium
    case heavy
    case success
    case warning
    case error
    case selection

    func trigger() {
        switch self {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Trigger haptic feedback on tap
    func hapticTap(_ feedback: HapticFeedback = .light) -> some View {
        self.onTapGesture {
            feedback.trigger()
        }
    }
}
