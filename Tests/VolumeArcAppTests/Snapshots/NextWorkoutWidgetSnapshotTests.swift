// VOL-139 Phase B pilot: visual-regression coverage for the iOS widget.
//
// The widget-host XCUITest path is still flaky on ephemeral simulators, so
// keep this first gate at the SwiftUI view layer. The test bundle compiles the
// real `Widgets/VolumeArcWidgets.swift` source with its `@main` wrapper
// disabled, then snapshots the actual `NextWorkoutWidgetView`.

#if canImport(SnapshotTesting) && canImport(UIKit) && canImport(WidgetKit)
import SnapshotTesting
import SwiftUI
import UIKit
import VolumeArcCore
import WidgetKit
import XCTest

@MainActor
final class NextWorkoutWidgetSnapshotTests: XCTestCase {
    private enum Metrics {
        static let systemSmall = CGSize(width: 170, height: 170)
        static let systemMedium = CGSize(width: 364, height: 170)
    }

    private let snapshot = WidgetSummarySnapshot(
        nextWorkoutTitle: "Lower Strength",
        readinessScore: "87",
        primaryLiftForecast: "Back Squat 225 x 5",
        nextActionTitle: "Start",
        syncSummary: "Synced 2m ago",
        streakDays: 7,
        coachPrompt: "Push the top set, then hold accessories steady.",
        updatedAt: Date(timeIntervalSinceReferenceDate: 0)
    )

    private var entry: NextWorkoutEntry {
        NextWorkoutEntry(
            date: Date(timeIntervalSinceReferenceDate: 0),
            snapshot: snapshot
        )
    }

    func testSystemSmallLight() {
        assertWidgetSnapshot(
            family: .systemSmall,
            size: Metrics.systemSmall,
            colorScheme: .light
        )
    }

    func testSystemSmallDark() {
        assertWidgetSnapshot(
            family: .systemSmall,
            size: Metrics.systemSmall,
            colorScheme: .dark
        )
    }

    func testSystemMediumLight() {
        assertWidgetSnapshot(
            family: .systemMedium,
            size: Metrics.systemMedium,
            colorScheme: .light
        )
    }

    func testSystemMediumDark() {
        assertWidgetSnapshot(
            family: .systemMedium,
            size: Metrics.systemMedium,
            colorScheme: .dark
        )
    }

    private func assertWidgetSnapshot(
        family: WidgetFamily,
        size: CGSize,
        colorScheme: ColorScheme,
        testName: String = #function,
        line: UInt = #line
    ) {
        let userInterfaceStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let view = NextWorkoutWidgetView(entry: entry, family: family)
            .environment(\.colorScheme, colorScheme)
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: size.width, height: size.height)

        assertVolumeArcSnapshot(
            of: view,
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .fixed(width: size.width, height: size.height),
                traits: UITraitCollection(userInterfaceStyle: userInterfaceStyle)
            ),
            in: self,
            testName: testName,
            line: line
        )
    }
}
#endif
