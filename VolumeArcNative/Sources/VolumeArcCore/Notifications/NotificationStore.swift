// NEGATIVE-CONTROL (green): VOL-246 cutover gate — no-op comment to prove
// the VolumeArc PR workflow actually builds + runs tests. DO NOT MERGE.
import Foundation

public protocol NotificationStore: Sendable {}

#if canImport(UserNotifications)
public struct UserNotificationCenterStore: NotificationStore {
    public init() {}
}
#endif

public struct InMemoryNotificationStore: NotificationStore {
    public init() {}
}

public protocol AccountSessionStore: Sendable {}

public struct UserDefaultsAccountSessionStore: AccountSessionStore {
    public init() {}
}
