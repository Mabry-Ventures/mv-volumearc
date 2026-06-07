import XCTest
@_spi(Testing) import VolumeArcUI

final class AppearancePreferenceTests: XCTestCase {
    func testUserSelectableCasesExposeSystemLightDarkAndWarm() {
        XCTAssertEqual(VolumeArcAppearancePreference.userSelectableCases, [.system, .light, .dark, .warm])
        XCTAssertTrue(VolumeArcAppearancePreference.allCases.contains(.warm))
    }
}
