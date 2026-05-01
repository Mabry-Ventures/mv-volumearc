import Foundation
import XCTest

final class AppIconAssetContractTests: XCTestCase {
    private struct PNGSize: Equatable {
        let width: UInt32
        let height: UInt32
    }

    func testAppIconCatalogShipsLightAndDarkStoreReadyIcons() throws {
        let appIconURL = try Self.appIconSetURL()
        let contentsURL = appIconURL.appendingPathComponent("Contents.json")
        let contentsData = try Data(contentsOf: contentsURL)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: contentsData) as? [String: Any],
            "AppIcon Contents.json should be a dictionary"
        )
        let images = try XCTUnwrap(
            root["images"] as? [[String: Any]],
            "AppIcon Contents.json should declare icon images"
        )

        XCTAssertEqual(images.count, 2, "AppIcon should ship exactly one light and one dark universal marketing icon")

        let light = try image(named: "AppIcon-Light.png", in: images)
        XCTAssertEqual(light["idiom"] as? String, "universal")
        XCTAssertEqual(light["platform"] as? String, "ios")
        XCTAssertEqual(light["size"] as? String, "1024x1024")
        XCTAssertNil(light["appearances"], "The light app icon should be the default variant")

        let dark = try image(named: "AppIcon-Dark.png", in: images)
        XCTAssertEqual(dark["idiom"] as? String, "universal")
        XCTAssertEqual(dark["platform"] as? String, "ios")
        XCTAssertEqual(dark["size"] as? String, "1024x1024")
        XCTAssertEqual(
            dark["appearances"] as? [[String: String]],
            [["appearance": "luminosity", "value": "dark"]],
            "The dark app icon should be wired through iOS luminosity metadata"
        )

        for filename in ["AppIcon-Light.png", "AppIcon-Dark.png"] {
            let imageURL = appIconURL.appendingPathComponent(filename)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: imageURL.path),
                "\(filename) should exist in AppIcon.appiconset"
            )
            XCTAssertEqual(
                try pngSize(at: imageURL),
                PNGSize(width: 1024, height: 1024),
                "\(filename) should be an App Store-ready 1024x1024 PNG"
            )
        }
    }

    private static func appIconSetURL(filePath: String = #filePath) throws -> URL {
        var cursor = URL(fileURLWithPath: filePath, isDirectory: false)
        while cursor.path != "/" {
            cursor.deleteLastPathComponent()
            let candidate = cursor
                .appendingPathComponent("App", isDirectory: true)
                .appendingPathComponent("Assets.xcassets", isDirectory: true)
                .appendingPathComponent("AppIcon.appiconset", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw AppIconAssetContractError.missingAppIconSet(filePath)
    }

    private func image(named filename: String, in images: [[String: Any]]) throws -> [String: Any] {
        try XCTUnwrap(
            images.first { $0["filename"] as? String == filename },
            "AppIcon Contents.json should reference \(filename)"
        )
    }

    private func pngSize(at url: URL) throws -> PNGSize {
        let data = try Data(contentsOf: url)
        let pngSignature = [UInt8](data.prefix(8))
        XCTAssertEqual(pngSignature, [137, 80, 78, 71, 13, 10, 26, 10], "\(url.lastPathComponent) should be a PNG")
        XCTAssertGreaterThanOrEqual(data.count, 24, "\(url.lastPathComponent) should include a PNG IHDR chunk")

        return PNGSize(
            width: data.uint32BigEndian(at: 16),
            height: data.uint32BigEndian(at: 20)
        )
    }
}

private enum AppIconAssetContractError: LocalizedError {
    case missingAppIconSet(String)

    var errorDescription: String? {
        switch self {
        case let .missingAppIconSet(filePath):
            "AppIcon.appiconset was not found from \(filePath)"
        }
    }
}

private extension Data {
    func uint32BigEndian(at offset: Int) -> UInt32 {
        self[offset..<offset + 4].reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}
