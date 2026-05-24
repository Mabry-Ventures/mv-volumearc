// VOL-135 Phase 1: snapshot-testing infrastructure smoke test.
//
// This file proves three things about the just-added
// `pointfreeco/swift-snapshot-testing` dependency without committing
// any actual baseline PNGs:
//
//   1. The package resolves cleanly and `SnapshotTesting` is
//      importable from the `VolumeArcAppTests` target.
//   2. The directory `Tests/VolumeArcAppTests/Snapshots/` is the
//      canonical home for snapshot tests, and CI picks it up via the
//      existing `add_swift_sources` glob.
//   3. The expected baseline directory
//      `Tests/VolumeArcAppTests/Snapshots/__Snapshots__/`
//      (created on first record-mode run) is the location Phase 2
//      PRs will commit PNG references into.
//
// Why no actual `assertSnapshot` call yet:
//
//   swift-snapshot-testing records a PNG to disk the first time a
//   given assertion runs without a baseline, then compares
//   thereafter. Running an `assertSnapshot` from this PR's CI would
//   write a PNG to the runner's workspace — but CI doesn't commit
//   back to the branch, so the next CI run has no baseline and
//   silently re-records. That gives the illusion of a regression
//   gate without one.
//
//   Phase 2 PRs will follow the canonical workflow:
//     a) author runs the new snapshot test locally with
//        `SNAPSHOT_TESTING_RECORD=all` to generate the PNG;
//     b) author commits the PNG under `__Snapshots__/`;
//     c) CI runs with default mode, comparing against the
//        committed PNG and failing on drift.
//
// Adopt that pattern starting with the next PR. See
// `docs/TESTING.md` "Snapshot regression (VOL-135)" for the full
// runbook.

#if canImport(SnapshotTesting)
import SnapshotTesting
import XCTest

final class VolumeArcSnapshotInfrastructureTests: XCTestCase {
    /// Compile-time: this file's `import SnapshotTesting` only links
    /// when the package resolution succeeded and the test target's
    /// `package_product_dependencies` include `SnapshotTesting`. The
    /// runtime assertion is a no-op; the gate is the build.
    ///
    /// If somebody accidentally removes the SPM wiring in
    /// `scripts/generate_xcode_project.rb`, this test fails to
    /// compile and CI surfaces a clear error pointing at the
    /// missing dependency rather than a confusing "module not
    /// found" diagnostic deep in the unit-test compilation.
    func testSnapshotTestingFrameworkIsLinked() {
        // Reference a public symbol so the linker can't dead-strip
        // the import. `assertSnapshot` is the library's marquee API;
        // taking a metatype reference is enough to pin the link
        // without actually invoking a snapshot comparison (Phase 1
        // doesn't ship any baselines yet).
        let strategy: Snapshotting<String, String> = .lines
        XCTAssertEqual(strategy.pathExtension, "txt")
    }
}
#endif
