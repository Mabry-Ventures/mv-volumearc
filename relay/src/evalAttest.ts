export interface EvalAttestEnv {
  RATE_LIMIT: KVNamespace;
  EVAL_ATTEST_STATE?: DurableObjectNamespace;
  EVAL_ATTEST_BROKER_ENABLED?: string;
  EVAL_ATTEST_BROKER_TOKEN?: string;
  EVAL_ATTEST_BROKER_ALLOWED_HOSTS?: string;
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

type EvalAttestStateResult =
  | { ok: true }
  | { ok: false; reason: string };

type EvalAttestStateKeyResult =
  | { ok: true; stored: EvalAttestStoredKey | null }
  | { ok: false; reason: string };

type EvalAttestStateChallengeResult =
  | { ok: true; stored: EvalAttestChallengeRecord | null }
  | { ok: false; reason: string };

type EvalAttestStateAssertionResult =
  | { ok: true; deviceId: string }
  | { ok: false; reason: string };

export class EvalAttestState implements DurableObject {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    if (request.method !== "POST") {
      return evalJson({ ok: false, reason: "method_not_allowed" }, 405);
    }

    const url = new URL(request.url);
    try {
      switch (url.pathname) {
        case "/key":
          return await this.storeKey(request);
        case "/key/lookup":
          return await this.lookupKey(request);
        case "/key/delete":
          return await this.deleteKey(request);
        case "/challenge":
          return await this.storeChallenge(request);
        case "/challenge/lookup":
          return await this.lookupChallenge(request);
        case "/challenge/delete":
          return await this.deleteChallenge(request);
        case "/assertion":
          return await this.finalizeAssertion(request);
        default:
          return evalJson({ ok: false, reason: "not_found" }, 404);
      }
    } catch {
      return evalJson({ ok: false, reason: "eval_attest_state_unavailable" }, 500);
    }
  }

  async alarm(): Promise<void> {
    const now = Date.now();
    const keys = await this.state.storage.list<EvalAttestStoredKey>({ prefix: "eval:attest:key:" });
    const challenges = await this.state.storage.list<EvalAttestChallengeRecord>({ prefix: "eval:attest:challenge:" });
    const expired: string[] = [];
    let nextAlarm: number | null = null;

    for (const [key, record] of [...keys, ...challenges]) {
      const expiry = Date.parse(record.expiresAt);
      if (!Number.isFinite(expiry) || expiry <= now) {
        expired.push(key);
      } else {
        nextAlarm = nextAlarm === null ? expiry : Math.min(nextAlarm, expiry);
      }
    }

    if (expired.length > 0) {
      await this.state.storage.delete(expired);
    }
    if (nextAlarm !== null) {
      await this.state.storage.setAlarm(nextAlarm + 60_000);
    }
  }

  private async storeKey(request: Request): Promise<Response> {
    const body = await request.json() as { keyId?: unknown; stored?: unknown };
    if (typeof body.keyId !== "string" || !isStoredEvalKey(body.stored)) {
      return evalJson({ ok: false, reason: "bad_request" }, 400);
    }

    await this.state.storage.put(evalStoredKey(body.keyId), body.stored);
    await this.scheduleSweep(body.stored.expiresAt);
    return evalJson({ ok: true }, 200);
  }

  private async lookupKey(request: Request): Promise<Response> {
    const body = await request.json() as { keyId?: unknown };
    if (typeof body.keyId !== "string") {
      return evalJson({ ok: false, reason: "bad_request" }, 400);
    }

    const stored = await this.state.storage.get<EvalAttestStoredKey>(evalStoredKey(body.keyId));
    return evalJson({ ok: true, stored: stored ?? null }, 200);
  }

  private async deleteKey(request: Request): Promise<Response> {
    const body = await request.json() as { keyId?: unknown };
    if (typeof body.keyId !== "string") {
      return evalJson({ ok: false, reason: "bad_request" }, 400);
    }

    await this.state.storage.delete(evalStoredKey(body.keyId));
    return evalJson({ ok: true }, 200);
  }

  private async storeChallenge(request: Request): Promise<Response> {
    const body = await request.json() as { challenge?: unknown; record?: unknown };
    if (typeof body.challenge !== "string" || !isEvalChallengeRecord(body.record)) {
      return evalJson({ ok: false, reason: "bad_request" }, 400);
    }

    await this.state.storage.put(evalChallengeKey(body.challenge), body.record);
    await this.scheduleSweep(body.record.expiresAt);
    return evalJson({ ok: true }, 200);
  }

  private async lookupChallenge(request: Request): Promise<Response> {
    const body = await request.json() as { challenge?: unknown };
    if (typeof body.challenge !== "string") {
      return evalJson({ ok: false, reason: "bad_request" }, 400);
    }

    const stored = await this.state.storage.get<EvalAttestChallengeRecord>(evalChallengeKey(body.challenge));
    return evalJson({ ok: true, stored: stored ?? null }, 200);
  }

  private async deleteChallenge(request: Request): Promise<Response> {
    const body = await request.json() as { challenge?: unknown };
    if (typeof body.challenge !== "string") {
      return evalJson({ ok: false, reason: "bad_request" }, 400);
    }

    await this.state.storage.delete(evalChallengeKey(body.challenge));
    return evalJson({ ok: true }, 200);
  }

  private async finalizeAssertion(request: Request): Promise<Response> {
    const body = await request.json() as {
      keyId?: unknown;
      challengeB64?: unknown;
      counter?: unknown;
    };
    if (
      typeof body.keyId !== "string" ||
      typeof body.challengeB64 !== "string" ||
      typeof body.counter !== "number"
    ) {
      return evalJson({ ok: false, reason: "bad_request" }, 400);
    }

    const result = await this.state.storage.transaction<EvalAttestStateAssertionResult>(async (txn) => {
      const storedKey = evalStoredKey(body.keyId as string);
      const stored = await txn.get<EvalAttestStoredKey>(storedKey);
      if (!stored) {
        return { ok: false, reason: "key_not_attested" };
      }
      if (Date.parse(stored.expiresAt) <= Date.now()) {
        await txn.delete(storedKey);
        return { ok: false, reason: "key_expired" };
      }

      const challengeKey = evalChallengeKey(body.challengeB64 as string);
      const challenge = await txn.get<EvalAttestChallengeRecord>(challengeKey);
      const failure = challengeFailure(challenge, body.keyId as string);
      if (failure) {
        if (failure === "challenge_expired") {
          await txn.delete(challengeKey);
        }
        return { ok: false, reason: failure };
      }
      if ((body.counter as number) <= stored.counter) {
        return { ok: false, reason: "counter_replay" };
      }

      await txn.delete(challengeKey);
      await txn.put(storedKey, { ...stored, counter: body.counter as number });
      return { ok: true, deviceId: stored.deviceId };
    });

    return evalJson(result, result.ok ? 200 : 409);
  }

  private async scheduleSweep(expiresAt: string): Promise<void> {
    const expiry = Date.parse(expiresAt);
    if (!Number.isFinite(expiry)) {
      return;
    }
    const scheduled = expiry + 60_000;
    const current = await this.state.storage.getAlarm();
    if (current === null || current > scheduled) {
      await this.state.storage.setAlarm(scheduled);
    }
  }
}

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
  await storeEvalKey(env, keyId, stored);

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
    await deleteEvalKey(env, keyId);
    return evalJson({ error: "attestation_invalid", reason: "key_expired" }, 401);
  }

  const challengeBytes = crypto.getRandomValues(new Uint8Array(32));
  const challenge = encodeBase64(challengeBytes);
  const issuedAt = new Date().toISOString();
  const expiresAt = new Date(Date.now() + CHALLENGE_TTL_SECONDS * 1000).toISOString();
  const record: EvalAttestChallengeRecord = { keyId, issuedAt, expiresAt };
  await storeEvalChallenge(env, challenge, record);

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
      await deleteEvalKey(env, keyId);
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
      await deleteEvalChallenge(env, challengeB64);
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

    const finalized = await finalizeEvalAssertion(env, { keyId, challengeB64, counter });
    if (!finalized.ok) {
      return finalized;
    }
    return { ok: true, deviceId: finalized.deviceId, keyId };
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
  if (!env.EVAL_ATTEST_STATE) {
    return false;
  }
  const allowedHosts = new Set(
    (env.EVAL_ATTEST_BROKER_ALLOWED_HOSTS ?? "")
      .split(",")
      .map((host) => host.trim().toLowerCase())
      .filter(Boolean),
  );
  if (allowedHosts.size === 0) {
    return false;
  }
  const hostname = new URL(request.url).hostname.toLowerCase();
  return allowedHosts.has(hostname);
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

async function storeEvalKey(env: EvalAttestEnv, keyId: string, stored: EvalAttestStoredKey): Promise<void> {
  const response = await evalAttestStateRequest<EvalAttestStateResult>(env, "/key", { keyId, stored });
  if (!response.ok) {
    throw new Error(response.reason);
  }
}

async function loadEvalKey(env: EvalAttestEnv, keyId: string): Promise<EvalAttestStoredKey | null> {
  const response = await evalAttestStateRequest<EvalAttestStateKeyResult>(env, "/key/lookup", { keyId });
  if (!response.ok) {
    throw new Error(response.reason);
  }
  return response.stored;
}

async function deleteEvalKey(env: EvalAttestEnv, keyId: string): Promise<void> {
  const response = await evalAttestStateRequest<EvalAttestStateResult>(env, "/key/delete", { keyId });
  if (!response.ok) {
    throw new Error(response.reason);
  }
}

async function storeEvalChallenge(
  env: EvalAttestEnv,
  challenge: string,
  record: EvalAttestChallengeRecord,
): Promise<void> {
  const response = await evalAttestStateRequest<EvalAttestStateResult>(env, "/challenge", { challenge, record });
  if (!response.ok) {
    throw new Error(response.reason);
  }
}

async function loadEvalChallenge(env: EvalAttestEnv, challenge: string): Promise<EvalAttestChallengeRecord | null> {
  const response = await evalAttestStateRequest<EvalAttestStateChallengeResult>(
    env,
    "/challenge/lookup",
    { challenge },
  );
  if (!response.ok) {
    throw new Error(response.reason);
  }
  return response.stored;
}

async function deleteEvalChallenge(env: EvalAttestEnv, challenge: string): Promise<void> {
  const response = await evalAttestStateRequest<EvalAttestStateResult>(env, "/challenge/delete", { challenge });
  if (!response.ok) {
    throw new Error(response.reason);
  }
}

async function finalizeEvalAssertion(
  env: EvalAttestEnv,
  input: { keyId: string; challengeB64: string; counter: number },
): Promise<EvalAttestStateAssertionResult> {
  return await evalAttestStateRequest<EvalAttestStateAssertionResult>(env, "/assertion", input);
}

async function evalAttestStateRequest<T extends EvalAttestStateResult>(
  env: EvalAttestEnv,
  path: string,
  payload: unknown,
): Promise<T> {
  const namespace = env.EVAL_ATTEST_STATE;
  if (!namespace) {
    throw new Error("eval_attest_state_missing");
  }
  const stub = namespace.get(namespace.idFromName("volumearc-eval-attest-v1"));
  const response = await stub.fetch(new Request(`https://eval-attest-state.local${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  }));
  const body = await response.json().catch(() => null) as T | null;
  if (!body || (!response.ok && !("reason" in body))) {
    throw new Error("eval_attest_state_unavailable");
  }
  return body;
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

function challengeFailure(record: EvalAttestChallengeRecord | undefined, keyId: string): string | null {
  if (!record) {
    return "challenge_not_found";
  }
  if (record.keyId !== keyId) {
    return "challenge_device_mismatch";
  }
  const expiry = Date.parse(record.expiresAt);
  if (!Number.isFinite(expiry) || expiry <= Date.now()) {
    return "challenge_expired";
  }
  return null;
}

function isStoredEvalKey(value: unknown): value is EvalAttestStoredKey {
  if (!value || typeof value !== "object") {
    return false;
  }
  const record = value as Record<string, unknown>;
  return typeof record.deviceId === "string" &&
    typeof record.publicKeyJwk === "object" &&
    record.publicKeyJwk !== null &&
    typeof record.counter === "number" &&
    typeof record.attestedAt === "string" &&
    typeof record.expiresAt === "string";
}

function isEvalChallengeRecord(value: unknown): value is EvalAttestChallengeRecord {
  if (!value || typeof value !== "object") {
    return false;
  }
  const record = value as Record<string, unknown>;
  return typeof record.keyId === "string" &&
    typeof record.issuedAt === "string" &&
    typeof record.expiresAt === "string";
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
