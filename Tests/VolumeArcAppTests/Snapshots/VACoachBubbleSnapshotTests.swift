// VOL-135: visual-regression coverage for the coach transcript bubble.
//
// This suite locks both the real-glass and reduce-transparency render paths
// while exercising the production VACoachBubble chrome, avatar, sender
// alignment, Dynamic Type footprint, and streaming indicator states. The
// text body uses an SPI-only deterministic placeholder so Xcode Cloud font
// rasterization cannot invalidate otherwise-identical component chrome.

import SnapshotTesting
import SwiftUI
import UIKit
@_spi(Testing) import VolumeArcUI
import XCTest

@MainActor
final class VACoachBubbleSnapshotTests: XCTestCase {
    private enum Metrics {
        static let canvasWidth: CGFloat = 392
        static let regularCanvasSize = CGSize(width: canvasWidth, height: 332)
        static let accessibilityCanvasSize = CGSize(width: canvasWidth, height: 520)
    }

    private enum Variant {
        case regular
        case accessibility

        var dynamicTypeSize: DynamicTypeSize {
            switch self {
            case .regular:
                return .medium
            case .accessibility:
                return .accessibility5
            }
        }

        var preferredContentSizeCategory: UIContentSizeCategory {
            switch self {
            case .regular:
                return .medium
            case .accessibility:
                return .accessibilityExtraExtraExtraLarge
            }
        }

        var canvasSize: CGSize {
            switch self {
            case .regular:
                return Metrics.regularCanvasSize
            case .accessibility:
                return Metrics.accessibilityCanvasSize
            }
        }
    }

    func testCoachTranscriptGlassLight() {
        assertCoachTranscriptSnapshot(colorScheme: .light, variant: .regular, reduceTransparency: false)
    }

    func testCoachTranscriptGlassDark() {
        assertCoachTranscriptSnapshot(colorScheme: .dark, variant: .regular, reduceTransparency: false)
    }

    func testCoachTranscriptGlassAccessibilityLight() {
        assertCoachTranscriptSnapshot(colorScheme: .light, variant: .accessibility, reduceTransparency: false)
    }

    func testCoachTranscriptGlassAccessibilityDark() {
        assertCoachTranscriptSnapshot(colorScheme: .dark, variant: .accessibility, reduceTransparency: false)
    }

    func testCoachTranscriptReducedTransparencyLight() {
        assertCoachTranscriptSnapshot(colorScheme: .light, variant: .regular, reduceTransparency: true)
    }

    func testCoachTranscriptReducedTransparencyDark() {
        assertCoachTranscriptSnapshot(colorScheme: .dark, variant: .regular, reduceTransparency: true)
    }

    func testCoachTranscriptReducedTransparencyAccessibilityLight() {
        assertCoachTranscriptSnapshot(colorScheme: .light, variant: .accessibility, reduceTransparency: true)
    }

    func testCoachTranscriptReducedTransparencyAccessibilityDark() {
        assertCoachTranscriptSnapshot(colorScheme: .dark, variant: .accessibility, reduceTransparency: true)
    }

    private func assertCoachTranscriptSnapshot(
        colorScheme: ColorScheme,
        variant: Variant,
        reduceTransparency: Bool,
        testName: String = #function,
        line: UInt = #line
    ) {
        let view = CoachTranscriptFixture(isAccessibilityVariant: variant == .accessibility)
            .frame(width: Metrics.canvasWidth, height: variant.canvasSize.height, alignment: .top)
            .snapshotEnvironment(
                colorScheme: colorScheme,
                dynamicTypeSize: variant.dynamicTypeSize,
                reduceTransparency: reduceTransparency
            )

        assertVolumeArcSnapshot(
            of: view,
            as: imageSnapshot(colorScheme: colorScheme, variant: variant),
            in: self,
            testName: testName,
            line: line
        )
    }

    private func imageSnapshot<Value: View>(
        colorScheme: ColorScheme,
        variant: Variant
    ) -> Snapshotting<Value, UIImage> {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.preferredContentSizeCategory = variant.preferredContentSizeCategory
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
            layout: .fixed(width: variant.canvasSize.width, height: variant.canvasSize.height),
            traits: traits
        )
    }
}

private extension View {
    func snapshotEnvironment(
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize,
        reduceTransparency: Bool
    ) -> some View {
        environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.layoutDirection, .leftToRight)
            .vaGlassReduceTransparencyOverride(reduceTransparency)
    }
}

private struct CoachTranscriptFixture: View {
    let isAccessibilityVariant: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            VA.Colors.surfaceGrouped

            VStack(alignment: .leading, spacing: VA.Space.md) {
                VACoachBubble(
                    sender: .coach,
                    content: isAccessibilityVariant
                        ? "Ready 82."
                        : "Readiness 82. Hold RPE 7.",
                    rendersDeterministicSnapshotContent: true
                )

                VACoachBubble(
                    sender: .user,
                    content: isAccessibilityVariant ? "Minimal." : "Make it minimal.",
                    rendersDeterministicSnapshotContent: true
                )

                VACoachBubble(
                    sender: .coach,
                    content: isAccessibilityVariant ? "Rest." : "Rest 90s.",
                    isStreaming: true,
                    rendersDeterministicSnapshotContent: true
                )
            }
            .padding(VA.Space.lg)
        }
    }
}
