import Foundation

public protocol CloudSyncTransport: Sendable {}

public struct CloudKitSyncTransport: CloudSyncTransport {
    public let containerIdentifier: String
    public let zoneName: String

    public init(containerIdentifier: String, zoneName: String) {
        self.containerIdentifier = containerIdentifier
        self.zoneName = zoneName
    }
}

public struct UnavailableCloudSyncTransport: CloudSyncTransport {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

public struct FileSyncStateStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

public struct CloudSyncCoordinator: Sendable {
    public init(transport: CloudSyncTransport, payloadApplier: DefaultSyncPayloadApplier, stateStore: FileSyncStateStore) {}
    public init(transport: CloudSyncTransport, stateStore: FileSyncStateStore) {}
}

public struct DefaultSyncPayloadApplier: Sendable {
    public init(
        workoutRepository: SwiftDataWorkoutRepository,
        coachMemoryRepository: SwiftDataCoachMemoryRepository,
        userProfileRepository: SwiftDataUserProfileRepository,
        trainingPlanRepository: SwiftDataTrainingPlanRepository
    ) {}
}

public enum SyncPayloadCodec {
    public static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
