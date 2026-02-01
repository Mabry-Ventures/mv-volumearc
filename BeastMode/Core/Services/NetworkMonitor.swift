// NetworkMonitor.swift
// BeastMode
// Network connectivity monitoring and offline mode support

import Foundation
import Network
import Combine
import os

// MARK: - Network Status

enum NetworkStatus: Equatable {
    case unknown
    case connected(ConnectionType)
    case disconnected

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var description: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .connected(let type):
            return "Connected (\(type.description))"
        case .disconnected:
            return "Disconnected"
        }
    }
}

enum ConnectionType: Equatable {
    case wifi
    case cellular
    case wiredEthernet
    case other

    var description: String {
        switch self {
        case .wifi: return "WiFi"
        case .cellular: return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .other: return "Other"
        }
    }

    var isExpensive: Bool {
        return self == .cellular
    }
}

// MARK: - Network Monitor

@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var status: NetworkStatus = .unknown
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var connectionType: ConnectionType = .other
    @Published private(set) var isExpensive: Bool = false
    @Published private(set) var isConstrained: Bool = false

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.beastmode.networkmonitor")

    private init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public Methods

    /// Start monitoring network status
    func startMonitoring() {
        Logger.network.info("Starting network monitoring")

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.updateStatus(from: path)
            }
        }

        monitor.start(queue: monitorQueue)
    }

    /// Stop monitoring network status
    func stopMonitoring() {
        Logger.network.info("Stopping network monitoring")
        monitor.cancel()
    }

    /// Check if network is available for a specific request type
    func canPerformRequest(requiresWiFi: Bool = false) -> Bool {
        guard isConnected else { return false }

        if requiresWiFi && connectionType != .wifi {
            return false
        }

        return true
    }

    // MARK: - Private Methods

    private func updateStatus(from path: NWPath) {
        let oldStatus = status

        if path.status == .satisfied {
            // Determine connection type
            if path.usesInterfaceType(.wifi) {
                connectionType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                connectionType = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                connectionType = .wiredEthernet
            } else {
                connectionType = .other
            }

            status = .connected(connectionType)
            isConnected = true
        } else {
            status = .disconnected
            isConnected = false
        }

        isExpensive = path.isExpensive
        isConstrained = path.isConstrained

        // Log status change
        if oldStatus != status {
            Logger.network.info("Network status changed: \(self.status.description)")

            // Notify observers via notification center
            NotificationCenter.default.post(
                name: .networkStatusChanged,
                object: nil,
                userInfo: ["status": status, "isConnected": isConnected]
            )
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let networkStatusChanged = Notification.Name("com.beastmode.networkStatusChanged")
}

// MARK: - Offline Manager

@MainActor
class OfflineManager: ObservableObject {
    static let shared = OfflineManager()

    @Published private(set) var pendingOperations: [PendingOperation] = []
    @Published private(set) var isProcessingQueue: Bool = false

    private let networkMonitor = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    private let persistenceKey = "com.beastmode.pendingOperations"

    private init() {
        loadPendingOperations()
        setupNetworkObserver()
    }

    // MARK: - Public Methods

    /// Queue an operation for later execution when online
    func queueOperation(_ operation: PendingOperation) {
        Logger.network.info("Queueing offline operation: \(operation.type.rawValue)")

        pendingOperations.append(operation)
        savePendingOperations()

        // Try to process immediately if online
        if networkMonitor.isConnected {
            Task {
                await processQueue()
            }
        }
    }

    /// Process all pending operations
    func processQueue() async {
        guard !isProcessingQueue else {
            Logger.network.info("Queue processing already in progress")
            return
        }

        guard networkMonitor.isConnected else {
            Logger.network.info("Cannot process queue - offline")
            return
        }

        isProcessingQueue = true
        Logger.network.info("Processing \(pendingOperations.count) pending operations")

        var successfulOperations: Set<UUID> = []

        for operation in pendingOperations {
            do {
                try await executeOperation(operation)
                successfulOperations.insert(operation.id)
                Logger.network.info("Successfully processed operation: \(operation.id)")
            } catch {
                Logger.network.error("Failed to process operation \(operation.id): \(error.localizedDescription)")

                // Mark as failed if max retries exceeded
                if operation.retryCount >= operation.maxRetries {
                    successfulOperations.insert(operation.id)
                    CrashReporter.shared.recordNonFatalError(
                        "Operation failed after max retries",
                        properties: ["operationType": operation.type.rawValue, "operationId": operation.id.uuidString]
                    )
                }
            }
        }

        // Remove successful operations
        pendingOperations.removeAll { successfulOperations.contains($0.id) }
        savePendingOperations()

        isProcessingQueue = false
    }

    /// Clear all pending operations
    func clearPendingOperations() {
        pendingOperations.removeAll()
        savePendingOperations()
    }

    /// Get count of pending operations
    var pendingCount: Int {
        pendingOperations.count
    }

    // MARK: - Private Methods

    private func setupNetworkObserver() {
        NotificationCenter.default.publisher(for: .networkStatusChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let isConnected = notification.userInfo?["isConnected"] as? Bool, isConnected {
                    Task { @MainActor [weak self] in
                        await self?.processQueue()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func executeOperation(_ operation: PendingOperation) async throws {
        switch operation.type {
        case .syncWorkout:
            // Sync workout to cloud
            Logger.network.info("Syncing workout: \(operation.payload["workoutId"] ?? "unknown")")
            // Implementation would go here

        case .uploadAnalytics:
            // Upload analytics data
            Logger.network.info("Uploading analytics")
            // Implementation would go here

        case .fetchAIReview:
            // Fetch AI review
            Logger.network.info("Fetching AI review")
            // Implementation would go here

        case .updateProfile:
            // Update user profile
            Logger.network.info("Updating profile")
            // Implementation would go here
        }
    }

    private func savePendingOperations() {
        guard let data = try? JSONEncoder().encode(pendingOperations) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func loadPendingOperations() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let operations = try? JSONDecoder().decode([PendingOperation].self, from: data) else {
            return
        }
        pendingOperations = operations
    }
}

// MARK: - Pending Operation

struct PendingOperation: Codable, Identifiable {
    let id: UUID
    let type: OperationType
    let payload: [String: String]
    let createdAt: Date
    var retryCount: Int
    let maxRetries: Int

    init(
        type: OperationType,
        payload: [String: String] = [:],
        maxRetries: Int = 3
    ) {
        self.id = UUID()
        self.type = type
        self.payload = payload
        self.createdAt = Date()
        self.retryCount = 0
        self.maxRetries = maxRetries
    }

    mutating func incrementRetry() {
        retryCount += 1
    }
}

enum OperationType: String, Codable {
    case syncWorkout
    case uploadAnalytics
    case fetchAIReview
    case updateProfile
}

// MARK: - Offline-Aware View Modifier

struct OfflineAwareModifier: ViewModifier {
    @StateObject private var networkMonitor = NetworkMonitor.shared
    let showBanner: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showBanner && !networkMonitor.isConnected {
                    OfflineBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: networkMonitor.isConnected)
    }
}

extension View {
    func offlineAware(showBanner: Bool = true) -> some View {
        modifier(OfflineAwareModifier(showBanner: showBanner))
    }
}

// MARK: - Offline Banner View

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.subheadline)

            Text("You're offline")
                .font(.subheadline.weight(.medium))

            Spacer()

            Text("Changes will sync when connected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color.orange.opacity(0.3))
    }
}

// MARK: - Preview

import SwiftUI

#Preview("Offline Banner") {
    VStack {
        OfflineBanner()
        Spacer()
    }
}
