export interface EvalAttestEnv {
  RATE_LIMIT: KVNamespace;
  EVAL_ATTEST_BROKER_ENABLED?: string;
  EVAL_ATTEST_BROKER_TOKEN?: string;
  EVAL_ATTEST_BROKER_KEY_TTL_SECONDS?: string;
}

export interface EvalAttestAuthSuccess {
  ok: true;
  deviceId: string;
  keyId: string;
}

export interface EvalAttestAuthFailure {
  ok: false;
  reason: string;
}

interface EvalAttestStoredKey {
  deviceId: string;
  publicKeyJwk: JsonWebKey;
  counter: number;
  attestedAt: string;
  expiresAt: string;
}

interface EvalAttestChallengeRecord {
  keyId: string;
  issuedAt: string;
  expiresAt: string;
}

const CHALLENGE_TTL_SECONDS = 5 * 60;
const DEFAULT_KEY_TTL_SECONDS = 24 * 60 * 60;
const MAX_KEY_TTL_SECONDS = 24 * 60 * 60;
const PRODUCTION_RELAY_HOST = "relay.volumearc.app";

export async function handleEvalAttestBootstrap(request: Request, env: EvalAttestEnv): Promise<Response> {
  const guard = brokerGuard(request, env);
  if (!guard.ok) {
    return evalJson({ error: guard.error, reason: guard.reason }, guard.status);
  }

  let body: { keyId?: unknown; publicKeyJwk?: unknown };
  try {
    body = await request.json() as typeof body;
  } catch {
    return evalJson({ error: "bad_request" }, 400);
  }

  if (typeof body.keyId !== "string" || !isPublicP256Jwk(body.publicKeyJwk)) {
    return evalJson({ error: "missing_fields" }, 400);
  }

  const keyId = body.keyId.trim();
  const publicKeyJwk = body.publicKeyJwk;
  if (!keyId) {
    return evalJson({ error: "missing_fields" }, 400);
  }

  const imported = await crypto.subtle.importKey(
    "jwk",
    publicKeyJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["verify"],
  );
  const publicKeyRaw = new Uint8Array(await crypto.subtle.exportKey("raw", imported) as ArrayBuffer);
  const expectedKeyId = encodeBase64(await sha256(publicKeyRaw));
  if (keyId !== expectedKeyId) {
    return evalJson({ error: "attestation_invalid", reason: "key_id_public_key_mismatch" }, 401);
  }

  const now = Date.now();
  const ttl = evalKeyTtlSeconds(env);
  const stored: EvalAttestStoredKey = {
    deviceId: `eval-broker:${keyId}`,
    publicKeyJwk,
    counter: 0,
    attestedAt: new Date(now).toISOString(),
    expiresAt: new Date(now + ttl * 1000).toISOString(),
  };
  await env.RATE_LIMIT.put(evalStoredKey(keyId), JSON.stringify(stored), {
    expirationTtl: ttl,
  });

  return evalJson({
    ok: true,
    keyId,
    attestedAt: stored.attestedAt,
    expiresAt: stored.expiresAt,
  }, 200);
}

export async function handleEvalAttestChallenge(request: Request, env: EvalAttestEnv): Promise<Response> {
  const guard = brokerGuard(request, env);
  if (!guard.ok) {
    return evalJson({ error: guard.error, reason: guard.reason }, guard.status);
  }

  let body: { keyId?: unknown };
  try {
    body = await request.json() as typeof body;
  } catch {
    return evalJson({ error: "bad_request" }, 400);
  }

  if (typeof body.keyId !== "string" || !body.keyId.trim()) {
    return evalJson({ error: "missing_fields" }, 400);
  }

  const keyId = body.keyId.trim();
  const stored = await loadEvalKey(env, keyId);
  if (!stored) {
    return evalJson({ error: "attestation_invalid", reason: "key_not_attested" }, 401);
  }
  if (Date.parse(stored.expiresAt) <= Date.now()) {
    await env.RATE_LIMIT.delete(evalStoredKey(keyId));
    return evalJson({ error: "attestation_invalid", reason: "key_expired" }, 401);
  }

  const challengeBytes = crypto.getRandomValues(new Uint8Array(32));
  const challenge = encodeBase64(challengeBytes);
  const issuedAt = new Date().toISOString();
  const expiresAt = new Date(Date.now() + CHALLENGE_TTL_SECONDS * 1000).toISOString();
  const record: EvalAttestChallengeRecord = { keyId, issuedAt, expiresAt };
  await env.RATE_LIMIT.put(evalChallengeKey(challenge), JSON.stringify(record), {
    expirationTtl: CHALLENGE_TTL_SECONDS,
  });

  return evalJson({ challenge, expiresAt }, 200);
}

export async function verifyEvalAttestAssertion(
  env: EvalAttestEnv,
  request: Request,
  requestBody: Uint8Array,
): Promise<EvalAttestAuthSuccess | EvalAttestAuthFailure> {
  if (!isEvalBrokerAllowed(request, env)) {
    return { ok: false, reason: "eval_attest_disabled" };
  }

  const keyId = request.headers.get("X-VA-Eval-Attest-Key-ID")?.trim();
  const assertionB64 = request.headers.get("X-VA-Eval-Attest-Assertion")?.trim();
  const challengeB64 = request.headers.get("X-VA-Eval-Attest-Nonce")?.trim();
  const counterHeader = request.headers.get("X-VA-Eval-Attest-Counter")?.trim();
  const presentCount = [keyId, assertionB64, challengeB64, counterHeader].filter(Boolean).length;
  if (presentCount === 0) {
    return { ok: false, reason: "eval_attest_missing" };
  }
  if (!keyId || !assertionB64 || !challengeB64 || !counterHeader) {
    return { ok: false, reason: "eval_attest_incomplete" };
  }

  const counter = Number.parseInt(counterHeader, 10);
  if (!Number.isSafeInteger(counter) || counter < 1) {
    return { ok: false, reason: "counter_invalid" };
  }

  try {
    const stored = await loadEvalKey(env, keyId);
    if (!stored) {
      return { ok: false, reason: "key_not_attested" };
    }
    if (Date.parse(stored.expiresAt) <= Date.now()) {
      await env.RATE_LIMIT.delete(evalStoredKey(keyId));
      return { ok: false, reason: "key_expired" };
    }
    if (counter <= stored.counter) {
      return { ok: false, reason: "counter_replay" };
    }

    const challenge = await loadEvalChallenge(env, challengeB64);
    if (!challenge) {
      return { ok: false, reason: "challenge_not_found" };
    }
    if (challenge.keyId !== keyId) {
      return { ok: false, reason: "challenge_device_mismatch" };
    }
    if (Date.parse(challenge.expiresAt) <= Date.now()) {
      await env.RATE_LIMIT.delete(evalChallengeKey(challengeB64));
      return { ok: false, reason: "challenge_expired" };
    }

    const publicKey = await crypto.subtle.importKey(
      "jwk",
      stored.publicKeyJwk,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    const ok = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      decodeBase64(assertionB64),
      evalSigningPayload(requestBody, challengeB64, counter),
    );
    if (!ok) {
      return { ok: false, reason: "signature_invalid" };
    }

    await env.RATE_LIMIT.delete(evalChallengeKey(challengeB64));
    await env.RATE_LIMIT.put(
      evalStoredKey(keyId),
      JSON.stringify({ ...stored, counter }),
      { expirationTtl: secondsUntil(stored.expiresAt) },
    );
    return { ok: true, deviceId: stored.deviceId, keyId };
  } catch {
    return { ok: false, reason: "eval_attest_invalid" };
  }
}

export function hasAnyEvalAttestHeader(request: Request): boolean {
  return request.headers.has("X-VA-Eval-Attest-Key-ID") ||
    request.headers.has("X-VA-Eval-Attest-Assertion") ||
    request.headers.has("X-VA-Eval-Attest-Nonce") ||
    request.headers.has("X-VA-Eval-Attest-Counter");
}

function brokerGuard(
  request: Request,
  env: EvalAttestEnv,
): { ok: true } | { ok: false; status: number; error: string; reason: string } {
  if (!isEvalBrokerAllowed(request, env)) {
    return { ok: false, status: 404, error: "not_found", reason: "eval_attest_disabled" };
  }
  if (!isAuthorizedBrokerRequest(request, env)) {
    return { ok: false, status: 401, error: "unauthorized", reason: "broker_token_invalid" };
  }
  return { ok: true };
}

function isEvalBrokerAllowed(request: Request, env: EvalAttestEnv): boolean {
  if (!enabled(env.EVAL_ATTEST_BROKER_ENABLED)) {
    return false;
  }
  const token = env.EVAL_ATTEST_BROKER_TOKEN?.trim();
  if (!token) {
    return false;
  }
  const hostname = new URL(request.url).hostname.toLowerCase();
  return hostname !== PRODUCTION_RELAY_HOST;
}

function isAuthorizedBrokerRequest(request: Request, env: EvalAttestEnv): boolean {
  const expected = env.EVAL_ATTEST_BROKER_TOKEN?.trim() ?? "";
  const actual = request.headers.get("Authorization")?.trim() ?? "";
  const prefix = "Bearer ";
  if (!actual.startsWith(prefix)) {
    return false;
  }
  return timingSafeEqual(actual.slice(prefix.length), expected);
}

function enabled(value: string | undefined): boolean {
  return value?.trim().toLowerCase() === "true" || value?.trim() === "1";
}

function timingSafeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let diff = left.byteLength ^ right.byteLength;
  const length = Math.max(left.byteLength, right.byteLength);
  for (let index = 0; index < length; index += 1) {
    diff |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return diff === 0;
}

function isPublicP256Jwk(value: unknown): value is JsonWebKey {
  if (!value || typeof value !== "object") {
    return false;
  }
  const jwk = value as Record<string, unknown>;
  return jwk.kty === "EC" &&
    jwk.crv === "P-256" &&
    typeof jwk.x === "string" &&
    typeof jwk.y === "string" &&
    typeof jwk.d === "undefined";
}

async function loadEvalKey(env: EvalAttestEnv, keyId: string): Promise<EvalAttestStoredKey | null> {
  const raw = await env.RATE_LIMIT.get(evalStoredKey(keyId));
  return raw ? JSON.parse(raw) as EvalAttestStoredKey : null;
}

async function loadEvalChallenge(env: EvalAttestEnv, challenge: string): Promise<EvalAttestChallengeRecord | null> {
  const raw = await env.RATE_LIMIT.get(evalChallengeKey(challenge));
  return raw ? JSON.parse(raw) as EvalAttestChallengeRecord : null;
}

function evalStoredKey(keyId: string): string {
  return `eval:attest:key:${keyId}`;
}

function evalChallengeKey(challenge: string): string {
  return `eval:attest:challenge:${challenge}`;
}

function evalKeyTtlSeconds(env: EvalAttestEnv): number {
  const configured = Number.parseInt(env.EVAL_ATTEST_BROKER_KEY_TTL_SECONDS ?? "", 10);
  if (!Number.isSafeInteger(configured) || configured < 60) {
    return DEFAULT_KEY_TTL_SECONDS;
  }
  return Math.min(configured, MAX_KEY_TTL_SECONDS);
}

function secondsUntil(expiresAt: string): number {
  const seconds = Math.floor((Date.parse(expiresAt) - Date.now()) / 1000);
  return Math.max(60, seconds);
}

function evalSigningPayload(requestBody: Uint8Array, challengeB64: string, counter: number): Uint8Array {
  const counterBytes = new Uint8Array(4);
  new DataView(counterBytes.buffer).setUint32(0, counter, false);
  return concatBytes(requestBody, decodeBase64(challengeB64), counterBytes);
}

function evalJson(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function concatBytes(...chunks: Uint8Array[]): Uint8Array {
  const length = chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0);
  const result = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}
