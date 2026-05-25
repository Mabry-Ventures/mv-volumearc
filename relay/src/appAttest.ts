import "reflect-metadata";

import { decode as decodeCbor } from "cbor-x";
import { X509Certificate } from "@peculiar/x509";

export interface AppAttestEnv {
  RATE_LIMIT: KVNamespace;
  ATTEST_KEYS?: KVNamespace;
  ATTEST_CHALLENGES?: KVNamespace;
  APP_ATTEST_STATE?: DurableObjectNamespace;
  APPLE_APP_ID?: string;
  APPLE_TEAM_ID?: string;
  APPLE_BUNDLE_ID?: string;
}

export interface AppAttestStoredKey {
  deviceId: string;
  publicKeyJwk: JsonWebKey;
  counter: number;
  attestedAt: string;
  environment: "production" | "development";
}

export interface AppAttestAuthSuccess {
  ok: true;
  deviceId: string;
  keyId: string;
}

export interface AppAttestAuthFailure {
  ok: false;
  reason: string;
}

const APP_ATTEST_ROOT_PEM = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

const APP_ATTEST_ROOT_SHA256 = "1cb9823ba28ba6ad2d33a006941de2ae4f513ef1d4e831b9f7e0fa7b6242c932";
const APP_ATTEST_EXTENSION_OID = "1.2.840.113635.100.8.2";
const CHALLENGE_TTL_SECONDS = 5 * 60;

interface ChallengeRecord {
  subject?: string;
  issuedAt: string;
  expiresAt: string;
}

interface ParsedAuthData {
  rpIdHash: Uint8Array;
  flags: number;
  counter: number;
  aaguid?: Uint8Array;
  credentialId?: Uint8Array;
}

type AppAttestStateResult =
  | { ok: true }
  | { ok: false; reason: string };

type AppAttestStateKeyResult =
  | { ok: true; stored: AppAttestStoredKey | null }
  | { ok: false; reason: string };

type AppAttestStateAssertionResult =
  | { ok: true; deviceId: string }
  | { ok: false; reason: string };

export class AppAttestState implements DurableObject {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    if (request.method !== "POST") {
      return stateJson({ ok: false, reason: "method_not_allowed" }, 405);
    }

    const url = new URL(request.url);
    try {
      switch (url.pathname) {
        case "/challenge":
          return await this.putChallenge(request);
        case "/key":
          return await this.lookupKey(request);
        case "/attestation":
          return await this.storeAttestation(request);
        case "/assertion":
          return await this.finalizeAssertion(request);
        default:
          return stateJson({ ok: false, reason: "not_found" }, 404);
      }
    } catch {
      return stateJson({ ok: false, reason: "app_attest_state_unavailable" }, 500);
    }
  }

  async alarm(): Promise<void> {
    const now = Date.now();
    const challenges = await this.state.storage.list<ChallengeRecord>({ prefix: "attest:challenge:" });
    const expired: string[] = [];
    let nextAlarm: number | null = null;

    for (const [key, record] of challenges) {
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

  private async putChallenge(request: Request): Promise<Response> {
    const body = await request.json() as { challenge?: unknown; record?: unknown };
    if (typeof body.challenge !== "string" || !isChallengeRecord(body.record)) {
      return stateJson({ ok: false, reason: "bad_request" }, 400);
    }

    await this.state.storage.put(challengeKey(body.challenge), body.record);
    await this.scheduleChallengeSweep(body.record.expiresAt);
    return stateJson({ ok: true }, 200);
  }

  private async lookupKey(request: Request): Promise<Response> {
    const body = await request.json() as { keyId?: unknown };
    if (typeof body.keyId !== "string") {
      return stateJson({ ok: false, reason: "bad_request" }, 400);
    }

    const stored = await this.state.storage.get<AppAttestStoredKey>(storedKey(body.keyId));
    return stateJson({ ok: true, stored: stored ?? null }, 200);
  }

  private async storeAttestation(request: Request): Promise<Response> {
    const body = await request.json() as {
      keyId?: unknown;
      challengeB64?: unknown;
      stored?: unknown;
    };
    if (
      typeof body.keyId !== "string" ||
      typeof body.challengeB64 !== "string" ||
      !isStoredKey(body.stored)
    ) {
      return stateJson({ ok: false, reason: "bad_request" }, 400);
    }

    const result = await this.state.storage.transaction<AppAttestStateResult>(async (txn) => {
      const key = challengeKey(body.challengeB64 as string);
      const challenge = await txn.get<ChallengeRecord>(key);
      const expectedSubject = (body.stored as AppAttestStoredKey).deviceId;
      const failure = challengeFailure(challenge, expectedSubject);
      if (failure) {
        if (failure === "challenge_expired") {
          await txn.delete(key);
        }
        return { ok: false, reason: failure };
      }

      await txn.delete(key);
      await txn.put(storedKey(body.keyId as string), body.stored as AppAttestStoredKey);
      return { ok: true };
    });

    return stateJson(result, result.ok ? 200 : 409);
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
      return stateJson({ ok: false, reason: "bad_request" }, 400);
    }

    const result = await this.state.storage.transaction<AppAttestStateAssertionResult>(async (txn) => {
      const stored = await txn.get<AppAttestStoredKey>(storedKey(body.keyId as string));
      if (!stored) {
        return { ok: false, reason: "key_not_attested" };
      }

      const key = challengeKey(body.challengeB64 as string);
      const challenge = await txn.get<ChallengeRecord>(key);
      const failure = challengeFailure(challenge, stored.deviceId);
      if (failure) {
        if (failure === "challenge_expired") {
          await txn.delete(key);
        }
        return { ok: false, reason: failure };
      }
      if ((body.counter as number) <= stored.counter) {
        return { ok: false, reason: "counter_replay" };
      }

      await txn.delete(key);
      await txn.put(storedKey(body.keyId as string), { ...stored, counter: body.counter as number });
      return { ok: true, deviceId: stored.deviceId };
    });

    return stateJson(result, result.ok ? 200 : 409);
  }

  private async scheduleChallengeSweep(expiresAt: string): Promise<void> {
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

export async function issueAppAttestChallenge(
  env: AppAttestEnv,
  subject?: string,
): Promise<{ challenge: string; expiresAt: string }> {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const challenge = encodeBase64(bytes);
  const expiresAt = new Date(Date.now() + CHALLENGE_TTL_SECONDS * 1000).toISOString();
  const record: ChallengeRecord = {
    ...(subject ? { subject } : {}),
    issuedAt: new Date().toISOString(),
    expiresAt,
  };
  await putChallengeRecord(env, challenge, record);
  return { challenge, expiresAt };
}

export async function verifyAndStoreAttestation(
  env: AppAttestEnv,
  input: { keyId: string; attestationObjectB64: string; challengeB64: string },
): Promise<{ attestedAt: string; environment: "production" | "development" }> {
  const attestationObject = decodeBase64(input.attestationObjectB64);
  const decoded = decodeAttestationObject(attestationObject);
  const authData = decoded.authData;
  const statement = decoded.attStmt;
  const x5c = cborArray(mapValue(statement, "x5c"), "x5c");
  if (x5c.length < 2) {
    throw new AppAttestValidationError("certificate_chain_missing");
  }

  const certificates = x5c.map((entry) => new X509Certificate(toArrayBuffer(cborBytes(entry, "x5c"))));
  const leaf = certificates[0];
  const intermediate = certificates[1];
  if (!leaf || !intermediate) {
    throw new AppAttestValidationError("certificate_chain_missing");
  }
  await verifyAppleCertificateChain(leaf, intermediate);

  const clientDataHash = await sha256(decodeBase64(input.challengeB64));
  const expectedNonce = await sha256(concatBytes(authData, clientDataHash));
  const certificateNonce = extractAppleAttestNonce(leaf);
  assertEqualBytes(certificateNonce, expectedNonce, "attestation_nonce_mismatch");

  const parsedAuth = parseAuthData(authData, true);
  const expectedRpIdHash = await sha256(new TextEncoder().encode(appId(env)));
  assertEqualBytes(parsedAuth.rpIdHash, expectedRpIdHash, "rp_id_hash_mismatch");

  const environment = appAttestEnvironment(parsedAuth.aaguid);
  const credentialId = parsedAuth.credentialId;
  if (!credentialId) {
    throw new AppAttestValidationError("credential_id_missing");
  }

  const keyIdBytes = decodeBase64(input.keyId);
  assertEqualBytes(credentialId, keyIdBytes, "credential_id_mismatch");

  const cryptoKey = await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" }, ["verify"]) as CryptoKey;
  const publicKeyRaw = new Uint8Array(await crypto.subtle.exportKey("raw", cryptoKey) as ArrayBuffer);
  const publicKeyHash = await sha256(publicKeyRaw);
  assertEqualBytes(publicKeyHash, keyIdBytes, "key_id_public_key_mismatch");

  const publicKeyJwk = await crypto.subtle.exportKey("jwk", cryptoKey) as JsonWebKey;
  const attestedAt = new Date().toISOString();
  const stored: AppAttestStoredKey = {
    deviceId: input.keyId,
    publicKeyJwk,
    counter: parsedAuth.counter,
    attestedAt,
    environment,
  };
  await finalizeAttestation(env, {
    keyId: input.keyId,
    challengeB64: input.challengeB64,
    stored,
  });

  return { attestedAt, environment };
}

export async function verifyAppAttestAssertion(
  env: AppAttestEnv,
  request: Request,
  requestBody: Uint8Array,
): Promise<AppAttestAuthSuccess | AppAttestAuthFailure> {
  const keyId = request.headers.get("X-VA-Attest-Key-ID")?.trim();
  const assertionB64 = request.headers.get("X-VA-Attest-Assertion")?.trim();
  const challengeB64 = request.headers.get("X-VA-Attest-Nonce")?.trim();

  const presentCount = [keyId, assertionB64, challengeB64].filter(Boolean).length;
  if (presentCount === 0) {
    return { ok: false, reason: "attestation_missing" };
  }
  if (!keyId || !assertionB64 || !challengeB64) {
    return { ok: false, reason: "attestation_incomplete" };
  }

  try {
    const stored = await loadStoredKey(env, keyId);
    if (!stored) {
      return { ok: false, reason: "key_not_attested" };
    }

    const assertion = decodeAssertionObject(decodeBase64(assertionB64));
    const parsedAuth = parseAuthData(assertion.authenticatorData, false);
    const expectedRpIdHash = await sha256(new TextEncoder().encode(appId(env)));
    assertEqualBytes(parsedAuth.rpIdHash, expectedRpIdHash, "rp_id_hash_mismatch");
    if (parsedAuth.counter <= stored.counter) {
      return { ok: false, reason: "counter_replay" };
    }

    const challengeBytes = decodeBase64(challengeB64);
    const clientDataHash = await sha256(concatBytes(requestBody, challengeBytes));
    const nonce = await sha256(concatBytes(assertion.authenticatorData, clientDataHash));
    const publicKey = await crypto.subtle.importKey(
      "jwk",
      stored.publicKeyJwk,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    const signature = derEcdsaSignatureToP1363(assertion.signature);
    const ok = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      signature,
      nonce,
    );
    if (!ok) {
      return { ok: false, reason: "signature_invalid" };
    }

    const finalized = await finalizeAssertionCounter(env, {
      keyId,
      challengeB64,
      counter: parsedAuth.counter,
    });
    if (!finalized.ok) {
      return finalized;
    }
    return { ok: true, deviceId: finalized.deviceId, keyId };
  } catch (error) {
    if (error instanceof AppAttestValidationError) {
      return { ok: false, reason: error.reason };
    }
    return { ok: false, reason: "attestation_invalid" };
  }
}

export class AppAttestValidationError extends Error {
  constructor(public readonly reason: string) {
    super(reason);
  }
}

function decodeAttestationObject(raw: Uint8Array): { authData: Uint8Array; attStmt: unknown } {
  const object = decodeCbor(raw);
  if (mapValue(object, "fmt") !== "apple-appattest") {
    throw new AppAttestValidationError("attestation_format_invalid");
  }
  const authData = cborBytes(mapValue(object, "authData"), "authData");
  const attStmt = mapValue(object, "attStmt");
  if (!attStmt) {
    throw new AppAttestValidationError("attestation_statement_missing");
  }
  return { authData, attStmt };
}

function decodeAssertionObject(raw: Uint8Array): { authenticatorData: Uint8Array; signature: Uint8Array } {
  const object = decodeCbor(raw);
  const authenticatorData = cborBytes(
    mapValue(object, "authenticatorData") ?? mapValue(object, "authData"),
    "authenticatorData",
  );
  const signature = cborBytes(mapValue(object, "signature"), "signature");
  return { authenticatorData, signature };
}

async function verifyAppleCertificateChain(leaf: X509Certificate, intermediate: X509Certificate): Promise<void> {
  const root = new X509Certificate(APP_ATTEST_ROOT_PEM);
  const rootDigest = await sha256(new Uint8Array(X509Certificate.toArrayBuffer(APP_ATTEST_ROOT_PEM)));
  if (hex(rootDigest) !== APP_ATTEST_ROOT_SHA256) {
    throw new AppAttestValidationError("apple_root_pin_mismatch");
  }
  const leafValid = await leaf.verify({ publicKey: intermediate, signatureOnly: true });
  if (!leafValid) {
    throw new AppAttestValidationError("leaf_signature_invalid");
  }
  const intermediateValid = await intermediate.verify({ publicKey: root, signatureOnly: true });
  if (!intermediateValid) {
    throw new AppAttestValidationError("intermediate_signature_invalid");
  }
  const now = Date.now();
  if (leaf.notBefore.getTime() > now || leaf.notAfter.getTime() < now) {
    throw new AppAttestValidationError("leaf_certificate_expired");
  }
  if (intermediate.notBefore.getTime() > now || intermediate.notAfter.getTime() < now) {
    throw new AppAttestValidationError("intermediate_certificate_expired");
  }
}

function extractAppleAttestNonce(certificate: X509Certificate): Uint8Array {
  const extension = certificate.getExtension(APP_ATTEST_EXTENSION_OID);
  if (!extension) {
    throw new AppAttestValidationError("attestation_extension_missing");
  }
  const bytes = new Uint8Array(extension.value);
  const sequence = readDerElement(bytes, 0, 0x30);
  const octet = readDerElement(sequence.value, 0, 0x04);
  return octet.value;
}

function parseAuthData(authData: Uint8Array, includesAttestedCredentialData: boolean): ParsedAuthData {
  if (authData.byteLength < 37) {
    throw new AppAttestValidationError("auth_data_too_short");
  }
  const rpIdHash = authData.slice(0, 32);
  const flags = authData[32] ?? 0;
  const counter =
    ((authData[33] ?? 0) << 24) |
    ((authData[34] ?? 0) << 16) |
    ((authData[35] ?? 0) << 8) |
    (authData[36] ?? 0);
  if (!includesAttestedCredentialData) {
    return { rpIdHash, flags, counter: counter >>> 0 };
  }
  if (authData.byteLength < 55) {
    throw new AppAttestValidationError("attested_credential_data_missing");
  }
  const aaguid = authData.slice(37, 53);
  const credentialLength = ((authData[53] ?? 0) << 8) | (authData[54] ?? 0);
  const credentialStart = 55;
  const credentialEnd = credentialStart + credentialLength;
  if (credentialLength <= 0 || authData.byteLength < credentialEnd) {
    throw new AppAttestValidationError("credential_id_invalid");
  }
  return {
    rpIdHash,
    flags,
    counter: counter >>> 0,
    aaguid,
    credentialId: authData.slice(credentialStart, credentialEnd),
  };
}

function appAttestEnvironment(aaguid: Uint8Array | undefined): "production" | "development" {
  if (!aaguid) {
    throw new AppAttestValidationError("aaguid_missing");
  }
  const production = concatBytes(new TextEncoder().encode("appattest"), new Uint8Array(7));
  const development = new TextEncoder().encode("appattestdevelop");
  if (bytesEqual(aaguid, production)) {
    return "production";
  }
  if (bytesEqual(aaguid, development)) {
    return "development";
  }
  throw new AppAttestValidationError("aaguid_mismatch");
}

function appId(env: AppAttestEnv): string {
  if (env.APPLE_APP_ID?.trim()) {
    return env.APPLE_APP_ID.trim();
  }
  const team = env.APPLE_TEAM_ID?.trim();
  const bundle = env.APPLE_BUNDLE_ID?.trim();
  if (!team || !bundle) {
    throw new AppAttestValidationError("app_id_unconfigured");
  }
  return `${team}.${bundle}`;
}

async function putChallengeRecord(env: AppAttestEnv, challenge: string, record: ChallengeRecord): Promise<void> {
  if (env.APP_ATTEST_STATE) {
    const response = await appAttestStateRequest<AppAttestStateResult>(env, "/challenge", {
      challenge,
      record,
    });
    if (!response.ok) {
      throw new AppAttestValidationError(response.reason);
    }
    return;
  }

  await challengeKV(env).put(challengeKey(challenge), JSON.stringify(record), {
    expirationTtl: CHALLENGE_TTL_SECONDS,
  });
}

async function loadStoredKey(env: AppAttestEnv, keyId: string): Promise<AppAttestStoredKey | null> {
  if (env.APP_ATTEST_STATE) {
    const response = await appAttestStateRequest<AppAttestStateKeyResult>(env, "/key", { keyId });
    if (!response.ok) {
      throw new AppAttestValidationError(response.reason);
    }
    return response.stored;
  }

  const rawStored = await keysKV(env).get(storedKey(keyId));
  return rawStored ? JSON.parse(rawStored) as AppAttestStoredKey : null;
}

async function finalizeAttestation(
  env: AppAttestEnv,
  input: { keyId: string; challengeB64: string; stored: AppAttestStoredKey },
): Promise<void> {
  if (env.APP_ATTEST_STATE) {
    const response = await appAttestStateRequest<AppAttestStateResult>(env, "/attestation", input);
    if (!response.ok) {
      throw new AppAttestValidationError(response.reason);
    }
    return;
  }

  const challenge = await consumeChallenge(env, input.challengeB64);
  if (challenge.subject && challenge.subject !== input.stored.deviceId) {
    throw new AppAttestValidationError("challenge_device_mismatch");
  }
  await keysKV(env).put(storedKey(input.keyId), JSON.stringify(input.stored));
}

async function finalizeAssertionCounter(
  env: AppAttestEnv,
  input: { keyId: string; challengeB64: string; counter: number },
): Promise<AppAttestStateAssertionResult> {
  if (env.APP_ATTEST_STATE) {
    return await appAttestStateRequest<AppAttestStateAssertionResult>(env, "/assertion", input);
  }

  const stored = await loadStoredKey(env, input.keyId);
  if (!stored) {
    return { ok: false, reason: "key_not_attested" };
  }

  const challenge = await consumeChallenge(env, input.challengeB64);
  if (challenge.subject && challenge.subject !== stored.deviceId) {
    return { ok: false, reason: "challenge_device_mismatch" };
  }
  if (input.counter <= stored.counter) {
    return { ok: false, reason: "counter_replay" };
  }

  try {
    await keysKV(env).put(
      storedKey(input.keyId),
      JSON.stringify({ ...stored, counter: input.counter }),
    );
  } catch {
    console.warn(JSON.stringify({
      category: "relay.auth",
      name: "app_attest_counter_update_failed",
      keyId: input.keyId,
      timestamp: new Date().toISOString(),
    }));
  }
  return { ok: true, deviceId: stored.deviceId };
}

async function appAttestStateRequest<T extends AppAttestStateResult>(
  env: AppAttestEnv,
  path: string,
  payload: unknown,
): Promise<T> {
  const namespace = env.APP_ATTEST_STATE;
  if (!namespace) {
    throw new AppAttestValidationError("app_attest_state_missing");
  }
  const stub = namespace.get(namespace.idFromName("volumearc-app-attest-v1"));
  const response = await stub.fetch(new Request(`https://app-attest-state.local${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  }));
  const body = await response.json().catch(() => null) as T | null;
  if (!body || (!response.ok && !("reason" in body))) {
    throw new AppAttestValidationError("app_attest_state_unavailable");
  }
  return body;
}

async function consumeChallenge(env: AppAttestEnv, challengeB64: string): Promise<ChallengeRecord> {
  const key = challengeKey(challengeB64);
  const raw = await challengeKV(env).get(key);
  if (!raw) {
    throw new AppAttestValidationError("challenge_not_found");
  }
  await challengeKV(env).delete(key);
  const record = JSON.parse(raw) as ChallengeRecord;
  if (Date.parse(record.expiresAt) <= Date.now()) {
    throw new AppAttestValidationError("challenge_expired");
  }
  return record;
}

function keysKV(env: AppAttestEnv): KVNamespace {
  return env.ATTEST_KEYS ?? env.RATE_LIMIT;
}

function challengeKV(env: AppAttestEnv): KVNamespace {
  return env.ATTEST_CHALLENGES ?? env.RATE_LIMIT;
}

function storedKey(keyId: string): string {
  return `attest:key:${keyId}`;
}

function challengeKey(challenge: string): string {
  return `attest:challenge:${challenge}`;
}

function challengeFailure(record: ChallengeRecord | undefined, expectedDeviceId: string): string | null {
  if (!record) {
    return "challenge_not_found";
  }
  if (record.subject && record.subject !== expectedDeviceId) {
    return "challenge_device_mismatch";
  }
  const expiry = Date.parse(record.expiresAt);
  if (!Number.isFinite(expiry) || expiry <= Date.now()) {
    return "challenge_expired";
  }
  return null;
}

function isChallengeRecord(value: unknown): value is ChallengeRecord {
  if (!value || typeof value !== "object") {
    return false;
  }
  const record = value as Record<string, unknown>;
  return (record.subject === undefined || typeof record.subject === "string") &&
    typeof record.issuedAt === "string" &&
    typeof record.expiresAt === "string";
}

function isStoredKey(value: unknown): value is AppAttestStoredKey {
  if (!value || typeof value !== "object") {
    return false;
  }
  const record = value as Record<string, unknown>;
  return typeof record.deviceId === "string" &&
    typeof record.publicKeyJwk === "object" &&
    record.publicKeyJwk !== null &&
    typeof record.counter === "number" &&
    typeof record.attestedAt === "string" &&
    (record.environment === "production" || record.environment === "development");
}

function stateJson(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function mapValue(value: unknown, key: string): unknown {
  if (value instanceof Map) {
    return value.get(key);
  }
  if (value && typeof value === "object" && key in value) {
    return (value as Record<string, unknown>)[key];
  }
  return undefined;
}

function cborArray(value: unknown, label: string): unknown[] {
  if (!Array.isArray(value)) {
    throw new AppAttestValidationError(`${label}_invalid`);
  }
  return value;
}

function cborBytes(value: unknown, label: string): Uint8Array {
  if (value instanceof Uint8Array) {
    return value;
  }
  if (value instanceof ArrayBuffer) {
    return new Uint8Array(value);
  }
  throw new AppAttestValidationError(`${label}_invalid`);
}

function readDerElement(bytes: Uint8Array, offset: number, expectedTag: number): { value: Uint8Array; next: number } {
  if (bytes[offset] !== expectedTag) {
    throw new AppAttestValidationError("der_tag_mismatch");
  }
  const lengthInfo = readDerLength(bytes, offset + 1);
  const start = lengthInfo.next;
  const end = start + lengthInfo.length;
  if (end > bytes.byteLength) {
    throw new AppAttestValidationError("der_length_invalid");
  }
  return { value: bytes.slice(start, end), next: end };
}

function readDerLength(bytes: Uint8Array, offset: number): { length: number; next: number } {
  const first = bytes[offset];
  if (first === undefined) {
    throw new AppAttestValidationError("der_length_missing");
  }
  if ((first & 0x80) === 0) {
    return { length: first, next: offset + 1 };
  }
  const byteCount = first & 0x7f;
  if (byteCount === 0 || byteCount > 4 || offset + byteCount >= bytes.byteLength) {
    throw new AppAttestValidationError("der_length_invalid");
  }
  let length = 0;
  for (let index = 0; index < byteCount; index += 1) {
    length = (length << 8) | (bytes[offset + 1 + index] ?? 0);
  }
  return { length, next: offset + 1 + byteCount };
}

function derEcdsaSignatureToP1363(signature: Uint8Array): Uint8Array {
  const sequence = readDerElement(signature, 0, 0x30);
  if (sequence.next !== signature.byteLength) {
    throw new AppAttestValidationError("signature_der_trailing_bytes");
  }
  const r = readDerElement(sequence.value, 0, 0x02);
  const s = readDerElement(sequence.value, r.next, 0x02);
  if (s.next !== sequence.value.byteLength) {
    throw new AppAttestValidationError("signature_der_invalid");
  }
  return concatBytes(leftPadInteger(r.value, 32), leftPadInteger(s.value, 32));
}

function leftPadInteger(value: Uint8Array, length: number): Uint8Array {
  let normalized = value;
  while (normalized.byteLength > length && normalized[0] === 0x00) {
    normalized = normalized.slice(1);
  }
  if (normalized.byteLength > length) {
    throw new AppAttestValidationError("signature_integer_too_large");
  }
  const padded = new Uint8Array(length);
  padded.set(normalized, length - normalized.byteLength);
  return padded;
}

function decodeBase64(value: string): Uint8Array {
  const normalized = value.trim().replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    throw new AppAttestValidationError("base64_invalid");
  }
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let index = 0; index < bytes.byteLength; index += 1) {
    binary += String.fromCharCode(bytes[index] ?? 0);
  }
  return btoa(binary);
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

function assertEqualBytes(actual: Uint8Array, expected: Uint8Array, reason: string): void {
  if (!bytesEqual(actual, expected)) {
    throw new AppAttestValidationError(reason);
  }
}

function bytesEqual(lhs: Uint8Array, rhs: Uint8Array): boolean {
  if (lhs.byteLength !== rhs.byteLength) {
    return false;
  }
  let diff = 0;
  for (let index = 0; index < lhs.byteLength; index += 1) {
    diff |= (lhs[index] ?? 0) ^ (rhs[index] ?? 0);
  }
  return diff === 0;
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes);
  return copy.buffer as ArrayBuffer;
}
