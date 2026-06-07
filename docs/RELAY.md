# AI Relay (`volumearc-ai-relay`)

A Cloudflare Worker that proxies iOS coach requests to Google's Gemini API with SSE streaming, App Attest validation, and per-attested-key rate limiting.

- **Worker name:** `volumearc-ai-relay`
- **Live endpoint (production):** `https://relay.volumearc.app` — custom domain configured via the `relay/wrangler.toml` route binding. Live since VOL-110.
- **Legacy endpoint (workers.dev fallback, deprecated):** `https://volumearc-ai-relay.jared-b6b.workers.dev` is **no longer routed**. Requests to this hostname return 404; do not point any new client, script, or workflow at it. Tracked here only so anyone reading old logs can identify the origin.
- **Source:** [`relay/`](../relay/)

## Models

| Tier | Gemini model | Header | Default |
|------|--------------|--------|---------|
| Flash Lite | `gemini-3.1-flash-lite` | `X-Coach-Tier: flash-lite` | Done |
| Pro        | `gemini-3.5-flash`      | `X-Coach-Tier: pro`        | Premium entitlement only |

Model IDs live in `relay/wrangler.toml` as `MODEL_DEFAULT` / `MODEL_PREMIUM`. Swapping a model is a `wrangler deploy` away — no iOS release. The VolumeArc Release branch pins Premium to stable `gemini-3.5-flash` instead of the hot-swapped `gemini-flash-latest` alias; `gemini-3.1-flash-lite` stays on the free/default path with a documented May 7, 2027 deprecation review requirement.

## Endpoints

### `POST /v1/health`
Returns `{ ok: true, model_default, model_premium }`. No auth required; useful for uptime monitoring.

### `POST /v1/coach`
Returns `Content-Type: text/event-stream` with per-token `data: {"text":"..."}` frames, terminated by `event: done`.

Request body:

```jsonc
{
  "intent": "progression" | "deload" | "form" | "recovery" | "substitution" | "planning" | "free",
  "style": "motivational" | "analytical" | "minimal" | "playful" | "precise",
  // Current iOS clients pre-render the prompt via CoachPromptTemplate and
  // send it verbatim. Do not also send raw question/contextBlock fields.
  "prompt": "<CoachPromptTemplate.render(...)>",
  "system": "<CoachPromptTemplate.systemPrompt(...)>"
}
```

Maximum combined length of all text-bearing coach payload fields (`prompt`,
`system`, legacy `question` / `contextBlock`, and message history): 32,000
characters. Requests exceeding this limit return HTTP 413
`payload_too_large`.

Legacy clients may send `question` + `contextBlock` without `prompt`; the Worker still renders a fallback prompt for that shape.

Required auth headers:

```http
X-VA-Attest-Key-ID: <keyID>
X-VA-Attest-Assertion: <base64 CBOR assertion>
X-VA-Attest-Nonce: <base64 relay challenge>
```

If App Attest headers validate, the Worker authenticates the request and forwards it to Gemini. Missing headers return 410 `app_attest_required`; invalid or incomplete headers return 401 `attestation_invalid`.

Staging-only coach evals may use `X-VA-Eval-Attest-*` headers minted by the VOL-244 eval attestation broker. The broker fails closed unless the Worker is explicitly enabled, has the `EVAL_ATTEST_STATE` Durable Object binding, and the request host is listed in `EVAL_ATTEST_BROKER_ALLOWED_HOSTS`; shipped app clients must always use App Attest.

### `POST /v1/attest/challenge`

Returns `{ challenge, expiresAt }`. Challenges are random 32-byte base64 values, stored with a 5-minute TTL, IP-rate-limited at issue time, and consumed on first use.

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

For App Attest-capable devices, the app:

1. Fetches a relay challenge.
2. Generates/attests a `DCAppAttestService` key, posts the attestation object to `/v1/attest/bootstrap`, and stores the relay-confirmed key ID.
3. For each coach request, fetches a fresh challenge and sends an assertion over `SHA256(requestBody || challenge)`.

The Worker validates the Apple App Attestation Root CA chain, pins the root hash, verifies the nonce extension, checks the app ID hash (`APPLE_TEAM_ID.APPLE_BUNDLE_ID`), verifies the credential ID/key ID binding, stores the public key + counter in the `APP_ATTEST_STATE` Durable Object, and requires counters to increase for assertions. The Durable Object transaction atomically consumes each challenge and advances the counter, avoiding KV's eventual-consistency replay gap.

For response-layer coach evals, staging Workers can enable `/v1/eval-attest/bootstrap` and `/v1/eval-attest/challenge`. The runner bootstraps an ephemeral P-256 public key with a broker token, signs each fixture request over `requestBody || challenge || counter`, and the relay consumes the challenge plus advances the counter in the `EVAL_ATTEST_STATE` Durable Object before forwarding. This path is deliberately fail-closed behind an explicit staging-host allowlist.

**Threat model:**
- Done Protects the Gemini API key (never leaves the Worker)
- Done Rate limits by attested App Attest key ID
- Done Valid App Attest assertions prove the request came from a genuine VolumeArc build on Apple hardware
- Done Tampered App Attest headers fail closed
- Done Missing App Attest headers return 410 instead of using a retired shared-secret fallback.

## Rate limiting

Sliding 10-minute window per attested key, capped at 30 requests. Implemented via Workers KV (`RATE_LIMIT` binding, namespace ID in `wrangler.toml`). A 429 is returned when exceeded; iOS handles this by falling back through the three-tier provider chain to `LocalHeuristicAICoachProvider`.

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
npx wrangler secret put EVAL_ATTEST_BROKER_TOKEN  # staging only
```

### Staging Worker (VOL-245)

`staging-relay.volumearc.app` is a separate Worker (`volumearc-ai-relay-staging`) that hosts the coach-eval attestation broker. Production (`relay.volumearc.app`) explicitly forbids the broker per `relay/wrangler.toml:44-47`, so the eval harness needs its own host. Config is checked in at `relay/wrangler.staging.toml`; deploy with:

```bash
cd relay
npx wrangler deploy -c wrangler.staging.toml
```

The staging Worker shares production's source code (`src/`) but uses isolated infrastructure:

- **KV namespace**: `RATE_LIMIT_STAGING` (id `186d7005f20a436b90c40d37ca175982`). Test traffic never touches production rate-limit state.
- **Durable Objects**: same `APP_ATTEST_STATE` + `EVAL_ATTEST_STATE` class names as production, but instantiated under the staging Worker so the SQLite state is isolated.
- **`EVAL_ATTEST_BROKER_ENABLED=true`** + **`EVAL_ATTEST_BROKER_ALLOWED_HOSTS=staging-relay.volumearc.app`** vars enable the broker endpoints. The broker fails closed unless the request host matches the allowlist AND the bootstrap Bearer token matches `EVAL_ATTEST_BROKER_TOKEN`.

Two secrets must be set after `wrangler deploy -c wrangler.staging.toml`:

```bash
cd relay
npx wrangler secret put GEMINI_API_KEY -c wrangler.staging.toml          # same value as production
npx wrangler secret put EVAL_ATTEST_BROKER_TOKEN -c wrangler.staging.toml # cryptographically random; mirrored to GH secret
```

The same `EVAL_ATTEST_BROKER_TOKEN` value must also be set as the GitHub repo secret `VOLUMEARC_EVAL_ATTEST_BROKER_TOKEN`, plus the staging host as `VOLUMEARC_EVAL_RELAY_BASE_URL`. The `coach-evals-nightly.yml` workflow reads both and fails closed if either is missing.

To **rotate** the broker token: regenerate, set on the staging Worker, set as the GH secret, in that order. The Worker honors the latest value; the GH secret feeds new workflow runs only. There is no live-rollover requirement because the broker key TTL (`EVAL_ATTEST_BROKER_KEY_TTL_SECONDS`, default 24h) bounds how long any given attestation key remains valid.

To **decommission**: `wrangler delete -c wrangler.staging.toml`, delete the two GH secrets, and (optionally) `wrangler kv namespace delete` the staging KV namespace. Production is unaffected.


Env vars (non-secret, live in `wrangler.toml`):
- `MODEL_DEFAULT`, `MODEL_PREMIUM`, `MAX_OUTPUT_TOKENS`, `REQUEST_TIMEOUT_MS`, `RATE_LIMIT_MAX_REQUESTS`, `RATE_LIMIT_WINDOW_SECONDS`
- `APPLE_TEAM_ID`, `APPLE_BUNDLE_ID` (or a full `APPLE_APP_ID`) for App Attest app-ID hash validation
- `EVAL_ATTEST_BROKER_ENABLED=true`, `EVAL_ATTEST_BROKER_ALLOWED_HOSTS=<staging-host>`, and optional `EVAL_ATTEST_BROKER_KEY_TTL_SECONDS` on staging only; do not set these for production.

Optional KV bindings:
- `ATTEST_KEYS` — legacy/local fallback App Attest public-key/counter store
- `ATTEST_CHALLENGES` — legacy/local fallback one-time challenge store

Production binds `APP_ATTEST_STATE` as a Durable Object and uses it for App Attest state. If that binding is absent, the Worker falls back to `ATTEST_KEYS` / `ATTEST_CHALLENGES`, or to `RATE_LIMIT` with `attest:*` prefixes, for local tests and emergency rollback builds. Staging response evals additionally bind `EVAL_ATTEST_STATE`; the eval broker does not run without that binding.

## Wiring the iOS side

The iOS client reads one relay config value at launch:

1. **Base URL** — from `VOLUMEARC_AI_RELAY_URL` env var (Xcode scheme for dev) OR `VolumeArcAIRelayURL` Info.plist key (release). Must be an HTTPS URL whose host is in the allowlist (`App/VolumeArcAIConfiguration.swift`).

The base URL is bootstrapped into Keychain at first launch and read from there on subsequent launches. Auth is always App Attest.

### For local development

Xcode scheme env vars (Edit Scheme → Run → Arguments → Environment Variables):

```bash
VOLUMEARC_AI_RELAY_URL  = https://relay.volumearc.app
```

### For Release / TestFlight

Xcode Cloud injects the relay URL from workflow environment variables in `ci_scripts/ci_post_clone.sh` before archive:

```bash
VOLUMEARC_AI_RELAY_URL = https://relay.volumearc.app
```

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

## Observability

Worker logs stream to [Cloudflare dashboard → Workers → volumearc-ai-relay → Logs](https://dash.cloudflare.com/). Enable Workers Observability (already on via `[observability]` block in `wrangler.toml`) for structured log retention.
