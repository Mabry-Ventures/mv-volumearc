// VOL-224 App Attest Phase A (client-side).
//
// Apple's App Attest establishes that a request to the Cloudflare Worker
// relay comes from a genuine instance of our app, not a tampered or
// repackaged binary, by anchoring the request to a key generated inside
// the Secure Enclave and attested by Apple's servers.
//
// This file is the client-side surface only. Phase B (VOL-225) implements
// server-side validation in the relay; Phase C (VOL-226) cuts over the
// production HMAC-only path to App-Attest-required. Until Phase B ships,
// this service is dormant in production callers — the helpers below
// produce attestation/assertion blobs that consumers can attach as advisory
// headers, but the relay still treats them as ignorable.
//
// ## Lifecycle
//
//   1. **First run**: app calls `bootstrapKeyIfNeeded()`. Service generates
//      a key inside Secure Enclave via `DCAppAttestService.generateKey`,
//      persists the resulting keyID in Keychain, then attests the key with
//      `DCAppAttestService.attestKey(_:clientDataHash:)`. The attestation
//      object (CBOR-encoded) is held in memory plus persisted so Phase B's
//      server can be told about the key once.
//
//   2. **Per request**: caller invokes `assertion(over:)` with a hash of
//      the request body. The service produces a small CBOR-encoded
//      assertion via `DCAppAttestService.generateAssertion(_:clientDataHash:)`
//      that the server can verify against the previously-attested public
//      key (Phase B).
//
// ## Availability + simulator behavior
//
// `DCAppAttestService.isSupported` returns false on:
//   - iOS Simulator (until Xcode 13+ runtime; even then unreliable on M1+)
//   - watchOS prior to Sonoma 10.1
//   - macOS, including Mac Catalyst.
//
// On unsupported devices, this service surfaces
// `VolumeArcAppAttestError.notSupported` and callers MUST fall back to the
// HMAC path. The relay's tier-1 anti-abuse posture (rate limits, request
// signing) covers the unsupported-device cohort.
//
// ## Determinstic / UI test mode
//
// In `-UITestMode 1` (deterministic) we short-circuit to
// `.notSupported` regardless of platform so journey tests don't depend
// on the simulator's flaky App Attest daemon. The HMAC path stays the
// single source of truth for tests.

#if canImport(DeviceCheck)
import DeviceCheck
#endif

import CryptoKit
import Foundation
import VolumeArcCore

/// Errors emitted by the App Attest service. Each maps to a specific
/// failure mode in `DCAppAttestService` plus the two synthetic states
/// (`notSupported`, `disabledForTests`) that callers must handle.
enum VolumeArcAppAttestError: Error, LocalizedError {
    /// `DCAppAttestService.isSupported == false` for this device. Caller
    /// must fall back to HMAC. Surfaced once on first use and cached.
    case notSupported
    /// Service is intentionally disabled — UI test mode or feature flag
    /// off. Distinct from `notSupported` so telemetry can tell the
    /// difference between a coverage gap and a deliberate skip.
    case disabledForTests
    /// `DCAppAttestService.generateKey` failed. The `OSStatus`-shape
    /// `DCError` is bridged here so the caller can decide retry / log.
    case generateKeyFailed(underlying: Error)
    /// `DCAppAttestService.attestKey` failed. Persistent (key was
    /// generated but Apple's attestation servers refused). Caller may
    /// re-bootstrap with a fresh key OR fall back to HMAC.
    case attestationFailed(underlying: Error)
    /// `DCAppAttestService.generateAssertion` failed. Almost always
    /// transient (network) or temporary (Secure Enclave busy). Caller
    /// should retry once before falling back.
    case assertionFailed(underlying: Error)
    /// Keychain persistence of the keyID failed AND no in-memory cache
    /// was available. Subsequent calls would have to re-bootstrap a
    /// fresh key, losing the existing server-side attestation.
    case keychainPersistFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "App Attest is not supported on this device."
        case .disabledForTests:
            return "App Attest is disabled in UI test mode."
        case let .generateKeyFailed(error):
            return "App Attest key generation failed: \(error.localizedDescription)"
        case let .attestationFailed(error):
            return "App Attest attestation failed: \(error.localizedDescription)"
        case let .assertionFailed(error):
            return "App Attest assertion failed: \(error.localizedDescription)"
        case let .keychainPersistFailed(error):
            return "App Attest keyID persistence failed: \(error.localizedDescription)"
        }
    }
}

/// Minimal protocol over `DCAppAttestService` so unit tests can substitute
/// a deterministic in-memory implementation. The real wrapper below adapts
/// the Apple framework's completion-handler API into async/await.
protocol AppAttestServiceProtocol: Sendable {
    /// `true` iff `DCAppAttestService.shared.isSupported` is true and the
    /// runtime hasn't disabled App Attest via test flags.
    var isSupported: Bool { get }

    /// Wrapper around `DCAppAttestService.generateKey(completionHandler:)`.
    /// Returns the base64-encoded keyID.
    func generateKey() async throws -> String

    /// Wrapper around `DCAppAttestService.attestKey(_:clientDataHash:completionHandler:)`.
    /// Returns the CBOR-encoded attestation object as `Data`.
    func attestKey(keyID: String, clientDataHash: Data) async throws -> Data

    /// Wrapper around `DCAppAttestService.generateAssertion(_:clientDataHash:completionHandler:)`.
    /// Returns the CBOR-encoded assertion as `Data`.
    func generateAssertion(keyID: String, clientDataHash: Data) async throws -> Data
}

/// Production-facing wrapper that drives the real
/// `DCAppAttestService.shared`. Adapts the Apple framework's
/// completion-handler API into async/await.
struct LiveAppAttestService: AppAttestServiceProtocol {
    var isSupported: Bool {
        // VOL-227 + VOL-149: deterministic test mode shortcuts to
        // unsupported so journey tests don't hit the simulator's App
        // Attest daemon (which can hang the runner for minutes).
        guard !VolumeArcRuntimeFlags.isDeterministicMode else { return false }
        #if canImport(DeviceCheck)
        return DCAppAttestService.shared.isSupported
        #else
        return false
        #endif
    }

    func generateKey() async throws -> String {
        #if canImport(DeviceCheck)
        try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.generateKey { keyID, error in
                if let error {
                    continuation.resume(throwing: VolumeArcAppAttestError.generateKeyFailed(underlying: error))
                    return
                }
                guard let keyID else {
                    continuation.resume(throwing: VolumeArcAppAttestError.generateKeyFailed(
                        underlying: NSError(domain: "VolumeArcAppAttest", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "generateKey returned nil keyID with no error.",
                        ])
                    ))
                    return
                }
                continuation.resume(returning: keyID)
            }
        }
        #else
        throw VolumeArcAppAttestError.notSupported
        #endif
    }

    func attestKey(keyID: String, clientDataHash: Data) async throws -> Data {
        #if canImport(DeviceCheck)
        try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash) { attestation, error in
                if let error {
                    continuation.resume(throwing: VolumeArcAppAttestError.attestationFailed(underlying: error))
                    return
                }
                guard let attestation else {
                    continuation.resume(throwing: VolumeArcAppAttestError.attestationFailed(
                        underlying: NSError(domain: "VolumeArcAppAttest", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "attestKey returned nil attestation with no error.",
                        ])
                    ))
                    return
                }
                continuation.resume(returning: attestation)
            }
        }
        #else
        throw VolumeArcAppAttestError.notSupported
        #endif
    }

    func generateAssertion(keyID: String, clientDataHash: Data) async throws -> Data {
        #if canImport(DeviceCheck)
        try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash) { assertion, error in
                if let error {
                    continuation.resume(throwing: VolumeArcAppAttestError.assertionFailed(underlying: error))
                    return
                }
                guard let assertion else {
                    continuation.resume(throwing: VolumeArcAppAttestError.assertionFailed(
                        underlying: NSError(domain: "VolumeArcAppAttest", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "generateAssertion returned nil with no error.",
                        ])
                    ))
                    return
                }
                continuation.resume(returning: assertion)
            }
        }
        #else
        throw VolumeArcAppAttestError.notSupported
        #endif
    }
}

/// Coordinates the App Attest key + attestation + per-request assertion
/// lifecycle. Persists the keyID to Keychain so a fresh key only happens
/// on first launch (or after explicit `reset()`). The attestation object
/// is cached in-memory; Phase B will persist it to the relay's
/// device-registry once the server endpoint exists.
actor VolumeArcAppAttestCoordinator {
    private let service: AppAttestServiceProtocol
    private let secureStore: VolumeArcSecureStore
    private let keyIDKey = "ai.relay.appattest.keyID"

    /// In-memory cache for the attestation object. The size is ~1-3 KB
    /// CBOR (per Apple's published example), so retaining it for the
    /// app's lifetime is acceptable.
    private var attestationCache: Data?

    init(
        service: AppAttestServiceProtocol = LiveAppAttestService(),
        secureStore: VolumeArcSecureStore = VolumeArcSecureStore()
    ) {
        self.service = service
        self.secureStore = secureStore
    }

    /// Lazily bootstrap a key (generate + attest) if one isn't already
    /// persisted. Returns the keyID, which callers MUST use for all
    /// subsequent assertion calls. Failures surface as
    /// `VolumeArcAppAttestError` and the caller decides whether to
    /// fall back to the HMAC path.
    func bootstrapKeyIfNeeded(challenge: Data) async throws -> String {
        guard service.isSupported else {
            throw VolumeArcAppAttestError.notSupported
        }

        if let existing = try? secureStore.load(keyIDKey), existing.isEmpty == false {
            return existing
        }

        let keyID = try await service.generateKey()
        let hash = Data(SHA256.hash(data: challenge))
        let attestation = try await service.attestKey(keyID: keyID, clientDataHash: hash)
        attestationCache = attestation

        do {
            try secureStore.save(keyID, for: keyIDKey)
        } catch {
            // The key still works for the current session even if Keychain
            // failed — Phase B's server-side flow will re-bootstrap on a
            // fresh keyID on next launch. We surface the error so the
            // telemetry sink records it but the assertion path can
            // continue.
            throw VolumeArcAppAttestError.keychainPersistFailed(underlying: error)
        }

        return keyID
    }

    /// Returns the cached attestation object if one was produced in the
    /// current session. `nil` if `bootstrapKeyIfNeeded` hasn't run yet —
    /// the keyID alone isn't enough for the relay; Phase B will need this
    /// CBOR blob the first time the relay sees a new device.
    func cachedAttestation() -> Data? {
        attestationCache
    }

    /// Produce an assertion over the given request body. The relay (in
    /// Phase B) will verify it against the previously-attested public
    /// key for this keyID. `requestBody` is hashed inside this method so
    /// callers don't have to think about the hash domain.
    func assertion(over requestBody: Data, nonce: Data) async throws -> AppAttestAssertion {
        guard service.isSupported else {
            throw VolumeArcAppAttestError.notSupported
        }

        guard let keyID = try? secureStore.load(keyIDKey), keyID.isEmpty == false else {
            // No bootstrapped key — caller has to call
            // `bootstrapKeyIfNeeded` first. Surfacing as `notSupported`
            // lets the HMAC fallback kick in without a new error case.
            throw VolumeArcAppAttestError.notSupported
        }

        // clientDataHash = SHA256(requestBody || nonce). The nonce
        // makes the assertion replay-resistant — Phase B's server will
        // hand out short-lived nonces and verify each assertion against
        // exactly one.
        var clientData = Data()
        clientData.append(requestBody)
        clientData.append(nonce)
        let hash = Data(SHA256.hash(data: clientData))

        let blob = try await service.generateAssertion(keyID: keyID, clientDataHash: hash)
        return AppAttestAssertion(keyID: keyID, assertion: blob, nonce: nonce)
    }

    /// Resets the persisted keyID. Used by recovery flows when Phase B
    /// reports that the server-side attestation record is missing or
    /// invalid for this key. Surfaces as a soft-reset — next call to
    /// `bootstrapKeyIfNeeded` regenerates from scratch.
    func reset() {
        attestationCache = nil
        try? secureStore.save("", for: keyIDKey)
    }
}

/// The wire-format bundle Phase B's relay expects on each authenticated
/// request. Wraps the assertion data plus the keyID + nonce so the server
/// can look up the right public key and verify replay protection in one
/// header roundtrip.
struct AppAttestAssertion: Sendable, Equatable {
    let keyID: String
    let assertion: Data
    let nonce: Data
}
