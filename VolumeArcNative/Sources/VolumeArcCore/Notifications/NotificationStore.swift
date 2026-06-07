import Foundation
#if canImport(Security)
import Security
#endif

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
    private let keychainService: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "com.mabryventures.VolumeArc.accountSession",
        keychainService: String = "com.mabryventures.VolumeArc.accountSession"
    ) {
        self.defaults = defaults
        self.key = key
        self.keychainService = keychainService
    }

    public func load() -> AccountSession? {
        #if canImport(Security)
        if let data = keychainData() {
            do {
                let session = try JSONDecoder().decode(AccountSession.self, from: data)
                defaults.removeObject(forKey: key)
                return session
            } catch {
                deleteKeychainData()
            }
        }
        if let legacyData = defaults.data(forKey: key) {
            defer { defaults.removeObject(forKey: key) }
            guard let session = try? JSONDecoder().decode(AccountSession.self, from: legacyData) else {
                return nil
            }
            saveKeychainData(legacyData)
            return session
        }
        return nil
        #else
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let session = try? JSONDecoder().decode(AccountSession.self, from: data) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return session
        #endif
    }

    public func save(_ session: AccountSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        #if canImport(Security)
        saveKeychainData(data)
        defaults.removeObject(forKey: key)
        #else
        defaults.set(data, forKey: key)
        #endif
    }

    public func clear() {
        defaults.removeObject(forKey: key)
        #if canImport(Security)
        deleteKeychainData()
        #endif
    }

    #if canImport(Security)
    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
    }

    private func keychainData() -> Data? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func saveKeychainData(_ data: Data) {
        deleteKeychainData()
        var query = keychainQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteKeychainData() {
        SecItemDelete(keychainQuery() as CFDictionary)
    }
    #endif
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
