import XCTest
@_spi(Testing) import VolumeArcUI

final class AppearancePreferenceTests: XCTestCase {
    func testUserSelectableCasesExcludeWarmBrandPersonality() {
        XCTAssertEqual(VolumeArcAppearancePreference.userSelectableCases, [.system, .light, .dark])
        XCTAssertTrue(VolumeArcAppearancePreference.allCases.contains(.warm))
    }
}
