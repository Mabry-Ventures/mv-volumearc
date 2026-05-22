// VOL-135 Phase 2 pilot: first real visual regression baseline.
//
// Keep this intentionally small. The goal is to prove that committed
// snapshot PNGs copied into the VolumeArcAppTests bundle compare green in
// Xcode Cloud's split build/test environment before scaling the matrix.

#if canImport(SnapshotTesting) && canImport(UIKit)
import SnapshotTesting
import SwiftUI
import UIKit
import VolumeArcUI
import XCTest

@MainActor
final class VAButtonSnapshotTests: XCTestCase {
    private func primaryButton() -> some View {
        VAButton(
            String(localized: "Start Workout", comment: "Snapshot fixture label for the primary VAButton"),
            style: .primary,
            action: {}
        )
        .padding(VA.Space.lg)
        .frame(width: VA.Space.onboardingMaxWidth)
    }

    func testVAButtonPrimaryLight() {
        assertVolumeArcSnapshot(
            of: primaryButton(),
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .sizeThatFits,
                traits: UITraitCollection(userInterfaceStyle: .light)
            ),
            in: self
        )
    }

    func testVAButtonPrimaryDark() {
        assertVolumeArcSnapshot(
            of: primaryButton(),
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .sizeThatFits,
                traits: UITraitCollection(userInterfaceStyle: .dark)
            ),
            in: self
        )
    }
}
#endif
