#if canImport(SnapshotTesting)
import Foundation
import SnapshotTesting
import XCTest

enum VolumeArcSnapshotReferences {
    private static let rootDirectoryName = "__Snapshots__"

    static func resolvedRecord(
        explicit record: SnapshotTestingConfiguration.Record?,
        filePath: StaticString,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SnapshotTestingConfiguration.Record {
        if let record {
            return record
        }
        if let rawValue = environment["SNAPSHOT_TESTING_RECORD"],
           let envRecord = SnapshotTestingConfiguration.Record(rawValue: rawValue) {
            return envRecord
        }
        if let markerRecord = markerRecord(filePath: filePath) {
            return markerRecord
        }
        return .never
    }

    static func directory(
        for testCase: XCTestCase,
        record: SnapshotTestingConfiguration.Record,
        filePath: StaticString
    ) throws -> String {
        if record == .all || record == .missing {
            return sourceDirectory(for: testCase, filePath: filePath)
        }

        let directory = try bundledDirectory(for: testCase)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SnapshotReferenceError.missingBundledReferences(directory)
        }
        return directory
    }

    private static func sourceDirectory(for testCase: XCTestCase, filePath: StaticString) -> String {
        URL(fileURLWithPath: "\(filePath)", isDirectory: false)
            .deletingLastPathComponent()
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
            .appendingPathComponent(String(describing: type(of: testCase)), isDirectory: true)
            .path
    }

    private static func markerRecord(filePath: StaticString) -> SnapshotTestingConfiguration.Record? {
        let markerURL = URL(fileURLWithPath: "\(filePath)", isDirectory: false)
            .deletingLastPathComponent()
            .appendingPathComponent(".record-snapshots", isDirectory: false)
        guard let rawValue = try? String(contentsOf: markerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return SnapshotTestingConfiguration.Record(rawValue: rawValue)
    }

    private static func bundledDirectory(for testCase: XCTestCase) throws -> String {
        guard let resourceURL = Bundle(for: type(of: testCase)).resourceURL else {
            throw SnapshotReferenceError.missingResourceURL
        }
        return resourceURL
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
            .appendingPathComponent(String(describing: type(of: testCase)), isDirectory: true)
            .path
    }
}

private enum SnapshotReferenceError: LocalizedError {
    case missingResourceURL
    case missingBundledReferences(String)

    var errorDescription: String? {
        switch self {
        case .missingResourceURL:
            return "VolumeArcAppTests bundle has no resource URL; snapshot references cannot be resolved."
        case .missingBundledReferences(let path):
            return """
            Bundled snapshot references were not found at \(path). Ensure \
            Tests/VolumeArcAppTests/Snapshots/__Snapshots__/ is committed and wired \
            into VolumeArcAppTests by scripts/generate_xcode_project.rb.
            """
        }
    }
}

func assertVolumeArcSnapshot<Value, Format>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, Format>,
    named name: String? = nil,
    record explicitRecord: SnapshotTestingConfiguration.Record? = nil,
    timeout: TimeInterval = 5,
    in testCase: XCTestCase,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let record = VolumeArcSnapshotReferences.resolvedRecord(
        explicit: explicitRecord,
        filePath: filePath
    )
    let snapshotDirectory: String
    do {
        snapshotDirectory = try VolumeArcSnapshotReferences.directory(
            for: testCase,
            record: record,
            filePath: filePath
        )
    } catch {
        XCTFail(error.localizedDescription, file: filePath, line: line)
        return
    }

    let failure = verifySnapshot(
        of: try value(),
        as: snapshotting,
        named: name,
        record: record,
        snapshotDirectory: snapshotDirectory,
        timeout: timeout,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
    guard let failure else { return }
    XCTFail(failure, file: filePath, line: line)
}
#endif
