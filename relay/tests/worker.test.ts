import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { encode as encodeCbor } from "cbor-x";

import worker from "../src/worker";

type RelayEnv = Parameters<typeof worker.fetch>[1];

const RELAY_SIGNING_KEY = "test-relay-signing-key";
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

function makeEnv(overrides: Partial<RelayEnv> = {}): RelayEnv {
  return {
    GEMINI_API_KEY: "gemini-test-key",
    RELAY_SIGNING_KEY,
    RATE_LIMIT: new InMemoryKV() as unknown as KVNamespace,
    MODEL_DEFAULT: "gemini-test-flash",
    MODEL_PREMIUM: "gemini-test-pro",
    MAX_OUTPUT_TOKENS: "800",
    REQUEST_TIMEOUT_MS: "1000",
    RATE_LIMIT_MAX_REQUESTS: "30",
    RATE_LIMIT_WINDOW_SECONDS: "600",
    ...overrides,
  };
}

async function hmacAuthHeader(deviceId = "device-a", secret = RELAY_SIGNING_KEY): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(deviceId));
  const hex = Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return `Bearer ${deviceId}.${hex}`;
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

async function requestChallenge(env: RelayEnv, authorization: string): Promise<string> {
  const response = await worker.fetch(
    new Request("https://relay.test/v1/attest/challenge", {
      method: "POST",
      headers: { Authorization: authorization },
    }),
    env,
  );
  expect(response.status).toBe(200);
  return (await json(response)).challenge as string;
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

describe("volumearc-ai-relay App Attest transition", () => {
  it("issues App Attest challenges only to HMAC-authenticated installs", async () => {
    const env = makeEnv();
    const unauthenticated = await worker.fetch(
      new Request("https://relay.test/v1/attest/challenge", { method: "POST" }),
      env,
    );
    expect(unauthenticated.status).toBe(401);

    const authenticated = await worker.fetch(
      new Request("https://relay.test/v1/attest/challenge", {
        method: "POST",
        headers: { Authorization: await hmacAuthHeader() },
      }),
      env,
    );

    expect(authenticated.status).toBe(200);
    const body = await json(authenticated);
    expect(typeof body.challenge).toBe("string");
    expect(typeof body.expiresAt).toBe("string");
    await expect(env.RATE_LIMIT.get(`attest:challenge:${body.challenge}`)).resolves.toContain("device-a");
  });

  it("keeps the Phase B HMAC fallback working for coach requests", async () => {
    const env = makeEnv();

    const response = await worker.fetch(
      coachRequest({ Authorization: await hmacAuthHeader() }),
      env,
    );

    expect(response.status).toBe(200);
    await expect(response.text()).resolves.toContain("Steady single today.");
    expect(fetch).toHaveBeenCalledTimes(1);
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

    const response = await worker.fetch(
      coachRequest({ Authorization: await hmacAuthHeader() }, body),
      env,
    );

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

    const response = await worker.fetch(
      coachRequest({ Authorization: await hmacAuthHeader() }, body),
      env,
    );

    expect(response.status).toBe(200);
    const upstreamInit = vi.mocked(fetch).mock.calls[0]?.[1] as RequestInit;
    const upstreamBody = JSON.parse(upstreamInit.body as string);
    const systemPrompt = upstreamBody.systemInstruction.parts[0].text as string;
    const userMessage = upstreamBody.contents.at(-1).parts[0].text as string;
    expect(systemPrompt).toContain("Data-driven");
    expect(systemPrompt).toContain("cite at least one specific number");
    expect(userMessage).toContain("[VAC:tmpl] intent=recovery style=analytical");
    expect(userMessage).toContain("HRV delta");
    expect(userMessage).toContain("Sleep: 49.0h");
  });

  it("preserves client-rendered prompt and system fields when present", async () => {
    const env = makeEnv();
    const body = JSON.stringify({
      intent: "progression",
      question: "Can I add weight?",
      contextBlock: "## Training context\n- Readiness: 82/100",
      style: "minimal",
      prompt: "client rendered prompt",
      system: "client rendered system",
    });

    const response = await worker.fetch(
      coachRequest({ Authorization: await hmacAuthHeader() }, body),
      env,
    );

    expect(response.status).toBe(200);
    const upstreamInit = vi.mocked(fetch).mock.calls[0]?.[1] as RequestInit;
    const upstreamBody = JSON.parse(upstreamInit.body as string);
    expect(upstreamBody.systemInstruction.parts[0].text).toBe("client rendered system");
    expect(upstreamBody.contents.at(-1).parts[0].text).toBe("client rendered prompt");
    expect(upstreamBody.generationConfig.temperature).toBe(0.7);
  });

  it("can require App Attest and reject HMAC-only coach requests for Phase C", async () => {
    const env = makeEnv({ REQUIRE_APP_ATTEST: "true" });

    const response = await worker.fetch(
      coachRequest({ Authorization: await hmacAuthHeader() }),
      env,
    );

    expect(response.status).toBe(410);
    await expect(json(response)).resolves.toMatchObject({ error: "app_attest_required" });
    expect(fetch).not.toHaveBeenCalled();
  });

  it("rejects incomplete App Attest headers instead of silently falling back to HMAC", async () => {
    const env = makeEnv();

    const response = await worker.fetch(
      coachRequest({
        Authorization: await hmacAuthHeader(),
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
    const auth = await hmacAuthHeader();
    const challengeResponse = await worker.fetch(
      new Request("https://relay.test/v1/attest/challenge", {
        method: "POST",
        headers: { Authorization: auth },
      }),
      env,
    );
    const challenge = (await json(challengeResponse)).challenge as string;

    const response = await worker.fetch(
      new Request("https://relay.test/v1/attest/bootstrap", {
        method: "POST",
        headers: {
          Authorization: auth,
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
    await expect(env.RATE_LIMIT.get(`attest:challenge:${challenge}`)).resolves.toContain("device-a");
  });

  it("accepts valid App Attest assertions and rejects replayed counters", async () => {
    const env = makeEnv();
    const authorization = await hmacAuthHeader();
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

    const challenge = await requestChallenge(env, authorization);
    const assertion = await signedAssertion(keyPair.privateKey, COACH_BODY, challenge, 1);
    const response = await worker.fetch(
      coachRequest({
        Authorization: authorization,
        "X-VA-Attest-Key-ID": keyId,
        "X-VA-Attest-Assertion": assertion,
        "X-VA-Attest-Nonce": challenge,
      }),
      env,
    );

    expect(response.status).toBe(200);
    await expect(response.text()).resolves.toContain("Steady single today.");
    await expect(env.RATE_LIMIT.get(`attest:key:${keyId}`)).resolves.toContain("\"counter\":1");

    const replayChallenge = await requestChallenge(env, authorization);
    const replayAssertion = await signedAssertion(keyPair.privateKey, COACH_BODY, replayChallenge, 1);
    const replay = await worker.fetch(
      coachRequest({
        Authorization: authorization,
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
    const auth = await hmacAuthHeader();
    const challengeResponse = await worker.fetch(
      new Request("https://relay.test/v1/attest/challenge", {
        method: "POST",
        headers: { Authorization: auth },
      }),
      env,
    );
    const challenge = (await json(challengeResponse)).challenge as string;
    const attestationObject = encodeCbor({
      fmt: "apple-appattest",
      authData: new Uint8Array(37),
      attStmt: { x5c: [] },
    });

    const response = await worker.fetch(
      new Request("https://relay.test/v1/attest/bootstrap", {
        method: "POST",
        headers: {
          Authorization: auth,
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
