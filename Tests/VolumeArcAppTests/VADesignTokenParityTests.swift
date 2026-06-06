#if canImport(UIKit)
import SwiftUI
import UIKit
import VolumeArcUI
import XCTest

@MainActor
final class VADesignTokenParityTests: XCTestCase {
    private enum Traits {
        static let light = UITraitCollection(userInterfaceStyle: .light)
        static let dark = UITraitCollection(userInterfaceStyle: .dark)
    }

    func testClaudeWarmPersonalityBrandTokensMatchNativePalette() {
        assertColor(VA.Colors.primary, matches: .hex(0xF2, 0x6A, 0x33), traits: Traits.light)
        assertColor(VA.Colors.primaryDeep, matches: .hex(0xD1, 0x4E, 0x1D), traits: Traits.light)
        assertColor(VA.Colors.sunriseA, matches: .hex(0xFF, 0xB3, 0x7A), traits: Traits.light)
        assertColor(VA.Colors.sunriseB, matches: .hex(0xF2, 0x6A, 0x33), traits: Traits.light)
        assertColor(VA.Colors.sunriseC, matches: .hex(0xC8, 0x4A, 0x6E), traits: Traits.light)

        assertColor(VA.Colors.primary, matches: .hex(0xE6, 0x8A, 0x52), traits: Traits.dark)
        assertColor(VA.Colors.primaryDeep, matches: .hex(0xC4, 0x68, 0x38), traits: Traits.dark)
        assertColor(VA.Colors.sunriseA, matches: .hex(0xFF, 0xA9, 0x70), traits: Traits.dark)
        assertColor(VA.Colors.sunriseB, matches: .hex(0xE6, 0x6B, 0x3A), traits: Traits.dark)
        assertColor(VA.Colors.sunriseC, matches: .hex(0xB2, 0x3E, 0x66), traits: Traits.dark)
    }

    private func assertColor(
        _ color: Color,
        matches expected: ExpectedColor,
        traits: UITraitCollection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let resolved = UIColor(color).resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        XCTAssertTrue(
            resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            "Expected an RGB color for \(resolved)",
            file: file,
            line: line
        )
        XCTAssertEqual(red, expected.red, accuracy: 0.006, file: file, line: line)
        XCTAssertEqual(green, expected.green, accuracy: 0.006, file: file, line: line)
        XCTAssertEqual(blue, expected.blue, accuracy: 0.006, file: file, line: line)
        XCTAssertEqual(alpha, 1, accuracy: 0.001, file: file, line: line)
    }
}

private struct ExpectedColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    static func hex(_ red: Int, _ green: Int, _ blue: Int) -> ExpectedColor {
        ExpectedColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255
        )
    }
}
#endif
