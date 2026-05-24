#!/usr/bin/env bash
# VOL-100 / VOL-147 response-layer coach eval placeholder.
#
# VOL-226 retired the shared client HMAC relay credential. The production
# relay now requires real App Attest assertions, which a generic shell runner
# cannot mint. Until the eval harness grows a real-device/App-Attest signer,
# this script records an explicit skipped result instead of sending requests
# through a retired auth path.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${VOLUMEARC_EVAL_OUTPUT_DIR:-$ROOT/.build/coach-evals/$(date -u +%Y%m%dT%H%M%SZ)}"

mkdir -p "$OUTPUT_DIR"

cat > "$OUTPUT_DIR/summary.json" <<'JSON'
{
  "total": 0,
  "passed": 0,
  "failed": 0,
  "status": "skipped",
  "reason": "VOL-226 retired the client HMAC path. Live response-layer coach evals now need a real-device App Attest signer before they can hit the production relay."
}
JSON

cat > "$OUTPUT_DIR/README.txt" <<'TEXT'
Coach response-layer evals skipped.

VOL-226 moved the relay to App Attest-only auth. The former shell harness used
the retired client HMAC credential and can no longer authenticate to the live
relay. Template-layer CoachEvalTests still run in the app test suite; live
response-layer evals need a follow-up real-device App Attest signer.
TEXT

echo "Coach response-layer evals skipped: App Attest-only relay requires a real-device signer."
