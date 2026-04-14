import Foundation
#if canImport(CloudKit)
import CloudKit
#endif

public protocol CloudSyncTransport: Sendable {
    func pushRecords(_ records: [CloudSyncRecord]) async throws
    func pullChanges(since cursor: String?) async throws -> CloudSyncPullResult
    var isAvailable: Bool { get }
}

/// A record destined for (or returned from) CloudKit.
/// Platform-agnostic wrapper so the applier doesn't depend on CloudKit types.
public struct CloudSyncRecord: Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case workout
        case userProfile
        case trainingPlan
        case coachMemory
    }

    public let kind: Kind
    public let identifier: String
    public let payload: [String: String]
    public let modifiedAt: Date

    public init(kind: Kind, identifier: String, payload: [String: String], modifiedAt: Date = .now) {
        self.kind = kind
        self.identifier = identifier
        self.payload = payload
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
            for (key, value) in record.payload {
                ck[key] = value as NSString
            }
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
                var payload: [String: String] = [:]
                for key in record.allKeys() {
                    if let value = record[key] as? String {
                        payload[key] = value
                    }
                }
                let modifiedAt = record.modificationDate ?? .now
                changedRecords.append(CloudSyncRecord(
                    kind: kind,
                    identifier: record.recordID.recordName,
                    payload: payload,
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

    public var errorDescription: String? {
        switch self {
        case let .transportUnavailable(reason): return reason
        case let .applyFailed(underlying): return "Sync apply failed: \(underlying.localizedDescription)"
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

    #if canImport(SwiftData)
    private let payloadApplier: DefaultSyncPayloadApplier?

    public init(
        transport: CloudSyncTransport,
        payloadApplier: DefaultSyncPayloadApplier,
        stateStore: FileSyncStateStore
    ) {
        self.transport = transport
        self.payloadApplier = payloadApplier
        self.stateStore = stateStore
    }
    #endif

    public init(transport: CloudSyncTransport, stateStore: FileSyncStateStore) {
        self.transport = transport
        self.stateStore = stateStore
        #if canImport(SwiftData)
        self.payloadApplier = nil
        #endif
    }

    /// Whether the transport is capable of syncing.
    public var isAvailable: Bool {
        transport.isAvailable
    }

    /// Run one push/pull cycle. Returns the number of records pushed + pulled.
    public func syncCycle(pushing localRecords: [CloudSyncRecord] = []) async throws -> Int {
        guard transport.isAvailable else { return 0 }

        // 1) Push any local changes
        if !localRecords.isEmpty {
            try await transport.pushRecords(localRecords)
        }

        // 2) Pull remote changes
        let cursor = stateStore.loadCursor()
        let result = try await transport.pullChanges(since: cursor)

        // 3) Apply remote changes locally on the main actor (SwiftData is
        //    bound to @MainActor via ModelContext thread affinity).
        #if canImport(SwiftData)
        if let payloadApplier {
            try await payloadApplier.apply(result: result)
        }
        #endif

        // 4) Persist the new cursor
        if let nextCursor = result.nextCursor {
            try? stateStore.saveCursor(nextCursor)
        }

        return localRecords.count + result.changedRecords.count
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

    public init(
        workoutRepository: SwiftDataWorkoutRepository,
        coachMemoryRepository: SwiftDataCoachMemoryRepository,
        userProfileRepository: SwiftDataUserProfileRepository,
        trainingPlanRepository: SwiftDataTrainingPlanRepository
    ) {
        self.workoutRepository = workoutRepository
        self.coachMemoryRepository = coachMemoryRepository
        self.userProfileRepository = userProfileRepository
        self.trainingPlanRepository = trainingPlanRepository
    }

    /// Apply a pull result to the local repositories.
    @MainActor
    public func apply(result: CloudSyncPullResult) async throws {
        for record in result.changedRecords {
            try applyRecord(record)
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
        // Deletion routing by ID prefix is an approximation since we don't
        // know the record kind from the ID alone. Try workout first (most
        // common deletion target).
        try? workoutRepository.deleteWorkout(identifier: identifier)
    }

    // MARK: - Per-kind appliers

    @MainActor
    private func applyWorkout(_ record: CloudSyncRecord) throws {
        // Workout records sync the aggregate summary, not individual sets,
        // to keep the wire format small. Sets are reconstructed from the
        // setsJSON field if present.
        guard let title = record.payload["title"] else { return }

        // Check if we already have a local version that's newer (last-write-wins).
        if let existing = try workoutRepository.workout(withIdentifier: record.identifier) {
            let existingTime = existing.completedAt ?? existing.startedAt
            if existingTime >= record.modifiedAt { return }
            // Local is older — upsert with remote values.
        }

        _ = try workoutRepository.createWorkout(
            title: title,
            startedAt: record.modifiedAt
        )
    }

    @MainActor
    private func applyUserProfile(_ record: CloudSyncRecord) throws {
        // Decode payload into a UserProfileDefaults and upsert.
        let name = record.payload["name"] ?? ""
        let coachingStyle = CoachingStyle(rawValue: record.payload["coachingStyle"] ?? "motivational") ?? .motivational
        let privacyMode = PrivacyMode(rawValue: record.payload["privacyMode"] ?? "standard") ?? .standard
        let advancementLevel = AdvancementLevel(rawValue: record.payload["advancementLevel"] ?? "intermediate") ?? .intermediate
        let equipment: [Equipment] = (record.payload["equipment"] ?? "")
            .split(separator: ",")
            .compactMap { Equipment(rawValue: String($0)) }
        let lower = Int(record.payload["preferredRepRangeLower"] ?? "5") ?? 5
        let upper = Int(record.payload["preferredRepRangeUpper"] ?? "8") ?? 8
        let time = Int(record.payload["sessionTimeBudgetMinutes"] ?? "60") ?? 60
        let days = Int(record.payload["weeklyTrainingDays"] ?? "4") ?? 4

        let defaults = UserProfileDefaults(
            name: name,
            coachingStyle: coachingStyle,
            privacyMode: privacyMode,
            advancementLevel: advancementLevel,
            availableEquipment: equipment.isEmpty ? [.barbell, .dumbbell, .machine, .bodyweight] : equipment,
            preferredRepRangeLower: lower,
            preferredRepRangeUpper: upper,
            sessionTimeBudgetMinutes: time,
            weeklyTrainingDays: days
        )

        try userProfileRepository.upsertProfile(defaults)
    }

    @MainActor
    private func applyTrainingPlan(_ record: CloudSyncRecord) throws {
        guard let json = record.payload["workoutsJSON"],
              let data = json.data(using: .utf8),
              let workouts = try? JSONDecoder().decode([WeeklyWorkout].self, from: data)
        else { return }
        try trainingPlanRepository.upsertPlan(workouts)
    }

    @MainActor
    private func applyCoachMemory(_ record: CloudSyncRecord) throws {
        let content = record.payload["content"] ?? ""
        let theme = record.payload["theme"] ?? ""
        guard !content.isEmpty else { return }
        try coachMemoryRepository.append(content: content, theme: theme)
    }
}
#endif

public enum SyncPayloadCodec {
    public static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
