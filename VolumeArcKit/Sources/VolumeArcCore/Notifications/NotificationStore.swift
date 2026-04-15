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
