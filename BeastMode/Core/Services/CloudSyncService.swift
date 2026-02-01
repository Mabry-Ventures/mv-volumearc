import Foundation
import CloudKit

/// Service for managing CloudKit synchronization
actor CloudSyncService {
    static let shared = CloudSyncService()

    private let container: CKContainer
    private let privateDatabase: CKDatabase

    private init() {
        self.container = CKContainer(identifier: Configuration.cloudKitContainerIdentifier)
        self.privateDatabase = container.privateCloudDatabase
    }

    // MARK: - Account Status

    /// Check if iCloud is available
    func checkAccountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    /// Check if the user is signed into iCloud
    func isSignedIn() async -> Bool {
        do {
            let status = try await checkAccountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    // MARK: - Sync Status

    enum SyncStatus {
        case idle
        case syncing
        case completed
        case failed(Error)
        case noAccount
    }

    @Published private(set) var syncStatus: SyncStatus = .idle

    /// Request a sync operation
    func requestSync() async {
        guard await isSignedIn() else {
            syncStatus = .noAccount
            return
        }

        syncStatus = .syncing

        // SwiftData with CloudKit handles sync automatically
        // This method can be used to trigger a manual refresh if needed

        syncStatus = .completed
    }

    // MARK: - Subscription Management

    /// Set up subscriptions for push notifications on data changes
    func setupSubscriptions() async throws {
        guard await isSignedIn() else { return }

        // Create subscription for workout changes
        let subscriptionID = "workout-changes"

        // Check if subscription already exists
        do {
            _ = try await privateDatabase.subscription(for: subscriptionID)
            // Subscription already exists
            return
        } catch {
            // Subscription doesn't exist, create it
        }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true

        subscription.notificationInfo = notificationInfo

        try await privateDatabase.save(subscription)
    }

    // MARK: - Data Export

    /// Export all user data for backup
    func exportUserData() async throws -> Data {
        // This would query all records and serialize them
        // For now, return empty data as SwiftData handles persistence
        return Data()
    }

    // MARK: - Error Recovery

    /// Handle sync conflicts
    func resolveConflict(localRecord: CKRecord, serverRecord: CKRecord) -> CKRecord {
        // Default strategy: server wins for most recent modification
        let localDate = localRecord.modificationDate ?? Date.distantPast
        let serverDate = serverRecord.modificationDate ?? Date.distantPast

        return serverDate >= localDate ? serverRecord : localRecord
    }
}

// MARK: - Sync Error Types

enum CloudSyncError: LocalizedError {
    case notSignedIn
    case networkUnavailable
    case quotaExceeded
    case serverError(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Please sign in to iCloud to sync your data"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .quotaExceeded:
            return "iCloud storage quota exceeded"
        case .serverError(let error):
            return "Server error: \(error.localizedDescription)"
        }
    }
}
