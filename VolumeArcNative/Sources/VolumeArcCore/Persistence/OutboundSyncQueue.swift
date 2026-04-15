#if canImport(SwiftData)
import Foundation
import SwiftData

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
    /// that were enqueued strictly before `olderThan`. Used by the sync
    /// applier to invalidate stale queued writes when an inbound pull
    /// delivers a newer server version. Pass `nil` for `olderThan` to
    /// remove every entry for the record regardless of timestamp — the
    /// applier uses this path on inbound deletes so a stale queued upsert
    /// can't resurrect a record deleted on another device.
    @MainActor
    func invalidateEntries(
        recordType: String,
        recordIdentifier: String,
        olderThan: Date?
    ) throws
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
        var descriptor = FetchDescriptor<OutboundSyncQueueRecord>(
            sortBy: [SortDescriptor(\.queuedAt, order: .forward)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(Self.snapshot(from:))
    }

    @MainActor
    public func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let context = ModelContext(container)
        let allRecords = try context.fetch(FetchDescriptor<OutboundSyncQueueRecord>())
        let idsToDelete = Set(ids)

        for record in allRecords where idsToDelete.contains(record.id) {
            context.delete(record)
        }

        try context.save()
    }

    @MainActor
    public func pendingRecords() throws -> [QueuedOutboundSyncChange] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<OutboundSyncQueueRecord>(
            sortBy: [SortDescriptor(\.queuedAt, order: .forward)]
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
        let descriptor = FetchDescriptor<OutboundSyncQueueRecord>()
        let rows = try context.fetch(descriptor)

        // VOL-67 Codex P2 fixup: the pull applier always calls us with
        // the current short-form `kind.rawValue`, but pre-rename queued
        // rows may still hold the legacy long-form (`userProfile`,
        // `trainingPlan`, `coachMemory`). Resolve both sides to a `Kind`
        // via `Kind.parse(_:)` so that a short-form call (e.g.,
        // `"profile"`) also matches rows stored with the long form
        // (`"userProfile"`). Without this, legacy rows would never be
        // invalidated and the next push would resend stale payloads
        // over newer server state.
        let targetKind = CloudSyncRecord.Kind.parse(recordType)

        var removed = 0
        for row in rows {
            guard row.recordIdentifier == recordIdentifier else { continue }

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

            if let olderThan, row.queuedAt >= olderThan {
                continue
            }
            context.delete(row)
            removed += 1
        }

        if removed > 0 {
            try context.save()
        }
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
