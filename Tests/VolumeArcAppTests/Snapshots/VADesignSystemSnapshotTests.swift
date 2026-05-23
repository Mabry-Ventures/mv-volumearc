// VOL-135 Phase 3: expand the bundled snapshot matrix across core
// design-system surfaces that appear on multiple app tabs.

#if canImport(SnapshotTesting) && canImport(UIKit)
import SnapshotTesting
import SwiftUI
import UIKit
import VolumeArcUI
import XCTest

@MainActor
final class VADesignSystemSnapshotTests: XCTestCase {
    private enum Metrics {
        static let width: CGFloat = 360
        static let cardCanvasSize = CGSize(width: 392, height: 144)
        static let toastCanvasSize = CGSize(width: 360, height: 101)
    }

    private enum CardFixtureStyle {
        case flat
        case elevated
        case accent
    }

    func testVACardFlatLight() {
        assertCardSnapshot(style: .flat, colorScheme: .light)
    }

    func testVACardFlatDark() {
        assertCardSnapshot(style: .flat, colorScheme: .dark)
    }

    func testVACardElevatedLight() {
        assertCardSnapshot(style: .elevated, colorScheme: .light)
    }

    func testVACardElevatedDark() {
        assertCardSnapshot(style: .elevated, colorScheme: .dark)
    }

    func testVACardAccentLight() {
        assertCardSnapshot(style: .accent, colorScheme: .light)
    }

    func testVACardAccentDark() {
        assertCardSnapshot(style: .accent, colorScheme: .dark)
    }

    func testVAToastSuccessLight() {
        assertToastSnapshot(kind: .success, colorScheme: .light)
    }

    func testVAToastSuccessDark() {
        assertToastSnapshot(kind: .success, colorScheme: .dark)
    }

    private func assertCardSnapshot(
        style: CardFixtureStyle,
        colorScheme: ColorScheme,
        testName: String = #function,
        line: UInt = #line
    ) {
        let view = ZStack {
            VA.Colors.surfaceGrouped
            card(style: style)
                .frame(width: Metrics.width)
        }
        .frame(width: Metrics.cardCanvasSize.width, height: Metrics.cardCanvasSize.height)
        .snapshotEnvironment(colorScheme)

        assertVolumeArcSnapshot(
            of: view,
            as: imageSnapshot(colorScheme: colorScheme, size: Metrics.cardCanvasSize),
            in: self,
            testName: testName,
            line: line
        )
    }

    private func assertToastSnapshot(
        kind: VAToast.Kind,
        colorScheme: ColorScheme,
        testName: String = #function,
        line: UInt = #line
    ) {
        let view = ZStack {
            VA.Colors.surfaceGrouped
            SnapshotToastChrome(kind: kind)
                .frame(width: Metrics.width)
        }
        .frame(width: Metrics.toastCanvasSize.width, height: Metrics.toastCanvasSize.height)
        .snapshotEnvironment(colorScheme)

        assertVolumeArcSnapshot(
            of: view,
            as: imageSnapshot(colorScheme: colorScheme, size: Metrics.toastCanvasSize),
            in: self,
            testName: testName,
            line: line
        )
    }

    @ViewBuilder
    private func card(style: CardFixtureStyle) -> some View {
        switch style {
        case .flat:
            VACard(style: .flat) {
                SnapshotCardContent()
            }
        case .elevated:
            VACard(style: .elevated) {
                SnapshotCardContent()
            }
        case .accent:
            VACard(style: .accent) {
                SnapshotCardContent()
            }
        }
    }

    private func imageSnapshot<Value: View>(
        colorScheme: ColorScheme,
        size: CGSize
    ) -> Snapshotting<Value, UIImage> {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.preferredContentSizeCategory = .large
            traits.layoutDirection = .leftToRight
            traits.accessibilityContrast = .normal
            traits.displayScale = 3
            traits.displayGamut = .SRGB
            traits.legibilityWeight = .regular
            traits.userInterfaceLevel = .base
        }
        return .image(
            precision: 0.99,
            perceptualPrecision: 0.98,
            layout: .fixed(width: size.width, height: size.height),
            traits: traits
        )
    }
}

private extension View {
    func snapshotEnvironment(_ colorScheme: ColorScheme) -> some View {
        environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.layoutDirection, .leftToRight)
    }
}

private struct SnapshotCardContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            HStack(spacing: VA.Space.sm) {
                Circle()
                    .fill(VA.Colors.primary)
                    .frame(width: 24, height: 24)
                Capsule()
                    .fill(VA.Colors.textPrimary.opacity(0.72))
                    .frame(width: 112, height: 12)
                Spacer()
                RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous)
                    .fill(VA.Colors.textPrimary.opacity(0.86))
                    .frame(width: 36, height: 24)
            }
            VStack(alignment: .leading, spacing: VA.Space.xs) {
                Capsule()
                    .fill(VA.Colors.textSecondary.opacity(0.76))
                    .frame(width: 300, height: 8)
                Capsule()
                    .fill(VA.Colors.textSecondary.opacity(0.52))
                    .frame(width: 232, height: 8)
            }
        }
    }
}

// Keep the toast fixture on deterministic chrome; Liquid Glass compositing is
// not pixel-stable across local and Xcode Cloud renderers.
private struct SnapshotToastChrome: View {
    let kind: VAToast.Kind

    var body: some View {
        HStack(alignment: .center, spacing: VA.Space.md) {
            Circle()
                .fill(tint)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(tint.opacity(0.28), lineWidth: 4)
                )

            VStack(alignment: .leading, spacing: VA.Space.xs) {
                Capsule()
                    .fill(VA.Colors.textPrimary.opacity(0.78))
                    .frame(width: 72, height: 10)
                Capsule()
                    .fill(VA.Colors.textSecondary.opacity(0.52))
                    .frame(width: 188, height: 8)
            }

            Spacer(minLength: 0)
        }
        .padding(VA.Space.md)
        .background(
            VA.Colors.surfacePrimary,
            in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
        .vaShadow(.md)
        .padding(.horizontal, VA.Space.lg)
    }

    private var tint: Color {
        switch kind {
        case .success: return VA.Colors.success
        case .info: return VA.Colors.info
        case .warning: return VA.Colors.warning
        case .error: return VA.Colors.error
        }
    }
}
#endif
