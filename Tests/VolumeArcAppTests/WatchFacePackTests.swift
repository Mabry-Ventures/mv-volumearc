import XCTest
@testable import VolumeArcCore

final class WatchFacePackTests: XCTestCase {
    func testPresetManifestMatchesDesignedPack() {
        XCTAssertEqual(WatchFacePreset.allCases.map(\.displayName), [
            "VolumeArc Modular",
            "VolumeArc Infograph",
            "VolumeArc Photo",
        ])

        XCTAssertEqual(WatchFacePreset.modular.family, "Modular Duo")
        XCTAssertEqual(WatchFacePreset.infograph.family, "Infograph")
        XCTAssertEqual(WatchFacePreset.photo.family, "Photos")
    }

    func testResourceNamesAreStableForBundledWatchFaceExports() {
        XCTAssertEqual(WatchFacePreset.modular.resourceName, "VolumeArc-Modular")
        XCTAssertEqual(WatchFacePreset.infograph.resourceName, "VolumeArc-Infograph")
        XCTAssertEqual(WatchFacePreset.photo.resourceName, "VolumeArc-Photo")
    }

    func testBundleDiscoveryReturnsNoPresetsUntilWatchFaceExportsArePresent() {
        XCTAssertEqual(WatchFacePack.bundledPresets(in: .init(for: Self.self)), [])
    }

    func testComplicationSlotManifestCoversAcceptanceCriteria() {
        XCTAssertEqual(WatchFacePreset.modular.complicationSlots.map(\.label), [
            "Readiness",
            "Next Workout",
            "Last Session",
            "Streak",
        ])
        XCTAssertTrue(WatchFacePreset.infograph.complicationSlots.contains { $0.label == "Next" })
        XCTAssertEqual(WatchFacePreset.photo.complicationSlots.map(\.label), [
            "Readiness",
            "Streak",
        ])
    }
}
