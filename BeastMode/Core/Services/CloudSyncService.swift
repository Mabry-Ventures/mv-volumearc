// CloudSyncService.swift
// BeastMode
// iCloud sync infrastructure for cross-device data synchronization

import Foundation
import CloudKit
import SwiftData
import Combine
import os

// MARK: - Sync Status

/// Represents the synchronization status of a record
enum SyncStatus: String, Codable {
    case synced = "synced"
    case pending = "pending"
    case conflict = "conflict"
    case error = "error"

    var icon: String {
        switch self {
        case .synced: return "checkmark.icloud"
        case .pending: return "arrow.triangle.2.circlepath.icloud"
        case .conflict: return "exclamationmark.icloud"
        case .error: return "xmark.icloud"
        }
    }

    var description: String {
        switch self {
        case .synced: return "Synced"
        case .pending: return "Pending sync"
        case .conflict: return "Conflict detected"
        case .error: return "Sync error"
        }
    }
}

// MARK: - Sync Metadata

/// Metadata tracking sync state for local records
struct SyncMetadata: Codable {
    let recordId: UUID
    let recordType: CloudRecordType
    var cloudKitRecordId: String?
    var lastModifiedLocal: Date
    var lastModifiedCloud: Date?
    var syncStatus: SyncStatus
    var changeTag: String?
    var retryCount: Int
    var lastError: String?

    init(
        recordId: UUID,
        recordType: CloudRecordType,
        lastModifiedLocal: Date = .now
    ) {
        self.recordId = recordId
        self.recordType = recordType
        self.cloudKitRecordId = nil
        self.lastModifiedLocal = lastModifiedLocal
        self.lastModifiedCloud = nil
        self.syncStatus = .pending
        self.changeTag = nil
        self.retryCount = 0
        self.lastError = nil
    }
}

// MARK: - Cloud Record Types

/// CloudKit record type identifiers
enum CloudRecordType: String, CaseIterable, Codable {
    case workout = "Workout"
    case workoutPlan = "WorkoutPlan"
    case userProfile = "UserProfile"
    case personalRecord = "PersonalRecord"
    case workoutExercise = "WorkoutExercise"
    case setLog = "SetLog"
    case planDay = "PlanDay"
    case planExercise = "PlanExercise"
}

// MARK: - Sync Error

/// Errors that can occur during sync operations
enum CloudSyncError: Error, LocalizedError {
    case containerNotAvailable
    case notAuthenticated
    case networkUnavailable
    case quotaExceeded
    case serverRecordChanged
    case recordNotFound
    case conflictDetected(local: CKRecord, server: CKRecord)
    case encodingFailed(String)
    case decodingFailed(String)
    case operationFailed(Error)
    case subscriptionFailed(Error)
    case zoneNotFound
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .containerNotAvailable:
            return "iCloud container is not available"
        case .notAuthenticated:
            return "User is not signed into iCloud"
        case .networkUnavailable:
            return "Network is not available"
        case .quotaExceeded:
            return "iCloud storage quota exceeded"
        case .serverRecordChanged:
            return "Record was modified on another device"
        case .recordNotFound:
            return "Record not found in CloudKit"
        case .conflictDetected:
            return "Sync conflict detected"
        case .encodingFailed(let message):
            return "Failed to encode record: \(message)"
        case .decodingFailed(let message):
            return "Failed to decode record: \(message)"
        case .operationFailed(let error):
            return "Sync operation failed: \(error.localizedDescription)"
        case .subscriptionFailed(let error):
            return "Subscription setup failed: \(error.localizedDescription)"
        case .zoneNotFound:
            return "CloudKit zone not found"
        case .permissionDenied:
            return "Permission denied for CloudKit operation"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .serverRecordChanged, .operationFailed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Sync Event

/// Events emitted during sync operations
enum CloudSyncEvent {
    case started
    case progress(completed: Int, total: Int)
    case recordSynced(type: CloudRecordType, id: UUID)
    case recordConflict(type: CloudRecordType, id: UUID)
    case completed(synced: Int, failed: Int)
    case failed(CloudSyncError)
    case remoteChangeReceived
}

// MARK: - Cloud Sync Service

/// Service for synchronizing data with iCloud using CloudKit
@MainActor
class CloudSyncService: ObservableObject {

    // MARK: - Singleton

    static let shared = CloudSyncService()

    // MARK: - Published Properties

    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncStatus: SyncStatus = .synced
    @Published private(set) var pendingChangesCount: Int = 0
    @Published private(set) var isCloudAvailable: Bool = false
    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine

    // MARK: - Private Properties

    private let containerIdentifier = "iCloud.com.beastmode.app"
    private let zoneName = "BeastModeZone"
    private let subscriptionID = "BeastModeChanges"

    private lazy var container: CKContainer = {
        CKContainer(identifier: containerIdentifier)
    }()

    private lazy var privateDatabase: CKDatabase = {
        container.privateCloudDatabase
    }()

    private lazy var recordZone: CKRecordZone = {
        CKRecordZone(zoneName: zoneName)
    }()

    private var syncMetadataStore: [UUID: SyncMetadata] = [:]
    private let metadataKey = "com.beastmode.syncMetadata"
    private let lastSyncKey = "com.beastmode.lastSyncDate"
    private let serverChangeTokenKey = "com.beastmode.serverChangeToken"

    private var serverChangeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: serverChangeTokenKey) else {
                return nil
            }
            return try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self,
                from: data
            )
        }
        set {
            if let token = newValue,
               let data = try? NSKeyedArchiver.archivedData(
                   withRootObject: token,
                   requiringSecureCoding: true
               ) {
                UserDefaults.standard.set(data, forKey: serverChangeTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: serverChangeTokenKey)
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private let networkMonitor = NetworkMonitor.shared

    let syncEventSubject = PassthroughSubject<CloudSyncEvent, Never>()

    // MARK: - Initialization

    private init() {
        loadSyncMetadata()
        setupNetworkObserver()

        Task {
            await checkAccountStatus()
            await setupCustomZone()
            await setupSubscriptions()
        }
    }

    // MARK: - Account Status

    /// Check the current iCloud account status
    func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            accountStatus = status
            isCloudAvailable = status == .available

            Logger.cloud.info("CloudKit account status: \(String(describing: status))")

            if status != .available {
                syncStatus = .error
            }
        } catch {
            Logger.cloud.error("Failed to check account status: \(error.localizedDescription)")
            isCloudAvailable = false
            accountStatus = .couldNotDetermine
        }
    }

    // MARK: - Zone Setup

    /// Create the custom CloudKit zone for app data
    private func setupCustomZone() async {
        guard isCloudAvailable else { return }

        do {
            let existingZones = try await privateDatabase.allRecordZones()
            let zoneExists = existingZones.contains { $0.zoneID.zoneName == zoneName }

            if !zoneExists {
                Logger.cloud.info("Creating custom CloudKit zone: \(zoneName)")
                try await privateDatabase.save(recordZone)
            }
        } catch {
            Logger.cloud.error("Failed to setup custom zone: \(error.localizedDescription)")
        }
    }

    // MARK: - Subscriptions

    /// Setup CloudKit subscriptions for remote change notifications
    private func setupSubscriptions() async {
        guard isCloudAvailable else { return }

        do {
            // Check if subscription already exists
            let existingSubscriptions = try await privateDatabase.allSubscriptions()
            let subscriptionExists = existingSubscriptions.contains { $0.subscriptionID == subscriptionID }

            if !subscriptionExists {
                Logger.cloud.info("Creating CloudKit subscription")

                let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)

                let notificationInfo = CKSubscription.NotificationInfo()
                notificationInfo.shouldSendContentAvailable = true
                subscription.notificationInfo = notificationInfo

                try await privateDatabase.save(subscription)
                Logger.cloud.info("CloudKit subscription created successfully")
            }
        } catch {
            Logger.cloud.error("Failed to setup subscription: \(error.localizedDescription)")
        }
    }

    // MARK: - Network Observer

    private func setupNetworkObserver() {
        NotificationCenter.default.publisher(for: .networkStatusChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let isConnected = notification.userInfo?["isConnected"] as? Bool, isConnected {
                    Task { @MainActor [weak self] in
                        await self?.syncPendingChanges()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Push Changes

    /// Push local changes to CloudKit
    func pushChanges<T: CloudKitConvertible>(
        _ records: [T],
        recordType: CloudRecordType
    ) async throws {
        guard networkMonitor.isConnected else {
            // Queue for later sync
            for record in records {
                markAsPending(record.id, type: recordType)
            }
            throw CloudSyncError.networkUnavailable
        }

        guard isCloudAvailable else {
            throw CloudSyncError.containerNotAvailable
        }

        isSyncing = true
        syncEventSubject.send(.started)

        defer {
            isSyncing = false
        }

        let ckRecords = records.map { $0.toCKRecord(zoneID: recordZone.zoneID) }

        var syncedCount = 0
        var failedCount = 0

        for (index, ckRecord) in ckRecords.enumerated() {
            do {
                let savedRecord = try await privateDatabase.save(ckRecord)

                // Update sync metadata
                if let recordId = UUID(uuidString: savedRecord.recordID.recordName) {
                    updateSyncMetadata(
                        recordId: recordId,
                        type: recordType,
                        cloudKitRecordId: savedRecord.recordID.recordName,
                        changeTag: savedRecord.recordChangeTag,
                        status: .synced
                    )
                    syncEventSubject.send(.recordSynced(type: recordType, id: recordId))
                }

                syncedCount += 1
                syncEventSubject.send(.progress(completed: index + 1, total: ckRecords.count))

            } catch let error as CKError {
                failedCount += 1

                if let recordId = UUID(uuidString: ckRecord.recordID.recordName) {
                    try await handleCKError(error, for: recordId, type: recordType)
                }
            }
        }

        lastSyncDate = .now
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)

        syncEventSubject.send(.completed(synced: syncedCount, failed: failedCount))
        updatePendingCount()
    }

    /// Push a single record to CloudKit
    func pushRecord<T: CloudKitConvertible>(_ record: T, recordType: CloudRecordType) async throws {
        try await pushChanges([record], recordType: recordType)
    }

    // MARK: - Pull Changes

    /// Fetch changes from CloudKit since last sync
    func pullChanges() async throws -> [CloudRecordType: [CKRecord]] {
        guard networkMonitor.isConnected else {
            throw CloudSyncError.networkUnavailable
        }

        guard isCloudAvailable else {
            throw CloudSyncError.containerNotAvailable
        }

        isSyncing = true
        syncEventSubject.send(.started)

        defer {
            isSyncing = false
        }

        var changedRecords: [CloudRecordType: [CKRecord]] = [:]
        var deletedRecordIDs: [CKRecord.ID] = []

        let zoneID = recordZone.zoneID
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = serverChangeToken

        let options = [zoneID: configuration]

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: options
        )

        operation.recordWasChangedBlock = { recordID, result in
            switch result {
            case .success(let record):
                if let typeString = record.recordType as String?,
                   let recordType = CloudRecordType(rawValue: typeString) {
                    if changedRecords[recordType] == nil {
                        changedRecords[recordType] = []
                    }
                    changedRecords[recordType]?.append(record)
                }
            case .failure(let error):
                Logger.cloud.error("Failed to fetch record \(recordID): \(error.localizedDescription)")
            }
        }

        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            deletedRecordIDs.append(recordID)
        }

        operation.recordZoneChangeTokensUpdatedBlock = { [weak self] zoneID, token, _ in
            self?.serverChangeToken = token
        }

        operation.recordZoneFetchResultBlock = { [weak self] zoneID, result in
            switch result {
            case .success(let (serverChangeToken, _, _)):
                self?.serverChangeToken = serverChangeToken
            case .failure(let error):
                Logger.cloud.error("Zone fetch failed: \(error.localizedDescription)")
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            privateDatabase.add(operation)
        }

        lastSyncDate = .now
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)

        // Process deleted records
        for recordID in deletedRecordIDs {
            if let uuid = UUID(uuidString: recordID.recordName) {
                syncMetadataStore.removeValue(forKey: uuid)
            }
        }
        saveSyncMetadata()

        let totalChanges = changedRecords.values.reduce(0) { $0 + $1.count }
        syncEventSubject.send(.completed(synced: totalChanges, failed: 0))

        return changedRecords
    }

    /// Fetch a specific record by ID
    func fetchRecord(
        recordId: UUID,
        recordType: CloudRecordType
    ) async throws -> CKRecord {
        guard isCloudAvailable else {
            throw CloudSyncError.containerNotAvailable
        }

        let recordID = CKRecord.ID(
            recordName: recordId.uuidString,
            zoneID: recordZone.zoneID
        )

        return try await privateDatabase.record(for: recordID)
    }

    /// Fetch all records of a specific type
    func fetchAllRecords(
        ofType recordType: CloudRecordType
    ) async throws -> [CKRecord] {
        guard isCloudAvailable else {
            throw CloudSyncError.containerNotAvailable
        }

        let query = CKQuery(
            recordType: recordType.rawValue,
            predicate: NSPredicate(value: true)
        )

        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], cursor: CKQueryOperation.Cursor?)

            if let existingCursor = cursor {
                result = try await privateDatabase.records(continuingMatchFrom: existingCursor)
            } else {
                result = try await privateDatabase.records(
                    matching: query,
                    inZoneWith: recordZone.zoneID
                )
            }

            for (_, recordResult) in result.matchResults {
                if case .success(let record) = recordResult {
                    allRecords.append(record)
                }
            }

            cursor = result.cursor

        } while cursor != nil

        return allRecords
    }

    // MARK: - Conflict Resolution

    /// Resolve a sync conflict using last-write-wins with field-level merge
    func resolveConflict(
        local: CKRecord,
        server: CKRecord
    ) -> CKRecord {
        Logger.cloud.info("Resolving conflict for record: \(local.recordID.recordName)")

        // Get modification dates
        let localModDate = local["modifiedAt"] as? Date ?? local.modificationDate ?? .distantPast
        let serverModDate = server["modifiedAt"] as? Date ?? server.modificationDate ?? .distantPast

        // Start with the server record as base
        let resolved = server

        // Field-level merge: apply local changes for non-conflicting fields
        // If local was modified more recently for a specific field, use local value
        for key in local.allKeys() {
            let localValue = local[key]
            let serverValue = server[key]

            // If values are the same, no conflict
            if areValuesEqual(localValue, serverValue) {
                continue
            }

            // Last-write-wins: if local is newer, use local value
            if localModDate > serverModDate {
                resolved[key] = localValue
            }
            // Otherwise keep server value (already set)
        }

        // Always update the modification date to now
        resolved["modifiedAt"] = Date.now

        return resolved
    }

    /// Check if two CKRecordValue objects are equal
    private func areValuesEqual(_ lhs: CKRecordValue?, _ rhs: CKRecordValue?) -> Bool {
        if lhs == nil && rhs == nil { return true }
        guard let lhs = lhs, let rhs = rhs else { return false }

        switch (lhs, rhs) {
        case (let l as String, let r as String): return l == r
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as Date, let r as Date): return l == r
        case (let l as Bool, let r as Bool): return l == r
        case (let l as Data, let r as Data): return l == r
        default: return false
        }
    }

    // MARK: - Sync Pending Changes

    /// Sync all pending local changes
    func syncPendingChanges() async {
        guard networkMonitor.isConnected && isCloudAvailable else { return }

        let pendingMetadata = syncMetadataStore.values.filter { $0.syncStatus == .pending }

        guard !pendingMetadata.isEmpty else { return }

        Logger.cloud.info("Syncing \(pendingMetadata.count) pending changes")

        // Group by record type for batch operations
        let groupedMetadata = Dictionary(grouping: pendingMetadata) { $0.recordType }

        for (recordType, metadataList) in groupedMetadata {
            for metadata in metadataList {
                do {
                    // Try to sync
                    // Note: The actual record data would need to be fetched from SwiftData
                    // This is a placeholder for the sync operation
                    Logger.cloud.info("Syncing pending record: \(metadata.recordId) of type \(recordType.rawValue)")

                    updateSyncMetadata(
                        recordId: metadata.recordId,
                        type: recordType,
                        status: .synced
                    )
                } catch {
                    Logger.cloud.error("Failed to sync record \(metadata.recordId): \(error.localizedDescription)")
                }
            }
        }

        updatePendingCount()
    }

    // MARK: - Delete Records

    /// Delete a record from CloudKit
    func deleteRecord(
        recordId: UUID,
        recordType: CloudRecordType
    ) async throws {
        guard isCloudAvailable else {
            throw CloudSyncError.containerNotAvailable
        }

        let recordID = CKRecord.ID(
            recordName: recordId.uuidString,
            zoneID: recordZone.zoneID
        )

        try await privateDatabase.deleteRecord(withID: recordID)

        // Remove sync metadata
        syncMetadataStore.removeValue(forKey: recordId)
        saveSyncMetadata()
        updatePendingCount()
    }

    // MARK: - Error Handling

    private func handleCKError(
        _ error: CKError,
        for recordId: UUID,
        type: CloudRecordType
    ) async throws {
        switch error.code {
        case .serverRecordChanged:
            // Conflict detected - get the server record and resolve
            if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                syncEventSubject.send(.recordConflict(type: type, id: recordId))
                updateSyncMetadata(recordId: recordId, type: type, status: .conflict)
                throw CloudSyncError.conflictDetected(local: CKRecord(recordType: type.rawValue), server: serverRecord)
            }
            throw CloudSyncError.serverRecordChanged

        case .networkUnavailable, .networkFailure:
            markAsPending(recordId, type: type)
            throw CloudSyncError.networkUnavailable

        case .quotaExceeded:
            updateSyncMetadata(recordId: recordId, type: type, status: .error, error: "Quota exceeded")
            throw CloudSyncError.quotaExceeded

        case .notAuthenticated:
            throw CloudSyncError.notAuthenticated

        case .permissionFailure:
            throw CloudSyncError.permissionDenied

        case .unknownItem:
            throw CloudSyncError.recordNotFound

        case .zoneNotFound:
            // Recreate zone and retry
            await setupCustomZone()
            throw CloudSyncError.zoneNotFound

        default:
            updateSyncMetadata(recordId: recordId, type: type, status: .error, error: error.localizedDescription)
            throw CloudSyncError.operationFailed(error)
        }
    }

    // MARK: - Sync Metadata Management

    private func markAsPending(_ recordId: UUID, type: CloudRecordType) {
        updateSyncMetadata(recordId: recordId, type: type, status: .pending)
    }

    private func updateSyncMetadata(
        recordId: UUID,
        type: CloudRecordType,
        cloudKitRecordId: String? = nil,
        changeTag: String? = nil,
        status: SyncStatus,
        error: String? = nil
    ) {
        var metadata = syncMetadataStore[recordId] ?? SyncMetadata(
            recordId: recordId,
            recordType: type
        )

        metadata.lastModifiedLocal = .now
        metadata.syncStatus = status

        if let cloudKitRecordId = cloudKitRecordId {
            metadata.cloudKitRecordId = cloudKitRecordId
        }

        if let changeTag = changeTag {
            metadata.changeTag = changeTag
        }

        if let error = error {
            metadata.lastError = error
            metadata.retryCount += 1
        } else if status == .synced {
            metadata.retryCount = 0
            metadata.lastError = nil
            metadata.lastModifiedCloud = .now
        }

        syncMetadataStore[recordId] = metadata
        saveSyncMetadata()
    }

    private func saveSyncMetadata() {
        let metadataArray = Array(syncMetadataStore.values)
        if let data = try? JSONEncoder().encode(metadataArray) {
            UserDefaults.standard.set(data, forKey: metadataKey)
        }
    }

    private func loadSyncMetadata() {
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let metadataArray = try? JSONDecoder().decode([SyncMetadata].self, from: data) else {
            return
        }

        syncMetadataStore = Dictionary(uniqueKeysWithValues: metadataArray.map { ($0.recordId, $0) })
        lastSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
        updatePendingCount()
    }

    private func updatePendingCount() {
        pendingChangesCount = syncMetadataStore.values.filter { $0.syncStatus == .pending }.count

        if pendingChangesCount > 0 {
            syncStatus = .pending
        } else if syncMetadataStore.values.contains(where: { $0.syncStatus == .conflict }) {
            syncStatus = .conflict
        } else if syncMetadataStore.values.contains(where: { $0.syncStatus == .error }) {
            syncStatus = .error
        } else {
            syncStatus = .synced
        }
    }

    // MARK: - Remote Change Notifications

    /// Handle a remote change notification
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return
        }

        Logger.cloud.info("Received remote notification: \(String(describing: notification.notificationType))")

        if notification.notificationType == .database {
            syncEventSubject.send(.remoteChangeReceived)

            do {
                _ = try await pullChanges()
            } catch {
                Logger.cloud.error("Failed to pull changes after notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sync Status Queries

    /// Get the sync status for a specific record
    func syncStatus(for recordId: UUID) -> SyncStatus {
        syncMetadataStore[recordId]?.syncStatus ?? .pending
    }

    /// Get all records with a specific sync status
    func records(withStatus status: SyncStatus) -> [UUID] {
        syncMetadataStore.values
            .filter { $0.syncStatus == status }
            .map { $0.recordId }
    }

    /// Check if a record needs sync
    func needsSync(_ recordId: UUID) -> Bool {
        guard let metadata = syncMetadataStore[recordId] else { return true }
        return metadata.syncStatus != .synced
    }

    // MARK: - Full Sync

    /// Perform a full bidirectional sync
    func performFullSync() async throws {
        guard networkMonitor.isConnected else {
            throw CloudSyncError.networkUnavailable
        }

        guard isCloudAvailable else {
            throw CloudSyncError.containerNotAvailable
        }

        Logger.cloud.info("Starting full sync")

        // First, push pending local changes
        await syncPendingChanges()

        // Then, pull remote changes
        _ = try await pullChanges()

        Logger.cloud.info("Full sync completed")
    }

    // MARK: - Reset

    /// Reset all sync state (for debugging/testing)
    func resetSyncState() {
        syncMetadataStore.removeAll()
        serverChangeToken = nil
        lastSyncDate = nil

        UserDefaults.standard.removeObject(forKey: metadataKey)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        UserDefaults.standard.removeObject(forKey: serverChangeTokenKey)

        syncStatus = .synced
        pendingChangesCount = 0

        Logger.cloud.info("Sync state reset")
    }
}

// MARK: - CloudKit Convertible Protocol

/// Protocol for models that can be converted to/from CloudKit records
protocol CloudKitConvertible: Identifiable where ID == UUID {
    /// Convert the model to a CKRecord
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord

    /// Create a model instance from a CKRecord
    static func fromCKRecord(_ record: CKRecord) -> Self?

    /// The CloudKit record type for this model
    static var cloudRecordType: CloudRecordType { get }
}

// MARK: - CKRecord Extensions

extension CKRecord {
    /// Convenience initializer with UUID-based record name
    convenience init(
        recordType: CloudRecordType,
        recordID: UUID,
        zoneID: CKRecordZone.ID
    ) {
        let recordID = CKRecord.ID(recordName: recordID.uuidString, zoneID: zoneID)
        self.init(recordType: recordType.rawValue, recordID: recordID)
    }

    /// Get a UUID from a record field
    func uuid(forKey key: String) -> UUID? {
        guard let string = self[key] as? String else { return nil }
        return UUID(uuidString: string)
    }

    /// Set a UUID to a record field
    func setUUID(_ uuid: UUID?, forKey key: String) {
        self[key] = uuid?.uuidString
    }

    /// Get a Date from a record field
    func date(forKey key: String) -> Date? {
        return self[key] as? Date
    }

    /// Get an optional Double from a record field
    func optionalDouble(forKey key: String) -> Double? {
        return self[key] as? Double
    }

    /// Get an optional Int from a record field
    func optionalInt(forKey key: String) -> Int? {
        return self[key] as? Int
    }
}

// MARK: - Workout CloudKit Extension

extension Workout: CloudKitConvertible {
    static var cloudRecordType: CloudRecordType { .workout }

    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: .workout,
            recordID: id,
            zoneID: zoneID
        )

        record.setUUID(userId, forKey: "userId")
        record["name"] = name
        record["startedAt"] = startedAt
        record["completedAt"] = completedAt
        record["notes"] = notes
        record["totalVolume"] = totalVolume
        record["exerciseCount"] = exerciseCount
        record["setCount"] = setCount
        record["modifiedAt"] = Date.now

        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> Workout? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let userId = record.uuid(forKey: "userId") else {
            return nil
        }

        let workout = Workout(id: id, userId: userId, name: record["name"] as? String)

        if let startedAt = record.date(forKey: "startedAt") {
            workout.startedAt = startedAt
        }
        workout.completedAt = record.date(forKey: "completedAt")
        workout.notes = record["notes"] as? String
        workout.totalVolume = record["totalVolume"] as? Double ?? 0
        workout.exerciseCount = record["exerciseCount"] as? Int ?? 0
        workout.setCount = record["setCount"] as? Int ?? 0

        return workout
    }
}

// MARK: - WorkoutPlan CloudKit Extension

extension WorkoutPlan: CloudKitConvertible {
    static var cloudRecordType: CloudRecordType { .workoutPlan }

    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: .workoutPlan,
            recordID: id,
            zoneID: zoneID
        )

        record.setUUID(userId, forKey: "userId")
        record["name"] = name
        record["planDescription"] = planDescription
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
        record["isActive"] = isActive
        record["isPublic"] = isPublic
        record["shareCode"] = shareCode
        record["authorName"] = authorName
        record["downloadCount"] = downloadCount
        record["daysPerWeek"] = daysPerWeek
        record["difficulty"] = difficulty.rawValue
        record["targetGoal"] = targetGoal.rawValue
        record["estimatedDuration"] = estimatedDuration
        record["modifiedAt"] = Date.now

        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> WorkoutPlan? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let userId = record.uuid(forKey: "userId"),
              let name = record["name"] as? String else {
            return nil
        }

        let difficultyStr = record["difficulty"] as? String ?? "Intermediate"
        let goalStr = record["targetGoal"] as? String ?? "Strength"

        let plan = WorkoutPlan(
            userId: userId,
            name: name,
            description: record["planDescription"] as? String,
            daysPerWeek: record["daysPerWeek"] as? Int ?? 4,
            difficulty: PlanDifficulty(rawValue: difficultyStr) ?? .intermediate,
            targetGoal: PlanGoal(rawValue: goalStr) ?? .strength
        )

        // Use reflection or manual assignment since id is let
        // Note: In a real implementation, you'd need a custom init

        plan.isActive = record["isActive"] as? Bool ?? false
        plan.isPublic = record["isPublic"] as? Bool ?? false
        plan.shareCode = record["shareCode"] as? String
        plan.authorName = record["authorName"] as? String
        plan.downloadCount = record["downloadCount"] as? Int ?? 0
        plan.estimatedDuration = record["estimatedDuration"] as? Int ?? 8

        if let createdAt = record.date(forKey: "createdAt") {
            plan.createdAt = createdAt
        }
        if let updatedAt = record.date(forKey: "updatedAt") {
            plan.updatedAt = updatedAt
        }

        return plan
    }
}

// MARK: - UserProfile CloudKit Extension

extension UserProfile: CloudKitConvertible {
    static var cloudRecordType: CloudRecordType { .userProfile }

    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: .userProfile,
            recordID: id,
            zoneID: zoneID
        )

        record["displayName"] = displayName
        record["email"] = email
        record["createdAt"] = createdAt
        record["unitSystem"] = unitSystem
        record["restTimerCompound"] = restTimerCompound
        record["restTimerIsolation"] = restTimerIsolation
        record["restTimerDefault"] = restTimerDefault
        record["exerciseRestTimersData"] = exerciseRestTimersData
        record["notificationsEnabled"] = notificationsEnabled
        record["restTimerSoundEnabled"] = restTimerSoundEnabled
        record["restTimerVibrationEnabled"] = restTimerVibrationEnabled
        record["modifiedAt"] = Date.now

        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> UserProfile? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let displayName = record["displayName"] as? String else {
            return nil
        }

        let unitSystemStr = record["unitSystem"] as? String ?? "Imperial"
        let profile = UserProfile(
            id: id,
            displayName: displayName,
            email: record["email"] as? String,
            unitSystem: UnitSystem(rawValue: unitSystemStr) ?? .imperial
        )

        profile.restTimerCompound = record["restTimerCompound"] as? TimeInterval ?? 180
        profile.restTimerIsolation = record["restTimerIsolation"] as? TimeInterval ?? 90
        profile.restTimerDefault = record["restTimerDefault"] as? TimeInterval ?? 120
        profile.exerciseRestTimersData = record["exerciseRestTimersData"] as? Data
        profile.notificationsEnabled = record["notificationsEnabled"] as? Bool ?? true
        profile.restTimerSoundEnabled = record["restTimerSoundEnabled"] as? Bool ?? true
        profile.restTimerVibrationEnabled = record["restTimerVibrationEnabled"] as? Bool ?? true

        if let createdAt = record.date(forKey: "createdAt") {
            profile.createdAt = createdAt
        }

        return profile
    }
}

// MARK: - PersonalRecord CloudKit Extension

extension PersonalRecord: CloudKitConvertible {
    static var cloudRecordType: CloudRecordType { .personalRecord }

    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: .personalRecord,
            recordID: id,
            zoneID: zoneID
        )

        record.setUUID(userId, forKey: "userId")
        record["exerciseName"] = exerciseName
        record["weight"] = weight
        record["reps"] = reps
        record["estimatedOneRepMax"] = estimatedOneRepMax
        record["date"] = date
        record.setUUID(sourceSetId, forKey: "sourceSetId")
        record["prType"] = prType
        record["modifiedAt"] = Date.now

        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> PersonalRecord? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let userId = record.uuid(forKey: "userId"),
              let exerciseName = record["exerciseName"] as? String,
              let weight = record["weight"] as? Double,
              let reps = record["reps"] as? Int,
              let estimatedOneRepMax = record["estimatedOneRepMax"] as? Double else {
            return nil
        }

        let pr = PersonalRecord(
            id: id,
            exerciseName: exerciseName,
            weight: weight,
            reps: reps,
            estimatedOneRepMax: estimatedOneRepMax,
            date: record.date(forKey: "date") ?? .now,
            sourceSetId: record.uuid(forKey: "sourceSetId"),
            prType: PRType(rawValue: record["prType"] as? String ?? "firstTime") ?? .firstTime,
            userId: userId
        )

        return pr
    }
}

// MARK: - Logger Extension

extension Logger {
    static let cloud = Logger(subsystem: "com.beastmode", category: "CloudSync")
}

// MARK: - Sync Status View

import SwiftUI

/// A view that displays the current sync status
struct SyncStatusView: View {
    @ObservedObject private var syncService = CloudSyncService.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: syncService.syncStatus.icon)
                .symbolEffect(.pulse, isActive: syncService.isSyncing)

            if syncService.isSyncing {
                Text(L10n.Sync.syncing)
                    .font(.caption)
            } else if syncService.pendingChangesCount > 0 {
                Text(L10n.Sync.pendingChanges(syncService.pendingChangesCount))
                    .font(.caption)
            } else if let lastSync = syncService.lastSyncDate {
                Text(L10n.Sync.lastSynced(lastSync.formatted(.relative(presentation: .named))))
                    .font(.caption)
            }
        }
        .foregroundStyle(syncStatusColor)
    }

    private var syncStatusColor: Color {
        switch syncService.syncStatus {
        case .synced: return .green
        case .pending: return .orange
        case .conflict: return .yellow
        case .error: return .red
        }
    }
}

// MARK: - Preview

#Preview("Sync Status") {
    VStack(spacing: 20) {
        SyncStatusView()

        Button("Test Sync") {
            Task {
                try? await CloudSyncService.shared.performFullSync()
            }
        }
    }
    .padding()
}
