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

        // Resolve through `illustrationAssetName` so the alias map (paused
        // variants → parent illustration) is honored. We extract the
        // imageset id from the asset path and check it ships on disk.
        var missing: [(exerciseID: String, resolvedAssetID: String)] = []
        for exercise in catalog {
            let resolvedAssetID = exercise.illustrationAssetName
                .replacingOccurrences(of: "\(Self.expectedNamespace)/", with: "")
            if !shippedIDs.contains(resolvedAssetID) {
                missing.append((exercise.id, resolvedAssetID))
            }
        }

        XCTAssertTrue(
            missing.isEmpty,
            "Catalog entries whose illustrationAssetName does not resolve to a shipped imageset: " +
            missing
                .sorted { $0.exerciseID < $1.exerciseID }
                .map { "\($0.exerciseID) → \($0.resolvedAssetID)" }
                .joined(separator: ", ")
        )

        // Catch orphaned imagesets — illustrations that aren't reachable
        // from any catalog entry's `illustrationAssetName`. These aren't
        // dangerous (just bloat) but the regression is worth surfacing.
        // We compute "reachable" through the resolved asset name so
        // aliased illustrations (e.g., `back-squat` referenced by both
        // `back-squat` and `paused-back-squat`) are correctly counted as
        // referenced.
        let reachableAssetIDs = Set(
            catalog.map {
                $0.illustrationAssetName
                    .replacingOccurrences(of: "\(Self.expectedNamespace)/", with: "")
            }
        )
        let orphaned = shippedIDs.subtracting(reachableAssetIDs).sorted()
        XCTAssertTrue(
            orphaned.isEmpty,
            "Illustration imagesets unreachable from any catalog entry: \(orphaned.joined(separator: ", "))"
        )
    }

    func testIllustrationAssetNameIsWellFormed() {
        // Every asset name must be `ExerciseIllustrations/<id>` where
        // <id> is either the exercise's own id or an explicit alias to
        // another catalog entry's id. This catches typos in the alias
        // map and any future drift between the namespace contract and
        // the runtime path.
        let allCatalogIDs = Set(VolumeArcExerciseCatalog.all.map(\.id))
        for exercise in VolumeArcExerciseCatalog.all {
            let assetName = exercise.illustrationAssetName
            XCTAssertTrue(
                assetName.hasPrefix("\(Self.expectedNamespace)/"),
                "Illustration asset name missing namespace prefix for \(exercise.id): \(assetName)"
            )

            let resolvedID = assetName
                .replacingOccurrences(of: "\(Self.expectedNamespace)/", with: "")
            let isSelfReference = resolvedID == exercise.id
            let isAliasToKnownEntry = allCatalogIDs.contains(resolvedID)
            XCTAssertTrue(
                isSelfReference || isAliasToKnownEntry,
                "Illustration alias for \(exercise.id) → \(resolvedID) is neither self-reference nor a known catalog entry"
            )
        }
    }

    func testPausedVariantsShareParentIllustration() {
        // VOL-105 sibling-collision fix contract: pure tempo/pause
        // variants share their parent lift's illustration. Pin the
        // current alias map so a future PR can't silently drop or
        // misroute the alias.
        let expected: [String: String] = [
            "paused-back-squat": "back-squat",
            "paused-bench-press": "bench-press",
            "paused-deadlift": "deadlift",
        ]
        for (variantID, parentID) in expected {
            guard let variant = VolumeArcExerciseCatalog.all.first(where: { $0.id == variantID }) else {
                XCTFail("Catalog missing expected variant \(variantID)")
                continue
            }
            XCTAssertEqual(
                variant.illustrationAssetName,
                "\(Self.expectedNamespace)/\(parentID)",
                "Paused variant \(variantID) should share illustration with parent \(parentID)"
            )
        }
    }
}
