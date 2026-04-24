# AI Relay (`volumearc-ai-relay`)

A Cloudflare Worker that proxies iOS coach requests to Google's Gemini API with SSE streaming, HMAC-signed bearer auth, and per-device rate limiting.

- **Worker name:** `volumearc-ai-relay`
- **Live endpoint:** `https://volumearc-ai-relay.jared-b6b.workers.dev`
- **Future custom domain:** `relay.volumearc.app` (queued — needs `volumearc.app` zone on this Cloudflare account)
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

Auth header:

```
Authorization: Bearer <device_id>.<hmac_sha256_hex>
```

Where `hmac_sha256_hex = HMAC-SHA256(RELAY_SIGNING_KEY, device_id)` rendered as lowercase hex.

## Auth model

Each iOS install generates a stable UUID at first launch (persisted to Keychain), then HMAC-signs it with the shared `RELAY_SIGNING_KEY` that lives in Worker secrets + the iOS Keychain. The Worker verifies the signature before forwarding to Gemini.

**Threat model (current):**
- ✅ Protects the Gemini API key (never leaves the Worker)
- ✅ Rate limits by device so a single extracted token can't DOS the relay
- ⚠️ A determined attacker who reverse-engineers a TestFlight IPA can extract the signing key and mint arbitrary bearer tokens. The 30-req/10-min-per-device KV rate limit is our only defense in depth.

**Production hardening (future follow-up):** migrate to Apple's [App Attest](https://developer.apple.com/documentation/devicecheck) so the Worker validates each request is from a genuine VolumeArc build. At that point we can drop the shared signing key entirely. Not yet ticketed — file a new Linear ticket under the VolumeArc team when it's sprint-worthy.

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
npx wrangler secret put RELAY_SIGNING_KEY   # 32-byte random, openssl rand -base64 32
```

Env vars (non-secret, live in `wrangler.toml`):
- `MODEL_DEFAULT`, `MODEL_PREMIUM`, `MAX_OUTPUT_TOKENS`, `REQUEST_TIMEOUT_MS`, `RATE_LIMIT_MAX_REQUESTS`, `RATE_LIMIT_WINDOW_SECONDS`

## Wiring the iOS side

The iOS client reads two pieces of config at launch:

1. **Base URL** — from `VOLUMEARC_OPENAI_BASE_URL` env var (Xcode scheme for dev) OR `VolumeArcOpenAIBaseURL` Info.plist key (release). Must be an HTTPS URL whose host is in the allowlist (`App/VolumeArcAIConfiguration.swift`).
2. **Signing key** — from `VOLUMEARC_RELAY_SIGNING_KEY` env var OR `VolumeArcRelaySigningKey` Info.plist key. Must match the Worker's `RELAY_SIGNING_KEY` secret exactly.

Both are bootstrapped into Keychain at first launch and read from there on subsequent launches. Rotating a secret requires an iOS release (acceptable — neither is a per-request credential).

### For local development

Xcode scheme env vars (Edit Scheme → Run → Arguments → Environment Variables):

```
VOLUMEARC_OPENAI_BASE_URL  = https://volumearc-ai-relay.jared-b6b.workers.dev
VOLUMEARC_RELAY_SIGNING_KEY = <contents of relay/.secrets/relay_signing_key.txt>
```

### For Release / TestFlight

Inject via xcconfig or a build phase script that writes Info.plist values from a secrets file. The signing key itself must not live in git.

## Promoting to `relay.volumearc.app`

When `volumearc.app` is added as a zone to the Mabry Ventures Cloudflare account:

1. Uncomment the `[[routes]]` block in `relay/wrangler.toml`
2. `wrangler deploy`
3. Confirm DNS is proxied (orange cloud) for the `relay` subdomain
4. Update `VOLUMEARC_OPENAI_BASE_URL` in the iOS config
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
