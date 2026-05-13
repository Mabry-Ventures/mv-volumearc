# Security & privacy posture

> **Audience:** App Store reviewers, security-curious users, contributors who touch anything that handles user data or talks to a network. Code-level architecture lives in [`docs/ARCHITECTURE.md`](ARCHITECTURE.md); this doc covers the *threat model* and the *policies*.
>
> **Status:** v1.0 launch baseline. Re-review before any major surface change (new third-party processor, new persisted PII, new network egress).

## Threat model

| Asset | Adversary | Mitigation |
|---|---|---|
| User HealthKit data (workouts, HR, active energy on watch) | Network attacker, third-party process running on the device, malicious shared device | Reads gated behind Apple's system HealthKit prompt. Reads stay in Apple Health on-device; nothing is uploaded to VolumeArc-owned servers. Per-platform read scope is least-privilege (iOS reads workouts only; watchOS reads workouts + HR + active energy because `HKLiveWorkoutDataSource` collects them during the session). See `HealthKitAuthorizationScope` in `VolumeArcCore/Health/HealthStore.swift`. |
| User workouts persisted by VolumeArc | Same | SwiftData → CloudKit private database. CloudKit's private DB is per-user, encrypted in transit and at rest by Apple, accessible only to the signed-in iCloud account. VolumeArc operators have **zero access** to the contents. |
| Coach prompts (free text the user types or speaks) | Coach-relay middleman, Gemini operator | TLS to `relay.volumearc.app` (Cloudflare Worker), TLS from the Worker to `generativelanguage.googleapis.com`. Prompts are forwarded; the Worker logs the request shape (path, status code, latency) but does NOT log prompt content or response bodies — see `relay/src/worker.ts`. Privacy-mode setting (`profile.privacy-mode`) controls a redaction layer that scrubs PII before the prompt leaves the device. |
| Crash reports + breadcrumbs (Sentry) | Sentry employee with database access; Sentry security incident | `VolumeArcSentryPIIScrubber` (VOL-72) strips known-PII fields (user name, email, HealthKit values, exercise notes) from every `Event` and `Breadcrumb` before send. Session Replay is off by default in v1.0; if/when enabled (post VOL-171 review), the masking config must be re-audited against this threat model. |
| Subscription receipts + entitlements (StoreKit) | Network attacker between app and Apple's IAP server | Handled by `StoreKit 2`'s verified `Transaction` path; we don't roll our own receipt validation. `purchasedProductIDs` is in-memory only — re-derived from `Transaction.currentEntitlements` on each launch. Revocation handled correctly (VOL-142) so a refunded user is downgraded immediately on the next `Transaction.updates` event. |
| App Group secrets (relay session token, device identity fallback) | Process running under another app's identity, jailbroken device, attacker with physical device + passcode | Primary: Keychain (`VolumeArcSecureStore`) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so the secret never roams via iCloud Keychain. Fallback: a suite-scoped `UserDefaults` (`com.mabryventures.VolumeArc.secure-fallback`) for cases where Keychain access fails (simulator-only quirk; never relied on in production). |
| Universal-link deep-link target | Spoofed deep link in a phishing email / SMS | The Universal Link domain (`volumearc.app`) is configured with `applinks` AASA; iOS validates the association at install time, then routes to our handler. Our handler (`VolumeArcApp.handle(url:)`) routes deterministically by path and ignores unrecognized paths. No path executes a code-load or eval. |

## Network egress

VolumeArc talks to exactly these hosts:

| Host | Purpose | Auth | TLS |
|---|---|---|---|
| `relay.volumearc.app` | Coach prompt forwarding to Gemini | Session token rotated per launch (HMAC-derived; see `VolumeArcRelaySessionProvider`) | TLS 1.2+ pinned to Cloudflare's chain |
| `o*.ingest.us.sentry.io` | Crash + telemetry events | Sentry DSN (publishable; no secret in client) | TLS 1.2+ |
| Apple-owned (HealthKit, CloudKit, App Store, Sign in with Apple, APNs, Universal Links) | OS-level integration | OS-managed | OS-managed |

No third-party analytics SDK, no ad SDK, no remote-config service (feature flags are local — `LocalFeatureFlagProvider`). Any new network egress requires an explicit audit pass through this doc + the privacy manifest (`App/PrivacyInfo.xcprivacy`) + the App Store privacy questionnaire.

## HMAC signing for the coach relay

The Cloudflare Worker (`relay/`) requires every coach request to carry an `Authorization: Bearer <session-token>` header. The session token is HMAC-derived per-launch from a device-scoped identity stored in the Keychain. Specifically:

1. On first launch, `VolumeArcRelaySessionProvider` generates a random 32-byte device-identity and stores it in the Keychain via `VolumeArcSecureStore`.
2. On each launch, the provider derives a fresh session token by HMAC-SHA256 of `(device-identity, current-day-bucket)` so a captured token expires within 24 hours.
3. The Worker validates the HMAC server-side; failed validation returns 401 and the app rotates / re-fetches.

The shared HMAC secret is configured as a Cloudflare Worker secret (set via `wrangler secret put`), never committed to the repo. The client-side device identity never leaves the device.

## Keychain vs UserDefaults

**Keychain (via `VolumeArcSecureStore`)** for secrets that need durability across reinstalls or that grant access to network resources:

- Relay session-token derivation seed (`device-identity`).
- StoreKit's own entitlement cache (managed by `StoreKit 2`; we don't store this directly).

**UserDefaults** for non-secret app state that's safe to leak in a backup:

- User profile + preferences (`UserProfileRepository` over SwiftData, NOT UserDefaults — preferences in UserDefaults are deprecated-style and shouldn't grow).
- Telemetry rolling buffer (`UserDefaultsTelemetrySink`) — bounded to last 100 events, PII-scrubbed before write.
- Runtime flags (`VolumeArcRuntimeFlags`) — deterministic-mode, simulate-prompts, etc. All test-only or operator-visible.
- Notification scheduling state.
- Onboarding completion + step state.

The dividing line: if it's a secret OR if its leakage would let an attacker make network calls as the user, it lives in Keychain. Otherwise UserDefaults is the right default.

## PII handling

**On-device data classified as PII:**
- User profile (name, age, training years, body weight if entered) — `UserProfileRepository` / SwiftData
- Coach memory (free text the user typed) — `CoachMemoryRepository`
- Workout notes (free text per session) — `WorkoutRecord.notes`
- HealthKit-sourced data (workouts, HR, active energy)

**Where PII may travel off-device:**

| Destination | Allowed PII | Mitigation |
|---|---|---|
| `relay.volumearc.app` → Gemini | Coach prompt body (free text the user typed) | Privacy-mode setting controls redaction. The relay logs request *shape* only (path / status / latency), never bodies. Gemini's data-handling per its API terms. |
| Sentry | Stack frames, breadcrumb trail, OS+device metadata | `VolumeArcSentryPIIScrubber` strips known PII fields from every Event / Breadcrumb before send (VOL-72). Session Replay is **off** in v1.0. |
| CloudKit private DB | Full workout records + profile + coach memory | Apple-managed encryption in transit and at rest; per-user private; VolumeArc operators have zero access. |
| Apple Health | Workouts (read + write); on watchOS also HR + active energy reads | User controls the grant; revocable via Settings → Privacy → Health. |
| Apple's IAP / receipts | Transaction metadata (no user content) | OS-managed. |

**PII NEVER travels to:**
- VolumeArc-owned analytics (we don't have an analytics SDK)
- Third-party ad networks (none)
- Remote config / experimentation services (none)

## Vulnerability disclosure

Email **security@volumearc.com**. PGP key forthcoming; until then, use TLS-mailbox-to-TLS-mailbox (any major provider) and include the word `security` in the subject so it auto-routes via Fastmail rules.

Response timeline:
- Acknowledgment within 2 business days.
- Triage + severity assessment within 5 business days.
- Critical (RCE, account compromise, mass data exfiltration): mitigation in flight within 24 hours of validation.
- High (data leak under specific conditions, auth bypass for a single account): mitigation in next release.
- Medium / Low: tracked in Linear, addressed per priority.

Coordinated disclosure preferred. We commit to **not** pursuing legal action against good-faith researchers operating within the spirit of this policy.

## Vulnerability surface monitored continuously

- **CodeQL** (`.github/workflows/codeql.yml`) — Swift + JS/TS SAST; `security-extended` query suite; runs on push to main + weekly cron.
- **TruffleHog** (`.github/workflows/trufflehog.yml`) — secret-leak scan on every PR diff + full-history on main push.
- **Dependabot** — Swift / GitHub Actions / Bundler updates open as explicit PRs; minor + patch grouped per ecosystem; major lands as individual PRs we explicitly review.
- **Sentry release health** — `VolumeArcSentryConfiguration` and `docs/INCIDENTS.md` alert routing.

## Related docs

- [`docs/PLATFORM.md`](PLATFORM.md) — canonical platform overview
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — module structure + dependency graph
- [`docs/INCIDENTS.md`](INCIDENTS.md) — incident response runbook (VOL-156)
- [`docs/RELAY.md`](RELAY.md) — Cloudflare Worker architecture
- [`docs/CONTRIBUTING.md`](CONTRIBUTING.md) — dev setup; security tooling section documents the CodeQL + TruffleHog wiring
