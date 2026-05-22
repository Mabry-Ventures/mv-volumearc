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

// NEGATIVE-CONTROL (red): VOL-246 cutover gate. The `optional!` below is a
// deliberate `force_unwrapping` violation (an opt-in rule enabled for
// production in .swiftlint.yml) so `swiftlint --strict` in ci_post_clone.sh
// fails the VolumeArc PR check (red-means-caught). It compiles and is never
// called, so it doesn't break the build. Edited in place (no new file) to
// avoid pbxproj churn. DO NOT MERGE — close after verification.
enum NegativeControlLintViolation {
    static func value() -> Int {
        let optional: Int? = 1
        return optional!
    }
}
