#if canImport(SwiftUI)
import SwiftUI

/// Standard animation tokens for VolumeArc.
/// Use these instead of ad-hoc `.animation()` calls.
public enum VAAnimation {
    /// Quick spring for button presses, taps, selection state.
    public static let quick = Animation.spring(response: 0.25, dampingFraction: 0.8)

    /// Standard spring for most UI transitions (default).
    public static let standard = Animation.spring(response: 0.35, dampingFraction: 0.8)

    /// Slow spring for hero transitions, card expansions.
    public static let slow = Animation.spring(response: 0.55, dampingFraction: 0.85)

    /// Bouncy spring for celebration moments (workout complete).
    public static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)

    /// Linear for continuous updates (timer countdown).
    public static let linear = Animation.linear(duration: 0.3)
}

// MARK: - View extensions

public extension View {
    /// Apply the standard VA spring animation, respecting Reduce Motion.
    func vaAnimation(_ animation: Animation = VAAnimation.standard, value: some Equatable) -> some View {
        self.animation(animation, value: value)
    }

    /// Scale + fade-in on appear. Respects Reduce Motion.
    func vaAppear() -> some View {
        modifier(VAAppearModifier())
    }
}

private struct VAAppearModifier: ViewModifier {
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .onAppear {
                withAnimation(VAAnimation.standard) {
                    hasAppeared = true
                }
            }
    }
}

// MARK: - Number ticker

/// A view that animates a numeric value change smoothly.
public struct VANumberTicker: View {
    private let value: Int
    private let font: Font

    @State private var displayedValue: Int = 0

    public init(value: Int, font: Font = VA.Typography.display) {
        self.value = value
        self.font = font
    }

    public var body: some View {
        Text("\(displayedValue)")
            .font(font)
            .contentTransition(.numericText())
            .onAppear { displayedValue = value }
            .onChange(of: value) { _, newValue in
                withAnimation(VAAnimation.standard) {
                    displayedValue = newValue
                }
            }
    }
}
#endif
