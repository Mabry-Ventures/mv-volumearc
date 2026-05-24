# App Attest — design spec

> **Status:** Phase A shipped (VOL-224); Phase B implemented (VOL-225); Phase C cutover remains open (VOL-226).
> **Owner:** @jared
> **Audit linkage:** Wave 1 critical-severity audit finding F-S-002 (relay device-anchor authenticity).

Apple's App Attest establishes that a request to the Cloudflare Worker relay (`relay/`) comes from a genuine instance of our app on a real device, not from a tampered or repackaged binary. Today the relay authenticates with HMAC-SHA256 of a per-device UUID against a shared signing key. The HMAC path proves "the request came from a device that has a valid signing key" — it doesn't prove the binary is unmodified, the app is signed by Mabry Ventures, or the request came from Apple hardware. App Attest closes that gap.

This document is the design spec for the 3-phase rollout:

| Phase | Ticket | Scope | Status |
|---|---|---|---|
| A | VOL-224 | Client-side service + key lifecycle + per-request assertion API | **Shipped** — service compiles, unit tests pass |
| B | VOL-225 | Server-side CBOR + X.509 chain validation in the Cloudflare Worker, new `/v1/attest/*` endpoints, iOS header integration with HMAC fallback | **Implemented** — Worker validates attestation/assertions; capable clients send `X-VA-Attest-*` headers; unsupported devices fall back to HMAC during the grace period |
| C | VOL-226 | Cutover from HMAC-required to App-Attest-required; retire HMAC | **Not started** |

## Phase A — client-side (VOL-224, landed)

### Files

  * `App/VolumeArcAppAttestService.swift`
    - `VolumeArcAppAttestError` — error taxonomy for callers
    - `AppAttestServiceProtocol` — minimal protocol over `DCAppAttestService` so unit tests can substitute a deterministic mock
    - `LiveAppAttestService` — async/await wrapper around `DCAppAttestService.shared`. Adapts completion-handler API; short-circuits to `.notSupported` in `-UITestMode 1` so journey tests don't hit the simulator's flaky App Attest daemon
    - `VolumeArcAppAttestCoordinator` — actor owning the lifecycle: bootstrap (generate + attest a Secure Enclave key on first run), reuse persisted keyID once relay-confirmed, persist the attestation object for the initial bootstrap roundtrip, produce per-request assertions over `SHA256(requestBody ‖ nonce)`, and `reset()` for Phase B recovery flows
    - `AppAttestAssertion` — wire-format bundle the relay will consume on each authenticated request
  * `App/VolumeArcAppAttestRelaySessionProvider.swift`
    - Wraps the legacy HMAC provider, fetches relay challenges, posts bootstrap attestations, and attaches assertion headers to `/v1/coach` requests.
    - `VolumeArcRelayAuthMode`: `hmac`, `appAttest`, or `appAttestPreferHMACFallback` (default).

  * `Tests/VolumeArcAppTests/VolumeArcAppAttestCoordinatorTests.swift` — 8 unit tests pinning the coordinator's lifecycle + hash domain

### Phase B transition behavior

  * The iOS app still sends the HMAC `Authorization` header. This keeps old clients, simulators, and unsupported devices working during the Phase B telemetry window.
  * Capable devices also attach `X-VA-Attest-Key-ID`, `X-VA-Attest-Assertion`, and `X-VA-Attest-Nonce` to coach requests.
  * If App Attest is unsupported or temporarily fails in `appAttestPreferHMACFallback` mode, the app records `relay.auth` telemetry and sends the HMAC-only request.
  * If any App Attest header is present but invalid, the relay returns 401 instead of falling back. This prevents downgrade-by-tamper.
  * The app includes App Attest entitlements (`development` for Debug, `production` for Release). Distribution provisioning must support the capability before archive/signing will succeed.

## Phase B — server-side validation (VOL-225, implemented)

### New relay endpoints

  * `POST /v1/attest/bootstrap`
    - Request: `{ keyID: string, attestationObject: string (base64-encoded CBOR), challenge: string }`
    - Response (success): `{ ok: true, attestedAt: ISO8601, environment: "development" | "production" }`
    - Response (failure): `{ error: "attestation_invalid", reason: "..." }`
    - Semantics: client sends once per install, after `bootstrapKeyIfNeeded()`. Server validates the attestation object (see "validation chain" below), then atomically consumes the challenge and stores the device's public key + counter (starts at 0) in the `APP_ATTEST_STATE` Durable Object keyed by `keyID`.

  * `POST /v1/attest/challenge`
    - Request: none (auth via existing HMAC bearer)
    - Response: `{ challenge: string (base64), expiresAt: ISO8601 }`
    - Semantics: server hands the client a short-lived nonce (5 min TTL) the client wraps into `clientData` for `bootstrap` AND for the next `assert` round-trip. The nonce defeats replay attacks. Stored in KV with the issuing deviceID; consumed-on-use.

  * `POST /v1/coach` (existing, extended)
    - Adds optional headers: `X-VA-Attest-Key-ID`, `X-VA-Attest-Assertion` (base64 CBOR), `X-VA-Attest-Nonce`
    - When all three are present, server validates the assertion against the stored public key for `keyID`, checks the signature covers `SHA256(requestBody || nonce)`, then asks the `APP_ATTEST_STATE` Durable Object to atomically consume the nonce and advance the counter. On success: proceed to Gemini proxy. On failure: 401 `{ error: "attestation_invalid" }`.
    - When the headers are absent (Phase B grace period, Phase C cutover hasn't flipped): fall back to HMAC. After Phase C flips `REQUIRE_APP_ATTEST=true`, HMAC-only coach requests return 410 `{ error: "app_attest_required" }`. Worker logs structured `relay.auth` events (`app_attest_succeeded`, `app_attest_failed`, `hmac_fallback_used`, `app_attest_required`) so Phase C can use production signal instead of guesswork.

### Validation chain (per Apple's spec)

For both `bootstrap` and `assert`:

  1. Decode the CBOR-encoded `attestationObject` (or assertion), requiring `fmt == "apple-appattest"` for bootstrap objects, into `{ attStmt, authData }`.
     - Library: `cbor-x`, smoke-tested with `wrangler deploy --dry-run`.
  2. Verify `statement.x5c` is a valid X.509 certificate chain leading to Apple's App Attest root CA.
     - Apple's root: <https://www.apple.com/certificateauthority/private/AppleAppAttestationRootCA.pem>
     - Pin the root cert hash in the Worker (not a URL fetch).
  3. Verify the leaf cert's public key was used to sign the assertion / attestation statement.
     - `crypto.subtle.verify` with ES256 (the only algorithm App Attest uses).
  4. For `bootstrap` only: verify the attestation extension OID `1.2.840.113635.100.8.2` contains `SHA256(authData || clientDataHash)`.
  5. For `bootstrap` only: verify `authData.aaguid` matches `appattestdevelop` (development) or `appattest` plus seven zero bytes (production), per Apple docs.
  6. For `bootstrap` only: verify the credential ID in `authData` matches the client's reported `keyID`.
  7. For `assert` only: verify `authData.counter` is strictly greater than the stored counter for this `keyID`. Then increment.

### KV namespaces

  * `APP_ATTEST_STATE` Durable Object — keyed by `keyID` for public keys/counters and by base64 challenge for nonce records. It is the production state store because Durable Object storage gives the relay a strongly consistent transaction for "consume nonce + update counter."
  * `ATTEST_KEYS` / `ATTEST_CHALLENGES` KV bindings are retained only as local-test and emergency rollback fallbacks when the Durable Object binding is absent.

### Risks / failure modes Phase B must handle

  * **Apple revokes the leaf cert mid-session**: surface as `attestation_invalid`; client `reset()`s and re-bootstraps.
  * **Counter regression** (replay attempt): hard 401, telemetry alert.
  * **Bootstrap/assertion race**: two simultaneous requests from the same install. The Durable Object transaction allows only one request to consume a challenge and advance the stored counter, so replay attempts fail even when they arrive concurrently.

### Testing

  * Client-side focused tests cover unsupported-device fallback, appAttest-only failure, HMAC mode bypass, confirmed-key reuse, and stale-unconfirmed-key reset.
  * Worker tests cover challenge authorization, HMAC fallback, Phase C `REQUIRE_APP_ATTEST`, incomplete header rejection, malformed bootstrap rejection, and a generated P-256 assertion fixture that proves valid assertions advance the counter while replayed counters fail.
  * Bundling smoke test: `npx wrangler deploy --dry-run --outdir /tmp/volumearc-relay-dry-run`.

## Phase C — cutover + retire HMAC (VOL-226, not started)

  1. Telemetry analysis: confirm ≥ 99% of production coach requests in the last 7 days carry valid App Attest headers (`attestation_missing` event rate < 1%).
  2. Confirm Release provisioning includes the App Attest entitlement already declared in `App/VolumeArc.Release.entitlements`.
  3. Flip Worker env var `REQUIRE_APP_ATTEST=true` so the HMAC fallback returns 410 when attestation headers are absent.
  4. Wait 1-2 release cycles for the cutover to soak in production. Monitor `coach.relay_unauthorized` telemetry.
  5. Remove HMAC code paths from `VolumeArcRelaySessionProvider` + relay `authenticate()`. Remove the `RELAY_SIGNING_KEY` secret rotation runbook from `docs/RELEASE.md`.

## Open questions

  * **Where does the device counter go for users with multiple devices?** Per Apple, each install gets a fresh attestation. iCloud sync of `keyID` is not supported (and would defeat the purpose). Each new device install re-bootstraps. The relay tracks them as independent keyIDs; a `users.deviceCount` analytic surfaces multi-device behavior.
  * **What happens on unsupported form factors?** `DCAppAttestService.isSupported` can return false on simulator and Mac Catalyst. v1.0 is iPhone-only with paired Apple Watch, so Phase C should decide whether any unsupported cohort is intentionally blocked or kept on a narrower fallback.

## References

  * Apple's [Establishing your app's integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-apps-integrity) docs.
  * Apple's [Validating apps that connect to your server](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server) docs.
  * VOL-224 PR (#230) — Phase A landing PR.
  * Audit finding F-S-002 in `docs/AUDIT.md` (the 2026-05-01 forensic production-readiness audit).
