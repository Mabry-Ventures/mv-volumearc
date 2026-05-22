// VOL-135 Phase 2 (pilot): the first real snapshot regression test.
//
// Scope is deliberately ONE component (`VAButton`) in light + dark only.
// This is a pilot to validate that baselines recorded locally (Xcode 26.5 /
// iOS 26.5 sim, 23F77) compare GREEN against the CI runner before we invest
// in the full component + screen matrix. If CI mismatches on this single
// component, we tune precision here (or escalate) rather than discovering the
// problem across ~30 committed baselines.
//
// Recording (one-time, by the author):
//   xcodebuild test \
//     -project VolumeArcApple.xcodeproj -scheme VolumeArcApp \
//     -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17' \
//     -only-testing:VolumeArcAppTests/VAButtonSnapshotTests \
//     SNAPSHOT_TESTING_RECORD=all
// then commit the PNGs under
//   Tests/VolumeArcAppTests/Snapshots/__Snapshots__/VAButtonSnapshotTests/
// CI runs the same test in compare mode and fails on drift.
//
// `perceptualPrecision: 0.98` tolerates the sub-pixel antialiasing / GPU
// differences that otherwise make snapshot tests flaky across machines while
// still catching real layout / color regressions. See docs/TESTING.md.

#if canImport(SnapshotTesting) && canImport(UIKit)
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
import VolumeArcUI

final class VAButtonSnapshotTests: XCTestCase {

    private func primaryButton() -> some View {
        VAButton("Start Workout", style: .primary, action: {})
            .padding()
            .frame(width: 320)
    }

    func testVAButtonPrimaryLight() {
        assertSnapshot(
            of: primaryButton(),
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .sizeThatFits,
                traits: UITraitCollection(userInterfaceStyle: .light)
            )
        )
    }

    func testVAButtonPrimaryDark() {
        assertSnapshot(
            of: primaryButton(),
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .sizeThatFits,
                traits: UITraitCollection(userInterfaceStyle: .dark)
            )
        )
    }
}
#endif
