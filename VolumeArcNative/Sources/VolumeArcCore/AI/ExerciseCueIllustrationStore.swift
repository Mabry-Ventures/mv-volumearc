import Foundation

public struct ExerciseCueIllustrationStore {
    public enum StoreError: Error, Equatable {
        case missingApplicationSupportDirectory
        case unsupportedSourceURL
        case unreadableSource
    }

    private let rootDirectory: URL
    private let fileManager: FileManager

    public init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            guard let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw StoreError.missingApplicationSupportDirectory
            }
            self.rootDirectory = applicationSupport
                .appendingPathComponent("VolumeArc", isDirectory: true)
                .appendingPathComponent("ExerciseCueIllustrations", isDirectory: true)
        }
    }

    public func saveGeneratedImage(
        from sourceURL: URL,
        exerciseID: String
    ) throws -> URL {
        guard sourceURL.isFileURL else {
            throw StoreError.unsupportedSourceURL
        }

        let sourceExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let exerciseDirectory = rootDirectory
            .appendingPathComponent(Self.storageKey(for: exerciseID), isDirectory: true)
        let destination = exerciseDirectory
            .appendingPathComponent("latest")
            .appendingPathExtension(sourceExtension)

        try fileManager.createDirectory(
            at: exerciseDirectory,
            withIntermediateDirectories: true
        )

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw StoreError.unreadableSource
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    public func latestIllustrationURL(for exerciseID: String) -> URL? {
        let exerciseDirectory = rootDirectory
            .appendingPathComponent(Self.storageKey(for: exerciseID), isDirectory: true)
        let candidates = (try? fileManager.contentsOfDirectory(
            at: exerciseDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return candidates.max { lhs, rhs in
            Self.modifiedAt(lhs) < Self.modifiedAt(rhs)
        }
    }

    public static func storageKey(for exerciseID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = exerciseID.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "exercise" : collapsed
    }

    private static func modifiedAt(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }
}
