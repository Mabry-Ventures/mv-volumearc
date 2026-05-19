# App Attest — design spec

> **Status:** Phase A scaffolded (VOL-224); Phase B + C not yet implemented (VOL-225, VOL-226).
> **Owner:** @jared
> **Audit linkage:** Wave 1 critical-severity audit finding F-S-002 (relay device-anchor authenticity).

Apple's App Attest establishes that a request to the Cloudflare Worker relay (`relay/`) comes from a genuine instance of our app on a real device, not from a tampered or repackaged binary. Today the relay authenticates with HMAC-SHA256 of a per-device UUID against a shared signing key. The HMAC path proves "the request came from a device that has a valid signing key" — it doesn't prove the binary is unmodified, the app is signed by Mabry Ventures, or the request came from Apple hardware. App Attest closes that gap.

This document is the design spec for the 3-phase rollout:

| Phase | Ticket | Scope | Status |
|---|---|---|---|
| A | VOL-224 | Client-side service + key lifecycle + per-request assertion API | **Scaffolded, dormant** — service compiles, unit tests pass, no relay integration yet |
| B | VOL-225 | Server-side CBOR + X.509 chain validation in the Cloudflare Worker, new `/v1/attest/*` endpoints | **Not started** |
| C | VOL-226 | Cutover from HMAC-required to App-Attest-required; retire HMAC | **Not started** |

## Phase A — client-side (VOL-224, landed)

### Files

  * `App/VolumeArcAppAttestService.swift`
    - `VolumeArcAppAttestError` — error taxonomy for callers
    - `AppAttestServiceProtocol` — minimal protocol over `DCAppAttestService` so unit tests can substitute a deterministic mock
    - `LiveAppAttestService` — async/await wrapper around `DCAppAttestService.shared`. Adapts completion-handler API; short-circuits to `.notSupported` in `-UITestMode 1` so journey tests don't hit the simulator's flaky App Attest daemon
    - `VolumeArcAppAttestCoordinator` — actor owning the lifecycle: bootstrap (generate + attest a Secure Enclave key on first run), reuse persisted keyID, produce per-request assertions over `SHA256(requestBody ‖ nonce)`, and `reset()` for Phase B recovery flows
    - `AppAttestAssertion` — wire-format bundle the relay will consume on each authenticated request

  * `Tests/VolumeArcAppTests/VolumeArcAppAttestCoordinatorTests.swift` — 8 unit tests pinning the coordinator's lifecycle + hash domain

### What Phase A does NOT do

  * It does NOT modify `VolumeArcRelaySessionProvider`. The HMAC `Authorization` header is the only auth signal the relay sees today. Phase B's server-side validation must ship before clients start sending App Attest headers — otherwise the headers would be plain ignored, adding latency without payoff.
  * It does NOT add the `com.apple.developer.devicecheck.appattest-environment` entitlement to the iOS app. That entitlement file change is part of Phase C cutover; Apple's framework gracefully degrades to `.notSupported` without it in Phase A.
  * It does NOT modify HMAC. HMAC retires in Phase C, after Phase B's server validation is proven stable in production.

## Phase B — server-side validation (VOL-225, not started)

### New relay endpoints

  * `POST /v1/attest/bootstrap`
    - Request: `{ keyID: string, attestationObject: string (base64-encoded CBOR), challenge: string }`
    - Response (success): `{ ok: true, attestedAt: ISO8601 }`
    - Response (failure): `{ error: "attestation_invalid", reason: "..." }`
    - Semantics: client sends once per install, after `bootstrapKeyIfNeeded()`. Server validates the attestation object (see "validation chain" below), stores the device's public key + counter (starts at 0) in a KV namespace keyed by `keyID`.

  * `POST /v1/attest/challenge`
    - Request: none (auth via existing HMAC bearer)
    - Response: `{ challenge: string (base64), expiresAt: ISO8601 }`
    - Semantics: server hands the client a short-lived nonce (5-15 min TTL) the client wraps into `clientData` for `bootstrap` AND for the next `assert` round-trip. The nonce defeats replay attacks. Stored in KV with the issuing deviceID; consumed-on-use.

  * `POST /v1/coach` (existing, extended)
    - Adds optional headers: `X-VA-Attest-Key-ID`, `X-VA-Attest-Assertion` (base64 CBOR), `X-VA-Attest-Nonce`
    - When all three are present, server validates the assertion against the stored public key for `keyID`, checks the signature covers `SHA256(requestBody || nonce)`, checks the counter is greater than the stored counter (then increments). On success: proceed to Gemini proxy. On failure: 401 `{ error: "attestation_invalid" }`.
    - When the headers are absent (Phase B grace period, Phase C cutover hasn't flipped): fall back to HMAC. Phase B logs `attestation_missing` telemetry for analytics — once we see ≥ 99% of requests carry attestation, we're ready for Phase C.

### Validation chain (per Apple's spec)

For both `bootstrap` and `assert`:

  1. Decode the CBOR-encoded `attestationObject` (or assertion) into `{ format, statement, authData }`.
     - Library: TBD (Cloudflare Workers compatible CBOR decoder; `cbor-x` is plausible but Workers runtime compatibility needs verification).
  2. Verify `statement.x5c` is a valid X.509 certificate chain leading to Apple's App Attest root CA.
     - Apple's root: <https://www.apple.com/certificateauthority/private/AppleAppAttestationRootCA.pem>
     - Pin the root cert hash in the Worker (not a URL fetch).
  3. Verify the leaf cert's public key was used to sign the assertion / attestation statement.
     - `crypto.subtle.verify` with ES256 (the only algorithm App Attest uses).
  4. For `bootstrap` only: verify the attestation extension OID `1.2.840.113635.100.8.2` contains `SHA256(authData || clientDataHash)`.
  5. For `bootstrap` only: verify `authData.aaguid` matches `appattestdevelop` (sandbox) or all-zeros (production), per Apple docs.
  6. For `bootstrap` only: verify the credential ID in `authData` matches the client's reported `keyID`.
  7. For `assert` only: verify `authData.counter` is strictly greater than the stored counter for this `keyID`. Then increment.

### KV namespaces

  * `ATTEST_KEYS` — keyed by `keyID`. Value: `{ publicKey: JWK, counter: number, attestedAt: ISO8601, deviceID: string }`. TTL: 1 year (matches App Store transfer policy).
  * `ATTEST_CHALLENGES` — keyed by challenge hex. Value: `{ deviceID, issuedAt }`. TTL: 15 min. Consumed-on-use (delete after first use).

### Risks / failure modes Phase B must handle

  * **Apple revokes the leaf cert mid-session**: surface as `attestation_invalid`; client `reset()`s and re-bootstraps.
  * **Counter regression** (replay attempt): hard 401, telemetry alert.
  * **Bootstrap race**: two simultaneous requests from the same install. KV's eventual consistency could allow both to succeed and store conflicting attestations. Mitigation: serialize via a per-`keyID` Durable Object lock OR accept "last write wins" since the second bootstrap is identical to the first.

### Testing

  * Reuse the `AppAttestServiceProtocol` mock from Phase A on the client side to generate deterministic attestation/assertion blobs for integration tests against a local `wrangler dev` Worker.
  * Server-side: pure-function tests for the validation chain (CBOR decode + cert chain + signature verify) using Apple's published example vectors.
  * End-to-end: a single XCUITest that bootstraps + sends one coach request + asserts 200; another that tampers with the assertion bytes and asserts 401.

## Phase C — cutover + retire HMAC (VOL-226, not started)

  1. Telemetry analysis: confirm ≥ 99% of production coach requests in the last 7 days carry valid App Attest headers (`attestation_missing` event rate < 1%).
  2. Add the `com.apple.developer.devicecheck.appattest-environment` entitlement to the iOS app (`production` value). Requires a new provisioning profile + App Store submission.
  3. Flip a Worker env var `REQUIRE_APP_ATTEST=true` so the HMAC fallback returns 401 when attestation headers are absent.
  4. Wait 1-2 release cycles for the cutover to soak in production. Monitor `coach.relay_unauthorized` telemetry.
  5. Remove HMAC code paths from `VolumeArcRelaySessionProvider` + relay `authenticate()`. Remove the `RELAY_SIGNING_KEY` secret rotation runbook from `docs/RELEASE.md`.

## Open questions

  * **CBOR library choice for the Worker.** `cbor-x` and `cbor-web` are the candidates. Workers runtime supports limited Node compat — both need a smoke-test deploy before committing.
  * **Where does the device counter go for users with multiple devices?** Per Apple, each install gets a fresh attestation. iCloud sync of `keyID` is not supported (and would defeat the purpose). Each new device install re-bootstraps. The relay tracks them as independent keyIDs; a `users.deviceCount` analytic surfaces multi-device behavior.
  * **What happens on iPad / Mac Catalyst?** `DCAppAttestService.isSupported` returns false on Mac Catalyst. Those users would always fall through to HMAC under Phase B's grace period. Phase C makes them blocked unless we also accept a softer fallback — TBD with product.

## References

  * Apple's [Establishing your app's integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-apps-integrity) docs.
  * Apple's [Validating apps that connect to your server](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server) docs.
  * VOL-224 PR (#230) — Phase A landing PR.
  * Audit finding F-S-002 in `docs/AUDIT.md` (the 2026-05-01 forensic production-readiness audit).
