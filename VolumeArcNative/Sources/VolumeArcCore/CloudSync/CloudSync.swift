import Foundation
#if canImport(CloudKit)
import CloudKit
#endif
#if canImport(SwiftData)
import SwiftData
#endif

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

#if canImport(CloudKit)
/// CloudKit-backed sync transport.
/// Pushes records to a private database zone and pulls changes via
/// `CKFetchRecordZoneChangesOperation` with server cursor tokens.
public final class CloudKitSyncTransport: CloudSyncTransport, @unchecked Sendable {
    public let containerIdentifier: String
    public let zoneName: String

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID

    public init(containerIdentifier: String, zoneName: String) {
        self.containerIdentifier = containerIdentifier
        self.zoneName = zoneName
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    public var isAvailable: Bool { true }

    public func pushRecords(_ records: [CloudSyncRecord]) async throws {
        guard !records.isEmpty else { return }

        try await ensureZoneExists()

        let ckRecords = records.map { record -> CKRecord in
            let id = CKRecord.ID(recordName: record.identifier, zoneID: zoneID)
            let ck = CKRecord(recordType: record.kind.rawValue, recordID: id)
            ck["operation"] = record.operation.rawValue as NSString
            ck["payloadJSON"] = record.payloadJSON as NSString
            ck["modifiedAt"] = record.modifiedAt as NSDate
            return ck
        }

        let operation = CKModifyRecordsOperation(recordsToSave: ckRecords, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    public func pullChanges(since cursor: String?) async throws -> CloudSyncPullResult {
        try await ensureZoneExists()

        var changedRecords: [CloudSyncRecord] = []
        var deletedRecordIDs: [String] = []
        var nextCursor: String? = cursor
        // VOL-67 Copilot (fixup #21): count records that we had to skip
        // because `SyncPayloadCodec.synthesizeLegacyPayloadJSON` returned
        // nil (missing required fields on a legacy CKRecord). If ANY
        // records are skipped, we clear `nextCursor` before returning so
        // the next `syncCycle` re-fetches the whole window instead of
        // advancing past un-applied changes. See the skip branch below.
        var legacySynthesisSkips = 0

        let token: CKServerChangeToken?
        if let cursor,
           let data = Data(base64Encoded: cursor),
           let unarchived = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data) {
            token = unarchived
        } else {
            token = nil
        }

        let options = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        options.previousServerChangeToken = token

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: options]
        )

        operation.recordWasChangedBlock = { _, result in
            if case let .success(record) = result,
               let kind = CloudSyncRecord.Kind.parse(record.recordType) {
                let modifiedAt = record.modificationDate ?? .now
                let operation = CloudSyncRecord.Operation(
                    rawValue: (record["operation"] as? String) ?? CloudSyncRecord.Operation.upsert.rawValue
                ) ?? .upsert

                // VOL-67 Codex P2 fixup: the modern wire format stores
                // the entire payload in a single `payloadJSON` key, but
                // pre-rename CKRecords may have stored individual field
                // keys instead. If `payloadJSON` is missing, synthesize
                // one by reading the known per-kind fields directly off
                // the CKRecord.
                //
                // VOL-67 Copilot (fixup #21): if synthesis returns nil
                // (legacy record is missing required fields), SKIP the
                // record entirely AND increment the skip counter.
                // Previously we fell back to an empty payloadJSON and
                // still appended the record — the applier then silently
                // dropped it on decode-failure while the cursor advanced
                // past it, losing the mutation permanently. Now we
                // neither produce a junk record nor advance the cursor
                // past it: the whole window gets re-fetched on the next
                // sync cycle. Successfully-synthesized records in the
                // same window still get applied by the coordinator —
                // they're idempotent on re-fetch because shouldApply
                // rejects equal-timestamp re-applies.
                let payloadJSON: String
                if let explicit = record["payloadJSON"] as? String, !explicit.isEmpty {
                    payloadJSON = explicit
                } else {
                    var fields: [String: Any] = [:]
                    for key in record.allKeys() {
                        if let value = record[key] {
                            fields[key] = value
                        }
                    }
                    guard let synthesized = SyncPayloadCodec.synthesizeLegacyPayloadJSON(
                        kind: kind,
                        fields: fields
                    ) else {
                        legacySynthesisSkips += 1
                        return
                    }
                    payloadJSON = synthesized
                }

                changedRecords.append(CloudSyncRecord(
                    kind: kind,
                    identifier: record.recordID.recordName,
                    operation: operation,
                    payloadJSON: payloadJSON,
                    modifiedAt: modifiedAt
                ))
            }
        }

        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            deletedRecordIDs.append(recordID.recordName)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.recordZoneChangeTokensUpdatedBlock = { _, newToken, _ in
                if let newToken,
                   let data = try? NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: true) {
                    nextCursor = data.base64EncodedString()
                }
            }
            operation.recordZoneFetchResultBlock = { _, result in
                if case let .success(success) = result,
                   let data = try? NSKeyedArchiver.archivedData(withRootObject: success.serverChangeToken, requiringSecureCoding: true) {
                    nextCursor = data.base64EncodedString()
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }

        // VOL-67 Copilot (fixup #21): if the legacy-payload synthesis
        // had to skip any records, force the next pull to re-fetch the
        // whole window by dropping the advanced cursor. The applier
        // still processes whatever records DID synthesize — the
        // re-apply is idempotent because shouldApply rejects equal or
        // older timestamps on the second round.
        if legacySynthesisSkips > 0 {
            nextCursor = nil
        }

        return CloudSyncPullResult(
            changedRecords: changedRecords,
            deletedRecordIDs: deletedRecordIDs,
            nextCursor: nextCursor
        )
    }

    /// Create the sync zone if it doesn't already exist. Safe to call repeatedly.
    private func ensureZoneExists() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordZonesOperation(
                recordZonesToSave: [zone],
                recordZoneIDsToDelete: nil
            )
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    // Zone already exists is not an error we care about.
                    if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
            database.add(operation)
        }
    }
}
#endif

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

// VOL-67 Copilot P2 (fixup #11): `CloudSyncCoordinator` references
// `OutboundSyncQueue` and `DefaultSyncPayloadApplier`, both of
// which are defined under `#if canImport(SwiftData)`. Without
// this wrap the whole actor would fail to compile on any
// platform where SwiftData is unavailable. Our current targets
// (iOS 26 + watchOS 26.4) both ship SwiftData, so in practice
// the guard is protective — if Apple ever adds a platform where
// SwiftData isn't present, the coordinator cleanly drops out
// instead of breaking the build.
#if canImport(SwiftData)
/// Coordinates push/pull cycles between local repositories and the cloud transport.
public actor CloudSyncCoordinator {
    private let transport: CloudSyncTransport
    private let stateStore: FileSyncStateStore
    private let outboundQueue: (any OutboundSyncQueue)?
    private let telemetrySink: (any TelemetrySink)?
    private let payloadApplier: DefaultSyncPayloadApplier?

    public init(
        transport: CloudSyncTransport,
        payloadApplier: DefaultSyncPayloadApplier,
        stateStore: FileSyncStateStore,
        outboundQueue: (any OutboundSyncQueue)? = nil,
        telemetrySink: (any TelemetrySink)? = nil
    ) {
        self.transport = transport
        self.payloadApplier = payloadApplier
        self.stateStore = stateStore
        self.outboundQueue = outboundQueue
        self.telemetrySink = telemetrySink
    }

    public init(
        transport: CloudSyncTransport,
        stateStore: FileSyncStateStore,
        outboundQueue: (any OutboundSyncQueue)? = nil,
        telemetrySink: (any TelemetrySink)? = nil
    ) {
        self.transport = transport
        self.stateStore = stateStore
        self.outboundQueue = outboundQueue
        self.telemetrySink = telemetrySink
        self.payloadApplier = nil
    }

    /// Whether the transport is capable of syncing.
    public var isAvailable: Bool {
        transport.isAvailable
    }

    /// Push up to `limit` queued local changes and delete them only after a successful transport call.
    ///
    /// VOL-67 Codex P1: drained rows are coalesced by `(recordType,
    /// recordIdentifier)` before the batch is handed to the transport.
    /// Without coalescing, a record that was mutated N times between
    /// sync cycles would produce N `CKRecord`s with the same
    /// `CKRecord.ID` in a single `CKModifyRecordsOperation`. CloudKit
    /// may reject such a batch outright or apply the records in an
    /// undefined order, leaving the queue stuck retrying or the
    /// remote state inconsistent. Because `drain(limit:)` returns
    /// rows in `queuedAt` ascending order, the "later operation
    /// wins" collapse handles every multi-mutation history we care
    /// about:
    ///   - `upsert → upsert → upsert` → keep the newest upsert (latest state)
    ///   - `upsert → delete` → keep the delete (tombstone wins)
    ///   - `delete → upsert` → keep the upsert (record was recreated)
    /// Every drained row is still deleted from the queue on success —
    /// including the superseded ones that didn't make it into the
    /// coalesced batch — so nothing stays queued after a successful push.
    public func push(limit: Int = 50, additionalRecords: [CloudSyncRecord] = []) async throws -> Int {
        guard transport.isAvailable else { return 0 }

        var records = additionalRecords
        var drainedChanges: [QueuedOutboundSyncChange] = []
        var quarantinedIDs: [UUID] = []
        // VOL-67 Codex P1 (fixup #14): tracks the coalesce keys whose
        // representative row failed to parse. See the per-key cleanup
        // comment below for why we track keys separately from IDs.
        var quarantinedKeys: Set<String> = []

        if let outboundQueue {
            drainedChanges = try await MainActor.run {
                try outboundQueue.drain(limit: limit)
            }

            // Coalesce by (normalized Kind, canonical identifier) so
            // the batch contains at most one entry per logical record.
            // VOL-67 Codex P2 (fixup #10): resolve both the
            // `recordType` and `recordIdentifier` through `Kind.parse`
            // and `canonicalQueueIdentifier(from:)` before building
            // the key. Without normalization, a legacy row
            // `(recordType: "userProfile", recordIdentifier: "userProfile")`
            // and a canonical row `(recordType: "profile",
            // recordIdentifier: "profile")` would hash to different
            // keys and both get pushed — two writes for the same
            // logical singleton profile, with undefined ordering.
            // Iterate in `queuedAt` order: each successive row
            // overwrites the previous one for the same normalized
            // key, so the final dict holds the latest operation per
            // logical record regardless of which alias form it was
            // queued under.
            var coalesced: [String: QueuedOutboundSyncChange] = [:]
            var orderedKeys: [String] = []
            for change in drainedChanges {
                let key = Self.coalesceKey(for: change)
                if coalesced[key] == nil {
                    orderedKeys.append(key)
                }
                coalesced[key] = change
            }
            // Preserve the latest-value-wins ordering in a stable sequence
            // so tests and transports see a predictable push order.
            let coalescedChanges = orderedKeys.compactMap { coalesced[$0] }

            // VOL-67 Copilot P2 (fixup #11): quarantine unparseable
            // rows instead of aborting the whole push. Previously,
            // `makeCloudSyncRecord(from:)` threw on an unsupported
            // `recordType` or `operation` string, which aborted
            // `push()` entirely and left every drained row in the
            // queue for the next cycle. A single corrupted row (from
            // a failed partial write, a schema drift, or a test
            // fixture) could permanently block all outbound sync
            // until the user reinstalled. Now bad rows are logged
            // to telemetry and routed into the per-key cleanup below.
            //
            // VOL-67 Codex P1 (fixup #14): also track which coalesce
            // keys got quarantined, so the post-push cleanup can
            // preserve older valid siblings for those keys. Without
            // this, a single malformed *latest* row for a key would
            // silently delete every older valid row for that same
            // key — losing the user's last known good state.
            var queuedRecords: [CloudSyncRecord] = []
            for change in coalescedChanges {
                let key = Self.coalesceKey(for: change)
                do {
                    queuedRecords.append(try Self.makeCloudSyncRecord(from: change))
                } catch {
                    quarantinedIDs.append(change.id)
                    quarantinedKeys.insert(key)
                    telemetrySink?.record(TelemetryEvent(
                        category: "sync",
                        name: "outbound_row_quarantined",
                        severity: .warning,
                        message: "Dropped unparseable outbound queue row \(change.id): \(error)",
                        metadata: [
                            "recordType": change.recordType,
                            "recordIdentifier": change.recordIdentifier,
                            "operation": change.operation,
                        ]
                    ))
                }
            }
            records.append(contentsOf: queuedRecords)
        }

        // Only call the transport when we have something to send.
        // Quarantine-only batches (and batches where every coalesced
        // row was quarantined) still need to run the cleanup below to
        // drop the unparseable rows — otherwise they'd be drained
        // forever and jam the queue.
        if !records.isEmpty {
            try await transport.pushRecords(records)
        }

        // VOL-67 Codex P1 (fixup #14): per-key cleanup. For keys whose
        // coalesced representative was successfully pushed, drop every
        // drained row sharing that key — the pushed record reflects
        // the newest intent, older siblings are resolved. For keys
        // whose coalesced representative was quarantined, drop ONLY
        // the specific unparseable row; older valid siblings stay in
        // the queue so the next push cycle can fall back to the last
        // known good state for that key. This preserves the "latest
        // wins + quarantine unparseable" semantics without silently
        // wiping older-but-valid state.
        if let outboundQueue {
            let quarantinedIDSet = Set(quarantinedIDs)
            var idsToDelete: [UUID] = []
            for change in drainedChanges {
                let key = Self.coalesceKey(for: change)
                if quarantinedKeys.contains(key) {
                    // Quarantined key: only delete the specific
                    // unparseable row, keep older siblings as fallback.
                    if quarantinedIDSet.contains(change.id) {
                        idsToDelete.append(change.id)
                    }
                } else {
                    // Pushed key: every drained row for this key is
                    // resolved, delete it.
                    idsToDelete.append(change.id)
                }
            }
            if !idsToDelete.isEmpty {
                try await MainActor.run {
                    try outboundQueue.delete(ids: idsToDelete)
                }
            }
        }

        return records.count
    }

    /// Run one pull/apply/push cycle. Returns the number of records pushed + pulled.
    ///
    /// Ordering rationale: pull and apply happen BEFORE push. Reversing
    /// these steps would let a stale queued mutation clobber newer remote
    /// state before the applier's `shouldApply` timestamp check could run
    /// — in the worst case, a queued upsert would resurrect a record that
    /// another device had deleted. Applying inbound records first also
    /// invalidates any queued outbound entries for the same identifier
    /// that are older than the freshly-pulled state (see
    /// `outboundQueue.invalidateEntries` calls in the per-kind apply
    /// methods and `applyDeletion`), so the subsequent push step doesn't
    /// emit stale writes in the first place.
    public func syncCycle(pushing localRecords: [CloudSyncRecord] = []) async throws -> Int {
        guard transport.isAvailable else { return 0 }

        // 1) Pull remote changes first so the applier can see them before
        //    any local queue drain runs.
        let cursor = stateStore.loadCursor()
        let result = try await transport.pullChanges(since: cursor)

        // 2) Apply remote changes locally on the main actor (SwiftData is
        //    bound to @MainActor via ModelContext thread affinity). The
        //    applier also invalidates stale queued entries whose state
        //    is older than the inbound timestamp.
        if let payloadApplier {
            try await payloadApplier.apply(result: result)
        }

        // 3) Persist the new cursor before pushing so a push failure
        //    can't force us to re-pull the same window twice.
        if let nextCursor = result.nextCursor {
            try? stateStore.saveCursor(nextCursor)
        }

        // 4) Push any remaining (still-valid) local changes.
        let pushedCount = try await push(additionalRecords: localRecords)

        return pushedCount + result.changedRecords.count
    }

    /// Produce the coalescing key for a queued change. VOL-67 Codex P2
    /// (fixup #10): the key is built from the normalized `Kind` raw
    /// value and the canonical queue identifier, so legacy long-form
    /// rows and canonical short-form rows collapse to the same slot.
    private static func coalesceKey(for change: QueuedOutboundSyncChange) -> String {
        if let kind = CloudSyncRecord.Kind.parse(change.recordType) {
            return "\(kind.rawValue)|\(kind.canonicalQueueIdentifier(from: change.recordIdentifier))"
        }
        // Unknown/future record type: fall back to the raw pair so we
        // don't accidentally merge records we don't understand.
        return "\(change.recordType)|\(change.recordIdentifier)"
    }

    private static func makeCloudSyncRecord(from change: QueuedOutboundSyncChange) throws -> CloudSyncRecord {
        guard let kind = CloudSyncRecord.Kind.parse(change.recordType) else {
            throw CloudSyncError.invalidQueuedRecord(reason: "Unsupported record type: \(change.recordType)")
        }
        guard let operation = CloudSyncRecord.Operation(rawValue: change.operation) else {
            throw CloudSyncError.invalidQueuedRecord(reason: "Unsupported queue operation: \(change.operation)")
        }

        // VOL-67 Codex P1 fixup: for delete tombstones, the authoritative
        // timestamp is the actual deletion instant recorded on the queue
        // row at enqueue time, NOT the `updatedAt` embedded in the
        // snapshotted payload (which reflects the record's state BEFORE
        // deletion). Using the payload's `updatedAt` let a queued delete
        // lose ordering to a newer inbound update and silently drop the
        // user's delete intent. For upserts we still prefer the payload's
        // embedded timestamp since that reflects the exact snapshot we
        // captured at enqueue.
        //
        // VOL-67 Codex P2 (fixup #14): reject upserts whose `payloadJSON`
        // can't be decoded BEFORE they reach the transport. Previously
        // we fell back to `change.queuedAt` as the modified timestamp
        // and sent the malformed payload anyway. Downstream appliers on
        // other devices then drop the record (decode fails there too),
        // but the server cursor still advances — so the mutation is
        // silently lost cross-device. Throwing here routes the row into
        // the push() quarantine path: it's never sent, it's deleted
        // from the local queue so it can't re-poison future cycles, and
        // the quarantine telemetry event surfaces it for diagnosis.
        let modifiedAt: Date
        if operation == .delete {
            modifiedAt = change.queuedAt
        } else {
            guard let decoded = SyncPayloadCodec.modifiedAt(for: kind, payloadJSON: change.payloadJSON) else {
                throw CloudSyncError.invalidQueuedRecord(
                    reason: "Unparseable upsert payload for \(kind.rawValue): modifiedAt decode failed"
                )
            }
            modifiedAt = decoded
        }

        // VOL-67 Codex P2 (fixup #10): also normalize the outbound
        // identifier so a legacy queue row gets pushed under the
        // canonical form — singletons always report as
        // `defaultIdentifier`, per-record kinds pass through
        // unchanged. This mirrors the coalesce key normalization
        // so the outbound batch is internally consistent.
        return CloudSyncRecord(
            kind: kind,
            identifier: kind.canonicalQueueIdentifier(from: change.recordIdentifier),
            operation: operation,
            payloadJSON: change.payloadJSON,
            modifiedAt: modifiedAt
        )
    }
}
#endif // canImport(SwiftData) — CloudSyncCoordinator

#if canImport(SwiftData)
/// Applies remote sync records to local SwiftData repositories.
/// Uses last-write-wins based on the record's `modifiedAt` timestamp.
public struct DefaultSyncPayloadApplier: Sendable {
    public let workoutRepository: SwiftDataWorkoutRepository
    public let coachMemoryRepository: SwiftDataCoachMemoryRepository
    public let userProfileRepository: SwiftDataUserProfileRepository
    public let trainingPlanRepository: SwiftDataTrainingPlanRepository
    private let telemetrySink: (any TelemetrySink)?
    private let outboundQueue: (any OutboundSyncQueue)?

    public init(
        workoutRepository: SwiftDataWorkoutRepository,
        coachMemoryRepository: SwiftDataCoachMemoryRepository,
        userProfileRepository: SwiftDataUserProfileRepository,
        trainingPlanRepository: SwiftDataTrainingPlanRepository,
        telemetrySink: (any TelemetrySink)? = nil,
        outboundQueue: (any OutboundSyncQueue)? = nil
    ) {
        self.workoutRepository = workoutRepository
        self.coachMemoryRepository = coachMemoryRepository
        self.userProfileRepository = userProfileRepository
        self.trainingPlanRepository = trainingPlanRepository
        self.telemetrySink = telemetrySink
        self.outboundQueue = outboundQueue
    }

    /// Apply a pull result to the local repositories.
    @MainActor
    public func apply(result: CloudSyncPullResult) async throws {
        for record in result.changedRecords {
            if record.operation == .delete {
                try applyDeletion(record)
            } else {
                try applyRecord(record)
            }
        }
        for deletedID in result.deletedRecordIDs {
            try applyDeletion(identifier: deletedID)
        }
    }

    @MainActor
    private func applyRecord(_ record: CloudSyncRecord) throws {
        switch record.kind {
        case .workout:
            try applyWorkout(record)
        case .userProfile:
            try applyUserProfile(record)
        case .trainingPlan:
            try applyTrainingPlan(record)
        case .coachMemory:
            try applyCoachMemory(record)
        }
    }

    /// VOL-67 Codex P1 (fixup #18): check whether the outbound queue
    /// holds a pending delete tombstone for `(kind, recordIdentifier)`
    /// whose `queuedAt` is strictly newer than `inboundTimestamp`.
    ///
    /// Used by the per-kind apply methods' "no existing local record"
    /// branch to avoid resurrecting a record the user just deleted.
    /// Scenario: `syncCycle()` pulls before pushing. The pull returns
    /// an inbound upsert for a record whose local row was already
    /// removed by a queued delete. Without this check, the apply path
    /// would insert the record back into the local store; the
    /// subsequent push would send the tombstone to CloudKit (deleting
    /// the server copy) but the newly-reinserted local row would
    /// survive, leaving the UI showing a zombie record until the next
    /// pull/apply cycle noticed the divergence.
    ///
    /// Identifier matching canonicalizes via `Kind.parse` +
    /// `canonicalQueueIdentifier(from:)` so the check also catches
    /// legacy-form queue rows (e.g., `recordType="userProfile"`
    /// matching against canonical `.userProfile` kind). Strict `>`
    /// matches the applier's `shouldApply` semantics: equal timestamps
    /// give priority to the inbound record, so only delete intents
    /// that are strictly newer than the inbound modification suppress
    /// the resurrection.
    ///
    /// VOL-67 Copilot (fixup #19): delegates to the queue's
    /// `hasPendingDeleteTombstone` method, which pushes the identifier
    /// + operation + timestamp filter into SwiftData via `#Predicate`.
    /// Previously this scanned the full pending-records list in
    /// application code, which was O(n) per inbound insert and could
    /// noticeably slow the pull/apply phase on devices with a large
    /// offline backlog. The predicate-narrowed fetch returns at most
    /// a handful of rows, so this check is now effectively O(1) per
    /// inbound record.
    @MainActor
    private func hasNewerLocalDeleteTombstone(
        kind: CloudSyncRecord.Kind,
        recordIdentifier: String,
        inboundTimestamp: Date
    ) throws -> Bool {
        guard let outboundQueue else { return false }

        // Build the candidate identifier set: canonical form plus any
        // singleton long-form alias (legacy rows may use either).
        let canonicalID = kind.canonicalQueueIdentifier(from: recordIdentifier)
        var candidateIdentifiers: Set<String> = [canonicalID, recordIdentifier]
        if kind.isSingleton {
            candidateIdentifiers.insert(kind.defaultIdentifier)
            switch kind {
            case .userProfile:
                candidateIdentifiers.insert("userProfile")
            case .trainingPlan:
                candidateIdentifiers.insert("trainingPlan")
            case .workout, .coachMemory:
                break
            }
        }

        // Build the candidate record-type set: canonical + any known
        // long-form alias for this kind.
        var candidateRecordTypes: Set<String> = [kind.rawValue]
        switch kind {
        case .userProfile:
            candidateRecordTypes.insert("userProfile")
        case .trainingPlan:
            candidateRecordTypes.insert("trainingPlan")
        case .coachMemory:
            candidateRecordTypes.insert("coachMemory")
        case .workout:
            break
        }

        return try outboundQueue.hasPendingDeleteTombstone(
            candidateRecordTypes: candidateRecordTypes,
            candidateIdentifiers: candidateIdentifiers,
            newerThan: inboundTimestamp
        )
    }

    @MainActor
    private func recordSuppressedInboundInsert(
        kind: CloudSyncRecord.Kind,
        recordIdentifier: String,
        inboundTimestamp: Date
    ) {
        telemetrySink?.record(TelemetryEvent(
            category: "sync",
            name: "inbound_upsert_suppressed_by_tombstone",
            severity: .info,
            message: "Pull upsert for \(kind.rawValue)/\(recordIdentifier) suppressed: local delete tombstone is newer than inbound",
            metadata: [
                "recordType": kind.rawValue,
                "recordIdentifier": recordIdentifier,
                "inboundTimestamp": ISO8601DateFormatter().string(from: inboundTimestamp),
            ]
        ))
    }

    @MainActor
    private func applyDeletion(identifier: String) throws {
        // Best-effort fallback for legacy deleted-record callbacks that don't
        // include a record kind. The identifier is matched against each
        // entity store; at most one hit is expected.
        let context = ModelContext(workoutRepository.container)

        // VOL-67 Codex P2 (fixup #7): accept both the current canonical
        // singleton identifier and the pre-rename legacy long form.
        // A legacy CK delete callback for "userProfile" must still
        // resolve to the profile entity and clear the canonical
        // "profile" queue row.
        let profileCanonical = CloudSyncRecord.Kind.userProfile.defaultIdentifier
        let planCanonical = CloudSyncRecord.Kind.trainingPlan.defaultIdentifier
        let isProfileIdentifier = (identifier == profileCanonical || identifier == "userProfile")
        let isPlanIdentifier = (identifier == planCanonical || identifier == "trainingPlan")

        if isProfileIdentifier {
            var profileDescriptor = FetchDescriptor<UserProfileRecord>()
            profileDescriptor.fetchLimit = 1
            if let profile = try context.fetch(profileDescriptor).first {
                context.delete(profile)
            }
        }

        if isPlanIdentifier {
            var planDescriptor = FetchDescriptor<TrainingPlanRecord>()
            planDescriptor.fetchLimit = 1
            if let plan = try context.fetch(planDescriptor).first {
                context.delete(plan)
            }
        }

        var workoutDescriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.identifier == identifier
            }
        )
        workoutDescriptor.fetchLimit = 1
        if let workout = try context.fetch(workoutDescriptor).first {
            context.delete(workout)
        }

        var memoryDescriptor = FetchDescriptor<CoachMemoryRecord>(
            predicate: #Predicate<CoachMemoryRecord> { memory in
                memory.identifier == identifier
            }
        )
        memoryDescriptor.fetchLimit = 1
        if let memory = try context.fetch(memoryDescriptor).first {
            context.delete(memory)
        }

        try context.save()

        // VOL-67 fixup: the legacy callback doesn't tell us which record
        // kind the deletion applies to, so sweep the queue for every kind.
        // For non-singleton kinds (workout, coachMemory), pass the
        // identifier through. For singletons, sweep the canonical queue
        // identifier only when the inbound ID looks like that singleton
        // (so a workout-UUID delete doesn't spuriously clear a queued
        // profile row).
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: identifier,
            olderThan: nil
        )
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.coachMemory.rawValue,
            recordIdentifier: identifier,
            olderThan: nil
        )
        if isProfileIdentifier {
            try outboundQueue?.invalidateEntries(
                recordType: CloudSyncRecord.Kind.userProfile.rawValue,
                recordIdentifier: profileCanonical,
                olderThan: nil
            )
        }
        if isPlanIdentifier {
            try outboundQueue?.invalidateEntries(
                recordType: CloudSyncRecord.Kind.trainingPlan.rawValue,
                recordIdentifier: planCanonical,
                olderThan: nil
            )
        }
    }

    // MARK: - Per-kind appliers

    @MainActor
    private func applyWorkout(_ record: CloudSyncRecord) throws {
        guard let payload = SyncPayloadCodec.decodeWorkoutPayload(from: record.payloadJSON) else { return }

        let context = ModelContext(workoutRepository.container)
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.identifier == record.identifier
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            guard shouldApply(
                kind: record.kind,
                identifier: record.identifier,
                localTimestamp: existing.updatedAt,
                inboundTimestamp: payload.updatedAt
            ) else { return }

            existing.title = payload.title
            existing.startedAt = payload.startedAt
            existing.completedAt = payload.completedAt
            existing.durationMinutes = payload.durationMinutes
            existing.exerciseIDsCSV = payload.exerciseIDsCSV
            existing.setsJSON = payload.setsJSON
            existing.totalVolumeLoad = payload.totalVolumeLoad
            existing.averageRPE = payload.averageRPE
            existing.completedSetCount = payload.completedSetCount
            existing.summary = payload.summary
            existing.updatedAt = payload.updatedAt
        } else {
            // VOL-67 Codex P1 (fixup #18): don't resurrect a record the
            // user just deleted locally. If the outbound queue has a
            // strictly newer delete tombstone for this workout, the
            // pending delete represents more recent user intent than
            // the inbound upsert — inserting here would make the
            // deleted workout visually reappear, and the subsequent
            // push would delete it on the server without removing the
            // reinserted local row. Skip and let the next push apply
            // the tombstone.
            if try hasNewerLocalDeleteTombstone(
                kind: record.kind,
                recordIdentifier: record.identifier,
                inboundTimestamp: payload.updatedAt
            ) {
                recordSuppressedInboundInsert(
                    kind: record.kind,
                    recordIdentifier: record.identifier,
                    inboundTimestamp: payload.updatedAt
                )
                return
            }

            context.insert(WorkoutRecord(
                identifier: record.identifier,
                title: payload.title,
                startedAt: payload.startedAt,
                completedAt: payload.completedAt,
                durationMinutes: payload.durationMinutes,
                exerciseIDsCSV: payload.exerciseIDsCSV,
                setsJSON: payload.setsJSON,
                totalVolumeLoad: payload.totalVolumeLoad,
                averageRPE: payload.averageRPE,
                completedSetCount: payload.completedSetCount,
                summary: payload.summary,
                updatedAt: payload.updatedAt
            ))
        }

        try context.save()

        // VOL-67 fixup: once the inbound record has been applied locally,
        // invalidate any queued outbound entry for the same workout that's
        // older than the inbound timestamp. Without this, the stale queued
        // payload would overwrite the newly-pulled server state on the
        // next push and we'd be right back in the "local clobbers server"
        // divergence Codex flagged.
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: record.identifier,
            olderThan: payload.updatedAt
        )
    }

    @MainActor
    private func applyUserProfile(_ record: CloudSyncRecord) throws {
        guard let payload = SyncPayloadCodec.decodeUserProfilePayload(from: record.payloadJSON) else { return }

        let context = ModelContext(userProfileRepository.container)
        var descriptor = FetchDescriptor<UserProfileRecord>()
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            guard shouldApply(
                kind: record.kind,
                identifier: record.identifier,
                localTimestamp: existing.updatedAt,
                inboundTimestamp: payload.updatedAt
            ) else { return }

            existing.name = payload.name
            existing.coachingStyle = payload.coachingStyle
            existing.privacyMode = payload.privacyMode
            existing.advancementLevel = payload.advancementLevel
            existing.availableEquipmentCSV = payload.availableEquipmentCSV
            existing.preferredRepRangeLower = payload.preferredRepRangeLower
            existing.preferredRepRangeUpper = payload.preferredRepRangeUpper
            existing.sessionTimeBudgetMinutes = payload.sessionTimeBudgetMinutes
            existing.weeklyTrainingDays = payload.weeklyTrainingDays
            existing.onboardingCompleted = payload.onboardingCompleted
            existing.updatedAt = payload.updatedAt
        } else {
            // VOL-67 Codex P1 (fixup #18): tombstone-wins check — same
            // resurrection race as workouts/memories. For singletons
            // the `recordIdentifier` canonicalizes to
            // `CloudSyncRecord.Kind.userProfile.defaultIdentifier`, so
            // any pending delete tombstone for this kind (under any
            // alias form) matches regardless of how it's stored.
            if try hasNewerLocalDeleteTombstone(
                kind: record.kind,
                recordIdentifier: record.identifier,
                inboundTimestamp: payload.updatedAt
            ) {
                recordSuppressedInboundInsert(
                    kind: record.kind,
                    recordIdentifier: record.identifier,
                    inboundTimestamp: payload.updatedAt
                )
                return
            }

            context.insert(UserProfileRecord(
                name: payload.name,
                coachingStyle: payload.coachingStyle,
                privacyMode: payload.privacyMode,
                advancementLevel: payload.advancementLevel,
                availableEquipmentCSV: payload.availableEquipmentCSV,
                preferredRepRangeLower: payload.preferredRepRangeLower,
                preferredRepRangeUpper: payload.preferredRepRangeUpper,
                sessionTimeBudgetMinutes: payload.sessionTimeBudgetMinutes,
                weeklyTrainingDays: payload.weeklyTrainingDays,
                onboardingCompleted: payload.onboardingCompleted,
                updatedAt: payload.updatedAt
            ))
        }

        try context.save()

        // VOL-67 fixup: invalidate stale queued profile writes (see
        // applyWorkout). Singleton kind — normalize the inbound
        // identifier to the canonical queue form so a legacy CK
        // record named "userProfile" still invalidates the queued
        // row stored under "profile".
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.userProfile.rawValue,
            recordIdentifier: CloudSyncRecord.Kind.userProfile.canonicalQueueIdentifier(from: record.identifier),
            olderThan: payload.updatedAt
        )
    }

    @MainActor
    private func applyTrainingPlan(_ record: CloudSyncRecord) throws {
        guard let payload = SyncPayloadCodec.decodeTrainingPlanPayload(from: record.payloadJSON) else { return }

        let context = ModelContext(trainingPlanRepository.container)
        var descriptor = FetchDescriptor<TrainingPlanRecord>()
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            guard shouldApply(
                kind: record.kind,
                identifier: record.identifier,
                localTimestamp: existing.updatedAt,
                inboundTimestamp: payload.updatedAt
            ) else { return }

            existing.workoutsJSON = payload.workoutsJSON
            existing.updatedAt = payload.updatedAt
        } else {
            // VOL-67 Codex P1 (fixup #18): tombstone-wins check.
            if try hasNewerLocalDeleteTombstone(
                kind: record.kind,
                recordIdentifier: record.identifier,
                inboundTimestamp: payload.updatedAt
            ) {
                recordSuppressedInboundInsert(
                    kind: record.kind,
                    recordIdentifier: record.identifier,
                    inboundTimestamp: payload.updatedAt
                )
                return
            }

            context.insert(TrainingPlanRecord(
                workoutsJSON: payload.workoutsJSON,
                updatedAt: payload.updatedAt
            ))
        }

        try context.save()

        // VOL-67 fixup: invalidate stale queued plan writes (see
        // applyWorkout). Singleton kind — normalize to canonical
        // queue identifier so a legacy CK record named
        // "trainingPlan" still clears the queued row stored under
        // "plan".
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.trainingPlan.rawValue,
            recordIdentifier: CloudSyncRecord.Kind.trainingPlan.canonicalQueueIdentifier(from: record.identifier),
            olderThan: payload.updatedAt
        )
    }

    @MainActor
    private func applyCoachMemory(_ record: CloudSyncRecord) throws {
        guard let payload = SyncPayloadCodec.decodeCoachMemoryPayload(from: record.payloadJSON) else { return }

        let context = ModelContext(coachMemoryRepository.container)
        var descriptor = FetchDescriptor<CoachMemoryRecord>(
            predicate: #Predicate<CoachMemoryRecord> { memory in
                memory.identifier == record.identifier
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            guard shouldApply(
                kind: record.kind,
                identifier: record.identifier,
                localTimestamp: existing.createdAt,
                inboundTimestamp: payload.createdAt
            ) else { return }

            existing.content = payload.content
            existing.theme = payload.theme
            existing.createdAt = payload.createdAt
        } else {
            // VOL-67 Codex P1 (fixup #18): tombstone-wins check — same
            // resurrection race as workouts. Skip the insert when the
            // outbound queue has a strictly newer delete for this
            // memory's identifier.
            if try hasNewerLocalDeleteTombstone(
                kind: record.kind,
                recordIdentifier: record.identifier,
                inboundTimestamp: payload.createdAt
            ) {
                recordSuppressedInboundInsert(
                    kind: record.kind,
                    recordIdentifier: record.identifier,
                    inboundTimestamp: payload.createdAt
                )
                return
            }

            context.insert(CoachMemoryRecord(
                identifier: record.identifier,
                content: payload.content,
                theme: payload.theme,
                createdAt: payload.createdAt
            ))
        }

        try context.save()

        // VOL-67 fixup: invalidate stale queued memory writes. Memories
        // use `createdAt` as the ordering field since they're append-only.
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.coachMemory.rawValue,
            recordIdentifier: record.identifier,
            olderThan: payload.createdAt
        )
    }

    @MainActor
    private func applyDeletion(_ record: CloudSyncRecord) throws {
        let context = ModelContext(workoutRepository.container)

        switch record.kind {
        case .workout:
            var descriptor = FetchDescriptor<WorkoutRecord>(
                predicate: #Predicate<WorkoutRecord> { workout in
                    workout.identifier == record.identifier
                }
            )
            descriptor.fetchLimit = 1
            if let workout = try context.fetch(descriptor).first {
                context.delete(workout)
            }
        case .userProfile:
            var descriptor = FetchDescriptor<UserProfileRecord>()
            descriptor.fetchLimit = 1
            if let profile = try context.fetch(descriptor).first {
                context.delete(profile)
            }
        case .trainingPlan:
            var descriptor = FetchDescriptor<TrainingPlanRecord>()
            descriptor.fetchLimit = 1
            if let plan = try context.fetch(descriptor).first {
                context.delete(plan)
            }
        case .coachMemory:
            var descriptor = FetchDescriptor<CoachMemoryRecord>(
                predicate: #Predicate<CoachMemoryRecord> { memory in
                    memory.identifier == record.identifier
                }
            )
            descriptor.fetchLimit = 1
            if let memory = try context.fetch(descriptor).first {
                context.delete(memory)
            }
        }

        try context.save()

        // VOL-67 fixup: unconditionally invalidate every queued entry for
        // this record. A delete is authoritative — we never want a stale
        // queued upsert to resurrect a record that was deleted on another
        // device. `olderThan: nil` clears the queue slot regardless of
        // timestamp for the exact `(recordType, recordIdentifier)`.
        // Normalize singleton identifiers to the canonical queue form
        // so a legacy CK delete for "userProfile" still clears the
        // queued "profile" row.
        try outboundQueue?.invalidateEntries(
            recordType: record.kind.rawValue,
            recordIdentifier: record.kind.canonicalQueueIdentifier(from: record.identifier),
            olderThan: nil
        )
    }

    private func shouldApply(
        kind: CloudSyncRecord.Kind,
        identifier: String,
        localTimestamp: Date,
        inboundTimestamp: Date
    ) -> Bool {
        guard localTimestamp > inboundTimestamp else { return true }

        telemetrySink?.record(TelemetryEvent(
            category: "sync",
            name: "sync_conflict_local_wins",
            severity: .info,
            message: "Dropped older inbound sync payload for \(kind.rawValue) \(identifier)",
            metadata: [
                "recordType": kind.rawValue,
                "identifier": identifier,
                "localTimestamp": ISO8601DateFormatter().string(from: localTimestamp),
                "inboundTimestamp": ISO8601DateFormatter().string(from: inboundTimestamp),
            ]
        ))

        return false
    }
}
#endif
