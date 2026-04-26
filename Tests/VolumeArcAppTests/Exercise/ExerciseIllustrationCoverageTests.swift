import XCTest
@testable import VolumeArcCore

/// VOL-105 Phase 2: pin the contract that every catalog entry has a
/// matching `.imageset` shipped under
/// `App/Assets.xcassets/ExerciseIllustrations/`.
///
/// We resolve the asset directory by walking up from the compiled test
/// bundle's source-file URL (via `#filePath`) — that gives us the
/// repo-relative path even when the test runs in the simulator. We don't
/// rely on `UIImage(named:)` because the unit-test bundle does not pull
/// in the host app's compiled `Assets.car` at runtime; what we actually
/// want to gate on is "did Phase 2 ship an illustration for every catalog
/// entry the source tree ships," which is a static-text question.
final class ExerciseIllustrationCoverageTests: XCTestCase {

    private static let expectedNamespace = "ExerciseIllustrations"

    /// Resolve the on-disk asset directory by walking up from this test
    /// file's path until we hit the repo root, then descending into
    /// `App/Assets.xcassets/ExerciseIllustrations/`. This works in both
    /// the simulator runner and a local `swift test` invocation.
    private static func assetDirectoryURL(filePath: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: filePath, isDirectory: false)
        // Walk up to repo root: this file lives at
        // Tests/VolumeArcAppTests/Exercise/ExerciseIllustrationCoverageTests.swift
        // — four levels up gets us to the repo root.
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        return url
            .appendingPathComponent("App", isDirectory: true)
            .appendingPathComponent("Assets.xcassets", isDirectory: true)
            .appendingPathComponent("ExerciseIllustrations", isDirectory: true)
    }

    func testEveryCatalogEntryHasAnIllustration() throws {
        let catalog = VolumeArcExerciseCatalog.all
        XCTAssertGreaterThanOrEqual(
            catalog.count,
            120,
            "Phase 1 floor regressed — catalog should still contain >= 120 entries"
        )

        let assetDir = Self.assetDirectoryURL()
        guard FileManager.default.fileExists(atPath: assetDir.path) else {
            throw XCTSkip(
                "Asset directory not present at \(assetDir.path). Test runs against the source tree; if the runner can't see it, skip."
            )
        }

        let imagesets = try FileManager.default
            .contentsOfDirectory(at: assetDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "imageset" }
            .map { $0.deletingPathExtension().lastPathComponent }
        let shippedIDs = Set(imagesets)

        var missing: [String] = []
        for exercise in catalog where !shippedIDs.contains(exercise.id) {
            missing.append(exercise.id)
        }

        XCTAssertTrue(
            missing.isEmpty,
            "Catalog entries missing an illustration imageset: \(missing.sorted().joined(separator: ", "))"
        )

        // Catch the reverse direction too — illustrations for entries that
        // were removed from the catalog. They aren't dangerous (just bloat)
        // but the regression is worth surfacing.
        let catalogIDs = Set(catalog.map(\.id))
        let orphaned = shippedIDs.subtracting(catalogIDs).sorted()
        XCTAssertTrue(
            orphaned.isEmpty,
            "Illustration imagesets without a matching catalog entry: \(orphaned.joined(separator: ", "))"
        )
    }

    func testIllustrationAssetNameMatchesId() {
        // Cheap sanity — illustrationAssetName must always be
        // `ExerciseIllustrations/<id>` so the Phase 2 wrap-imagesets script
        // and the catalog stay in lockstep regardless of any future ID
        // renames.
        for exercise in VolumeArcExerciseCatalog.all {
            XCTAssertEqual(
                exercise.illustrationAssetName,
                "\(Self.expectedNamespace)/\(exercise.id)",
                "Illustration asset name diverged from id for \(exercise.id)"
            )
        }
    }
}
