import Foundation
import XCTest

final class AppIconAssetContractTests: XCTestCase {
    private struct PNGSize: Equatable {
        let width: UInt32
        let height: UInt32
    }

    private struct PNGMetadata: Equatable {
        let width: UInt32
        let height: UInt32
        let bitDepth: UInt8
        let colorType: UInt8

        var size: PNGSize {
            PNGSize(width: width, height: height)
        }
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

        XCTAssertEqual(
            images.count,
            3,
            "AppIcon should ship light, dark, and tinted universal marketing icons"
        )

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
                try pngMetadata(at: imageURL).size,
                PNGSize(width: 1024, height: 1024),
                "\(filename) should be an App Store-ready 1024x1024 PNG"
            )
        }
    }

    func testAppIconCatalogShipsTintedVariant() throws {
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

        let tinted = try image(named: "AppIcon-Tinted.png", in: images)
        XCTAssertEqual(tinted["idiom"] as? String, "universal")
        XCTAssertEqual(tinted["platform"] as? String, "ios")
        XCTAssertEqual(tinted["size"] as? String, "1024x1024")
        XCTAssertEqual(
            tinted["appearances"] as? [[String: String]],
            [["appearance": "luminosity", "value": "tinted"]],
            "The tinted app icon should be wired through iOS tinted-luminosity metadata"
        )

        let imageURL = appIconURL.appendingPathComponent("AppIcon-Tinted.png")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: imageURL.path),
            "AppIcon-Tinted.png should exist in AppIcon.appiconset"
        )

        let metadata = try pngMetadata(at: imageURL)
        XCTAssertEqual(metadata.size, PNGSize(width: 1024, height: 1024))
        XCTAssertEqual(metadata.bitDepth, 8, "Tinted app icon should be 8-bit PNG")
        XCTAssertEqual(metadata.colorType, 4, "Tinted app icon should be grayscale with alpha")
    }

    private static func appIconSetURL(filePath: String = #filePath) throws -> URL {
        // Prefer the copy bundled into the test bundle. `generate_xcode_project.rb`
        // wires `App/Assets.xcassets/AppIcon.appiconset` in as a folder
        // reference, so the real Contents.json + PNGs are present in the
        // bundle on every host. This is the only path that works on Xcode
        // Cloud, where unit tests run in the simulator sandbox and cannot
        // read the host source tree (`/Volumes/workspace/repository`) via
        // `#filePath`.
        if let bundled = Bundle(for: AppIconAssetContractTests.self)
            .url(forResource: "AppIcon", withExtension: "appiconset") {
            return bundled
        }

        // Fallback: walk up from this source file to the catalog. Kept for
        // any environment where the resource isn't bundled but the source
        // tree is reachable (e.g. `swift test` outside the Xcode project).
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

    private func pngMetadata(at url: URL) throws -> PNGMetadata {
        let data = try Data(contentsOf: url)
        let pngSignature = [UInt8](data.prefix(8))
        XCTAssertEqual(pngSignature, [137, 80, 78, 71, 13, 10, 26, 10], "\(url.lastPathComponent) should be a PNG")
        XCTAssertGreaterThanOrEqual(data.count, 26, "\(url.lastPathComponent) should include a complete PNG IHDR chunk")

        return PNGMetadata(
            width: data.uint32BigEndian(at: 16),
            height: data.uint32BigEndian(at: 20),
            bitDepth: data[24],
            colorType: data[25]
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
