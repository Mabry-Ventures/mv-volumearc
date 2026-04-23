#if canImport(SwiftUI) && canImport(VolumeArcUI)
import XCTest
import SwiftUI
import VolumeArcUI

/// Compile-guard tests for the iOS 26 Liquid Glass design tokens.
///
/// These tests don't render anything — they pin down the public API surface
/// for `VA.Materials` so a future refactor can't quietly drop the tokens or
/// change their types without a test failure. Rendering correctness is
/// verified by the XCUITest launch-state smoke suite, not here.
@available(iOS 26.0, *)
@MainActor
final class VolumeArcMaterialsTests: XCTestCase {
    func testGlassTokenIsAvailable() {
        let glass: Glass = VA.Materials.glass
        XCTAssertEqual(glass, Glass.regular)
    }

    func testInteractiveGlassTokenIsAvailable() {
        let interactive: Glass = VA.Materials.glassInteractive
        // We can't compare `interactive` to `Glass.regular` for inequality
        // because `Glass` only conforms to `Equatable` and the underlying
        // representation is opaque — assert it's a valid value by round
        // tripping it through another modifier.
        XCTAssertEqual(interactive, Glass.regular.interactive())
    }

    func testTintedGlassTokenIsAvailable() {
        let tinted: Glass = VA.Materials.tintedGlass(.red)
        XCTAssertEqual(tinted, Glass.regular.tint(.red))
    }

    func testTintedGlassAcceptsNilTint() {
        let cleared: Glass = VA.Materials.tintedGlass(nil)
        XCTAssertEqual(cleared, Glass.regular.tint(nil))
    }

    func testGlassBackgroundModifierCompiles() {
        // Compile-guard: assert the public view modifiers exist with the
        // expected shape signatures. We don't need to render the result —
        // just that the call compiles against the live module.
        _ = Color.clear.vaGlassBackground()
        _ = Color.clear.vaGlassBackground(in: Circle())
        _ = Color.clear.vaInteractiveGlassBackground()
        _ = Color.clear.vaInteractiveGlassBackground(in: Capsule())
        _ = Color.clear.vaTintedGlassBackground(.blue)
        _ = Color.clear.vaTintedGlassBackground(nil, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
