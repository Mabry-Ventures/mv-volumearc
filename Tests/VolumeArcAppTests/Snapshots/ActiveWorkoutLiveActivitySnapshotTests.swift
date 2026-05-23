// VOL-241: visual-regression coverage for the Apple Watch supplemental
// Live Activity surface. The view is pure SwiftUI and driven by the same
// snapshot the ActivityKit widget receives at runtime.

import ActivityKit
import SnapshotTesting
import SwiftUI
import UIKit
import VolumeArcCore
import WidgetKit
import XCTest

@MainActor
final class ActiveWorkoutLiveActivitySnapshotTests: XCTestCase {
    private enum Metrics {
        static let watchSmall = CGSize(width: 170, height: 80)
        static let lockScreenRegular = CGSize(width: 393, height: 150)
        static let lockScreenAccessibility = CGSize(width: 393, height: 214)
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

        var lockScreenSize: CGSize {
            switch self {
            case .regular:
                return Metrics.lockScreenRegular
            case .accessibility:
                return Metrics.lockScreenAccessibility
            }
        }
    }

    private let countdownSnapshot = ActiveWorkoutLiveActivitySnapshot(
        workoutTitle: "Lower Strength",
        activeExerciseName: "Back Squat",
        targetSummary: "225lb x 5",
        setProgressSummary: "Set 3/5 · 225 lb",
        restSecondsRemaining: 42
    )

    private let restCompleteSnapshot = ActiveWorkoutLiveActivitySnapshot(
        workoutTitle: "Lower Strength",
        activeExerciseName: "Back Squat",
        targetSummary: "225lb x 5",
        setProgressSummary: "Set 4/5 · 225 lb",
        restSecondsRemaining: nil
    )

    func testWatchSmallLight() {
        assertWatchLiveActivitySnapshot(countdownSnapshot, colorScheme: .light)
    }

    func testWatchSmallDark() {
        assertWatchLiveActivitySnapshot(countdownSnapshot, colorScheme: .dark)
    }

    func testWatchSmallRestCompleteLight() {
        assertWatchLiveActivitySnapshot(restCompleteSnapshot, colorScheme: .light)
    }

    func testWatchSmallRestCompleteDark() {
        assertWatchLiveActivitySnapshot(restCompleteSnapshot, colorScheme: .dark)
    }

    func testLockScreenCountdownLight() {
        assertLockScreenLiveActivitySnapshot(countdownSnapshot, colorScheme: .light, variant: .regular)
    }

    func testLockScreenCountdownDark() {
        assertLockScreenLiveActivitySnapshot(countdownSnapshot, colorScheme: .dark, variant: .regular)
    }

    func testLockScreenCountdownAccessibilityLight() {
        assertLockScreenLiveActivitySnapshot(countdownSnapshot, colorScheme: .light, variant: .accessibility)
    }

    func testLockScreenCountdownAccessibilityDark() {
        assertLockScreenLiveActivitySnapshot(countdownSnapshot, colorScheme: .dark, variant: .accessibility)
    }

    func testLockScreenRestCompleteLight() {
        assertLockScreenLiveActivitySnapshot(restCompleteSnapshot, colorScheme: .light, variant: .regular)
    }

    func testLockScreenRestCompleteDark() {
        assertLockScreenLiveActivitySnapshot(restCompleteSnapshot, colorScheme: .dark, variant: .regular)
    }

    func testLockScreenRestCompleteAccessibilityLight() {
        assertLockScreenLiveActivitySnapshot(restCompleteSnapshot, colorScheme: .light, variant: .accessibility)
    }

    func testLockScreenRestCompleteAccessibilityDark() {
        assertLockScreenLiveActivitySnapshot(restCompleteSnapshot, colorScheme: .dark, variant: .accessibility)
    }

    private func assertWatchLiveActivitySnapshot(
        _ snapshot: ActiveWorkoutLiveActivitySnapshot,
        colorScheme: ColorScheme,
        testName: String = #function,
        line: UInt = #line
    ) {
        let view = ActiveWorkoutLiveActivityContentView(
            snapshot: snapshot,
            activityFamily: .small
        )
        .snapshotEnvironment(colorScheme: colorScheme, dynamicTypeSize: .medium)
        .frame(width: Metrics.watchSmall.width, height: Metrics.watchSmall.height)

        assertVolumeArcSnapshot(
            of: view,
            as: imageSnapshot(
                colorScheme: colorScheme,
                preferredContentSizeCategory: .medium,
                size: Metrics.watchSmall
            ),
            in: self,
            testName: testName,
            line: line
        )
    }

    private func assertLockScreenLiveActivitySnapshot(
        _ snapshot: ActiveWorkoutLiveActivitySnapshot,
        colorScheme: ColorScheme,
        variant: Variant,
        testName: String = #function,
        line: UInt = #line
    ) {
        let view = ActiveWorkoutLiveActivityContentView(snapshot: snapshot)
            .snapshotEnvironment(colorScheme: colorScheme, dynamicTypeSize: variant.dynamicTypeSize)
            .frame(width: variant.lockScreenSize.width, height: variant.lockScreenSize.height)

        assertVolumeArcSnapshot(
            of: view,
            as: imageSnapshot(
                colorScheme: colorScheme,
                preferredContentSizeCategory: variant.preferredContentSizeCategory,
                size: variant.lockScreenSize
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
