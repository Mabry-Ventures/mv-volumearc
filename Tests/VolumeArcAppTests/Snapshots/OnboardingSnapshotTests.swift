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

    private enum Variant: Equatable {
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

        func snapshotName(
            colorScheme: ColorScheme,
            reduceTransparency: Bool
        ) -> String {
            let theme = colorScheme == .dark ? "dark" : "light"
            let type = self == .accessibility ? "Accessibility" : ""
            let transparency = reduceTransparency ? "" : "ReduceTransparencyOff"
            return "\(theme)\(type)\(transparency)"
        }
    }

    private enum SnapshotStep {
        case profile
        case preferences
        case coachingStyle
        case permissions
        case done

        var onboardingStep: OnboardingSnapshotStep {
            switch self {
            case .profile:
                return .profile
            case .preferences:
                return .preferences
            case .coachingStyle:
                return .coachingStyle
            case .permissions:
                return .permissions
            case .done:
                return .done
            }
        }

        var result: OnboardingResult {
            switch self {
            case .profile:
                return OnboardingResult(
                    name: "Maya",
                    advancementLevel: .advanced,
                    weeklyDays: 4,
                    sessionMinutes: 60,
                    coachingStyle: .motivational
                )
            case .preferences:
                return OnboardingResult(
                    name: "Maya",
                    advancementLevel: .intermediate,
                    weeklyDays: 5,
                    sessionMinutes: 75,
                    coachingStyle: .motivational
                )
            case .coachingStyle:
                return OnboardingResult(
                    name: "Maya",
                    advancementLevel: .intermediate,
                    weeklyDays: 4,
                    sessionMinutes: 60,
                    coachingStyle: .minimal,
                    privacyMode: .strict
                )
            case .permissions:
                return OnboardingResult(name: "Maya")
            case .done:
                return OnboardingResult(name: "Maya")
            }
        }

        var healthAuthorizationHandler: (() async -> Bool)? {
            switch self {
            case .permissions:
                return { true }
            case .profile, .preferences, .coachingStyle, .done:
                return nil
            }
        }

        var appleAccountHandler: ((OnboardingAppleAccount) async -> Void)? {
            switch self {
            case .profile:
                return { _ in }
            case .preferences, .coachingStyle, .permissions, .done:
                return nil
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

    func testProfileStepSnapshots() {
        assertOnboardingStepSnapshots(.profile)
    }

    func testPreferencesStepSnapshots() {
        assertOnboardingStepSnapshots(.preferences)
    }

    func testCoachingStyleStepSnapshots() {
        assertOnboardingStepSnapshots(.coachingStyle)
    }

    func testPermissionsStepSnapshots() {
        assertOnboardingStepSnapshots(.permissions)
    }

    func testDoneStepSnapshots() {
        assertOnboardingStepSnapshots(.done)
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

    private func assertOnboardingStepSnapshots(
        _ step: SnapshotStep,
        testName: String = #function,
        line: UInt = #line
    ) {
        for colorScheme in [ColorScheme.light, .dark] {
            for variant in [Variant.regular, .accessibility] {
                for reduceTransparency in [true, false] {
                    assertOnboardingStepSnapshot(
                        step,
                        colorScheme: colorScheme,
                        variant: variant,
                        reduceTransparency: reduceTransparency,
                        testName: testName,
                        line: line
                    )
                }
            }
        }
    }

    private func assertOnboardingStepSnapshot(
        _ step: SnapshotStep,
        colorScheme: ColorScheme,
        variant: Variant,
        reduceTransparency: Bool,
        testName: String,
        line: UInt
    ) {
        let view = OnboardingView(
            isPresented: .constant(true),
            onComplete: { _ in },
            onRequestHealthAuthorization: step.healthAuthorizationHandler,
            onConnectAppleAccount: step.appleAccountHandler,
            snapshotStep: step.onboardingStep,
            snapshotResult: step.result
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
            named: variant.snapshotName(
                colorScheme: colorScheme,
                reduceTransparency: reduceTransparency
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
