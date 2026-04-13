import Foundation

enum VolumeArcCloudConfiguration {
    static let syncZoneName = "VolumeArcSyncZone"

    static var containerIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "VolumeArcCloudKitContainer") as? String
    }

    static var startupWarning: String? {
        let containerIdentifier = containerIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard containerIdentifier.isEmpty else { return nil }
        return "CloudKit container is not configured, so sync will stay local on this build."
    }
}
