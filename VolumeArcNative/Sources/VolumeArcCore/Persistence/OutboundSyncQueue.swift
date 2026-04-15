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
}

public struct NoOpOutboundSyncQueue: OutboundSyncQueue {
    public init() {}

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
}

public struct SwiftDataOutboundSyncQueue: OutboundSyncQueue, Sendable {
    public let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
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
        context.insert(OutboundSyncQueueRecord(
            recordType: recordType,
            recordIdentifier: recordIdentifier,
            operation: operation,
            payloadJSON: payloadJSON,
            queuedAt: queuedAt
        ))
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
