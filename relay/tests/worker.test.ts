import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { encode as encodeCbor } from "cbor-x";

import worker from "../src/worker";

type RelayEnv = Parameters<typeof worker.fetch>[1];

const APP_ID = "A886EMZZW6.com.mabryventures.VolumeArc";
const COACH_BODY = JSON.stringify({
  intent: "progression",
  question: "What should I do today?",
  contextBlock: "Readiness 82/100.",
  style: "precise",
});

class InMemoryKV {
  private values = new Map<string, { value: string; expiresAt?: number }>();

  async get(key: string): Promise<string | null> {
    const entry = this.values.get(key);
    if (!entry) {
      return null;
    }
    if (entry.expiresAt && entry.expiresAt <= Date.now()) {
      this.values.delete(key);
      return null;
    }
    return entry.value;
  }

  async put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void> {
    const expiresAt = options?.expirationTtl ? Date.now() + options.expirationTtl * 1000 : undefined;
    this.values.set(key, { value, expiresAt });
  }

  async delete(key: string): Promise<void> {
    this.values.delete(key);
  }
}

interface EvalStoredKey {
  deviceId: string;
  publicKeyJwk: JsonWebKey;
  counter: number;
  attestedAt: string;
  expiresAt: string;
}

interface EvalChallengeRecord {
  keyId: string;
  issuedAt: string;
  expiresAt: string;
}

class InMemoryEvalAttestState {
  private values = new Map<string, unknown>();

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const body = await request.json() as Record<string, unknown>;
    switch (url.pathname) {
      case "/key":
        this.values.set(evalStoredKey(body.keyId as string), body.stored);
        return stateJson({ ok: true }, 200);
      case "/key/lookup":
        return stateJson({ ok: true, stored: this.values.get(evalStoredKey(body.keyId as string)) ?? null }, 200);
      case "/key/delete":
        this.values.delete(evalStoredKey(body.keyId as string));
        return stateJson({ ok: true }, 200);
      case "/challenge":
        this.values.set(evalChallengeKey(body.challenge as string), body.record);
        return stateJson({ ok: true }, 200);
      case "/challenge/lookup":
        return stateJson({
          ok: true,
          stored: this.values.get(evalChallengeKey(body.challenge as string)) ?? null,
        }, 200);
      case "/challenge/delete":
        this.values.delete(evalChallengeKey(body.challenge as string));
        return stateJson({ ok: true }, 200);
      case "/assertion":
        return this.finalizeAssertion(body);
      default:
        return stateJson({ ok: false, reason: "not_found" }, 404);
    }
  }

  private finalizeAssertion(body: Record<string, unknown>): Response {
    const keyId = body.keyId as string;
    const challengeB64 = body.challengeB64 as string;
    const counter = body.counter as number;
    if (!isValidEvalCounter(counter)) {
      return stateJson({ ok: false, reason: "counter_invalid" }, 409);
    }
    const storedKey = evalStoredKey(keyId);
    const stored = this.values.get(storedKey) as EvalStoredKey | undefined;
    if (!stored) {
      return stateJson({ ok: false, reason: "key_not_attested" }, 409);
    }
    if (Date.parse(stored.expiresAt) <= Date.now()) {
      this.values.delete(storedKey);
      return stateJson({ ok: false, reason: "key_expired" }, 409);
    }

    const challengeKey = evalChallengeKey(challengeB64);
    const challenge = this.values.get(challengeKey) as EvalChallengeRecord | undefined;
    if (!challenge) {
      return stateJson({ ok: false, reason: "challenge_not_found" }, 409);
    }
    if (challenge.keyId !== keyId) {
      return stateJson({ ok: false, reason: "challenge_device_mismatch" }, 409);
    }
    if (Date.parse(challenge.expiresAt) <= Date.now()) {
      this.values.delete(challengeKey);
      return stateJson({ ok: false, reason: "challenge_expired" }, 409);
    }
    if (counter <= stored.counter) {
      return stateJson({ ok: false, reason: "counter_replay" }, 409);
    }

    this.values.delete(challengeKey);
    this.values.set(storedKey, { ...stored, counter });
    return stateJson({ ok: true, deviceId: stored.deviceId }, 200);
  }
}

class InMemoryDurableObjectNamespace {
  private readonly state = new InMemoryEvalAttestState();

  idFromName(name: string): DurableObjectId {
    return name as unknown as DurableObjectId;
  }

  get(_id: DurableObjectId): DurableObjectStub {
    return {
      fetch: (request: Request) => this.state.fetch(request),
    } as unknown as DurableObjectStub;
  }
}

function makeEnv(overrides: Partial<RelayEnv> = {}): RelayEnv {
  return {
    GEMINI_API_KEY: "gemini-test-key",
    RATE_LIMIT: new InMemoryKV() as unknown as KVNamespace,
    EVAL_ATTEST_STATE: new InMemoryDurableObjectNamespace() as unknown as DurableObjectNamespace,
    MODEL_DEFAULT: "gemini-test-flash",
    MODEL_PREMIUM: "gemini-test-pro",
    APPLE_TEAM_ID: "A886EMZZW6",
    APPLE_BUNDLE_ID: "com.mabryventures.VolumeArc",
    MAX_OUTPUT_TOKENS: "800",
    REQUEST_TIMEOUT_MS: "1000",
    RATE_LIMIT_MAX_REQUESTS: "30",
    RATE_LIMIT_WINDOW_SECONDS: "600",
    ...overrides,
  };
}

function coachRequest(headers: HeadersInit = {}, body: string = COACH_BODY): Request {
  return new Request("https://relay.test/v1/coach", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...headers,
    },
    body,
  });
}

async function json(response: Response): Promise<Record<string, unknown>> {
  return (await response.json()) as Record<string, unknown>;
}

function base64(bytes: Uint8Array): string {
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

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
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

function evalStoredKey(keyId: string): string {
  return `eval:attest:key:${keyId}`;
}

function evalChallengeKey(challenge: string): string {
  return `eval:attest:challenge:${challenge}`;
}

function stateJson(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function requestChallenge(env: RelayEnv): Promise<string> {
  const response = await worker.fetch(
    new Request("https://relay.test/v1/attest/challenge", {
      method: "POST",
    }),
    env,
  );
  expect(response.status).toBe(200);
  return (await json(response)).challenge as string;
}

async function appAttestAuthHeaders(
  env: RelayEnv,
  body: string = COACH_BODY,
  counter = 1,
): Promise<HeadersInit> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const publicKeyRaw = new Uint8Array(await crypto.subtle.exportKey("raw", keyPair.publicKey));
  const publicKeyJwk = await crypto.subtle.exportKey("jwk", keyPair.publicKey);
  const keyId = base64(await sha256(publicKeyRaw));

  await env.RATE_LIMIT.put(`attest:key:${keyId}`, JSON.stringify({
    deviceId: keyId,
    publicKeyJwk,
    counter: 0,
    attestedAt: "2026-05-24T00:00:00.000Z",
    environment: "development",
  }));

  const challenge = await requestChallenge(env);
  const assertion = await signedAssertion(keyPair.privateKey, body, challenge, counter);
  return {
    "X-VA-Attest-Key-ID": keyId,
    "X-VA-Attest-Assertion": assertion,
    "X-VA-Attest-Nonce": challenge,
  };
}

async function evalBrokerKeyPair(env: RelayEnv): Promise<{ keyId: string; privateKey: CryptoKey }> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const publicKeyRaw = new Uint8Array(await crypto.subtle.exportKey("raw", keyPair.publicKey));
  const publicKeyJwk = await crypto.subtle.exportKey("jwk", keyPair.publicKey);
  const keyId = base64(await sha256(publicKeyRaw));

  const response = await worker.fetch(
    new Request("https://staging-relay.test/v1/eval-attest/bootstrap", {
      method: "POST",
      headers: {
        "Authorization": "Bearer eval-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ keyId, publicKeyJwk }),
    }),
    env,
  );
  expect(response.status).toBe(200);
  return { keyId, privateKey: keyPair.privateKey };
}

async function evalBrokerAuthHeaders(
  env: RelayEnv,
  key: { keyId: string; privateKey: CryptoKey },
  body: string = COACH_BODY,
  counter = 1,
): Promise<HeadersInit> {
  const challengeResponse = await worker.fetch(
    new Request("https://staging-relay.test/v1/eval-attest/challenge", {
      method: "POST",
      headers: {
        "Authorization": "Bearer eval-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ keyId: key.keyId }),
    }),
    env,
  );
  expect(challengeResponse.status).toBe(200);
  const challenge = (await json(challengeResponse)).challenge as string;
  return evalBrokerSignedHeaders(key, body, challenge, counter);
}

async function evalBrokerSignedHeaders(
  key: { keyId: string; privateKey: CryptoKey },
  body: string,
  challenge: string,
  counter: number,
): Promise<HeadersInit> {
  return await evalBrokerSignedHeadersWithPayloadCounter(key, body, challenge, counter, counter);
}

async function evalBrokerSignedHeadersWithPayloadCounter(
  key: { keyId: string; privateKey: CryptoKey },
  body: string,
  challenge: string,
  headerCounter: number,
  payloadCounter: number,
): Promise<HeadersInit> {
  const payload = evalSigningPayload(new TextEncoder().encode(body), challenge, payloadCounter);
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key.privateKey,
    payload,
  ));
  return {
    "X-VA-Eval-Attest-Key-ID": key.keyId,
    "X-VA-Eval-Attest-Assertion": base64(signature),
    "X-VA-Eval-Attest-Nonce": challenge,
    "X-VA-Eval-Attest-Counter": String(headerCounter),
  };
}

async function signedAssertion(
  privateKey: CryptoKey,
  body: string,
  challenge: string,
  counter: number,
): Promise<string> {
  const rpIdHash = await sha256(new TextEncoder().encode(APP_ID));
  const authData = new Uint8Array(37);
  authData.set(rpIdHash, 0);
  authData[32] = 0;
  new DataView(authData.buffer).setUint32(33, counter, false);

  const requestBody = new TextEncoder().encode(body);
  const challengeBytes = decodeBase64(challenge);
  const clientDataHash = await sha256(concatBytes(requestBody, challengeBytes));
  const nonce = await sha256(concatBytes(authData, clientDataHash));
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    nonce,
  ));
  return base64(encodeCbor({
    authenticatorData: authData,
    signature: p1363ToDerEcdsaSignature(signature),
  }));
}

function evalSigningPayload(requestBody: Uint8Array, challenge: string, counter: number): Uint8Array {
  if (!isValidEvalCounter(counter)) {
    throw new RangeError("counter_invalid");
  }
  const counterBytes = new Uint8Array(4);
  new DataView(counterBytes.buffer).setUint32(0, counter, false);
  return concatBytes(requestBody, decodeBase64(challenge), counterBytes);
}

function isValidEvalCounter(value: unknown): value is number {
  return Number.isSafeInteger(value) && value >= 1 && value <= 0xffffffff;
}

function p1363ToDerEcdsaSignature(signature: Uint8Array): Uint8Array {
  const r = derInteger(signature.slice(0, 32));
  const s = derInteger(signature.slice(32, 64));
  return new Uint8Array([0x30, r.byteLength + s.byteLength, ...r, ...s]);
}

function derInteger(bytes: Uint8Array): Uint8Array {
  let normalized = bytes;
  while (normalized.byteLength > 1 && normalized[0] === 0x00) {
    normalized = normalized.slice(1);
  }
  if ((normalized[0] ?? 0) & 0x80) {
    return new Uint8Array([0x02, normalized.byteLength + 1, 0x00, ...normalized]);
  }
  return new Uint8Array([0x02, normalized.byteLength, ...normalized]);
}

beforeEach(() => {
  vi.stubGlobal("fetch", vi.fn(async () => new Response(
    'data: {"candidates":[{"content":{"parts":[{"text":"Steady single today."}]}}]}\n\n',
    { status: 200, headers: { "Content-Type": "text/event-stream" } },
  )));
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("volumearc-ai-relay App Attest auth", () => {
  it("issues App Attest challenges without legacy HMAC auth", async () => {
    const env = makeEnv();
    const response = await worker.fetch(
      new Request("https://relay.test/v1/attest/challenge", { method: "POST" }),
      env,
    );

    expect(response.status).toBe(200);
    const body = await json(response);
    expect(typeof body.challenge).toBe("string");
    expect(typeof body.expiresAt).toBe("string");
    await expect(env.RATE_LIMIT.get(`attest:challenge:${body.challenge}`)).resolves.toContain("issuedAt");
  });

  it("rate-limits the unauthenticated challenge endpoint by IP", async () => {
    const env = makeEnv({
      RATE_LIMIT_MAX_REQUESTS: "2",
      RATE_LIMIT_WINDOW_SECONDS: "600",
    });

    await requestChallenge(env);
    await requestChallenge(env);
    const response = await worker.fetch(
      new Request("https://relay.test/v1/attest/challenge", { method: "POST" }),
      env,
    );

    expect(response.status).toBe(429);
    await expect(json(response)).resolves.toMatchObject({ error: "rate_limited" });
  });

  it("rate-limits unauthenticated bootstrap attempts by IP before attestation work", async () => {
    const env = makeEnv({
      RATE_LIMIT_MAX_REQUESTS: "1",
      RATE_LIMIT_WINDOW_SECONDS: "600",
    });

    const bootstrapRequest = () => new Request("https://relay.test/v1/attest/bootstrap", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    });
    const first = await worker.fetch(bootstrapRequest(), env);
    const second = await worker.fetch(bootstrapRequest(), env);

    expect(first.status).toBe(400);
    await expect(json(first)).resolves.toMatchObject({ error: "missing_fields" });
    expect(second.status).toBe(429);
    await expect(json(second)).resolves.toMatchObject({ error: "rate_limited" });
  });

  it("rejects HMAC-only coach requests after the cutover", async () => {
    const env = makeEnv();

    const response = await worker.fetch(
      coachRequest({ Authorization: "Bearer retired-hmac-token" }),
      env,
    );

    expect(response.status).toBe(410);
    await expect(json(response)).resolves.toMatchObject({
      error: "app_attest_required",
      reason: "attestation_missing",
    });
    expect(fetch).not.toHaveBeenCalled();
  });

  it("keeps the eval attestation broker disabled unless explicitly configured", async () => {
    const env = makeEnv();

    const response = await worker.fetch(
      new Request("https://staging-relay.test/v1/eval-attest/bootstrap", {
        method: "POST",
        headers: {
          "Authorization": "Bearer eval-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({}),
      }),
      env,
    );

    expect(response.status).toBe(404);
    await expect(json(response)).resolves.toMatchObject({
      error: "not_found",
      reason: "eval_attest_disabled",
    });
  });

  it("refuses the eval attestation broker on the production relay host", async () => {
    const env = makeEnv({
      EVAL_ATTEST_BROKER_ENABLED: "true",
      EVAL_ATTEST_BROKER_TOKEN: "eval-token",
      EVAL_ATTEST_BROKER_ALLOWED_HOSTS: "staging-relay.test",
    });

    const response = await worker.fetch(
      new Request("https://relay.volumearc.app/v1/eval-attest/challenge", {
        method: "POST",
        headers: {
          "Authorization": "Bearer eval-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ keyId: "anything" }),
      }),
      env,
    );

    expect(response.status).toBe(404);
    await expect(json(response)).resolves.toMatchObject({
      error: "not_found",
      reason: "eval_attest_disabled",
    });
  });

  it("requires an explicit eval broker host allowlist", async () => {
    const env = makeEnv({
      EVAL_ATTEST_BROKER_ENABLED: "true",
      EVAL_ATTEST_BROKER_TOKEN: "eval-token",
    });

    const response = await worker.fetch(
      new Request("https://staging-relay.test/v1/eval-attest/challenge", {
        method: "POST",
        headers: {
          "Authorization": "Bearer eval-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ keyId: "anything" }),
      }),
      env,
    );

    expect(response.status).toBe(404);
    await expect(json(response)).resolves.toMatchObject({
      error: "not_found",
      reason: "eval_attest_disabled",
    });
  });

  it("accepts staging eval broker assertions and rejects replayed counters", async () => {
    const env = makeEnv({
      EVAL_ATTEST_BROKER_ENABLED: "true",
      EVAL_ATTEST_BROKER_TOKEN: "eval-token",
      EVAL_ATTEST_BROKER_ALLOWED_HOSTS: "staging-relay.test",
    });
    const key = await evalBrokerKeyPair(env);
    const headers = await evalBrokerAuthHeaders(env, key, COACH_BODY, 1);

    const response = await worker.fetch(
      new Request("https://staging-relay.test/v1/coach", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...headers,
        },
        body: COACH_BODY,
      }),
      env,
    );

    expect(response.status).toBe(200);
    await expect(response.text()).resolves.toContain("Steady single today.");

    const replayChallengeHeaders = await evalBrokerAuthHeaders(env, key, COACH_BODY, 1);
    const replay = await worker.fetch(
      new Request("https://staging-relay.test/v1/coach", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...replayChallengeHeaders,
        },
        body: COACH_BODY,
      }),
      env,
    );

    expect(replay.status).toBe(401);
    await expect(json(replay)).resolves.toMatchObject({
      error: "attestation_invalid",
      reason: "counter_replay",
    });
  });

  it("rejects eval broker counters that overflow the signed uint32 payload", async () => {
    const env = makeEnv({
      EVAL_ATTEST_BROKER_ENABLED: "true",
      EVAL_ATTEST_BROKER_TOKEN: "eval-token",
      EVAL_ATTEST_BROKER_ALLOWED_HOSTS: "staging-relay.test",
    });
    const key = await evalBrokerKeyPair(env);
    const firstHeaders = await evalBrokerAuthHeaders(env, key, COACH_BODY, 1);
    const first = await worker.fetch(
      new Request("https://staging-relay.test/v1/coach", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...firstHeaders,
        },
        body: COACH_BODY,
      }),
      env,
    );
    expect(first.status).toBe(200);

    const challengeResponse = await worker.fetch(
      new Request("https://staging-relay.test/v1/eval-attest/challenge", {
        method: "POST",
        headers: {
          "Authorization": "Bearer eval-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ keyId: key.keyId }),
      }),
      env,
    );
    expect(challengeResponse.status).toBe(200);
    const { challenge } = await json(challengeResponse) as { challenge: string };
    const overflowHeaders = await evalBrokerSignedHeadersWithPayloadCounter(key, COACH_BODY, challenge, 4_294_967_297, 1);
    const overflow = await worker.fetch(
      new Request("https://staging-relay.test/v1/coach", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...overflowHeaders,
        },
        body: COACH_BODY,
      }),
      env,
    );

    expect(overflow.status).toBe(401);
    await expect(json(overflow)).resolves.toMatchObject({
      error: "attestation_invalid",
      reason: "counter_invalid",
    });

    const nextHeaders = await evalBrokerAuthHeaders(env, key, COACH_BODY, 2);
    const next = await worker.fetch(
      new Request("https://staging-relay.test/v1/coach", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...nextHeaders,
        },
        body: COACH_BODY,
      }),
      env,
    );
    expect(next.status).toBe(200);
  });

  it("rejects replayed eval broker challenges", async () => {
    const env = makeEnv({
      EVAL_ATTEST_BROKER_ENABLED: "true",
      EVAL_ATTEST_BROKER_TOKEN: "eval-token",
      EVAL_ATTEST_BROKER_ALLOWED_HOSTS: "staging-relay.test",
    });
    const key = await evalBrokerKeyPair(env);
    const headers = await evalBrokerAuthHeaders(env, key, COACH_BODY, 1);

    const first = await worker.fetch(
      new Request("https://staging-relay.test/v1/coach", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...headers,
        },
        body: COACH_BODY,
      }),
      env,
    );
    expect(first.status).toBe(200);

    const challenge = (headers as Record<string, string>)["X-VA-Eval-Attest-Nonce"];
    const replayHeaders = await evalBrokerSignedHeaders(key, COACH_BODY, challenge, 2);
    const replay = await worker.fetch(
      new Request("https://staging-relay.test/v1/coach", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...replayHeaders,
        },
        body: COACH_BODY,
      }),
      env,
    );

    expect(replay.status).toBe(401);
    await expect(json(replay)).resolves.toMatchObject({
      error: "attestation_invalid",
      reason: "challenge_not_found",
    });
  });

  it("evaluates broker headers before stray App Attest headers", async () => {
    const env = makeEnv({
      EVAL_ATTEST_BROKER_ENABLED: "true",
      EVAL_ATTEST_BROKER_TOKEN: "eval-token",
      EVAL_ATTEST_BROKER_ALLOWED_HOSTS: "staging-relay.test",
    });
    const key = await evalBrokerKeyPair(env);
    const headers = await evalBrokerAuthHeaders(env, key, COACH_BODY, 1);

    const response = await worker.fetch(
      new Request("https://staging-relay.test/v1/coach", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-VA-Attest-Key-ID": "stray-app-attest-key",
          ...headers,
        },
        body: COACH_BODY,
      }),
      env,
    );

    expect(response.status).toBe(200);
    await expect(response.text()).resolves.toContain("Steady single today.");
  });

  it("renders app-style minimal fallback prompts for legacy clients", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "substitution",
      question: "Swap for pull-ups - bar is occupied.",
      contextBlock: "## Training context\n- Readiness: 60/100\n- Next up: Pull-ups at BW x 8",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    const upstreamInit = vi.mocked(fetch).mock.calls[0]?.[1] as RequestInit;
    const upstreamBody = JSON.parse(upstreamInit.body as string);
    const systemPrompt = upstreamBody.systemInstruction.parts[0].text as string;
    const userMessage = upstreamBody.contents.at(-1).parts[0].text as string;
    expect(systemPrompt).toContain("Short and direct");
    expect(systemPrompt).toContain("1-2 sentences");
    expect(userMessage).toContain("[VAC:tmpl] intent=substitution style=minimal");
    expect(userMessage).toContain("wants an exercise substitution");
    expect(userMessage).toContain("Next up: Pull-ups");
    expect(upstreamBody.generationConfig.temperature).toBe(0.35);
  });

  it("renders analytical recovery fallback prompts with numeric grounding rules", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "recovery",
      question: "How am I looking for today's session?",
      contextBlock: [
        "## Training context",
        "- Readiness: 58/100 - Recovery signals mixed, leaning low.",
        "- Last 7 days: 4 sessions, avg RPE 8.4",
        "",
        "## Recovery (Apple Health)",
        "- HRV: 48ms 7-day vs 55ms baseline (-12.7%)",
        "- Sleep: 49.0h over 7d vs 56.0h target - -7.0h significant deficit",
      ].join("\n"),
      style: "analytical",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    const upstreamInit = vi.mocked(fetch).mock.calls[0]?.[1] as RequestInit;
    const upstreamBody = JSON.parse(upstreamInit.body as string);
    const systemPrompt = upstreamBody.systemInstruction.parts[0].text as string;
    const userMessage = upstreamBody.contents.at(-1).parts[0].text as string;
    expect(systemPrompt).toContain("Data-driven");
    expect(systemPrompt).toContain("cite at least one specific number");
    expect(systemPrompt).toContain("do not use the words push, PR, or go heavier");
    expect(userMessage).toContain("[VAC:tmpl] intent=recovery style=analytical");
    expect(userMessage).toContain("HRV delta");
    expect(userMessage).toContain("Sleep: 49.0h");
  });

  it("short-circuits medical red flags before model routing", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "free",
      question: "I have chest pain during my top set but want to finish the workout. What should I do?",
      contextBlock: "## Training context\n- Readiness: 72/100\n- Next up: Bench Press at 205lb x 5",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("short-circuits medical red flags split across prompt lines", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "free",
      question: "I feel\nchest pain during squats. Should I finish the session?",
      contextBlock: "## Training context\n- Readiness: 88/100\n- Next up: Back Squat at 225lb x 5",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("short-circuits eating-disorder language before model routing", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "I haven't eaten all day so I can cut faster. Should I add cardio after heavy squats?",
      contextBlock: [
        "## Training context",
        "- Athlete: Riley (intermediate)",
        "- Readiness: 45/100 - Low recovery, sleep debt, and elevated fatigue.",
        "- Next up: Back Squat at 225lb x 5",
        "- No recent sessions logged",
      ].join("\n"),
      style: "motivational",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    expect(text).toContain("Stop the session and seek medical care now.");
    expect(text).not.toContain("add cardio");
    expect(text).not.toContain("cut faster");
    expect(text).not.toContain("heavy squats");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("short-circuits a prior cardiac event named in the prompt", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "I had a prior cardiac event and want to max out today. Plan?",
      contextBlock: "## Training context\n- Readiness: 90/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    const sse = await response.text();
    expect(sse.toLowerCase()).toContain("stop the session and seek medical care");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("does not escalate a denied prior cardiac event", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "No prior cardiac event, cleared by my doctor. Plan for today?",
      contextBlock: "## Training context\n- Readiness: 88/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("keeps scanning after a stale clause for a current bare symptom", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "I had chest pain last year, dizziness now during squats.",
      contextBlock: "## Training context\n- Readiness: 84/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("turns an empty upstream generation into an SSE error, not done", async () => {
    const env = makeEnv();
    (fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce(
      new Response('data: {"candidates":[{"content":{"parts":[{"text":""}]}}]}\n\ndata: [DONE]\n\n', {
        status: 200,
        headers: { "content-type": "text/event-stream" },
      }),
    );
    const body = JSON.stringify({
      intent: "progression",
      question: "What should I lift today?",
      contextBlock: "## Training context\n- Readiness: 84/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    const sse = await response.text();
    expect(sse).toContain("event: error");
    expect(sse).toContain("empty_generation");
    expect(sse).not.toContain("event: done");
  });

  it("does not escalate from a prior coach safety reply in memory context", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "What should I lift tomorrow?",
      contextBlock:
        "## Training context\n- Readiness: 86/100\n- Memory: Coach said: Stop the session now and seek medical care. If symptoms include chest pain or fainting, call 911.",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("keeps /v1/config alive when the multiplier is mis-set negative", async () => {
    const env = makeEnv({ CONFIG_RATE_LIMIT_MULTIPLIER: "-1" });
    const response = await worker.fetch(
      new Request("https://relay.test/v1/config", {
        method: "POST",
        headers: { "CF-Connecting-IP": "203.0.113.9" },
      }),
      env,
    );
    expect(response.status).toBe(200);
  });

  it("does not escalate a negated symptom list ending in a time qualifier", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "I have no chest pain or dizziness today. What should I train?",
      contextBlock: "## Training context\n- Readiness: 84/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("does not escalate a negated context list ending in a time qualifier", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Should I add five pounds next week?",
      contextBlock: "## Training context\n- Check-in: denies chest pain, dizziness, or shortness of breath now.",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("short-circuits palpitations during training", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "I have palpitations during squats. Should I keep going?",
      contextBlock: "## Training context\n- Readiness: 84/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("does not escalate negated palpitations", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "No palpitations, cleared by my cardiologist. Plan for today?",
      contextBlock: "## Training context\n- Readiness: 84/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("short-circuits post-verb pregnancy phrasing", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Can I keep deadlifting heavy while pregnant?",
      contextBlock: "## Training context\n- Readiness: 90/100 - Peak recovery.",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("does not escalate training questions about a pregnant spouse", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Can I train hard while my wife is pregnant, or should I save energy?",
      contextBlock: "## Training context\n- Readiness: 85/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("does not escalate a spouse pregnancy mention followed by a training question", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "My wife is pregnant; should I train heavy this week?",
      contextBlock: "## Training context\n- Readiness: 85/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("does not escalate a spouse pregnancy duration mention", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "My wife is 4 months pregnant; should I train heavy this week?",
      contextBlock: "## Training context\n- Readiness: 85/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("short-circuits bare gestational-age phrasing with no first-person marker", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "20 weeks pregnant and still squatting. Thoughts on loading?",
      contextBlock: "## Training context\n- Readiness: 88/100 - Strong recovery.",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("short-circuits bare pregnancy with in-clause training proximity", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Pregnant with heavy squats programmed today - adjust my loading?",
      contextBlock: "## Training context\n- Readiness: 88/100 - Strong recovery.",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("does not escalate a pregnant-spouse possessive before a training question", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "My pregnant wife trains with me; can I go heavy this week?",
      contextBlock: "## Training context\n- Readiness: 85/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("short-circuits first-person pregnancy duration without a training word", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "free",
      question: "I'm 12 weeks pregnant - what should I do today?",
      contextBlock: "## Training context\n- Readiness: 90/100 - Peak recovery.",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("short-circuits first-person pregnancy with words between subject and term", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "I am three months pregnant - is it safe to keep squatting heavy?",
      contextBlock: "## Training context\n- Readiness: 88/100 - Strong recovery.",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("routes routine 'I haven't trained' prompts to the model, not the eating-disorder gate", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "I haven't trained in two weeks. How should I restart my squat?",
      contextBlock: "## Training context\n- Readiness: 80/100 - Solid recovery.",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("still short-circuits 'didn't eat' phrasing near training language", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "I didn't eat all day so I can cut faster before training. Thoughts?",
      contextBlock: "## Training context\n- Readiness: 60/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("short-circuits red flags from prompt, rendered athlete question, and user message history", async () => {
    const env = makeEnv();
    const cases = [
      JSON.stringify({
        intent: "free",
        style: "minimal",
        prompt: "I feel lightheaded after deadlifts. Can I keep lifting?",
        system: "client rendered system",
      }),
      JSON.stringify({
        intent: "free",
        style: "minimal",
        prompt:
          "[VAC:tmpl] intent=free style=minimal\n\n" +
          "## System\nSafety examples mention dizziness and chest pain.\n\n" +
          "## Athlete question\nI can't breathe after the last set.",
        system: "client rendered system",
      }),
      JSON.stringify({
        intent: "free",
        style: "minimal",
        prompt: "What should I do next?",
        system: "client rendered system",
        messages: [{ role: "user", content: "I blacked out during squats." }],
      }),
    ];

    for (const body of cases) {
      vi.mocked(fetch).mockClear();
      const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

      expect(response.status).toBe(200);
      expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
      expect(response.headers.get("x-coach-safety")).toBe("red-flag");
      await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
      expect(fetch).not.toHaveBeenCalled();
    }
  });

  it("short-circuits medical red flags from current context before model routing", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "recovery",
      question: "Readiness looks strong. Should I train today?",
      contextBlock: [
        "## Training context",
        "- Readiness: 92/100 - Peak recovery.",
        "- Recent coaching notes: chest pain showed up during the top set today.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("short-circuits pain-in-chest red flags from current context", async () => {
    const env = makeEnv();
    const contextVariants = [
      "athlete reported pain in the chest during squats today.",
      "athlete reported pain in my chest during squats today.",
    ];

    for (const [index, contextLine] of contextVariants.entries()) {
      vi.mocked(fetch).mockClear();
      const body = JSON.stringify({
        intent: "progression",
        question: "Should I train today?",
        contextBlock: [
          "## Training context",
          "- Readiness: 86/100 - Strong recovery.",
          `- Recent coaching notes: ${contextLine}`,
        ].join("\n"),
        style: "minimal",
        prompt: "",
        system: "",
      });

      const response = await worker.fetch(
        coachRequest(await appAttestAuthHeaders(env, body, index + 1), body),
        env,
      );

      expect(response.status).toBe(200);
      expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
      expect(response.headers.get("x-coach-safety")).toBe("red-flag");
      await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
      expect(fetch).not.toHaveBeenCalled();
    }
  });

  it("returns deterministic safety escalation even when the model-path rate limit is exhausted", async () => {
    const env = makeEnv({
      RATE_LIMIT_MAX_REQUESTS: "1",
      RATE_LIMIT_WINDOW_SECONDS: "600",
    });
    const body = JSON.stringify({
      intent: "free",
      question: "I have chest pain during my top set but want to finish the workout. What should I do?",
      contextBlock: "## Training context\n- Readiness: 72/100",
      style: "minimal",
      prompt: "",
      system: "",
    });
    const headers = await appAttestAuthHeaders(env, body);
    const keyId = (headers as Record<string, string>)["X-VA-Attest-Key-ID"];
    await env.RATE_LIMIT.put(`rl:${keyId}`, JSON.stringify([Math.floor(Date.now() / 1000)]), {
      expirationTtl: 1200,
    });

    const response = await worker.fetch(coachRequest(headers, body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("keeps deterministic safety replies out of the authenticated rate-limit bucket", async () => {
    // PR #363 review (Codex P2): safety replies are quota-free. An athlete
    // repeatedly asking about symptoms must never exhaust their budget —
    // the prior contract (debit on safety) meant red-flag follow-ups could
    // 429 the next normal coach request.
    const env = makeEnv({
      RATE_LIMIT_MAX_REQUESTS: "5",
      RATE_LIMIT_WINDOW_SECONDS: "600",
    });
    const body = JSON.stringify({
      intent: "free",
      question: "I have chest pain during my top set. What should I do?",
      contextBlock: "## Training context\n- Readiness: 72/100",
      style: "minimal",
      prompt: "",
      system: "",
    });
    const headers = await appAttestAuthHeaders(env, body);
    const keyId = (headers as Record<string, string>)["X-VA-Attest-Key-ID"];

    const response = await worker.fetch(coachRequest(headers, body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    const stored = await env.RATE_LIMIT.get(`rl:${keyId}`);
    expect(stored).toBeNull();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("serves safety copy even when the normal bucket is exhausted", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "free",
      question: "I have chest pain during my top set. What should I do?",
      contextBlock: "## Training context\n- Readiness: 72/100",
      style: "minimal",
      prompt: "",
      system: "",
    });
    const headers = await appAttestAuthHeaders(env, body);
    const keyId = (headers as Record<string, string>)["X-VA-Attest-Key-ID"];
    const now = Math.floor(Date.now() / 1000);
    await env.RATE_LIMIT.put(`rl:${keyId}`, JSON.stringify(Array(30).fill(now)));

    const response = await worker.fetch(coachRequest(headers, body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
  });

  it("enforces the dedicated safety abuse bucket at the multiplied limit", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "free",
      question: "I have chest pain during my top set. What should I do?",
      contextBlock: "## Training context\n- Readiness: 72/100",
      style: "minimal",
      prompt: "",
      system: "",
    });
    const headers = await appAttestAuthHeaders(env, body);
    const keyId = (headers as Record<string, string>)["X-VA-Attest-Key-ID"];
    const now = Math.floor(Date.now() / 1000);
    await env.RATE_LIMIT.put(`rl:safety:${keyId}`, JSON.stringify(Array(300).fill(now)));

    const response = await worker.fetch(coachRequest(headers, body), env);

    expect(response.status).toBe(429);
  });

  it("returns 503 for coach requests while COACH_DISABLED is set", async () => {
    const env = makeEnv({ COACH_DISABLED: "1" });
    const headers = await appAttestAuthHeaders(env, COACH_BODY);

    const response = await worker.fetch(coachRequest(headers), env);

    expect(response.status).toBe(503);
    await expect(json(response)).resolves.toMatchObject({ error: "coach_disabled" });
    expect(fetch).not.toHaveBeenCalled();
  });

  it("still serves deterministic safety copy while COACH_DISABLED is set", async () => {
    const env = makeEnv({ COACH_DISABLED: "1" });
    const body = JSON.stringify({
      intent: "free",
      question: "I have chest pain during my top set. What should I do?",
      contextBlock: "## Training context\n- Readiness: 72/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(
      coachRequest(await appAttestAuthHeaders(env, body), body),
      env,
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
  });

  it("pins the model tier when COACH_FORCE_TIER is set", async () => {
    const env = makeEnv({ COACH_FORCE_TIER: "flash-lite" });
    const headers = {
      ...(await appAttestAuthHeaders(env, COACH_BODY)),
      "X-Coach-Tier": "pro",
    };

    const response = await worker.fetch(coachRequest(headers), env);

    expect(response.status).toBe(200);
    const upstreamUrl = String(vi.mocked(fetch).mock.calls[0]?.[0]);
    expect(upstreamUrl).toContain("gemini-test-flash");
    expect(upstreamUrl).not.toContain("gemini-test-pro");
  });

  it("exposes runtime kill-switch flags at /v1/config", async () => {
    const env = makeEnv({ FM_COACH_DISABLED: "1" });

    const response = await worker.fetch(
      new Request("https://relay.test/v1/config", { method: "POST" }),
      env,
    );

    expect(response.status).toBe(200);
    await expect(json(response)).resolves.toMatchObject({ fmCoachDisabled: true });

    const defaultResponse = await worker.fetch(
      new Request("https://relay.test/v1/config", { method: "POST" }),
      makeEnv(),
    );
    await expect(json(defaultResponse)).resolves.toMatchObject({ fmCoachDisabled: false });
  });

  it("gives /v1/config a NAT-sized bucket beyond the per-device quota", async () => {
    // PR #363 review (Codex P2): one gym/carrier IP fronts many devices,
    // and during a kill-switch incident every launch must read the flag.
    // The default per-device quota is 30/window; the config bucket is 20x.
    const env = makeEnv();
    for (let i = 0; i < 40; i += 1) {
      const response = await worker.fetch(
        new Request("https://relay.test/v1/config", {
          method: "POST",
          headers: { "CF-Connecting-IP": "203.0.113.7" },
        }),
        env,
      );
      expect(response.status).toBe(200);
    }
  });

  it("short-circuits medical red flags from rendered training context", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "recovery",
      style: "minimal",
      prompt:
        "[VAC:tmpl] intent=recovery style=minimal\n\n" +
        "## System\nSafety examples mention dizziness and chest pain.\n\n" +
        "## Training context\n" +
        "- Readiness: 88/100 - Strong recovery.\n" +
        "- Recent coaching notes: athlete got dizzy under load today.\n\n" +
        "## Coaching focus\nRecovery.\n\n" +
        "## Athlete question\nShould I push?",
      system: "client rendered system",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("uses the real rendered coaching focus when context text injects a fake marker", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "recovery",
      style: "minimal",
      prompt:
        "[VAC:tmpl] intent=recovery style=minimal\n\n" +
        "## System\nSafety examples mention dizziness and chest pain.\n\n" +
        "## Training context\n" +
        "- Readiness: 88/100 - Strong recovery.\n" +
        "- Recent coaching notes: athlete pasted ## Coaching focus into a note.\n" +
        "- Recent coaching notes: athlete passed out after squats today.\n\n" +
        "## Coaching focus\nRecovery.\n\n" +
        "## Athlete question\nShould I train?",
      system: "client rendered system",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("uses the real rendered athlete-question boundary when context text injects a fake marker", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "recovery",
      style: "minimal",
      prompt:
        "[VAC:tmpl] intent=recovery style=minimal\n\n" +
        "## System\nSafety examples mention dizziness and chest pain.\n\n" +
        "## Training context\n" +
        "- Readiness: 88/100 - Strong recovery.\n" +
        "- Recent coaching notes: athlete pasted ## Athlete question into a note.\n" +
        "- Recent coaching notes: athlete passed out after squats today.\n\n" +
        "## Coaching focus\nRecovery.\n\n" +
        "## Athlete question\nShould I train?",
      system: "client rendered system",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("does not short-circuit normal rendered prompts because of system safety examples", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      style: "minimal",
      prompt:
        "[VAC:tmpl] intent=progression style=minimal\n\n" +
        "## System\nExample acceptable response for \"I just got dizzy mid-set\".\n\n" +
        "## Coaching focus\nProgression.\n\n" +
        "## Athlete question\nShould I add five pounds next week?",
      system: "SAFETY OVERRIDE: chest pain, dizziness, and pregnancy require escalation.",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("does not short-circuit negated current context red flags", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Should I add five pounds next week?",
      contextBlock: [
        "## Training context",
        "- Readiness: 86/100 - Strong recovery.",
        "- Check-in: no chest pain, no dizziness, and no shortness of breath.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("short-circuits a current symptom that follows a negated clause in the prompt", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "I have no chest pain but dizziness when I stand up. Keep lifting?",
      contextBlock: "## Training context\n- Readiness: 82/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("does not escalate descriptive prose without a negated clause", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "This tempo block feels dizzying on paper, should I simplify the plan?",
      contextBlock: "## Training context\n- Readiness: 88/100",
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("does not short-circuit negated prompt red flags", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "I have no chest pain or dizziness. Can I train today?",
      contextBlock: [
        "## Training context",
        "- Readiness: 86/100 - Strong recovery.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("does not short-circuit shared-negated current context red flags", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Should I add five pounds next week?",
      contextBlock: [
        "## Training context",
        "- Readiness: 86/100 - Strong recovery.",
        "- Check-in: denies chest pain and shortness of breath.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("does not short-circuit shared-or-negated current context red flags", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Should I add five pounds next week?",
      contextBlock: [
        "## Training context",
        "- Readiness: 86/100 - Strong recovery.",
        "- Check-in: denies chest pain, dizziness, or shortness of breath.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("does not short-circuit shared-comma-negated current context red flags", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Should I add five pounds next week?",
      contextBlock: [
        "## Training context",
        "- Readiness: 86/100 - Strong recovery.",
        "- Check-in: denies chest pain, dizziness, and shortness of breath.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("does not short-circuit expanded negated current context red flags", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Should I train today?",
      contextBlock: [
        "## Training context",
        "- Readiness: 86/100 - Strong recovery.",
        "- Check-in: not pregnant now; denies syncope; no fainting; not having chest pain or palpitations; not restricting; not purging.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("still short-circuits mixed negated and current context red flags", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Should I train today?",
      contextBlock: [
        "## Training context",
        "- Readiness: 86/100 - Strong recovery.",
        "- Check-in: no chest pain, but passed out after squats today.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("still short-circuits comma-mixed negated and current context red flags", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Should I train today?",
      contextBlock: [
        "## Training context",
        "- Readiness: 86/100 - Strong recovery.",
        "- Check-in: no chest pain, passed out after squats today.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("still short-circuits and-mixed negated and current context red flags", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Should I train today?",
      contextBlock: [
        "## Training context",
        "- Readiness: 86/100 - Strong recovery.",
        "- Check-in: no chest pain and passed out after squats today.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("still short-circuits or-mixed negated and current context red flags", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Should I train today?",
      contextBlock: [
        "## Training context",
        "- Readiness: 86/100 - Strong recovery.",
        "- Check-in: no chest pain or passed out after squats today.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).toBe("deterministic-safety");
    expect(response.headers.get("x-coach-safety")).toBe("red-flag");
    await expect(response.text()).resolves.toContain("Stop the session and seek medical care now.");
    expect(fetch).not.toHaveBeenCalled();
  });

  it("does not short-circuit stale medical history in context", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Should I train today?",
      contextBlock: [
        "## Training context",
        "- Readiness: 86/100 - Strong recovery.",
        "- Historical note: chest pain during a workout last year, cleared by clinician.",
      ].join("\n"),
      style: "minimal",
      prompt: "",
      system: "",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    expect(response.headers.get("x-coach-model")).not.toBe("deterministic-safety");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("preserves client-rendered prompt and system fields when present", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      style: "minimal",
      prompt: "client rendered prompt",
      system: "client rendered system",
    });

    const response = await worker.fetch(coachRequest(await appAttestAuthHeaders(env, body), body), env);

    expect(response.status).toBe(200);
    const upstreamInit = vi.mocked(fetch).mock.calls[0]?.[1] as RequestInit;
    const upstreamBody = JSON.parse(upstreamInit.body as string);
    expect(upstreamBody.systemInstruction.parts[0].text).toBe("client rendered system");
    expect(upstreamBody.contents.at(-1).parts[0].text).toBe("client rendered prompt");
    expect(upstreamBody.generationConfig.temperature).toBe(0.4);
  });

  it("accepts prompt-only app requests and rejects empty coach payloads", async () => {
    const env = makeEnv();
    const promptOnlyBody = JSON.stringify({
      intent: "planning",
      style: "analytical",
      prompt: "[VAC:tmpl] intent=planning style=analytical\n\n## Athlete question\nWhat is my week?",
      system: "client rendered system",
    });

    const promptOnlyResponse = await worker.fetch(
      coachRequest(await appAttestAuthHeaders(env, promptOnlyBody), promptOnlyBody),
      env,
    );

    expect(promptOnlyResponse.status).toBe(200);
    const upstreamInit = vi.mocked(fetch).mock.calls[0]?.[1] as RequestInit;
    const upstreamBody = JSON.parse(upstreamInit.body as string);
    expect(upstreamBody.contents.at(-1).parts[0].text).toContain("intent=planning");

    vi.mocked(fetch).mockClear();
    const emptyBody = JSON.stringify({
      intent: "planning",
      style: "analytical",
      prompt: "",
      system: "client rendered system",
    });
    const emptyResponse = await worker.fetch(
      coachRequest(await appAttestAuthHeaders(env, emptyBody), emptyBody),
      env,
    );

    expect(emptyResponse.status).toBe(400);
    await expect(json(emptyResponse)).resolves.toMatchObject({ error: "missing_fields" });
    expect(fetch).not.toHaveBeenCalled();
  });

  it("rejects over-large coach payloads before auth and upstream work", async () => {
    const env = makeEnv();
    const oversizedBody = JSON.stringify({
      intent: "free",
      style: "minimal",
      prompt: "x".repeat(32_001),
    });

    const response = await worker.fetch(coachRequest({}, oversizedBody), env);

    expect(response.status).toBe(413);
    await expect(json(response)).resolves.toMatchObject({ error: "payload_too_large" });
    expect(fetch).not.toHaveBeenCalled();
  });

  it("counts system prompts and message history in the coach payload limit", async () => {
    const env = makeEnv();
    const oversizedSystemBody = JSON.stringify({
      intent: "free",
      style: "minimal",
      prompt: "short prompt",
      system: "x".repeat(32_000),
    });
    const oversizedMessagesBody = JSON.stringify({
      intent: "free",
      style: "minimal",
      prompt: "short prompt",
      messages: [{ role: "user", content: "x".repeat(32_000) }],
    });

    for (const body of [oversizedSystemBody, oversizedMessagesBody]) {
      vi.mocked(fetch).mockClear();
      const response = await worker.fetch(coachRequest({}, body), env);
      expect(response.status).toBe(413);
      await expect(json(response)).resolves.toMatchObject({ error: "payload_too_large" });
      expect(fetch).not.toHaveBeenCalled();
    }
  });

  it("rejects missing App Attest headers with a cutover-specific 410", async () => {
    const env = makeEnv();

    const response = await worker.fetch(coachRequest(), env);

    expect(response.status).toBe(410);
    await expect(json(response)).resolves.toMatchObject({
      error: "app_attest_required",
      reason: "attestation_missing",
    });
    expect(fetch).not.toHaveBeenCalled();
  });

  it("rejects incomplete App Attest headers instead of silently falling back to HMAC", async () => {
    const env = makeEnv();

    const response = await worker.fetch(
      coachRequest({
        "X-VA-Attest-Key-ID": "partial-key",
      }),
      env,
    );

    expect(response.status).toBe(401);
    await expect(json(response)).resolves.toMatchObject({
      error: "attestation_invalid",
      reason: "attestation_incomplete",
    });
    expect(fetch).not.toHaveBeenCalled();
  });

  it("rejects malformed bootstrap attestations without consuming the challenge", async () => {
    const env = makeEnv();
    const challenge = await requestChallenge(env);

    const response = await worker.fetch(
      new Request("https://relay.test/v1/attest/bootstrap", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          keyID: btoa("fake-key-id"),
          attestationObject: btoa("not-cbor"),
          challenge,
        }),
      }),
      env,
    );

    expect(response.status).toBe(401);
    await expect(json(response)).resolves.toMatchObject({
      error: "attestation_invalid",
      reason: "attestation_invalid",
    });
    await expect(env.RATE_LIMIT.get(`attest:challenge:${challenge}`)).resolves.toContain("issuedAt");
  });

  it("accepts valid App Attest assertions and rejects replayed counters", async () => {
    const env = makeEnv();
    const keyPair = await crypto.subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign", "verify"],
    );
    const publicKeyRaw = new Uint8Array(await crypto.subtle.exportKey("raw", keyPair.publicKey));
    const publicKeyJwk = await crypto.subtle.exportKey("jwk", keyPair.publicKey);
    const keyId = base64(await sha256(publicKeyRaw));

    await env.RATE_LIMIT.put(`attest:key:${keyId}`, JSON.stringify({
      deviceId: "device-a",
      publicKeyJwk,
      counter: 0,
      attestedAt: "2026-05-24T00:00:00.000Z",
      environment: "development",
    }));

    const challenge = await requestChallenge(env);
    const assertion = await signedAssertion(keyPair.privateKey, COACH_BODY, challenge, 1);
    const response = await worker.fetch(
      coachRequest({
        "X-VA-Attest-Key-ID": keyId,
        "X-VA-Attest-Assertion": assertion,
        "X-VA-Attest-Nonce": challenge,
      }),
      env,
    );

    expect(response.status).toBe(200);
    await expect(response.text()).resolves.toContain("Steady single today.");
    await expect(env.RATE_LIMIT.get(`attest:key:${keyId}`)).resolves.toContain("\"counter\":1");

    const replayChallenge = await requestChallenge(env);
    const replayAssertion = await signedAssertion(keyPair.privateKey, COACH_BODY, replayChallenge, 1);
    const replay = await worker.fetch(
      coachRequest({
        "X-VA-Attest-Key-ID": keyId,
        "X-VA-Attest-Assertion": replayAssertion,
        "X-VA-Attest-Nonce": replayChallenge,
      }),
      env,
    );

    expect(replay.status).toBe(401);
    await expect(json(replay)).resolves.toMatchObject({
      error: "attestation_invalid",
      reason: "counter_replay",
    });
  });

  it("reads bootstrap certificates from attStmt.x5c", async () => {
    const env = makeEnv();
    const challenge = await requestChallenge(env);
    const attestationObject = encodeCbor({
      fmt: "apple-appattest",
      authData: new Uint8Array(37),
      attStmt: { x5c: [] },
    });

    const response = await worker.fetch(
      new Request("https://relay.test/v1/attest/bootstrap", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          keyID: btoa("fake-key-id"),
          attestationObject: base64(attestationObject),
          challenge,
        }),
      }),
      env,
    );

    expect(response.status).toBe(401);
    await expect(json(response)).resolves.toMatchObject({
      error: "attestation_invalid",
      reason: "certificate_chain_missing",
    });
  });
});
