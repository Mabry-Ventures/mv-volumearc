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
               let kind = CloudSyncRecord.Kind(rawValue: record.recordType) {
                let modifiedAt = record.modificationDate ?? .now
                let operation = CloudSyncRecord.Operation(
                    rawValue: (record["operation"] as? String) ?? CloudSyncRecord.Operation.upsert.rawValue
                ) ?? .upsert
                changedRecords.append(CloudSyncRecord(
                    kind: kind,
                    identifier: record.recordID.recordName,
                    operation: operation,
                    payloadJSON: (record["payloadJSON"] as? String) ?? "",
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

/// Coordinates push/pull cycles between local repositories and the cloud transport.
public actor CloudSyncCoordinator {
    private let transport: CloudSyncTransport
    private let stateStore: FileSyncStateStore
    private let outboundQueue: (any OutboundSyncQueue)?

    #if canImport(SwiftData)
    private let payloadApplier: DefaultSyncPayloadApplier?

    public init(
        transport: CloudSyncTransport,
        payloadApplier: DefaultSyncPayloadApplier,
        stateStore: FileSyncStateStore,
        outboundQueue: (any OutboundSyncQueue)? = nil
    ) {
        self.transport = transport
        self.payloadApplier = payloadApplier
        self.stateStore = stateStore
        self.outboundQueue = outboundQueue
    }
    #endif

    public init(
        transport: CloudSyncTransport,
        stateStore: FileSyncStateStore,
        outboundQueue: (any OutboundSyncQueue)? = nil
    ) {
        self.transport = transport
        self.stateStore = stateStore
        self.outboundQueue = outboundQueue
        #if canImport(SwiftData)
        self.payloadApplier = nil
        #endif
    }

    /// Whether the transport is capable of syncing.
    public var isAvailable: Bool {
        transport.isAvailable
    }

    /// Push up to `limit` queued local changes and delete them only after a successful transport call.
    public func push(limit: Int = 50, additionalRecords: [CloudSyncRecord] = []) async throws -> Int {
        guard transport.isAvailable else { return 0 }

        var records = additionalRecords
        var drainedChanges: [QueuedOutboundSyncChange] = []

        if let outboundQueue {
            drainedChanges = try await MainActor.run {
                try outboundQueue.drain(limit: limit)
            }
            let queuedRecords = try drainedChanges.map(Self.makeCloudSyncRecord(from:))
            records.append(contentsOf: queuedRecords)
        }

        guard !records.isEmpty else { return 0 }

        try await transport.pushRecords(records)

        if let outboundQueue, !drainedChanges.isEmpty {
            try await MainActor.run {
                try outboundQueue.delete(ids: drainedChanges.map(\.id))
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
        #if canImport(SwiftData)
        if let payloadApplier {
            try await payloadApplier.apply(result: result)
        }
        #endif

        // 3) Persist the new cursor before pushing so a push failure
        //    can't force us to re-pull the same window twice.
        if let nextCursor = result.nextCursor {
            try? stateStore.saveCursor(nextCursor)
        }

        // 4) Push any remaining (still-valid) local changes.
        let pushedCount = try await push(additionalRecords: localRecords)

        return pushedCount + result.changedRecords.count
    }

    private static func makeCloudSyncRecord(from change: QueuedOutboundSyncChange) throws -> CloudSyncRecord {
        guard let kind = CloudSyncRecord.Kind(rawValue: change.recordType) else {
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
        let modifiedAt: Date
        if operation == .delete {
            modifiedAt = change.queuedAt
        } else {
            modifiedAt = SyncPayloadCodec.modifiedAt(for: kind, payloadJSON: change.payloadJSON) ?? change.queuedAt
        }

        return CloudSyncRecord(
            kind: kind,
            identifier: change.recordIdentifier,
            operation: operation,
            payloadJSON: change.payloadJSON,
            modifiedAt: modifiedAt
        )
    }
}

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

    @MainActor
    private func applyDeletion(identifier: String) throws {
        // Best-effort fallback for legacy deleted-record callbacks that don't
        // include a record kind.
        let context = ModelContext(workoutRepository.container)

        if identifier == CloudSyncRecord.Kind.userProfile.defaultIdentifier {
            var profileDescriptor = FetchDescriptor<UserProfileRecord>()
            profileDescriptor.fetchLimit = 1
            if let profile = try context.fetch(profileDescriptor).first {
                context.delete(profile)
            }
        }

        if identifier == CloudSyncRecord.Kind.trainingPlan.defaultIdentifier {
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
        // kind the deletion applies to, so sweep the queue for every kind
        // that matches this identifier. One of them will be a no-op.
        for kind in CloudSyncRecord.Kind.allCases {
            try outboundQueue?.invalidateEntries(
                recordType: kind.rawValue,
                recordIdentifier: identifier,
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

        // VOL-67 fixup: invalidate stale queued profile writes (see applyWorkout).
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.userProfile.rawValue,
            recordIdentifier: record.identifier,
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
            context.insert(TrainingPlanRecord(
                workoutsJSON: payload.workoutsJSON,
                updatedAt: payload.updatedAt
            ))
        }

        try context.save()

        // VOL-67 fixup: invalidate stale queued plan writes (see applyWorkout).
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.trainingPlan.rawValue,
            recordIdentifier: record.identifier,
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
        try outboundQueue?.invalidateEntries(
            recordType: record.kind.rawValue,
            recordIdentifier: record.identifier,
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
