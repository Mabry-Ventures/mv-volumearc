/**
 * volumearc-ai-relay — Cloudflare Worker proxying iOS coach requests to Gemini.
 *
 * Routes
 *   POST /v1/health             → { ok, model }
 *   POST /v1/attest/challenge   → one-time App Attest nonce
 *   POST /v1/attest/bootstrap   → Apple-chain attestation validation
 *   POST /v1/coach              → SSE stream of Gemini token chunks
 *
 * Auth
 *   iOS sends `Authorization: Bearer <device-id>.<hmac-hex>`. The HMAC is
 *   computed by the iOS relay-session provider using the same
 *   RELAY_SIGNING_KEY that lives in Worker secrets. During App Attest Phase
 *   B, capable clients also send X-VA-Attest-* assertion headers; the Worker
 *   validates those first and falls back to HMAC only when the headers are
 *   absent so old clients keep working through the transition.
 *
 * Rate limiting
 *   RATE_LIMIT KV namespace, keyed by device ID. Sliding 10-minute window.
 *
 * Model selection
 *   X-Coach-Tier: flash-lite (default) or pro. Mapped to MODEL_DEFAULT /
 *   MODEL_PREMIUM env vars so ops can swap models without a deploy.
 */

import {
  AppAttestValidationError,
  appAttestRequired,
  issueAppAttestChallenge,
  verifyAndStoreAttestation,
  verifyAppAttestAssertion,
} from "./appAttest";

export { AppAttestState } from "./appAttest";

interface Env {
  GEMINI_API_KEY: string;
  RELAY_SIGNING_KEY: string;
  RATE_LIMIT: KVNamespace;
  ATTEST_KEYS?: KVNamespace;
  ATTEST_CHALLENGES?: KVNamespace;
  APP_ATTEST_STATE?: DurableObjectNamespace;
  APPLE_APP_ID?: string;
  APPLE_TEAM_ID?: string;
  APPLE_BUNDLE_ID?: string;
  REQUIRE_APP_ATTEST?: string;
  MODEL_DEFAULT: string;
  MODEL_PREMIUM: string;
  MAX_OUTPUT_TOKENS: string;
  REQUEST_TIMEOUT_MS: string;
  RATE_LIMIT_MAX_REQUESTS: string;
  RATE_LIMIT_WINDOW_SECONDS: string;
}

interface CoachRequestBody {
  intent: "progression" | "deload" | "form" | "recovery" | "substitution" | "free";
  question: string;
  contextBlock: string;
  style?: "motivational" | "precise" | "playful";
  messages?: Array<{ role: "user" | "assistant"; content: string }>;
  /**
   * Optional client-rendered prompt. When present, the Worker uses this
   * verbatim as the user message instead of constructing one from
   * `{question, contextBlock}`. Lets the iOS `CoachPromptTemplate` remain
   * the single source of truth for prompt shape (and keeps the template
   * marker flowing end-to-end for VOL-64 regression coverage).
   */
  prompt?: string;
  /** Optional client-rendered system prompt; overrides Worker's default. */
  system?: string;
}

interface AuthSuccess {
  ok: true;
  deviceId: string;
  method: "app_attest" | "hmac";
}

interface AuthFailure {
  ok: false;
  status: number;
  error: string;
  reason?: string;
}

type AuthResult = AuthSuccess | AuthFailure;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    try {
      if (url.pathname === "/v1/health") {
        return handleHealth(env);
      }
      if (url.pathname === "/v1/attest/challenge") {
        return await handleAppAttestChallenge(request, env);
      }
      if (url.pathname === "/v1/attest/bootstrap") {
        return await handleAppAttestBootstrap(request, env);
      }
      if (url.pathname === "/v1/coach") {
        return await handleCoach(request, env);
      }
      return json({ error: "not_found" }, 404);
    } catch (err) {
      const message = err instanceof Error ? err.message : "unknown";
      return json({ error: "internal", message }, 500);
    }
  },
};

function handleHealth(env: Env): Response {
  return json({ ok: true, model_default: env.MODEL_DEFAULT, model_premium: env.MODEL_PREMIUM }, 200);
}

async function handleCoach(request: Request, env: Env): Promise<Response> {
  let body: CoachRequestBody;
  let bodyText: string;
  try {
    bodyText = await request.text();
    body = JSON.parse(bodyText) as CoachRequestBody;
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  if (!body.question || !body.contextBlock || !body.intent) {
    return json({ error: "missing_fields" }, 400);
  }

  const auth = await authenticate(request, env, new TextEncoder().encode(bodyText));
  if (!auth.ok) {
    recordAuthEvent(auth.reason ?? auth.error, { status: String(auth.status) });
    return json({ error: auth.error, reason: auth.reason }, auth.status);
  }

  const rateOk = await checkRateLimit(auth.deviceId, env);
  if (!rateOk) {
    return json({ error: "rate_limited" }, 429);
  }

  const tier = request.headers.get("X-Coach-Tier")?.toLowerCase();
  const model = tier === "pro" ? env.MODEL_PREMIUM : env.MODEL_DEFAULT;

  return streamGemini(body, model, env);
}

async function handleAppAttestChallenge(request: Request, env: Env): Promise<Response> {
  const deviceId = await authenticateHMAC(request, env);
  if (!deviceId) {
    recordAuthEvent("app_attest_challenge_unauthorized");
    return json({ error: "unauthorized" }, 401);
  }
  const challenge = await issueAppAttestChallenge(env, deviceId);
  recordAuthEvent("app_attest_challenge_issued");
  return json({ challenge: challenge.challenge, expiresAt: challenge.expiresAt }, 200);
}

async function handleAppAttestBootstrap(request: Request, env: Env): Promise<Response> {
  const deviceId = await authenticateHMAC(request, env);
  if (!deviceId) {
    recordAuthEvent("app_attest_bootstrap_unauthorized");
    return json({ error: "unauthorized" }, 401);
  }

  let body: {
    keyID?: string;
    key_id?: string;
    attestationObject?: string;
    attestation_object_b64?: string;
    challenge?: string;
    challenge_b64?: string;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const keyId = body.keyID ?? body.key_id;
  const attestationObject = body.attestationObject ?? body.attestation_object_b64;
  const challenge = body.challenge ?? body.challenge_b64;
  if (!keyId || !attestationObject || !challenge) {
    return json({ error: "missing_fields" }, 400);
  }

  try {
    const result = await verifyAndStoreAttestation(env, {
      deviceId,
      keyId,
      attestationObjectB64: attestationObject,
      challengeB64: challenge,
    });
    recordAuthEvent("app_attest_succeeded", { environment: result.environment });
    return json({ ok: true, attestedAt: result.attestedAt, environment: result.environment }, 200);
  } catch (error) {
    const reason = error instanceof AppAttestValidationError ? error.reason : "attestation_invalid";
    recordAuthEvent("app_attest_failed", { reason });
    return json({ error: "attestation_invalid", reason }, 401);
  }
}

async function streamGemini(body: CoachRequestBody, model: string, env: Env): Promise<Response> {
  const systemPrompt = body.system?.trim() || buildSystemPrompt(body.style ?? "motivational");
  const userMessage = body.prompt?.trim() || `${body.contextBlock}\n\n${body.question}`.trim();

  const history = (body.messages ?? []).map((m) => ({
    role: m.role === "assistant" ? "model" : "user",
    parts: [{ text: m.content }],
  }));

  const geminiBody = {
    contents: [...history, { role: "user", parts: [{ text: userMessage }] }],
    systemInstruction: { parts: [{ text: systemPrompt }] },
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: Number.parseInt(env.MAX_OUTPUT_TOKENS, 10) || 800,
      responseMimeType: "text/plain",
    },
    safetySettings: [
      { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_MEDIUM_AND_ABOVE" },
      { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_MEDIUM_AND_ABOVE" },
      { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_MEDIUM_AND_ABOVE" },
      { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_ONLY_HIGH" },
    ],
  };

  const upstream = `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${env.GEMINI_API_KEY}`;

  const controller = new AbortController();
  const timeoutMs = Number.parseInt(env.REQUEST_TIMEOUT_MS, 10) || 60000;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  let upstreamResp: Response;
  try {
    upstreamResp = await fetch(upstream, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(geminiBody),
      signal: controller.signal,
    });
  } catch (err) {
    clearTimeout(timeout);
    const message = err instanceof Error ? err.message : "upstream_failure";
    return json({ error: "upstream", message }, 502);
  }

  if (!upstreamResp.ok || !upstreamResp.body) {
    clearTimeout(timeout);
    const text = await upstreamResp.text().catch(() => "");
    return json({ error: "upstream_status", status: upstreamResp.status, body: text.slice(0, 500) }, 502);
  }

  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  (async () => {
    try {
      const reader = upstreamResp.body!.getReader();
      let buffered = "";
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buffered += decoder.decode(value, { stream: true });
        const lines = buffered.split("\n");
        buffered = lines.pop() ?? "";
        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed || !trimmed.startsWith("data:")) continue;
          const payload = trimmed.slice(5).trim();
          if (payload === "[DONE]") continue;
          try {
            const chunk = JSON.parse(payload) as GeminiStreamChunk;
            const text = chunk.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
            if (text) {
              await writer.write(encoder.encode(`data: ${JSON.stringify({ text })}\n\n`));
            }
          } catch {
            // Skip malformed JSON lines; upstream occasionally emits keepalives.
          }
        }
      }
      await writer.write(encoder.encode(`event: done\ndata: {}\n\n`));
    } catch (err) {
      const message = err instanceof Error ? err.message : "stream_error";
      await writer.write(encoder.encode(`event: error\ndata: ${JSON.stringify({ message })}\n\n`));
    } finally {
      clearTimeout(timeout);
      await writer.close().catch(() => {});
    }
  })();

  return new Response(readable, {
    status: 200,
    headers: {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-transform",
      "x-accel-buffering": "no",
      "x-coach-model": model,
    },
  });
}

interface GeminiStreamChunk {
  candidates?: Array<{
    content?: { parts?: Array<{ text?: string }> };
  }>;
}

function buildSystemPrompt(style: "motivational" | "precise" | "playful"): string {
  const tone =
    style === "precise"
      ? "direct, numerical, and brief"
      : style === "playful"
      ? "warm, lightly humorous, and brief"
      : "encouraging, concrete, and brief";
  return [
    "You are VolumeArc, an evidence-based strength-training coach.",
    `Respond in a tone that is ${tone}. Keep responses under three sentences unless the user explicitly asks for more detail.`,
    "Ground every recommendation in the provided context block (readiness, recent sessions, training plan, equipment).",
    "If the context is thin, say what's missing rather than guessing.",
    "Never recommend maximal lifts, competition programming, or medical advice. Defer to a clinician for injury questions.",
  ].join(" ");
}

// --- Auth ---------------------------------------------------------------

async function authenticate(request: Request, env: Env, requestBody: Uint8Array): Promise<AuthResult> {
  const appAttest = await verifyAppAttestAssertion(env, request, requestBody);
  if (appAttest.ok) {
    recordAuthEvent("app_attest_succeeded");
    return { ok: true, deviceId: appAttest.deviceId, method: "app_attest" };
  }

  const hasAnyAppAttestHeader =
    request.headers.has("X-VA-Attest-Key-ID") ||
    request.headers.has("X-VA-Attest-Assertion") ||
    request.headers.has("X-VA-Attest-Nonce");
  if (hasAnyAppAttestHeader) {
    recordAuthEvent("app_attest_failed", { reason: appAttest.reason });
    return { ok: false, status: 401, error: "attestation_invalid", reason: appAttest.reason };
  }

  if (appAttestRequired(env)) {
    recordAuthEvent("app_attest_required");
    return { ok: false, status: 410, error: "app_attest_required" };
  }

  const deviceId = await authenticateHMAC(request, env);
  if (!deviceId) {
    return { ok: false, status: 401, error: "unauthorized" };
  }
  recordAuthEvent("hmac_fallback_used");
  return { ok: true, deviceId, method: "hmac" };
}

async function authenticateHMAC(request: Request, env: Env): Promise<string | null> {
  const header = request.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice(7).trim();
  const dotIndex = token.indexOf(".");
  if (dotIndex < 1 || dotIndex === token.length - 1) return null;

  const deviceId = token.slice(0, dotIndex);
  const signature = token.slice(dotIndex + 1);
  if (!/^[0-9a-f]{64}$/i.test(signature)) return null;

  const expected = await hmacHex(env.RELAY_SIGNING_KEY, deviceId);
  if (!timingSafeEqualHex(signature, expected)) return null;
  return deviceId;
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(message));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function recordAuthEvent(name: string, metadata: Record<string, string> = {}): void {
  console.log(JSON.stringify({
    category: "relay.auth",
    name,
    metadata,
    timestamp: new Date().toISOString(),
  }));
}

// --- Rate limiting ------------------------------------------------------

async function checkRateLimit(deviceId: string, env: Env): Promise<boolean> {
  const limit = Number.parseInt(env.RATE_LIMIT_MAX_REQUESTS, 10) || 30;
  const windowSec = Number.parseInt(env.RATE_LIMIT_WINDOW_SECONDS, 10) || 600;
  const key = `rl:${deviceId}`;
  const raw = await env.RATE_LIMIT.get(key);
  const now = Math.floor(Date.now() / 1000);
  let stamps: number[] = [];
  if (raw) {
    try {
      stamps = JSON.parse(raw) as number[];
    } catch {
      stamps = [];
    }
  }
  const cutoff = now - windowSec;
  stamps = stamps.filter((s) => s >= cutoff);
  if (stamps.length >= limit) return false;
  stamps.push(now);
  await env.RATE_LIMIT.put(key, JSON.stringify(stamps), { expirationTtl: windowSec * 2 });
  return true;
}

// --- Helpers ------------------------------------------------------------

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}
