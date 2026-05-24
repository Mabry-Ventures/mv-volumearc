# AI Relay (`volumearc-ai-relay`)

A Cloudflare Worker that proxies iOS coach requests to Google's Gemini API with SSE streaming, App Attest validation, HMAC transition fallback, and per-device rate limiting.

- **Worker name:** `volumearc-ai-relay`
- **Live endpoint (production):** `https://relay.volumearc.app` — custom domain configured via the `relay/wrangler.toml` route binding. Live since VOL-110.
- **Legacy endpoint (workers.dev fallback, deprecated):** `https://volumearc-ai-relay.jared-b6b.workers.dev` is **no longer routed**. Requests to this hostname return 404; do not point any new client, script, or workflow at it. Tracked here only so anyone reading old logs can identify the origin.
- **Source:** [`relay/`](../relay/)

## Models

| Tier | Gemini model | Header | Default |
|------|--------------|--------|---------|
| Flash Lite | `gemini-3.1-flash-lite-preview` | `X-Coach-Tier: flash-lite` | ✅ |
| Pro        | `gemini-3.1-pro-preview`        | `X-Coach-Tier: pro`        | Premium entitlement only |

Model IDs live in `relay/wrangler.toml` as `MODEL_DEFAULT` / `MODEL_PREMIUM`. Swapping a model is a `wrangler deploy` away — no iOS release.

## Endpoints

### `POST /v1/health`
Returns `{ ok: true, model_default, model_premium }`. No auth required; useful for uptime monitoring.

### `POST /v1/coach`
Returns `Content-Type: text/event-stream` with per-token `data: {"text":"..."}` frames, terminated by `event: done`.

Request body:

```jsonc
{
  "intent": "progression" | "deload" | "form" | "recovery" | "substitution" | "free",
  "question": "user's question",
  "contextBlock": "readiness + recent sessions + plan",
  "style": "motivational" | "precise" | "playful",
  // Optional: iOS pre-renders the prompt via CoachPromptTemplate and sends
  // it verbatim so the template marker + system prompt stay on-device.
  "prompt": "<CoachPromptTemplate.render(...)>",
  "system": "<CoachPromptTemplate.systemPrompt(...)>"
}
```

Phase B auth headers:

```http
Authorization: Bearer <device_id>.<hmac_sha256_hex>
X-VA-Attest-Key-ID: <keyID>
X-VA-Attest-Assertion: <base64 CBOR assertion>
X-VA-Attest-Nonce: <base64 relay challenge>
```

Where `hmac_sha256_hex = HMAC-SHA256(RELAY_SIGNING_KEY, device_id)` rendered as lowercase hex.

During the VOL-225/VOL-226 transition, `Authorization` remains present on all iOS requests. Capable devices also send the `X-VA-Attest-*` headers. If those headers validate, the Worker authenticates via App Attest; if they are absent, the Worker uses the HMAC fallback unless `REQUIRE_APP_ATTEST=true`. If any App Attest header is present but invalid or incomplete, the Worker returns 401 and does not downgrade to HMAC. Once `REQUIRE_APP_ATTEST=true`, HMAC-only coach requests return 410 so retired clients can distinguish cutover from bad credentials.

### `POST /v1/attest/challenge`

Returns `{ challenge, expiresAt }` for HMAC-authenticated installs. Challenges are random 32-byte base64 values, stored with a 5-minute TTL, tied to the issuing device ID, and consumed on first use.

### `POST /v1/attest/bootstrap`

Validates the first-run App Attest attestation object and stores the install's public key/counter.

Request body:

```json
{
  "keyID": "<base64 App Attest key ID>",
  "attestationObject": "<base64 CBOR attestation object>",
  "challenge": "<challenge from /v1/attest/challenge>"
}
```

Success response:

```json
{ "ok": true, "attestedAt": "2026-05-24T00:00:00.000Z", "environment": "production" }
```

## Auth model

Each iOS install generates a stable UUID at first launch (persisted to Keychain), then HMAC-signs it with the shared `RELAY_SIGNING_KEY` that lives in Worker secrets + the iOS Keychain. That legacy credential remains the bootstrap/fallback channel during Phase B.

For App Attest-capable devices, the app:

1. Fetches a relay challenge with the HMAC header.
2. Generates/attests a `DCAppAttestService` key, posts the attestation object to `/v1/attest/bootstrap`, and stores the relay-confirmed key ID.
3. For each coach request, fetches a fresh challenge and sends an assertion over `SHA256(requestBody || challenge)`.

The Worker validates the Apple App Attestation Root CA chain, pins the root hash, verifies the nonce extension, checks the app ID hash (`APPLE_TEAM_ID.APPLE_BUNDLE_ID`), verifies the credential ID/key ID binding, stores the public key + counter in the `APP_ATTEST_STATE` Durable Object, and requires counters to increase for assertions. The Durable Object transaction atomically consumes each challenge and advances the counter, avoiding KV's eventual-consistency replay gap.

**Threat model (Phase B):**
- ✅ Protects the Gemini API key (never leaves the Worker)
- ✅ Rate limits by stable install ID
- ✅ Valid App Attest assertions prove the request came from a genuine VolumeArc build on Apple hardware
- ✅ Tampered App Attest headers fail closed instead of falling back
- ⚠️ HMAC-only clients still work during the Phase B grace period, so a determined attacker who reverse-engineers a TestFlight IPA can still mint fallback tokens until VOL-226 flips `REQUIRE_APP_ATTEST=true`.

## Rate limiting

Sliding 10-minute window per device, capped at 30 requests. Implemented via Workers KV (`RATE_LIMIT` binding, namespace ID in `wrangler.toml`). A 429 is returned when exceeded; iOS handles this by falling back through the three-tier provider chain to `LocalHeuristicAICoachProvider`.

Tuning the thresholds:

```toml
# relay/wrangler.toml
RATE_LIMIT_MAX_REQUESTS = "30"
RATE_LIMIT_WINDOW_SECONDS = "600"
```

## Local development

```bash
cd relay
npm install
wrangler login   # one-time per developer
wrangler dev     # spins up a local Worker against the deployed KV + secrets
```

Local `wrangler dev` uses the production Gemini key and KV by default. To isolate, use `--local` and seed fake env vars via `.dev.vars` (gitignored).

## Deployment

```bash
cd relay
npm install
npx wrangler deploy
```

Secrets (only set once, stored server-side encrypted):

```bash
npx wrangler secret put GEMINI_API_KEY      # Google AI Studio key
npx wrangler secret put RELAY_SIGNING_KEY   # 32-byte random, openssl rand -base64 32; Phase B bootstrap/fallback
```

Env vars (non-secret, live in `wrangler.toml`):
- `MODEL_DEFAULT`, `MODEL_PREMIUM`, `MAX_OUTPUT_TOKENS`, `REQUEST_TIMEOUT_MS`, `RATE_LIMIT_MAX_REQUESTS`, `RATE_LIMIT_WINDOW_SECONDS`
- `APPLE_TEAM_ID`, `APPLE_BUNDLE_ID` (or a full `APPLE_APP_ID`) for App Attest app-ID hash validation
- `REQUIRE_APP_ATTEST` (`false` in Phase B, `true` in Phase C)

Optional KV bindings:
- `ATTEST_KEYS` — legacy/local fallback App Attest public-key/counter store
- `ATTEST_CHALLENGES` — legacy/local fallback one-time challenge store

Production binds `APP_ATTEST_STATE` as a Durable Object and uses it for App Attest state. If that binding is absent, the Worker falls back to `ATTEST_KEYS` / `ATTEST_CHALLENGES`, or to `RATE_LIMIT` with `attest:*` prefixes, for local tests and emergency rollback builds.

## Wiring the iOS side

The iOS client reads three pieces of config at launch:

1. **Base URL** — from `VOLUMEARC_AI_RELAY_URL` env var (Xcode scheme for dev) OR `VolumeArcAIRelayURL` Info.plist key (release). Must be an HTTPS URL whose host is in the allowlist (`App/VolumeArcAIConfiguration.swift`).
2. **Signing key** — from `VOLUMEARC_RELAY_SIGNING_KEY` env var OR `VolumeArcRelaySigningKey` Info.plist key. Must match the Worker's `RELAY_SIGNING_KEY` secret exactly.
3. **Relay auth mode** — from `VOLUMEARC_RELAY_AUTH_MODE` env var OR `VolumeArcRelayAuthMode` Info.plist key. Default: `appAttestPreferHMACFallback`.

The base URL and signing key are bootstrapped into Keychain at first launch and read from there on subsequent launches. The auth mode remains an env/Info.plist switch. Rotating the signing key requires an iOS release while HMAC fallback remains active.

### For local development

Xcode scheme env vars (Edit Scheme → Run → Arguments → Environment Variables):

```bash
VOLUMEARC_AI_RELAY_URL  = https://relay.volumearc.app
VOLUMEARC_RELAY_SIGNING_KEY = <contents of relay/.secrets/relay_signing_key.txt>
VOLUMEARC_RELAY_AUTH_MODE = appAttestPreferHMACFallback
```

### For Release / TestFlight

Xcode Cloud injects the relay URL and signing key from workflow environment variables in `ci_scripts/ci_post_clone.sh` before archive:

```bash
VOLUMEARC_AI_RELAY_URL = https://relay.volumearc.app
VOLUMEARC_RELAY_SIGNING_KEY = <same value as Worker RELAY_SIGNING_KEY>
```

`VOLUMEARC_RELAY_SIGNING_KEY` must be marked secret in Xcode Cloud and must never live in git. Local release tooling (`fastlane ios beta` and `scripts/archive_for_distribution.sh`) reads the same env var, patches `App/Info.plist` only for the duration of the archive, then restores the source file.

## Promoting to `relay.volumearc.app`

When `volumearc.app` is added as a zone to the Mabry Ventures Cloudflare account:

1. Uncomment the `[[routes]]` block in `relay/wrangler.toml`
2. `wrangler deploy`
3. Confirm DNS is proxied (orange cloud) for the `relay` subdomain
4. Update `VOLUMEARC_AI_RELAY_URL` in the iOS config
5. Leave the `.workers.dev` host in the allowlist for a release cycle as a fallback

iOS does not require a release to change the URL — it reads from Info.plist / env var.

## Rotating secrets

**`GEMINI_API_KEY`:**
1. Generate new key at https://aistudio.google.com/apikey
2. `wrangler secret put GEMINI_API_KEY` (paste new value)
3. Revoke old key in AI Studio
4. Zero iOS impact

**`RELAY_SIGNING_KEY`:**
1. `openssl rand -base64 32 | wrangler secret put RELAY_SIGNING_KEY`
2. Update every iOS build's Info.plist value (new key goes into next TestFlight build)
3. Old iOS clients fail auth until they pick up the new key — acceptable if rotation is paired with a release, painful otherwise. Consider adding dual-key support here if rotation ever becomes routine.

## Observability

Worker logs stream to [Cloudflare dashboard → Workers → volumearc-ai-relay → Logs](https://dash.cloudflare.com/). Enable Workers Observability (already on via `[observability]` block in `wrangler.toml`) for structured log retention.
