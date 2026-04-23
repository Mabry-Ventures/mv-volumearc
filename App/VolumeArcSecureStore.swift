import Foundation
import Security
#if canImport(OSLog)
import OSLog
#endif

enum VolumeArcSecureStoreError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData
    /// The Keychain reported an error that would normally trigger the
    /// Debug/simulator UserDefaults fallback, but the current build is a
    /// Release device build where silently persisting secrets to
    /// UserDefaults is unacceptable. Callers must surface this error to
    /// the user / telemetry instead of downgrading storage.
    case keychainUnavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            return "Keychain request failed with status \(status)."
        case .invalidData:
            return "Keychain data was unreadable."
        case let .keychainUnavailable(status):
            return "Keychain is unavailable (status \(status)); refusing to fall back to UserDefaults on a Release device build."
        }
    }
}

struct VolumeArcSecureStore: @unchecked Sendable {
    private let service = "com.mabryventures.VolumeArc"

    // MARK: - Fallback fence
    //
    // VOL-84: The UserDefaults fallback below is only available in Debug
    // or simulator builds. On a Release device build a Keychain failure
    // must hard-fail with `VolumeArcSecureStoreError.keychainUnavailable`
    // rather than silently persisting secrets (relay tokens, device IDs,
    // Sentry DSN) to UserDefaults, which offers an order of magnitude
    // less protection at rest and outside the secure enclave.
    #if DEBUG || targetEnvironment(simulator)
    private let fallbackDefaults = UserDefaults(suiteName: "com.mabryventures.VolumeArc.secure-fallback")
    #endif

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
            if Self.isFallbackEligible(status) {
                try writeFallback(value: value, for: key, status: status)
                return
            }

            guard status == errSecSuccess else {
                throw VolumeArcSecureStoreError.unexpectedStatus(status)
            }
        case errSecItemNotFound:
            var createQuery = query
            attributes.forEach { createQuery[$0.key] = $0.value }
            let status = SecItemAdd(createQuery as CFDictionary, nil)
            if Self.isFallbackEligible(status) {
                try writeFallback(value: value, for: key, status: status)
                return
            }

            guard status == errSecSuccess else {
                throw VolumeArcSecureStoreError.unexpectedStatus(status)
            }
        case let status where Self.isFallbackEligible(status):
            try writeFallback(value: value, for: key, status: status)
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
        case let status where Self.isFallbackEligible(status):
            return try readFallback(for: key, status: status)
        default:
            throw VolumeArcSecureStoreError.unexpectedStatus(status)
        }
    }

    // MARK: - Fallback helpers

    /// Whether `status` represents a Keychain error that the fallback
    /// path is designed to handle (`errSecMissingEntitlement` from a
    /// simulator or a build without the right entitlement, or
    /// `errSecNotAvailable` from a device without Keychain access).
    ///
    /// Returning `true` does NOT mean the fallback will be taken —
    /// `writeFallback` / `readFallback` still enforce the Release-device
    /// hard-fail. This predicate only filters out unrelated Keychain
    /// failures so they can surface as `unexpectedStatus` instead of
    /// being miscategorised as a fence decision.
    private static func isFallbackEligible(_ status: OSStatus) -> Bool {
        status == errSecMissingEntitlement || status == errSecNotAvailable
    }

    private func writeFallback(value: String, for key: String, status: OSStatus) throws {
        #if DEBUG || targetEnvironment(simulator)
        Self.logFallbackActivation(operation: "save", key: key, status: status)
        fallbackDefaults?.set(value, forKey: fallbackKey(for: key))
        #else
        throw VolumeArcSecureStoreError.keychainUnavailable(status)
        #endif
    }

    private func readFallback(for key: String, status: OSStatus) throws -> String? {
        #if DEBUG || targetEnvironment(simulator)
        Self.logFallbackActivation(operation: "load", key: key, status: status)
        return fallbackDefaults?.string(forKey: fallbackKey(for: key))
        #else
        throw VolumeArcSecureStoreError.keychainUnavailable(status)
        #endif
    }

    #if DEBUG || targetEnvironment(simulator)
    private static func logFallbackActivation(operation: String, key: String, status: OSStatus) {
        #if canImport(OSLog)
        let logger = Logger(subsystem: "com.mabryventures.VolumeArc", category: "secure-store")
        logger.warning(
            """
            VolumeArcSecureStore fallback activated (Debug/simulator only): \
            op=\(operation) key=\(key) status=\(status) — \
            Release device builds will throw keychainUnavailable instead.
            """
        )
        #endif
    }
    #endif

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
