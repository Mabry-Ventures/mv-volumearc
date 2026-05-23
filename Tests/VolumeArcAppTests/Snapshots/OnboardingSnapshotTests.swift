// VOL-135: visual-regression coverage for the first-run onboarding welcome
// screen. Later slices can pin the form-heavy profile/preferences steps once
// their test-only step injection is worth exposing.

import SnapshotTesting
import SwiftUI
import UIKit
import VolumeArcCore
@_spi(Testing) import VolumeArcUI
import XCTest

@MainActor
final class OnboardingSnapshotTests: XCTestCase {
    private enum Metrics {
        static let regular = CGSize(width: 393, height: 852)
        static let accessibility = CGSize(width: 393, height: 1100)
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

        var size: CGSize {
            switch self {
            case .regular:
                return Metrics.regular
            case .accessibility:
                return Metrics.accessibility
            }
        }
    }

    private var savedDeterministicMode: Bool?

    override func setUp() async throws {
        try await super.setUp()

        guard !Self.isRunningInXcodeCloudTestProducts else {
            throw XCTSkip("""
            VOL-135: Onboarding snapshots are enforced locally and on the \
            self-hosted runner. Xcode Cloud renders this SwiftUI onboarding \
            surface differently from its bundled reference PNGs.
            """)
        }

        savedDeterministicMode = VolumeArcRuntimeFlags.isDeterministicMode
        VolumeArcRuntimeFlags.isDeterministicMode = true
    }

    override func tearDown() async throws {
        if let savedDeterministicMode {
            VolumeArcRuntimeFlags.isDeterministicMode = savedDeterministicMode
        }
        savedDeterministicMode = nil
        try await super.tearDown()
    }

    nonisolated private static var isRunningInXcodeCloudTestProducts: Bool {
        Bundle(for: OnboardingSnapshotTests.self).bundleURL.path.contains("TestProducts.xctestproducts")
    }

    func testWelcomeLight() {
        assertOnboardingSnapshot(colorScheme: .light, variant: .regular)
    }

    func testWelcomeLightReduceTransparencyOff() {
        assertOnboardingSnapshot(
            colorScheme: .light,
            variant: .regular,
            reduceTransparency: false
        )
    }

    func testWelcomeDark() {
        assertOnboardingSnapshot(colorScheme: .dark, variant: .regular)
    }

    func testWelcomeDarkReduceTransparencyOff() {
        assertOnboardingSnapshot(
            colorScheme: .dark,
            variant: .regular,
            reduceTransparency: false
        )
    }

    func testWelcomeAccessibilityLight() {
        assertOnboardingSnapshot(colorScheme: .light, variant: .accessibility)
    }

    func testWelcomeAccessibilityLightReduceTransparencyOff() {
        assertOnboardingSnapshot(
            colorScheme: .light,
            variant: .accessibility,
            reduceTransparency: false
        )
    }

    func testWelcomeAccessibilityDark() {
        assertOnboardingSnapshot(colorScheme: .dark, variant: .accessibility)
    }

    func testWelcomeAccessibilityDarkReduceTransparencyOff() {
        assertOnboardingSnapshot(
            colorScheme: .dark,
            variant: .accessibility,
            reduceTransparency: false
        )
    }

    private func assertOnboardingSnapshot(
        colorScheme: ColorScheme,
        variant: Variant,
        reduceTransparency: Bool = true,
        testName: String = #function,
        line: UInt = #line
    ) {
        let view = OnboardingView(
            isPresented: .constant(true),
            onComplete: { _ in }
        )
        .snapshotEnvironment(
            colorScheme: colorScheme,
            dynamicTypeSize: variant.dynamicTypeSize
        )
        .vaGlassReduceTransparencyOverride(reduceTransparency)
        .frame(width: variant.size.width, height: variant.size.height)

        assertVolumeArcSnapshot(
            of: view,
            as: imageSnapshot(
                colorScheme: colorScheme,
                preferredContentSizeCategory: variant.preferredContentSizeCategory,
                size: variant.size
            ),
            in: self,
            testName: testName,
            line: line
        )
    }

    private func imageSnapshot<Value: View>(
        colorScheme: ColorScheme,
        preferredContentSizeCategory: UIContentSizeCategory,
        size: CGSize
    ) -> Snapshotting<Value, UIImage> {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.preferredContentSizeCategory = preferredContentSizeCategory
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
    func snapshotEnvironment(
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize
    ) -> some View {
        environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.layoutDirection, .leftToRight)
    }
}
