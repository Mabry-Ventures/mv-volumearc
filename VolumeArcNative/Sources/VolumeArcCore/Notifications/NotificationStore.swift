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

public struct AccountSession: Codable, Equatable, Sendable {
    public let provider: String
    public let userID: String
    public let displayName: String
    public let email: String?
    public let connectedAt: Date

    public init(
        provider: String,
        userID: String,
        displayName: String,
        email: String?,
        connectedAt: Date = .now
    ) {
        self.provider = provider
        self.userID = userID
        self.displayName = displayName
        self.email = email
        self.connectedAt = connectedAt
    }
}

public protocol AccountSessionStore: Sendable {
    func load() -> AccountSession?
    func save(_ session: AccountSession)
    func clear()
}

public final class UserDefaultsAccountSessionStore: AccountSessionStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "com.mabryventures.VolumeArc.accountSession"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AccountSession? {
        guard let data = defaults.data(forKey: key),
              let session = try? JSONDecoder().decode(AccountSession.self, from: data)
        else { return nil }
        return session
    }

    public func save(_ session: AccountSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

public final class InMemoryAccountSessionStore: AccountSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AccountSession?

    public init(session: AccountSession? = nil) {
        self.session = session
    }

    public func load() -> AccountSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    public func save(_ session: AccountSession) {
        lock.lock()
        defer { lock.unlock() }
        self.session = session
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        session = nil
    }
}
