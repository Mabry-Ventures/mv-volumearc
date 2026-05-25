import Foundation

/// A completed workout read from an external health source and normalized
/// into the fields VolumeArc's local history/readiness pipeline can consume.
public struct ImportedHealthWorkout: Sendable, Equatable {
    public let externalIdentifier: String
    public let sourceName: String
    public let sourceBundleIdentifier: String?
    public let title: String
    public let activityIdentifier: String
    public let startedAt: Date
    public let endedAt: Date
    public let durationMinutes: Int
    public let activeEnergyKilocalories: Double?

    public init(
        externalIdentifier: String,
        sourceName: String,
        sourceBundleIdentifier: String? = nil,
        title: String,
        activityIdentifier: String,
        startedAt: Date,
        endedAt: Date,
        durationMinutes: Int,
        activeEnergyKilocalories: Double? = nil
    ) {
        self.externalIdentifier = externalIdentifier
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.title = title
        self.activityIdentifier = activityIdentifier
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMinutes = durationMinutes
        self.activeEnergyKilocalories = activeEnergyKilocalories
    }

    /// Stable local record identifier for deduping imports across refreshes.
    public var localWorkoutIdentifier: String {
        let source = Self.sanitizeIdentifierComponent(sourceBundleIdentifier ?? sourceName)
        let external = Self.sanitizeIdentifierComponent(externalIdentifier)
        return "external-health-\(source)-\(external)"
    }

    public var summary: String {
        var parts = ["Imported from Apple Health", sourceName.isEmpty ? nil : sourceName]
            .compactMap { $0 }
            .joined(separator: " / ")
        if let activeEnergyKilocalories {
            parts += " · \(Int(activeEnergyKilocalories.rounded())) kcal"
        }
        return parts
    }

    /// HealthKit-derived samples stay out of the CloudKit-backed SwiftData
    /// store. Readiness only needs a normalized session value.
    public var readinessSession: RecentSession {
        RecentSession(
            title: title,
            sourceName: sourceName.isEmpty ? "Apple Health" : sourceName,
            date: endedAt,
            durationMinutes: durationMinutes,
            exerciseIDs: ["healthkit-\(activityIdentifier)"],
            totalVolumeLoad: 0,
            averageRPE: 7.0,
            completedSetCount: 0
        )
    }

    private static func sanitizeIdentifierComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return sanitized.isEmpty ? "unknown" : sanitized.lowercased()
    }
}

/// Reads completed workouts from HealthKit or another external health source.
public protocol HealthWorkoutImporting: Sendable {
    func completedWorkouts(since startDate: Date, now: Date) async throws -> [ImportedHealthWorkout]
}

public struct UnavailableHealthWorkoutImporter: HealthWorkoutImporting {
    public init() {}

    public func completedWorkouts(since startDate: Date, now: Date) async throws -> [ImportedHealthWorkout] {
        []
    }
}
