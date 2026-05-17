#!/usr/bin/env bash
# VOL-100: coach prompt eval harness — response-quality layer.
#
# Reads each fixture under `Tests/Evals/CoachEvalFixtures/*.json`, POSTs it to
# the live relay with the same `Bearer <deviceID>.<hmac>` signature the iOS
# app uses, and asserts the JSON `expectedAssertions` against the streamed
# response text.
#
# Intentionally NOT wired into `scripts/test_apple_targets.sh` — this burns
# Gemini API budget and is model-dependent. Target audience: nightly CI
# workflow (follow-up ticket) + on-demand local sanity checks.
#
# Requires:
#   - `VOLUMEARC_RELAY_SIGNING_KEY`  HMAC signing key (same value the iOS
#                                    app reads from env or Info.plist).
#   - `VOLUMEARC_EVAL_DEVICE_ID`     stable device ID to sign with. Defaults
#                                    to `coach-eval-harness` so the relay's
#                                    device-ID → principal mapping stays
#                                    consistent across runs.
#   - `VOLUMEARC_RELAY_BASE_URL`     override the relay endpoint (default:
#                                    `https://volumearc-ai-relay.jared-b6b.workers.dev`).
#   - `curl`, `jq`, `openssl`        standard on macOS and Linux runners.
#
# Exit codes:
#   0  all fixtures passed.
#   1  one or more fixtures failed response-quality assertions.
#   2  missing dependency / unconfigured env.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_DIR="$ROOT/Tests/Evals/CoachEvalFixtures"
RELAY_BASE_URL="${VOLUMEARC_RELAY_BASE_URL:-https://volumearc-ai-relay.jared-b6b.workers.dev}"
DEVICE_ID="${VOLUMEARC_EVAL_DEVICE_ID:-coach-eval-harness}"
OUTPUT_DIR="${VOLUMEARC_EVAL_OUTPUT_DIR:-$ROOT/.build/coach-evals/$(date -u +%Y%m%dT%H%M%SZ)}"

# --- preflight ---------------------------------------------------------------

die() {
    printf '\nrun_coach_evals: %s\n' "$*" >&2
    exit "${2:-2}"
}

command -v curl >/dev/null 2>&1 || die "curl not found on PATH"
command -v jq >/dev/null 2>&1 || die "jq not found on PATH (brew install jq)"
command -v openssl >/dev/null 2>&1 || die "openssl not found on PATH"

if [[ ! -d "$FIXTURES_DIR" ]]; then
    die "fixture directory not found: $FIXTURES_DIR"
fi

if [[ -z "${VOLUMEARC_RELAY_SIGNING_KEY:-}" ]]; then
    die "VOLUMEARC_RELAY_SIGNING_KEY is not set — same value the iOS app reads"
fi

mkdir -p "$OUTPUT_DIR"

# --- auth helpers ------------------------------------------------------------

# HMAC-SHA256 hex of DEVICE_ID keyed with the signing key, matching
# `VolumeArcRelaySessionProvider.hmacHex` on iOS.
compute_signature() {
    local device="$1"
    local key="$2"
    printf '%s' "$device" | openssl dgst -sha256 -hmac "$key" -binary | xxd -p -c 256
}

# --- response-quality assertion engine --------------------------------------

normalize_lower() {
    # Lowercase + strip excess whitespace for substring checks.
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' '
}

count_sentences() {
    # Approximate sentence count. Splits on ., !, ? followed by space or EOL.
    # Filters empty fragments. Good enough for a hard upper bound.
    local text="$1"
    printf '%s' "$text" \
        | tr -d '\r' \
        | awk 'BEGIN { RS="[.!?]+"; n=0 }
               { gsub(/^[ \t\n]+|[ \t\n]+$/, ""); if (length($0) > 0) n++ }
               END { print n }'
}

# Run every expectedAssertion against the response text.
# Prints a summary + returns 0 (pass) / 1 (fail).
run_assertions() {
    local fixture_id="$1"
    local assertions_json="$2"
    local response="$3"
    local failures=()
    local response_lc
    response_lc=$(normalize_lower "$response")

    # maxSentences — hard upper bound.
    local max_sentences
    max_sentences=$(printf '%s' "$assertions_json" | jq -r '.maxSentences // empty')
    if [[ -n "$max_sentences" ]]; then
        local actual
        actual=$(count_sentences "$response")
        # Allow a +1 grace to avoid tokenizer-edge false positives; the
        # template already caps at 3 via the system prompt.
        if (( actual > max_sentences + 1 )); then
            failures+=("maxSentences=$max_sentences violated (got $actual)")
        fi
    fi

    # mustContainNumericContext — response mentions at least one number.
    local must_numeric
    must_numeric=$(printf '%s' "$assertions_json" | jq -r '.mustContainNumericContext // false')
    if [[ "$must_numeric" == "true" ]]; then
        if ! printf '%s' "$response" | grep -Eq '[0-9]'; then
            failures+=("mustContainNumericContext: no digit found in response")
        fi
    fi

    # mustMentionReadinessOrRPE — cite at least one of the grounded signals.
    local must_mention_readiness
    must_mention_readiness=$(printf '%s' "$assertions_json" | jq -r '.mustMentionReadinessOrRPE // false')
    if [[ "$must_mention_readiness" == "true" ]]; then
        if ! grep -Eiq 'readiness|rpe|recover|fatigue' <<<"$response"; then
            failures+=("mustMentionReadinessOrRPE: response lacks readiness/rpe/recover/fatigue reference")
        fi
    fi

    # mustNotMention — banned phrases.
    while IFS= read -r banned; do
        [[ -z "$banned" ]] && continue
        local banned_lc
        banned_lc=$(normalize_lower "$banned")
        if [[ "$response_lc" == *"$banned_lc"* ]]; then
            failures+=("mustNotMention: found banned phrase '$banned'")
        fi
    done < <(printf '%s' "$assertions_json" | jq -r '.mustNotMention // [] | .[]')

    # mustAnchorOnNextExercise — response must reference the lift or a plausible
    # substitute by name. We look for the Next-up exercise name from the
    # fixture context, pulled out by the caller.
    local must_anchor_next
    must_anchor_next=$(printf '%s' "$assertions_json" | jq -r '.mustAnchorOnNextExercise // false')
    if [[ "$must_anchor_next" == "true" ]]; then
        # Caller passes the next-exercise hint via FIXTURE_NEXT_EXERCISE.
        if [[ -n "${FIXTURE_NEXT_EXERCISE:-}" ]]; then
            local hint_lc
            hint_lc=$(normalize_lower "$FIXTURE_NEXT_EXERCISE")
            # Token fragment — use the primary noun ("squat", "bench", etc.).
            # We assume "<adj> <noun>" or just a noun and take the last word.
            local primary
            primary=$(printf '%s' "$hint_lc" | awk '{ print $NF }')
            if [[ "$response_lc" != *"$primary"* ]]; then
                failures+=("mustAnchorOnNextExercise: response does not reference primary movement '$primary'")
            fi
        fi
    fi

    # mustFlagPainSignal — the response must not blithely recommend loading
    # through the pain signal. We look for at least one of the expected
    # hedging/flagging words.
    local must_flag_pain
    must_flag_pain=$(printf '%s' "$assertions_json" | jq -r '.mustFlagPainSignal // false')
    if [[ "$must_flag_pain" == "true" ]]; then
        if ! grep -Eiq 'pain|injur|see (a |your )?(doctor|physio)|ease off|skip|back off|flag' <<<"$response"; then
            failures+=("mustFlagPainSignal: response does not acknowledge pain/injury guardrail")
        fi
    fi

    if [[ ${#failures[@]} -eq 0 ]]; then
        printf '  PASS  %s\n' "$fixture_id"
        return 0
    fi
    printf '  FAIL  %s\n' "$fixture_id"
    for f in "${failures[@]}"; do
        printf '        - %s\n' "$f"
    done
    return 1
}

# --- main loop ---------------------------------------------------------------

fixture_files=()
while IFS= read -r path; do
    fixture_files+=("$path")
done < <(find "$FIXTURES_DIR" -type f -name '*.json' | sort)

total=${#fixture_files[@]}
if (( total == 0 )); then
    die "no fixture files found under $FIXTURES_DIR"
fi

signature=$(compute_signature "$DEVICE_ID" "$VOLUMEARC_RELAY_SIGNING_KEY")
auth_header="Authorization: Bearer ${DEVICE_ID}.${signature}"

printf 'Running %d coach eval fixture(s) against %s\n' "$total" "$RELAY_BASE_URL"
printf 'Device ID: %s  (signature %s...)\n' "$DEVICE_ID" "${signature:0:12}"
printf 'Output dir: %s\n\n' "$OUTPUT_DIR"

passed=0
failed=0
summary_rows=()

for fixture_path in "${fixture_files[@]}"; do
    fixture_name=$(basename "$fixture_path" .json)
    fixture_id=$(jq -r '.id' "$fixture_path")
    intent=$(jq -r '.intent' "$fixture_path")
    question=$(jq -r '.question' "$fixture_path")
    context_block=$(jq -r '.contextBlock' "$fixture_path")
    style=$(jq -r '.style' "$fixture_path")
    expected=$(jq -c '.expectedAssertions' "$fixture_path")

    # Pull the next-exercise hint out of the contextBlock for the anchor check.
    # VOL-183: the original `([^ ]+( [^ ]+)*?) at .*$` regex used `*?`
    # (lazy quantifier), which isn't valid POSIX ERE — BSD sed on macOS
    # errors with `RE error: repetition-operator operand invalid` even
    # with `-E`. The lazy form was needed when `at` could appear inside
    # exercise names, but our exercise catalog doesn't have that shape;
    # a greedy `(.+) at [^ ]+$` capture works because `[^ ]+$` anchors
    # the trailing token (e.g., `225x5`) so the `at` consumed by the
    # match has to be the last one on the line.
    FIXTURE_NEXT_EXERCISE=""
    if grep -q '^- Next up:' <<<"$context_block"; then
        FIXTURE_NEXT_EXERCISE=$(grep '^- Next up:' <<<"$context_block" \
            | sed -E 's/^- Next up: (.+) at [^ ]+$/\1/' \
            | head -n 1)
    fi
    export FIXTURE_NEXT_EXERCISE

    # Render the prompt payload the relay expects.
    body=$(jq -n \
        --arg intent "$intent" \
        --arg question "$question" \
        --arg contextBlock "$context_block" \
        --arg style "$style" \
        --arg prompt "" \
        --arg system "" \
        '{intent: $intent, question: $question, contextBlock: $contextBlock, style: $style, prompt: $prompt, system: $system}')
    # We let the relay re-render via its own template (the Worker is the
    # source of truth for the Gemini request). Sending `prompt: ""` matches
    # older iOS clients that did the same; newer clients pre-render. The
    # eval harness intentionally leaves rendering to the server so a
    # regression in the Worker's template is caught here.

    response_path="$OUTPUT_DIR/${fixture_name}.response.txt"
    http_status_path="$OUTPUT_DIR/${fixture_name}.status"

    # `--no-buffer` + `-N` so we consume the SSE stream progressively and
    # don't time out on slow models. We capture the full stream to a file
    # and post-process to extract `data: {"text": "..."}` frames.
    raw_stream_path="$OUTPUT_DIR/${fixture_name}.stream"
    http_code=$(curl -sS -N --no-buffer \
        -o "$raw_stream_path" \
        -w '%{http_code}' \
        -H "$auth_header" \
        -H 'Content-Type: application/json' \
        -H 'Accept: text/event-stream' \
        -H 'X-Coach-Tier: flash-lite' \
        --data "$body" \
        --max-time 60 \
        "${RELAY_BASE_URL%/}/v1/coach" \
        || echo "000")
    printf '%s' "$http_code" > "$http_status_path"

    if [[ "$http_code" != "200" ]]; then
        printf '  FAIL  %s (HTTP %s)\n' "$fixture_id" "$http_code"
        summary_rows+=("$fixture_id|FAIL|HTTP $http_code")
        failed=$((failed + 1))
        continue
    fi

    # Concatenate all `data: {"text": "..."}` chunks into a single response.
    response_text=$(grep -E '^data: ' "$raw_stream_path" \
        | sed -E 's/^data: //' \
        | jq -r '.text // empty' 2>/dev/null \
        | tr -d '\r' \
        | tr '\n' ' ' \
        | sed -E 's/  +/ /g')
    printf '%s\n' "$response_text" > "$response_path"

    if [[ -z "$response_text" ]]; then
        printf '  FAIL  %s (empty response)\n' "$fixture_id"
        summary_rows+=("$fixture_id|FAIL|empty response")
        failed=$((failed + 1))
        continue
    fi

    if run_assertions "$fixture_id" "$expected" "$response_text"; then
        passed=$((passed + 1))
        summary_rows+=("$fixture_id|PASS|-")
    else
        failed=$((failed + 1))
        summary_rows+=("$fixture_id|FAIL|assertion mismatch")
    fi
done

# --- results summary ---------------------------------------------------------

printf '\n--- summary ---\n'
printf '%-60s  %-4s  %s\n' "fixture" "pass" "note"
printf -- '-%.0s' {1..100}
printf '\n'
for row in "${summary_rows[@]}"; do
    IFS='|' read -r id verdict note <<<"$row"
    printf '%-60s  %-4s  %s\n' "$id" "$verdict" "$note"
done
printf '\n%d passed, %d failed, %d total\n' "$passed" "$failed" "$total"
printf 'Per-fixture responses saved under: %s\n' "$OUTPUT_DIR"

# Emit a machine-readable JSON summary next to the raw stream files so the
# nightly CI workflow can parse it without scraping stdout.
summary_json="$OUTPUT_DIR/summary.json"
{
    printf '{\n'
    printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "relay": "%s",\n' "$RELAY_BASE_URL"
    printf '  "total": %d,\n' "$total"
    printf '  "passed": %d,\n' "$passed"
    printf '  "failed": %d,\n' "$failed"
    printf '  "fixtures": [\n'
    sep=""
    for row in "${summary_rows[@]}"; do
        IFS='|' read -r id verdict note <<<"$row"
        printf '%s    {"id": "%s", "verdict": "%s", "note": "%s"}' \
            "$sep" "$id" "$verdict" "$note"
        sep=$',\n'
    done
    printf '\n  ]\n'
    printf '}\n'
} > "$summary_json"
printf 'Summary JSON: %s\n' "$summary_json"

if (( failed > 0 )); then
    exit 1
fi
exit 0
