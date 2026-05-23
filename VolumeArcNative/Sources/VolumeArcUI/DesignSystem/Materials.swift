#if canImport(SwiftUI)
import SwiftUI

// MARK: - Liquid Glass material tokens
//
// VolumeArc adopts iOS 26's real Liquid Glass APIs (`SwiftUI.Glass`,
// `View.glassEffect(_:in:)`, `GlassEffectContainer`, `GlassEffectTransition`).
// All glass surfaces in the design system route through these tokens so the
// rendering treatment stays consistent across cards, sheets, toasts, bubbles,
// and chrome — and so the fallback story for `accessibilityReduceTransparency`
// lives in exactly one place.
//
// The deployment target is iOS 26.0+, so the real Glass APIs are always
// available at runtime. The `@available(iOS 26.0, *)` annotations are
// belt-and-suspenders so the module would still compile cleanly if the
// floor were ever lowered.

public extension VA {
    /// Liquid Glass material tokens. Apply via the `vaGlass*` view modifiers
    /// on `View` to pick up the right reduce-transparency fallback automatically.
    enum Materials {
        /// Primary Liquid Glass material — used for cards, sheets, toasts, and
        /// hero chrome that should sit on top of the canvas with depth.
        @available(iOS 26.0, *)
        public static var glass: Glass { .regular }

        /// Interactive Liquid Glass — for tappable surfaces (buttons, chips,
        /// composer fields). The system reacts to touches with subtle motion.
        @available(iOS 26.0, *)
        public static var glassInteractive: Glass { Glass.regular.interactive() }

        /// Tinted Liquid Glass for state/accent surfaces (e.g., a tinted toast
        /// border, a brand-tinted card chrome). The tint blends with the
        /// underlying canvas — pass `nil` to clear the tint.
        @available(iOS 26.0, *)
        public static func tintedGlass(_ color: Color?) -> Glass {
            Glass.regular.tint(color)
        }
    }
}

// MARK: - View modifiers
//
// Each modifier handles the `accessibilityReduceTransparency` fallback to a
// solid `VA.Colors.surfacePrimary` fill, and keeps a belt-and-suspenders
// `.regularMaterial` fallback for pre-iOS 26 toolchains.

public extension View {
    /// Apply the primary Liquid Glass background clipped to the supplied shape.
    /// Falls back to a solid surface fill when `accessibilityReduceTransparency`
    /// is on, or to `.regularMaterial` on pre-iOS 26 toolchains.
    @ViewBuilder
    func vaGlassBackground<S: Shape>(in shape: S) -> some View {
        modifier(VAGlassBackgroundModifier(kind: .regular, shape: shape))
    }

    /// Convenience for the standard card-radius shape.
    func vaGlassBackground() -> some View {
        vaGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
    }

    /// Apply an interactive Liquid Glass background — use for tappable surfaces
    /// (chips, composer fields, secondary buttons).
    @ViewBuilder
    func vaInteractiveGlassBackground<S: Shape>(in shape: S) -> some View {
        modifier(VAGlassBackgroundModifier(kind: .interactive, shape: shape))
    }

    /// Convenience for the standard interactive-radius shape.
    func vaInteractiveGlassBackground() -> some View {
        vaInteractiveGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
    }

    /// Apply a tinted Liquid Glass background. Pass `nil` to clear the tint.
    @ViewBuilder
    func vaTintedGlassBackground<S: Shape>(_ tint: Color?, in shape: S) -> some View {
        modifier(VAGlassBackgroundModifier(kind: .tinted(tint), shape: shape))
    }

    /// Convenience for the standard card-radius shape.
    func vaTintedGlassBackground(_ tint: Color?) -> some View {
        vaTintedGlassBackground(tint, in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
    }
}

@_spi(Testing) public extension View {
    /// Test-only override for deterministic visual snapshots of glass-backed
    /// components. Production code leaves this unset and follows the system
    /// accessibilityReduceTransparency value.
    func vaGlassReduceTransparencyOverride(_ override: Bool?) -> some View {
        environment(\.vaGlassReduceTransparencyOverride, override)
    }
}

// MARK: - Internal modifier

/// Identifies which `VA.Materials` token to apply. Stored as a value type so
/// the actual `Glass` instance is constructed inside an `iOS 26+` branch.
private enum VAGlassKind {
    case regular
    case interactive
    case tinted(Color?)
}

private struct VAGlassReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

private extension EnvironmentValues {
    var vaGlassReduceTransparencyOverride: Bool? {
        get { self[VAGlassReduceTransparencyOverrideKey.self] }
        set { self[VAGlassReduceTransparencyOverrideKey.self] = newValue }
    }
}

private struct VAGlassBackgroundModifier<S: Shape>: ViewModifier {
    let kind: VAGlassKind
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.vaGlassReduceTransparencyOverride) private var reduceTransparencyOverride

    func body(content: Content) -> some View {
        if reduceTransparencyOverride ?? reduceTransparency {
            // Reduce-transparency users get a solid surface fill — no blur,
            // no see-through. Matches the design system's surface hierarchy.
            content.background(VA.Colors.surfacePrimary, in: shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(resolvedGlass, in: shape)
        } else {
            // Belt-and-suspenders fallback for pre-iOS 26 toolchains. The
            // shipping deployment target is iOS 26+, so this branch is dead
            // code at runtime — it's here so the module compiles cleanly if
            // the floor is ever lowered.
            content.background(.regularMaterial, in: shape)
        }
    }

    @available(iOS 26.0, *)
    private var resolvedGlass: Glass {
        switch kind {
        case .regular: return VA.Materials.glass
        case .interactive: return VA.Materials.glassInteractive
        case .tinted(let color): return VA.Materials.tintedGlass(color)
        }
    }
}
#endif
