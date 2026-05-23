// VOL-135: visual-regression coverage for the Premium paywall shell.
// StoreKit `Product` values are intentionally not constructed here; the
// snapshot pins the deterministic loaded-empty and failure states around the
// real hero, feature matrix, CTA, and legal chrome.

import SnapshotTesting
import SwiftUI
import UIKit
@_spi(Testing) import VolumeArcCore
@_spi(Testing) import VolumeArcUI
import XCTest

@MainActor
final class PaywallSnapshotTests: XCTestCase {
    private static let storeKitUnavailableMessage = String(
        localized: "StoreKit temporarily unavailable.",
        comment: "Paywall failure shell message used in snapshot tests"
    )

    override func setUpWithError() throws {
        try super.setUpWithError()

        guard !Self.isRunningInXcodeCloudTestProducts else {
            throw XCTSkip("""
            VOL-135: Paywall snapshots are enforced locally and on the \
            self-hosted runner. Xcode Cloud renders this SwiftUI paywall \
            surface differently from its bundled reference PNGs.
            """)
        }
    }

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

        var capturesPlanState: Bool {
            switch self {
            case .regular:
                return false
            case .accessibility:
                return true
            }
        }
    }

    nonisolated private static var isRunningInXcodeCloudTestProducts: Bool {
        Bundle(for: PaywallSnapshotTests.self).bundleURL.path.contains("TestProducts.xctestproducts")
    }

    func testLoadedEmptyPlansLight() {
        assertPaywallSnapshot(loadingState: .loaded, colorScheme: .light, variant: .regular)
    }

    func testLoadedEmptyPlansLightReduceTransparencyOff() {
        assertPaywallSnapshot(
            loadingState: .loaded,
            colorScheme: .light,
            variant: .regular,
            reduceTransparency: false
        )
    }

    func testLoadedEmptyPlansDark() {
        assertPaywallSnapshot(loadingState: .loaded, colorScheme: .dark, variant: .regular)
    }

    func testLoadedEmptyPlansDarkReduceTransparencyOff() {
        assertPaywallSnapshot(
            loadingState: .loaded,
            colorScheme: .dark,
            variant: .regular,
            reduceTransparency: false
        )
    }

    func testLoadedEmptyPlansAccessibilityLight() {
        assertPaywallSnapshot(loadingState: .loaded, colorScheme: .light, variant: .accessibility)
    }

    func testLoadedEmptyPlansAccessibilityLightReduceTransparencyOff() {
        assertPaywallSnapshot(
            loadingState: .loaded,
            colorScheme: .light,
            variant: .accessibility,
            reduceTransparency: false
        )
    }

    func testLoadedEmptyPlansAccessibilityDark() {
        assertPaywallSnapshot(loadingState: .loaded, colorScheme: .dark, variant: .accessibility)
    }

    func testLoadedEmptyPlansAccessibilityDarkReduceTransparencyOff() {
        assertPaywallSnapshot(
            loadingState: .loaded,
            colorScheme: .dark,
            variant: .accessibility,
            reduceTransparency: false
        )
    }

    func testFailedPlansLight() {
        assertPaywallSnapshot(
            loadingState: .failed(Self.storeKitUnavailableMessage),
            colorScheme: .light,
            variant: .regular
        )
    }

    func testFailedPlansLightReduceTransparencyOff() {
        assertPaywallSnapshot(
            loadingState: .failed(Self.storeKitUnavailableMessage),
            colorScheme: .light,
            variant: .regular,
            reduceTransparency: false
        )
    }

    func testFailedPlansDark() {
        assertPaywallSnapshot(
            loadingState: .failed(Self.storeKitUnavailableMessage),
            colorScheme: .dark,
            variant: .regular
        )
    }

    func testFailedPlansDarkReduceTransparencyOff() {
        assertPaywallSnapshot(
            loadingState: .failed(Self.storeKitUnavailableMessage),
            colorScheme: .dark,
            variant: .regular,
            reduceTransparency: false
        )
    }

    func testFailedPlansAccessibilityLight() {
        assertPaywallSnapshot(
            loadingState: .failed(Self.storeKitUnavailableMessage),
            colorScheme: .light,
            variant: .accessibility
        )
    }

    func testFailedPlansAccessibilityLightReduceTransparencyOff() {
        assertPaywallSnapshot(
            loadingState: .failed(Self.storeKitUnavailableMessage),
            colorScheme: .light,
            variant: .accessibility,
            reduceTransparency: false
        )
    }

    func testFailedPlansAccessibilityDark() {
        assertPaywallSnapshot(
            loadingState: .failed(Self.storeKitUnavailableMessage),
            colorScheme: .dark,
            variant: .accessibility
        )
    }

    func testFailedPlansAccessibilityDarkReduceTransparencyOff() {
        assertPaywallSnapshot(
            loadingState: .failed(Self.storeKitUnavailableMessage),
            colorScheme: .dark,
            variant: .accessibility,
            reduceTransparency: false
        )
    }

    private func assertPaywallSnapshot(
        loadingState: StoreKitSubscriptionStore.LoadingState,
        colorScheme: ColorScheme,
        variant: Variant,
        reduceTransparency: Bool = true,
        testName: String = #function,
        line: UInt = #line
    ) {
        let store = StoreKitSubscriptionStore(
            productIDs: [],
            loadingState: loadingState
        )
        let paywall = PaywallView(
            subscriptionStore: store,
            isPresented: .constant(true)
        )
        let view = Group {
            // Xcode Cloud renders SwiftUI navigation chrome differently from
            // local/self-hosted sims, so snapshot production content surfaces.
            // At accessibility5 the full paywall top is dominated by hero +
            // features; use the plan-state surface so empty/error copy is pinned.
            if variant.capturesPlanState {
                paywall.snapshotPlanStateContent
            } else {
                paywall.snapshotContent
            }
        }
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
