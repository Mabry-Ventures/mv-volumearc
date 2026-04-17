#if canImport(SwiftData)
import Foundation
import SwiftData

/// VOL-67 Codex P2 (fixup #28): thrown by repository `stageUpsert`
/// helpers when `SyncPayloadCodec.encode*Payload(from:)` returns nil
/// for a primary record mutation — i.e., the record can't be
/// serialized to a valid outbound queue payload (malformed fields,
/// non-finite `Double`, etc.). The caller must propagate this error
/// up to the repository method's `throws` signature so `context.save()`
/// never runs and the primary record mutation is rolled back along
/// with the queue row insertion, guaranteeing atomic "record + queue
/// row" semantics. Without this, a local write could commit without
/// its corresponding outbound row and silently never sync.
public enum OutboundQueueStagingError: Error, LocalizedError {
    case payloadEncodingFailed(recordType: String, recordIdentifier: String)

    public var errorDescription: String? {
        switch self {
        case let .payloadEncodingFailed(recordType, recordIdentifier):
            return "Failed to encode outbound queue payload for \(recordType) \(recordIdentifier); refusing to commit local write without a matching sync row."
        }
    }
}

@Model
public final class OutboundSyncQueueRecord {
    public var id: UUID = UUID()
    public var recordType: String = ""
    public var recordIdentifier: String = ""
    public var operation: String = ""
    public var payloadJSON: String = ""
    public var queuedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        recordType: String = "",
        recordIdentifier: String = "",
        operation: String = "",
        payloadJSON: String = "",
        queuedAt: Date = .now
    ) {
        self.id = id
        self.recordType = recordType
        self.recordIdentifier = recordIdentifier
        self.operation = operation
        self.payloadJSON = payloadJSON
        self.queuedAt = queuedAt
    }
}

public struct QueuedOutboundSyncChange: Sendable, Equatable {
    public let id: UUID
    public let recordType: String
    public let recordIdentifier: String
    public let operation: String
    public let payloadJSON: String
    public let queuedAt: Date

    public init(
        id: UUID,
        recordType: String,
        recordIdentifier: String,
        operation: String,
        payloadJSON: String,
        queuedAt: Date
    ) {
        self.id = id
        self.recordType = recordType
        self.recordIdentifier = recordIdentifier
        self.operation = operation
        self.payloadJSON = payloadJSON
        self.queuedAt = queuedAt
    }
}

public protocol OutboundSyncQueue: Sendable {
    /// Atomic-write helper: inserts a queue row into a caller-owned
    /// `ModelContext` without saving. The caller is expected to save
    /// the context after staging, which means the primary record
    /// write and the queue row commit in the SAME SwiftData
    /// transaction. VOL-67 Codex P2: without this, a save-then-enqueue
    /// pattern could leave the local record persisted but the queue
    /// row missing (and the mutation would never reach CloudKit) if
    /// the queue write failed after the record write succeeded.
    @MainActor
    func stage(
        into context: ModelContext,
        recordType: String,
        recordIdentifier: String,
        operation: String,
        payloadJSON: String,
        queuedAt: Date
    )

    /// Standalone enqueue that creates its own context and saves.
    /// Kept for callers (notably tests) that want to prepopulate the
    /// queue without owning a repository context. Production
    /// repository mutations should use `stage(into:)` for atomicity.
    @MainActor
    func enqueue(
        recordType: String,
        recordIdentifier: String,
        operation: String,
        payloadJSON: String,
        queuedAt: Date
    ) throws

    @MainActor
    func drain(limit: Int) throws -> [QueuedOutboundSyncChange]

    @MainActor
    func delete(ids: [UUID]) throws

    @MainActor
    func pendingRecords() throws -> [QueuedOutboundSyncChange]

    /// Remove queued entries for a given `recordType` + `recordIdentifier`
    /// whose `queuedAt` is `<=` `olderThan`. Ties (`queuedAt == olderThan`)
    /// ARE invalidated so the queue's tie-breaking semantics match
    /// `DefaultSyncPayloadApplier.shouldApply`, which uses strict `>` for
    /// its "local newer" branch (i.e., inbound wins on equal timestamps).
    /// See fixup #6 regression test
    /// `testInvalidateEntriesDropsRowsOnExactTimestampTies` — a
    /// same-timestamp queue row that survives invalidation would be
    /// re-sent on the next push and clobber the freshly-applied inbound
    /// state.
    ///
    /// Used by the sync applier to invalidate stale queued writes when
    /// an inbound pull delivers a newer server version. Pass `nil` for
    /// `olderThan` to remove every entry for the record regardless of
    /// timestamp — the applier uses this path on inbound deletes so a
    /// stale queued upsert can't resurrect a record deleted on another
    /// device.
    @MainActor
    func invalidateEntries(
        recordType: String,
        recordIdentifier: String,
        olderThan: Date?
    ) throws

    /// VOL-67 Copilot (fixup #19): targeted probe for a pending delete
    /// tombstone whose `queuedAt` is strictly newer than `newerThan`.
    /// Returns `true` if ANY queue row matches
    /// `(recordIdentifier in: candidateIdentifiers)` AND
    /// `operation == "delete"` AND `queuedAt > newerThan` AND
    /// (`recordType in: candidateRecordTypes` OR `candidateRecordTypes`
    /// is empty). The applier uses this in its tombstone-wins check
    /// (see `DefaultSyncPayloadApplier.hasNewerLocalDeleteTombstone`)
    /// instead of scanning the full pending queue on every inbound
    /// insert — which would be O(n) per inbound record on devices
    /// with a large offline backlog.
    ///
    /// Callers pass the canonical-form identifier plus any known
    /// legacy-form aliases so the lookup catches tombstones stored
    /// under either shape. Same for `candidateRecordTypes`: a caller
    /// doing a lookup for `.userProfile` would pass
    /// `["profile", "userProfile"]` so legacy long-form rows
    /// still match.
    @MainActor
    func hasPendingDeleteTombstone(
        candidateRecordTypes: Set<String>,
        candidateIdentifiers: Set<String>,
        newerThan: Date
    ) throws -> Bool
}

public struct NoOpOutboundSyncQueue: OutboundSyncQueue {
    public init() {}

    @MainActor
    public func stage(
        into context: ModelContext,
        recordType: String,
        recordIdentifier: String,
        operation: String,
        payloadJSON: String,
        queuedAt: Date
    ) {}

    @MainActor
    public func enqueue(
        recordType: String,
        recordIdentifier: String,
        operation: String,
        payloadJSON: String,
        queuedAt: Date
    ) throws {}

    @MainActor
    public func drain(limit: Int) throws -> [QueuedOutboundSyncChange] { [] }

    @MainActor
    public func delete(ids: [UUID]) throws {}

    @MainActor
    public func pendingRecords() throws -> [QueuedOutboundSyncChange] { [] }

    @MainActor
    public func invalidateEntries(
        recordType: String,
        recordIdentifier: String,
        olderThan: Date?
    ) throws {}

    @MainActor
    public func hasPendingDeleteTombstone(
        candidateRecordTypes: Set<String>,
        candidateIdentifiers: Set<String>,
        newerThan: Date
    ) throws -> Bool { false }
}

public struct SwiftDataOutboundSyncQueue: OutboundSyncQueue, Sendable {
    public let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    @MainActor
    public func stage(
        into context: ModelContext,
        recordType: String,
        recordIdentifier: String,
        operation: String,
        payloadJSON: String,
        queuedAt: Date = .now
    ) {
        context.insert(OutboundSyncQueueRecord(
            recordType: recordType,
            recordIdentifier: recordIdentifier,
            operation: operation,
            payloadJSON: payloadJSON,
            queuedAt: queuedAt
        ))
    }

    @MainActor
    public func enqueue(
        recordType: String,
        recordIdentifier: String,
        operation: String,
        payloadJSON: String,
        queuedAt: Date = .now
    ) throws {
        let context = ModelContext(container)
        stage(
            into: context,
            recordType: recordType,
            recordIdentifier: recordIdentifier,
            operation: operation,
            payloadJSON: payloadJSON,
            queuedAt: queuedAt
        )
        try context.save()
    }

    @MainActor
    public func drain(limit: Int) throws -> [QueuedOutboundSyncChange] {
        let context = ModelContext(container)
        // VOL-67 Copilot (fixup #34): secondary sort by `id` makes
        // ordering deterministic for rows with the same `queuedAt`
        // (e.g., `.distantPast`-clamped singletons, fast successive
        // writes, clock granularity). Without it, SwiftData is free
        // to return tied rows in arbitrary order, which makes the
        // push path's "later wins" coalescing non-deterministic.
        var descriptor = FetchDescriptor<OutboundSyncQueueRecord>(
            sortBy: [
                SortDescriptor(\.queuedAt, order: .forward),
                SortDescriptor(\.id, order: .forward),
            ]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(Self.snapshot(from:))
    }

    @MainActor
    public func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let context = ModelContext(container)
        // VOL-67 Copilot perf P2 (fixup #11): narrow via a
        // `#Predicate` that matches the target ID set directly
        // instead of scanning every queued row. Called on every
        // successful push; scanning the whole queue on each push
        // turns O(1) deletes into O(n) work on offline-backlog
        // devices.
        let idsToDelete = ids
        let descriptor = FetchDescriptor<OutboundSyncQueueRecord>(
            predicate: #Predicate<OutboundSyncQueueRecord> { record in
                idsToDelete.contains(record.id)
            }
        )
        let recordsToDelete = try context.fetch(descriptor)

        for record in recordsToDelete {
            context.delete(record)
        }

        try context.save()
    }

    @MainActor
    public func pendingRecords() throws -> [QueuedOutboundSyncChange] {
        let context = ModelContext(container)
        // VOL-67 Copilot (fixup #34): same secondary sort as drain().
        let descriptor = FetchDescriptor<OutboundSyncQueueRecord>(
            sortBy: [
                SortDescriptor(\.queuedAt, order: .forward),
                SortDescriptor(\.id, order: .forward),
            ]
        )
        return try context.fetch(descriptor).map(Self.snapshot(from:))
    }

    @MainActor
    public func invalidateEntries(
        recordType: String,
        recordIdentifier: String,
        olderThan: Date?
    ) throws {
        let context = ModelContext(container)

        // VOL-67 Copilot P2 (fixup #11): fetch rows whose
        // `recordIdentifier` matches ANY known alias form for the
        // target kind, not just the canonical passed-in identifier.
        //
        // Fixup #9 added a `#Predicate` narrowing the fetch by
        // `row.recordIdentifier == targetIdentifier` to avoid the
        // O(n) scan. But the applier calls this with the canonical
        // short form ("profile" / "plan") while legacy queue rows
        // may be stored with long-form identifiers ("userProfile" /
        // "trainingPlan"). The narrowed predicate silently missed
        // those rows, leaving stale legacy-form entries in the
        // queue to be pushed on the next sync.
        //
        // Build a set of candidate identifiers: the passed identifier
        // plus every known alias for the resolved kind's singleton
        // forms. For per-record (non-singleton) kinds we only need
        // the passed identifier because workout / memory IDs are
        // UUID-style and don't have canonical aliases.
        let targetKind = CloudSyncRecord.Kind.parse(recordType)
        let candidateIdentifiers: Set<String> = {
            var set: Set<String> = [recordIdentifier]
            guard let kind = targetKind, kind.isSingleton else { return set }
            set.insert(kind.defaultIdentifier)
            switch kind {
            case .userProfile:
                set.insert("userProfile")
            case .trainingPlan:
                set.insert("trainingPlan")
            case .workout, .coachMemory:
                break
            }
            return set
        }()

        let candidatesDescriptor = FetchDescriptor<OutboundSyncQueueRecord>(
            predicate: #Predicate<OutboundSyncQueueRecord> { row in
                candidateIdentifiers.contains(row.recordIdentifier)
            }
        )
        let rows = try context.fetch(candidatesDescriptor)

        // VOL-67 Codex P2 fixup: the pull applier always calls us with
        // the current short-form `kind.rawValue`, but pre-rename queued
        // rows may still hold the legacy long-form (`userProfile`,
        // `trainingPlan`, `coachMemory`). Resolve both sides to a `Kind`
        // via `Kind.parse(_:)` so that a short-form call (e.g.,
        // `"profile"`) also matches rows stored with the long form
        // (`"userProfile"`). Without this, legacy rows would never be
        // invalidated and the next push would resend stale payloads
        // over newer server state.

        var removed = 0
        for row in rows {
            let rowKind = CloudSyncRecord.Kind.parse(row.recordType)
            // Match by resolved kind when both sides parse; fall back to
            // exact string match for unknown/future record types.
            let matches: Bool
            if let targetKind, let rowKind {
                matches = targetKind == rowKind
            } else {
                matches = row.recordType == recordType
            }
            guard matches else { continue }

            // VOL-67 Codex P2 fixup: strict greater-than matches the
            // applier's `shouldApply` semantics (inbound wins on ties).
            // With `>=` we'd keep same-timestamp rows even though the
            // applier just applied the inbound record — the row would
            // then be resent on the next push and overwrite the freshly
            // applied state. Strict `>` drops the row on equal
            // timestamps, consistent with "inbound wins ties".
            if let olderThan, row.queuedAt > olderThan {
                continue
            }
            context.delete(row)
            removed += 1
        }

        if removed > 0 {
            try context.save()
        }
    }

    @MainActor
    public func hasPendingDeleteTombstone(
        candidateRecordTypes: Set<String>,
        candidateIdentifiers: Set<String>,
        newerThan: Date
    ) throws -> Bool {
        // VOL-67 Copilot (fixup #19): targeted `#Predicate` narrowing the
        // fetch to rows that could plausibly match before doing any
        // application-level filtering. The applier calls this on every
        // inbound upsert whose local record doesn't exist; on devices
        // with a large offline backlog, scanning `pendingRecords()` and
        // filtering in-process was O(n) per inbound record and could
        // substantially slow the pull/apply phase. The predicate pushes
        // the identifier + operation + timestamp filter into SwiftData,
        // so the fetch returns only the handful of rows that could
        // actually be newer-than-inbound delete tombstones.
        //
        // The record-type comparison is left to the caller side because
        // `#Predicate` can't reference an external `Set<String>` for
        // multi-value equality across a captured array reliably in
        // some SwiftData versions, but matching by identifier +
        // operation + timestamp is sufficient to narrow the fetch to
        // O(1)-ish in practice (queue rows are keyed by identifier,
        // and delete tombstones are rare compared to upserts). We then
        // verify the recordType matches `candidateRecordTypes` in Swift
        // before returning — over an already-narrowed row set.
        //
        // VOL-67 Codex P2 (fixup #30): REMOVED the `fetchLimit = 1`
        // that fixup #19 added as an optimization. With the cap, if
        // multiple queue rows shared an identifier but differed in
        // record type (unlikely but possible), the fetch could return
        // the wrong row first and the in-memory record-type filter
        // would incorrectly yield `false`. That would let an inbound
        // upsert bypass the tombstone-wins safeguard and reinsert a
        // locally-deleted record. The identifier + operation +
        // timestamp predicate still narrows to a handful of rows in
        // practice, and the in-memory type filter runs over that
        // narrow set — correct in every case.
        guard !candidateIdentifiers.isEmpty else { return false }

        let context = ModelContext(container)
        let deleteOp = CloudSyncRecord.Operation.delete.rawValue
        let idsToMatch = candidateIdentifiers
        let threshold = newerThan

        let descriptor = FetchDescriptor<OutboundSyncQueueRecord>(
            predicate: #Predicate<OutboundSyncQueueRecord> { row in
                idsToMatch.contains(row.recordIdentifier) &&
                row.operation == deleteOp &&
                row.queuedAt > threshold
            }
        )

        // If the caller restricted record types, do the final filter
        // in-process — the narrowed fetch makes this trivial.
        let candidateRows = try context.fetch(descriptor)
        if candidateRecordTypes.isEmpty {
            return !candidateRows.isEmpty
        }
        return candidateRows.contains { candidateRecordTypes.contains($0.recordType) }
    }

    private static func snapshot(from record: OutboundSyncQueueRecord) -> QueuedOutboundSyncChange {
        QueuedOutboundSyncChange(
            id: record.id,
            recordType: record.recordType,
            recordIdentifier: record.recordIdentifier,
            operation: record.operation,
            payloadJSON: record.payloadJSON,
            queuedAt: record.queuedAt
        )
    }
}
#endif
