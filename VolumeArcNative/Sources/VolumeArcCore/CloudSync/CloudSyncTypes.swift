import Foundation

public protocol CloudSyncTransport: Sendable {
    func pushRecords(_ records: [CloudSyncRecord]) async throws
    func pullChanges(since cursor: String?) async throws -> CloudSyncPullResult
    var isAvailable: Bool { get }
}

/// A record destined for (or returned from) CloudKit.
/// Platform-agnostic wrapper so the applier doesn't depend on CloudKit types.
public struct CloudSyncRecord: Sendable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case workout
        case userProfile = "profile"
        case trainingPlan = "plan"
        case coachMemory = "memory"

        public var defaultIdentifier: String {
            rawValue
        }

        /// Resolve a `Kind` from a raw-string record type coming from
        /// an external source (CloudKit, the persisted outbound queue,
        /// legacy on-disk records). Tries the current short-form raw
        /// values first, then falls back to the pre-rename long-form
        /// names that earlier, unshipped versions of this code may
        /// have written. VOL-67 Codex P2: without this, an upgrade
        /// from a previous schema would silently drop records whose
        /// `recordType` was `userProfile` / `trainingPlan` /
        /// `coachMemory` instead of `profile` / `plan` / `memory`.
        public static func parse(_ raw: String) -> Kind? {
            if let direct = Kind(rawValue: raw) {
                return direct
            }
            switch raw {
            case "userProfile": return .userProfile
            case "trainingPlan": return .trainingPlan
            case "coachMemory": return .coachMemory
            default: return nil
            }
        }

        /// Whether this kind stores a single record per user (profile,
        /// plan) or can have many (workout, memory). Singletons always
        /// enqueue under `defaultIdentifier` regardless of what
        /// identifier CloudKit returned on the inbound side, so
        /// `canonicalQueueIdentifier(_:)` normalizes inbound IDs to
        /// keep invalidation aligned with queue rows.
        public var isSingleton: Bool {
            switch self {
            case .userProfile, .trainingPlan: return true
            case .workout, .coachMemory: return false
            }
        }

        /// Return the identifier a queue row would have been written
        /// under for this kind. For singletons, always `defaultIdentifier`
        /// (regardless of what CloudKit sent). For per-record kinds,
        /// pass through the inbound identifier unchanged.
        ///
        /// VOL-67 Codex P2 (fixup #7): the applier was passing
        /// `record.identifier` from the inbound CK record directly
        /// into `invalidateEntries`. For a legacy profile record
        /// whose `recordName` was `"userProfile"` (the pre-rename
        /// canonical form), that identifier no longer matched the
        /// queue row's canonical `"profile"` — so applying the
        /// legacy record locally didn't clear the stale queued
        /// upsert, and the next push resent stale state.
        public func canonicalQueueIdentifier(
            from inboundIdentifier: String
        ) -> String {
            isSingleton ? defaultIdentifier : inboundIdentifier
        }
    }

    public enum Operation: String, Sendable, Codable {
        case upsert
        case delete
    }

    public let kind: Kind
    public let identifier: String
    public let operation: Operation
    public let payloadJSON: String
    public let modifiedAt: Date

    public init(
        kind: Kind,
        identifier: String,
        operation: Operation,
        payloadJSON: String,
        modifiedAt: Date = .now
    ) {
        self.kind = kind
        self.identifier = identifier
        self.operation = operation
        self.payloadJSON = payloadJSON
        self.modifiedAt = modifiedAt
    }
}

public struct CloudSyncPullResult: Sendable {
    public let changedRecords: [CloudSyncRecord]
    public let deletedRecordIDs: [String]
    public let nextCursor: String?

    public init(changedRecords: [CloudSyncRecord], deletedRecordIDs: [String], nextCursor: String?) {
        self.changedRecords = changedRecords
        self.deletedRecordIDs = deletedRecordIDs
        self.nextCursor = nextCursor
    }
}

public struct UnavailableCloudSyncTransport: CloudSyncTransport {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public var isAvailable: Bool { false }

    public func pushRecords(_ records: [CloudSyncRecord]) async throws {
        throw CloudSyncError.transportUnavailable(reason: reason)
    }

    public func pullChanges(since cursor: String?) async throws -> CloudSyncPullResult {
        throw CloudSyncError.transportUnavailable(reason: reason)
    }
}

public enum CloudSyncError: Error, LocalizedError {
    case transportUnavailable(reason: String)
    case applyFailed(underlying: Error)
    case invalidQueuedRecord(reason: String)

    public var errorDescription: String? {
        switch self {
        case let .transportUnavailable(reason): return reason
        case let .applyFailed(underlying): return "Sync apply failed: \(underlying.localizedDescription)"
        case let .invalidQueuedRecord(reason): return reason
        }
    }
}

// MARK: - Timestamp newtype (VOL-130)

/// Wall-clock instant with explicit unit constructors so callers can't
/// accidentally pass milliseconds where seconds are expected (or vice
/// versa) when round-tripping through CloudKit, JSON, or legacy
/// numeric encodings.
///
/// VOL-130: prior to this type, the auto-detect path in
/// `CloudKitSyncTransport.pullChanges` (`raw > 100_000_000_000` ⇒ ms,
/// else seconds) was the *only* defense against a foreign client
/// writing a timestamp in the wrong unit. That heuristic is correct
/// today but fragile — a unit-tagged newtype contains the hazard at
/// construction time and makes encode/decode round-trips testable in
/// isolation.
///
/// `Timestamp` is intentionally `Date`-bridged so existing public API
/// surfaces (e.g. `CloudSyncRecord.modifiedAt`) don't have to change
/// in lockstep. Callsites that handle raw numeric inputs (CKRecord
/// custom fields, JSON payload decoding) should construct via
/// `seconds(_:)` / `milliseconds(_:)` / `autoDetect(_:)` so the unit
/// is stated rather than inferred.
public struct Timestamp: Hashable, Sendable, Codable {
    /// Magnitudes above this are interpreted as milliseconds-since-epoch
    /// by `autoDetect(_:)`. Equivalent to ~5,138 AD if read as
    /// seconds — well past any plausible user-visible date.
    public static let secondsVsMillisecondsThreshold: Double = 100_000_000_000

    public let date: Date

    public init(date: Date) { self.date = date }

    public static func seconds(_ value: Double) -> Timestamp {
        Timestamp(date: Date(timeIntervalSince1970: value))
    }

    public static func milliseconds(_ value: Double) -> Timestamp {
        Timestamp(date: Date(timeIntervalSince1970: value / 1_000))
    }

    /// Best-effort heuristic for foreign data of unknown unit. Use
    /// `seconds(_:)` or `milliseconds(_:)` whenever the unit is known
    /// — `autoDetect` is only correct as long as the heuristic
    /// threshold remains in the future.
    public static func autoDetect(_ raw: Double) -> Timestamp? {
        guard raw.isFinite else { return nil }
        let seconds = abs(raw) > secondsVsMillisecondsThreshold ? raw / 1_000 : raw
        return Timestamp(date: Date(timeIntervalSince1970: seconds))
    }

    public var secondsSinceEpoch: Double { date.timeIntervalSince1970 }
    public var millisecondsSinceEpoch: Double { date.timeIntervalSince1970 * 1_000 }
}

/// Persists sync cursor/token state to a file on disk so sync can resume across launches.
public struct FileSyncStateStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func loadCursor() -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func saveCursor(_ cursor: String) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(cursor.utf8).write(to: url, options: .atomic)
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
