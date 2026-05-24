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
        static let systemLarge = CGSize(width: 364, height: 382)
        static let accessoryCircular = CGSize(width: 72, height: 72)
        static let accessoryRectangular = CGSize(width: 160, height: 72)
        static let accessoryInline = CGSize(width: 260, height: 32)
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

    func testSystemLargeLight() {
        assertWidgetSnapshot(
            family: .systemLarge,
            size: Metrics.systemLarge,
            colorScheme: .light
        )
    }

    func testSystemLargeDark() {
        assertWidgetSnapshot(
            family: .systemLarge,
            size: Metrics.systemLarge,
            colorScheme: .dark
        )
    }

    func testAccessoryCircularLight() {
        assertWidgetSnapshot(
            family: .accessoryCircular,
            size: Metrics.accessoryCircular,
            colorScheme: .light
        )
    }

    func testAccessoryCircularDark() {
        assertWidgetSnapshot(
            family: .accessoryCircular,
            size: Metrics.accessoryCircular,
            colorScheme: .dark
        )
    }

    func testAccessoryRectangularLight() throws {
        try skipAccessoryRectangularInXcodeCloud()

        assertWidgetSnapshot(
            family: .accessoryRectangular,
            size: Metrics.accessoryRectangular,
            colorScheme: .light
        )
    }

    func testAccessoryRectangularDark() throws {
        try skipAccessoryRectangularInXcodeCloud()

        assertWidgetSnapshot(
            family: .accessoryRectangular,
            size: Metrics.accessoryRectangular,
            colorScheme: .dark
        )
    }

    func testAccessoryInlineLight() {
        assertWidgetSnapshot(
            family: .accessoryInline,
            size: Metrics.accessoryInline,
            colorScheme: .light
        )
    }

    func testAccessoryInlineDark() {
        assertWidgetSnapshot(
            family: .accessoryInline,
            size: Metrics.accessoryInline,
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

    private func skipAccessoryRectangularInXcodeCloud() throws {
        try XCTSkipIf(Self.isRunningInXcodeCloudTestProducts, """
        VOL-139: accessory rectangular widget snapshots are enforced locally \
        and on the self-hosted runner. Xcode Cloud renders this WidgetKit \
        family differently from its bundled reference PNGs.
        """)
    }

    nonisolated private static var isRunningInXcodeCloudTestProducts: Bool {
        Bundle(for: NextWorkoutWidgetSnapshotTests.self).bundleURL.path.contains("TestProducts.xctestproducts")
    }
}
#endif
