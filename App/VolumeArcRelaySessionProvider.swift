import CryptoKit
import Foundation
import VolumeArcCore

/// Produces the `Authorization: Bearer <device>.<hmac>` header the relay
/// expects. The signing key lives in Keychain (bootstrapped from
/// `VOLUMEARC_RELAY_SIGNING_KEY` env var or `VolumeArcRelaySigningKey`
/// Info.plist key). The device ID is a stable UUID generated on first
/// launch and persisted to Keychain with a UserDefaults fallback.
///
/// The previous implementation fetched a session token from a `/relay/session`
/// endpoint; the new Cloudflare Worker computes auth locally via HMAC, so
/// there's no round-trip. This cuts coach-request latency by one network
/// hop and removes a class of transient auth failures.
actor VolumeArcRelaySessionProvider: AIRelayCredentialsProviding {
    private let secureStore = VolumeArcSecureStore()
    private let signingKeyKey = "ai.relay.signingKey"
    private let deviceIDKey = "ai.relay.deviceID"
    private let fallbackDefaults = UserDefaults(suiteName: "com.mabryventures.VolumeArc.device-identity")

    init(baseURL: URL, applicationID: String) {
        _ = baseURL
        _ = applicationID
    }

    func authorizationHeaderValue() async throws -> String {
        // VOL-116: persist the device ID BEFORE resolving the signing key.
        // The device ID is a stable identity for this install — it must be
        // generated and persisted on first call regardless of whether the
        // signing key is bootstrapped yet. Otherwise:
        //   1. The first auth attempt before signing-key bootstrap throws
        //      from `resolveSigningKey()` and never persists a device ID.
        //   2. A later attempt (after the signing key arrives) generates a
        //      fresh device ID, breaking "stable device identity across the
        //      lifetime of the install" — the relay's rate-limit, telemetry,
        //      and abuse signals all key on this ID.
        // Test coverage: `testRelayProviderDeviceIDIsStableAcrossCalls` runs
        // with no signing key configured and asserts the device ID is still
        // persisted to Keychain after two `try?` calls.
        let device = deviceID()
        let signingKey = try resolveSigningKey()
        let signature = Self.hmacHex(key: signingKey, message: device)
        return "Bearer \(device).\(signature)"
    }

    private func resolveSigningKey() throws -> String {
        if let fromStore = try secureStore.load(signingKeyKey), fromStore.isEmpty == false {
            return fromStore
        }
        let bootstrap = ProcessInfo.processInfo.environment["VOLUMEARC_RELAY_SIGNING_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "VolumeArcRelaySigningKey") as? String
        guard let bootstrap, bootstrap.isEmpty == false else {
            throw AIRuntimeIntegrationError.relayUnavailable(
                reason: "Relay signing key is not configured; set VOLUMEARC_RELAY_SIGNING_KEY or Info.plist VolumeArcRelaySigningKey."
            )
        }
        try? secureStore.save(bootstrap, for: signingKeyKey)
        return bootstrap
    }

    private func deviceID() -> String {
        if let existing = try? secureStore.load(deviceIDKey), existing.isEmpty == false {
            return existing
        }
        if let fallback = fallbackDefaults?.string(forKey: deviceIDKey), fallback.isEmpty == false {
            return fallback
        }
        let generated = UUID().uuidString.lowercased()
        do {
            try secureStore.save(generated, for: deviceIDKey)
        } catch {
            fallbackDefaults?.set(generated, forKey: deviceIDKey)
        }
        return generated
    }

    private static func hmacHex(key: String, message: String) -> String {
        let keyData = Data(key.utf8)
        let messageData = Data(message.utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: messageData, using: SymmetricKey(data: keyData))
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }
}
