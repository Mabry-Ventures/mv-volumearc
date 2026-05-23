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
        let toast = VAToast(
            kind: kind,
            title: "Set logged",
            message: "Bench press 185 x 5 captured."
        )
        let view = ZStack {
            VA.Colors.surfaceGrouped
            VAToastView(toast: toast)
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
        return .image(
            precision: 0.99,
            perceptualPrecision: 0.98,
            layout: .fixed(width: size.width, height: size.height),
            traits: UITraitCollection(userInterfaceStyle: style)
        )
    }
}

private extension View {
    func snapshotEnvironment(_ colorScheme: ColorScheme) -> some View {
        environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, Locale(identifier: "en_US"))
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
