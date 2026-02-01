// NetworkMonitorTests.swift
// BeastModeTests
// Unit tests for NetworkMonitor connectivity tracking

import Testing
import Foundation
@testable import BeastMode

@Suite("NetworkMonitor Tests")
struct NetworkMonitorTests {

    // MARK: - NetworkStatus Tests

    @Test("NetworkStatus connected returns isConnected true")
    func networkStatusConnectedIsConnected() {
        let wifiStatus = NetworkStatus.connected(.wifi)
        #expect(wifiStatus.isConnected == true)

        let cellularStatus = NetworkStatus.connected(.cellular)
        #expect(cellularStatus.isConnected == true)
    }

    @Test("NetworkStatus disconnected returns isConnected false")
    func networkStatusDisconnectedNotConnected() {
        let status = NetworkStatus.disconnected
        #expect(status.isConnected == false)
    }

    @Test("NetworkStatus unknown returns isConnected false")
    func networkStatusUnknownNotConnected() {
        let status = NetworkStatus.unknown
        #expect(status.isConnected == false)
    }

    @Test("NetworkStatus descriptions are correct")
    func networkStatusDescriptions() {
        #expect(NetworkStatus.unknown.description == "Unknown")
        #expect(NetworkStatus.disconnected.description == "Disconnected")
        #expect(NetworkStatus.connected(.wifi).description == "Connected (WiFi)")
        #expect(NetworkStatus.connected(.cellular).description == "Connected (Cellular)")
        #expect(NetworkStatus.connected(.wiredEthernet).description == "Connected (Ethernet)")
        #expect(NetworkStatus.connected(.other).description == "Connected (Other)")
    }

    // MARK: - ConnectionType Tests

    @Test("ConnectionType descriptions are correct")
    func connectionTypeDescriptions() {
        #expect(ConnectionType.wifi.description == "WiFi")
        #expect(ConnectionType.cellular.description == "Cellular")
        #expect(ConnectionType.wiredEthernet.description == "Ethernet")
        #expect(ConnectionType.other.description == "Other")
    }

    @Test("ConnectionType isExpensive property")
    func connectionTypeIsExpensive() {
        #expect(ConnectionType.wifi.isExpensive == false)
        #expect(ConnectionType.cellular.isExpensive == true)
        #expect(ConnectionType.wiredEthernet.isExpensive == false)
        #expect(ConnectionType.other.isExpensive == false)
    }

    // MARK: - NetworkStatus Equality Tests

    @Test("NetworkStatus equality")
    func networkStatusEquality() {
        #expect(NetworkStatus.unknown == NetworkStatus.unknown)
        #expect(NetworkStatus.disconnected == NetworkStatus.disconnected)
        #expect(NetworkStatus.connected(.wifi) == NetworkStatus.connected(.wifi))
        #expect(NetworkStatus.connected(.wifi) != NetworkStatus.connected(.cellular))
        #expect(NetworkStatus.connected(.wifi) != NetworkStatus.disconnected)
    }

    // MARK: - PendingOperation Tests

    @Test("PendingOperation initialization")
    func pendingOperationInitialization() {
        let operation = PendingOperation(
            type: .syncWorkout,
            payload: ["workoutId": "123"],
            maxRetries: 5
        )

        #expect(operation.type == .syncWorkout)
        #expect(operation.payload["workoutId"] == "123")
        #expect(operation.maxRetries == 5)
        #expect(operation.retryCount == 0)
        #expect(operation.createdAt <= Date())
    }

    @Test("PendingOperation increment retry")
    func pendingOperationIncrementRetry() {
        var operation = PendingOperation(type: .uploadAnalytics)

        #expect(operation.retryCount == 0)

        operation.incrementRetry()
        #expect(operation.retryCount == 1)

        operation.incrementRetry()
        #expect(operation.retryCount == 2)
    }

    @Test("PendingOperation default max retries")
    func pendingOperationDefaultMaxRetries() {
        let operation = PendingOperation(type: .fetchAIReview)
        #expect(operation.maxRetries == 3)
    }

    // MARK: - OperationType Tests

    @Test("OperationType raw values")
    func operationTypeRawValues() {
        #expect(OperationType.syncWorkout.rawValue == "syncWorkout")
        #expect(OperationType.uploadAnalytics.rawValue == "uploadAnalytics")
        #expect(OperationType.fetchAIReview.rawValue == "fetchAIReview")
        #expect(OperationType.updateProfile.rawValue == "updateProfile")
    }

    @Test("OperationType is codable")
    func operationTypeCodable() throws {
        let original = OperationType.syncWorkout
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OperationType.self, from: encoded)
        #expect(original == decoded)
    }

    // MARK: - PendingOperation Codable Tests

    @Test("PendingOperation is codable")
    func pendingOperationCodable() throws {
        let original = PendingOperation(
            type: .syncWorkout,
            payload: ["key": "value"],
            maxRetries: 3
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PendingOperation.self, from: encoded)

        #expect(original.id == decoded.id)
        #expect(original.type == decoded.type)
        #expect(original.payload == decoded.payload)
        #expect(original.maxRetries == decoded.maxRetries)
    }
}

// MARK: - NetworkMonitor Shared Instance Tests

@Suite("NetworkMonitor Shared Instance Tests")
@MainActor
struct NetworkMonitorSharedTests {

    @Test("Shared instance exists")
    func sharedInstanceExists() async {
        let monitor = NetworkMonitor.shared
        #expect(monitor != nil)
    }

    @Test("Can perform request check")
    func canPerformRequestCheck() async {
        let monitor = NetworkMonitor.shared

        // Just verify the method doesn't crash
        _ = monitor.canPerformRequest(requiresWiFi: false)
        _ = monitor.canPerformRequest(requiresWiFi: true)
    }
}
