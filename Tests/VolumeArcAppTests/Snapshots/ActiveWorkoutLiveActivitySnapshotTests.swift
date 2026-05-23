// VOL-241: visual-regression coverage for the Apple Watch supplemental
// Live Activity surface. The view is pure SwiftUI and driven by the same
// snapshot the ActivityKit widget receives at runtime.

#if canImport(ActivityKit) && canImport(SnapshotTesting) && canImport(UIKit) && canImport(WidgetKit)
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

    private func assertWatchLiveActivitySnapshot(
        _ snapshot: ActiveWorkoutLiveActivitySnapshot,
        colorScheme: ColorScheme,
        testName: String = #function,
        line: UInt = #line
    ) {
        let userInterfaceStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let view = ActiveWorkoutLiveActivityContentView(
            snapshot: snapshot,
            activityFamily: .small
        )
        .environment(\.colorScheme, colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .frame(width: Metrics.watchSmall.width, height: Metrics.watchSmall.height)

        assertVolumeArcSnapshot(
            of: view,
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .fixed(width: Metrics.watchSmall.width, height: Metrics.watchSmall.height),
                traits: UITraitCollection(userInterfaceStyle: userInterfaceStyle)
            ),
            in: self,
            testName: testName,
            line: line
        )
    }
}
#endif
