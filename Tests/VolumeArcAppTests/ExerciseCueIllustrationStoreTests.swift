import XCTest
@testable import VolumeArcCore

final class ExerciseCueIllustrationStoreTests: XCTestCase {
    private var rootDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExerciseCueIllustrationStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        rootDirectory = nil
        try super.tearDownWithError()
    }

    func testStorageKeySanitizesExerciseIdentifier() {
        XCTAssertEqual(
            ExerciseCueIllustrationStore.storageKey(for: "Back Squat / Low-Bar"),
            "back-squat-low-bar"
        )
        XCTAssertEqual(ExerciseCueIllustrationStore.storageKey(for: "   "), "exercise")
    }

    func testSaveGeneratedImageCopiesSourceToLatestExerciseSlot() throws {
        let source = rootDirectory.appendingPathComponent("generated.png")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: source)

        let store = try ExerciseCueIllustrationStore(rootDirectory: rootDirectory)
        let saved = try store.saveGeneratedImage(from: source, exerciseID: "Back Squat")

        XCTAssertEqual(saved.lastPathComponent, "latest.png")
        XCTAssertEqual(saved.deletingLastPathComponent().lastPathComponent, "back-squat")
        XCTAssertEqual(try Data(contentsOf: saved), Data("first".utf8))
        XCTAssertEqual(store.latestIllustrationURL(for: "Back Squat")?.lastPathComponent, "latest.png")
    }

    func testSaveGeneratedImageReplacesExistingLatestFile() throws {
        let source = rootDirectory.appendingPathComponent("generated.png")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let store = try ExerciseCueIllustrationStore(rootDirectory: rootDirectory)
        try Data("first".utf8).write(to: source)
        _ = try store.saveGeneratedImage(from: source, exerciseID: "deadlift")

        try Data("second".utf8).write(to: source)
        let saved = try store.saveGeneratedImage(from: source, exerciseID: "deadlift")

        XCTAssertEqual(try Data(contentsOf: saved), Data("second".utf8))
    }
}
