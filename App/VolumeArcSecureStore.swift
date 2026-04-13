import Foundation
import Security

enum VolumeArcSecureStoreError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            return "Keychain request failed with status \(status)."
        case .invalidData:
            return "Keychain data was unreadable."
        }
    }
}

struct VolumeArcSecureStore: @unchecked Sendable {
    private let service = "com.mabryventures.VolumeArc"
    private let fallbackDefaults = UserDefaults(suiteName: "com.mabryventures.VolumeArc.secure-fallback")

    func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(for: key)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let existingStatus = SecItemCopyMatching(query as CFDictionary, nil)
        switch existingStatus {
        case errSecSuccess:
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if shouldUseFallback(for: status) {
                fallbackDefaults?.set(value, forKey: fallbackKey(for: key))
                return
            }

            guard status == errSecSuccess else {
                throw VolumeArcSecureStoreError.unexpectedStatus(status)
            }
        case errSecItemNotFound:
            var createQuery = query
            attributes.forEach { createQuery[$0.key] = $0.value }
            let status = SecItemAdd(createQuery as CFDictionary, nil)
            if shouldUseFallback(for: status) {
                fallbackDefaults?.set(value, forKey: fallbackKey(for: key))
                return
            }

            guard status == errSecSuccess else {
                throw VolumeArcSecureStoreError.unexpectedStatus(status)
            }
        case let status where shouldUseFallback(for: status):
            fallbackDefaults?.set(value, forKey: fallbackKey(for: key))
        default:
            throw VolumeArcSecureStoreError.unexpectedStatus(existingStatus)
        }
    }

    func load(_ key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw VolumeArcSecureStoreError.invalidData
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        case let status where shouldUseFallback(for: status):
            return fallbackDefaults?.string(forKey: fallbackKey(for: key))
        default:
            throw VolumeArcSecureStoreError.unexpectedStatus(status)
        }
    }

    private func shouldUseFallback(for status: OSStatus) -> Bool {
        guard allowsFallbackStorage else { return false }
        return status == errSecMissingEntitlement || status == errSecNotAvailable
    }

    private var allowsFallbackStorage: Bool {
        #if DEBUG || targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private func fallbackKey(for key: String) -> String {
        "\(service).\(key)"
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
