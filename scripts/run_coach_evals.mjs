#!/usr/bin/env node

import { webcrypto } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const fixturesDir = path.join(root, "Tests", "Evals", "CoachEvalFixtures");
const relayBaseUrl = process.env.VOLUMEARC_RELAY_BASE_URL ?? "https://relay.volumearc.app";
const outputDir = process.env.VOLUMEARC_EVAL_OUTPUT_DIR ??
  path.join(root, ".build", "coach-evals", new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z"));
const brokerToken = process.env.VOLUMEARC_EVAL_ATTEST_BROKER_TOKEN ?? "";
const deviceIdBase = process.env.VOLUMEARC_EVAL_DEVICE_ID ?? "coach-eval-harness";
const httpTimeoutMs = positiveInt(process.env.VOLUMEARC_EVAL_HTTP_TIMEOUT_MS, 60_000);

const encoder = new TextEncoder();
const subtle = webcrypto.subtle;

async function main() {
  await preflight();
  await fs.mkdir(outputDir, { recursive: true });

  const fixtureFiles = (await fs.readdir(fixturesDir))
    .filter((name) => name.endsWith(".json"))
    .sort()
    .map((name) => path.join(fixturesDir, name));
  if (fixtureFiles.length === 0) {
    throw configError(`no fixture files found under ${fixturesDir}`);
  }

  const attester = new EvalBrokerAttester(relayBaseUrl, brokerToken, deviceIdBase);
  await attester.bootstrap();

  console.log(`Running ${fixtureFiles.length} coach eval fixture(s) against ${relayBaseUrl}`);
  console.log("Auth mode: staging eval attestation broker");
  console.log(`Output dir: ${outputDir}\n`);

  const rows = [];
  let passed = 0;
  let failed = 0;

  for (const fixturePath of fixtureFiles) {
    const fixtureName = path.basename(fixturePath, ".json");
    const fixture = JSON.parse(await fs.readFile(fixturePath, "utf8"));
    const result = await runFixture(fixture, fixtureName, attester);
    rows.push(result);
    if (result.verdict === "PASS") {
      passed += 1;
    } else {
      failed += 1;
    }
  }

  printSummary(rows, passed, failed);
  await writeSummary(rows, passed, failed);

  if (failed > 0) {
    process.exitCode = 1;
  }
}

async function preflight() {
  if (typeof fetch !== "function") {
    throw configError("global fetch is unavailable; use Node 20+ for coach evals");
  }
  await fs.access(fixturesDir).catch(() => {
    throw configError(`fixture directory not found: ${fixturesDir}`);
  });
  if (!brokerToken.trim()) {
    throw configError("VOLUMEARC_EVAL_ATTEST_BROKER_TOKEN is not set");
  }
  const url = new URL(relayBaseUrl);
  if (url.hostname.toLowerCase() === "relay.volumearc.app") {
    throw configError(
      "VOLUMEARC_RELAY_BASE_URL points at production. The eval attestation broker is staging-only; set VOLUMEARC_RELAY_BASE_URL to the staging relay.",
    );
  }
}

async function runFixture(fixture, fixtureName, attester) {
  const fixtureId = fixture.id ?? fixtureName;
  const bodyObject = {
    intent: fixture.intent,
    question: fixture.question,
    contextBlock: fixture.contextBlock,
    style: fixture.style,
    prompt: "",
    system: "",
  };
  const body = JSON.stringify(bodyObject);
  const responsePath = path.join(outputDir, `${fixtureName}.response.txt`);
  const streamPath = path.join(outputDir, `${fixtureName}.stream`);
  const statusPath = path.join(outputDir, `${fixtureName}.status`);

  let httpStatus = "000";
  let rawStream = "";
  try {
    const authHeaders = await attester.headersFor(body);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), httpTimeoutMs);
    const response = await fetch(`${relayBaseUrl.replace(/\/$/, "")}/v1/coach`, {
      method: "POST",
      headers: {
        "Accept": "text/event-stream",
        "Content-Type": "application/json",
        "X-Coach-Tier": "flash-lite",
        ...authHeaders,
      },
      body,
      signal: controller.signal,
    });
    clearTimeout(timeout);
    httpStatus = String(response.status);
    rawStream = await response.text();
  } catch (error) {
    rawStream = error instanceof Error ? error.message : String(error);
  }

  await fs.writeFile(statusPath, httpStatus);
  await fs.writeFile(streamPath, rawStream);

  const readiness = readinessScore(fixture.contextBlock);
  if (httpStatus !== "200") {
    console.log(`  FAIL  ${fixtureId} (HTTP ${httpStatus})`);
    return row(fixture, readiness, "FAIL", `HTTP ${httpStatus}`);
  }

  const responseText = extractSSEText(rawStream).replace(/\r/g, "").replace(/ {2,}/g, " ").trim();
  await fs.writeFile(responsePath, `${responseText}\n`);
  if (!responseText) {
    console.log(`  FAIL  ${fixtureId} (empty response)`);
    return row(fixture, readiness, "FAIL", "empty response");
  }

  const failures = runAssertions(fixture, responseText);
  if (failures.length === 0) {
    console.log(`  PASS  ${fixtureId}`);
    return row(fixture, readiness, "PASS", "-");
  }

  console.log(`  FAIL  ${fixtureId}`);
  for (const failure of failures) {
    console.log(`        - ${failure}`);
  }
  return row(fixture, readiness, "FAIL", failures.join("; "));
}

class EvalBrokerAttester {
  constructor(baseUrl, token, deviceId) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.token = token;
    this.deviceId = deviceId;
    this.counter = 0;
  }

  async bootstrap() {
    const keyPair = await subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign", "verify"],
    );
    const publicKeyRaw = new Uint8Array(await subtle.exportKey("raw", keyPair.publicKey));
    const publicKeyJwk = await subtle.exportKey("jwk", keyPair.publicKey);
    this.privateKey = keyPair.privateKey;
    this.keyId = base64(await sha256(publicKeyRaw));

    const response = await this.brokerFetch("/v1/eval-attest/bootstrap", {
      keyId: this.keyId,
      publicKeyJwk,
      runner: this.deviceId,
    });
    if (!response.ok) {
      throw configError(`eval broker bootstrap failed: HTTP ${response.status} ${await response.text()}`);
    }
  }

  async headersFor(body) {
    this.counter += 1;
    const challengeResponse = await this.brokerFetch("/v1/eval-attest/challenge", {
      keyId: this.keyId,
    });
    if (!challengeResponse.ok) {
      throw configError(`eval broker challenge failed: HTTP ${challengeResponse.status} ${await challengeResponse.text()}`);
    }
    const { challenge } = await challengeResponse.json();
    if (typeof challenge !== "string" || !challenge) {
      throw configError("eval broker challenge response missing challenge");
    }
    const signature = new Uint8Array(await subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      this.privateKey,
      evalSigningPayload(encoder.encode(body), challenge, this.counter),
    ));
    return {
      "X-VA-Eval-Attest-Key-ID": this.keyId,
      "X-VA-Eval-Attest-Assertion": base64(signature),
      "X-VA-Eval-Attest-Nonce": challenge,
      "X-VA-Eval-Attest-Counter": String(this.counter),
    };
  }

  async brokerFetch(endpoint, payload) {
    return await fetch(`${this.baseUrl}${endpoint}`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${this.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
  }
}

function runAssertions(fixture, response) {
  const assertions = fixture.expectedAssertions ?? {};
  const failures = [];
  const responseLower = normalizeLower(response);

  if (Number.isSafeInteger(assertions.maxSentences)) {
    const actual = countSentences(response);
    if (actual > assertions.maxSentences + 1) {
      failures.push(`maxSentences=${assertions.maxSentences} violated (got ${actual})`);
    }
  }

  if (assertions.mustContainNumericContext === true && !/[0-9]/.test(response)) {
    failures.push("mustContainNumericContext: no digit found in response");
  }

  if (
    assertions.mustMentionReadinessOrRPE === true &&
    !/(readiness|rpe|recover|fatigue)/i.test(response)
  ) {
    failures.push("mustMentionReadinessOrRPE: response lacks readiness/rpe/recover/fatigue reference");
  }

  for (const banned of assertions.mustNotMention ?? []) {
    const bannedLower = normalizeLower(String(banned));
    if (bannedLower && responseLower.includes(bannedLower)) {
      failures.push(`mustNotMention: found banned phrase '${banned}'`);
    }
  }

  if (Number.isSafeInteger(assertions.maxEnumeratedPlanDays)) {
    const actual = enumeratedPlanDayCount(response);
    if (actual > assertions.maxEnumeratedPlanDays) {
      failures.push(`maxEnumeratedPlanDays=${assertions.maxEnumeratedPlanDays} violated (got ${actual})`);
    }
  }

  if (assertions.mustAnchorOnNextExercise === true) {
    const next = nextExercise(fixture.contextBlock);
    if (next) {
      const primary = normalizeLower(next).split(" ").filter(Boolean).at(-1);
      if (primary && !responseLower.includes(primary)) {
        failures.push(`mustAnchorOnNextExercise: response does not reference primary movement '${primary}'`);
      }
    }
  }

  if (
    assertions.mustFlagPainSignal === true &&
    !/(pain|injur|see (a |your )?(doctor|physio)|ease off|skip|back off|flag)/i.test(response)
  ) {
    failures.push("mustFlagPainSignal: response does not acknowledge pain/injury guardrail");
  }

  return failures;
}

function extractSSEText(raw) {
  const chunks = [];
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) {
      continue;
    }
    const payload = trimmed.slice(5).trim();
    if (!payload || payload === "[DONE]" || payload === "{}") {
      continue;
    }
    try {
      const decoded = JSON.parse(payload);
      if (typeof decoded.text === "string") {
        chunks.push(decoded.text);
      }
    } catch {
      // Skip malformed keepalive frames.
    }
  }
  return chunks.join("");
}

function countSentences(text) {
  let count = 0;
  let segmentHasText = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const prev = index > 0 ? text[index - 1] : "";
    const next = index < text.length - 1 ? text[index + 1] : "";
    if (char && !/\s/.test(char)) {
      segmentHasText = true;
    }
    if (/[.!?]/.test(char) && !(char === "." && /[0-9]/.test(prev) && /[0-9]/.test(next))) {
      if (segmentHasText) {
        count += 1;
        segmentHasText = false;
      }
    }
  }
  return count + (segmentHasText ? 1 : 0);
}

function enumeratedPlanDayCount(text) {
  const lower = String(text ?? "").toLowerCase();
  const weekdayTokens = lower.match(/\b(mon(day)?|tue(sday)?|wed(nesday)?|thu(rsday)?|fri(day)?|sat(urday)?|sun(day)?)\b/g) ?? [];
  const uniqueWeekdays = new Set(weekdayTokens.map((token) => token.slice(0, 3)));
  let maxDayNumber = 0;
  const numericDayPatterns = [
    /(?:^|\n)\s*(?:[-*]\s*)?day\s*([1-9][0-9]?)(?=\s*[:.)-]|\s*$)/gm,
    /\bon\s+day\s*([1-9][0-9]?)(?=\s*[:.)-]|\s*$)/g,
    /\b([1-9][0-9]?)(?:st|nd|rd|th)\s+day\b/g,
  ];
  for (const pattern of numericDayPatterns) {
    for (const match of lower.matchAll(pattern)) {
      maxDayNumber = Math.max(maxDayNumber, Number.parseInt(match[1], 10));
    }
  }
  return Math.max(uniqueWeekdays.size, maxDayNumber);
}

function readinessScore(contextBlock) {
  const match = String(contextBlock ?? "").match(/^- Readiness:\s*([0-9]+)\/100/m);
  return match ? Number.parseInt(match[1], 10) : null;
}

function nextExercise(contextBlock) {
  const match = String(contextBlock ?? "").match(/^- Next up: (.+) at \S+$/m);
  return match ? match[1] : "";
}

function row(fixture, readiness, verdict, note) {
  return {
    id: fixture.id ?? "unknown",
    verdict,
    note,
    intent: fixture.intent ?? "unknown",
    style: fixture.style ?? "unknown",
    readiness,
  };
}

function printSummary(rows, passed, failed) {
  console.log("\n--- summary ---");
  console.log(`${"fixture".padEnd(60)}  pass  note`);
  console.log("-".repeat(100));
  for (const item of rows) {
    console.log(`${item.id.padEnd(60)}  ${item.verdict.padEnd(4)}  ${item.note}`);
  }
  console.log(`\n${passed} passed, ${failed} failed, ${rows.length} total`);
  console.log(`Per-fixture responses saved under: ${outputDir}`);
  console.log(`Summary JSON: ${path.join(outputDir, "summary.json")}`);
}

async function writeSummary(rows, passed, failed) {
  const summary = {
    timestamp: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    relay: relayBaseUrl,
    authMode: "eval_attest_broker",
    total: rows.length,
    passed,
    failed,
    fixtures: rows,
  };
  await fs.writeFile(path.join(outputDir, "summary.json"), `${JSON.stringify(summary, null, 2)}\n`);
}

function evalSigningPayload(requestBody, challenge, counter) {
  if (!Number.isSafeInteger(counter) || counter < 1 || counter > 0xffffffff) {
    throw configError("eval broker counter must be a uint32");
  }
  const counterBytes = new Uint8Array(4);
  new DataView(counterBytes.buffer).setUint32(0, counter, false);
  return concatBytes(requestBody, decodeBase64(challenge), counterBytes);
}

async function sha256(data) {
  return new Uint8Array(await subtle.digest("SHA-256", data));
}

function base64(bytes) {
  return Buffer.from(bytes).toString("base64");
}

function decodeBase64(value) {
  return new Uint8Array(Buffer.from(value, "base64"));
}

function concatBytes(...chunks) {
  const length = chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0);
  const result = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

function normalizeLower(value) {
  return String(value).toLowerCase().replace(/\s+/g, " ").trim();
}

function positiveInt(value, fallback) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function configError(message) {
  const error = new Error(`run_coach_evals: ${message}`);
  error.exitCode = 2;
  return error;
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(error?.exitCode ?? 1);
});
