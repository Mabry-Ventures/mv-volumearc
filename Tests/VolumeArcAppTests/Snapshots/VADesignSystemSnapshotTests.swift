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
        let view = card(style: style)
            .environment(\.colorScheme, colorScheme)
            .frame(width: Metrics.width)
            .padding(VA.Space.lg)
            .background(VA.Colors.surfaceGrouped)

        assertVolumeArcSnapshot(
            of: view,
            as: imageSnapshot(colorScheme: colorScheme),
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
        let toast = VAToast(
            kind: kind,
            title: "Set logged",
            message: "Bench press 185 x 5 captured."
        )
        let view = VAToastView(toast: toast)
            .environment(\.colorScheme, colorScheme)
            .frame(width: Metrics.width)
            .padding(.vertical, VA.Space.lg)
            .background(VA.Colors.surfaceGrouped)

        assertVolumeArcSnapshot(
            of: view,
            as: imageSnapshot(colorScheme: colorScheme),
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
        colorScheme: ColorScheme
    ) -> Snapshotting<Value, UIImage> {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return .image(
            precision: 0.99,
            perceptualPrecision: 0.98,
            layout: .sizeThatFits,
            traits: UITraitCollection(userInterfaceStyle: style)
        )
    }
}

private struct SnapshotCardContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            HStack(spacing: VA.Space.sm) {
                Image(systemName: "bolt.heart.fill")
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.primary)
                Text("Readiness")
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textPrimary)
                Spacer()
                Text("87")
                    .font(VA.Typography.title2)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .monospacedDigit()
            }
            Text("Strong recovery trend. Hold the top set and push accessory volume.")
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
