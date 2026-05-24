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
# workflow + on-demand local sanity checks.
#
# Requires:
#   - `VOLUMEARC_RELAY_SIGNING_KEY`  HMAC signing key (same value the iOS
#                                    app reads from env or Info.plist).
#   - `VOLUMEARC_EVAL_DEVICE_ID`     device ID prefix to sign with. Defaults
#                                    to `coach-eval-harness`; the harness
#                                    shards fixtures across deterministic
#                                    suffixes so suites larger than the
#                                    production per-device window do not
#                                    self-rate-limit.
#   - `VOLUMEARC_RELAY_BASE_URL`     override the relay endpoint (default:
#                                    `https://relay.volumearc.app`). VOL-223:
#                                    legacy `workers.dev` default was dead and
#                                    made the nightly eval a silent canary.
#   - `curl`, `jq`, `openssl`        standard on macOS and Linux runners.
#
# Exit codes:
#   0  all fixtures passed.
#   1  one or more fixtures failed response-quality assertions.
#   2  missing dependency / unconfigured env.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_DIR="$ROOT/Tests/Evals/CoachEvalFixtures"
RELAY_BASE_URL="${VOLUMEARC_RELAY_BASE_URL:-https://relay.volumearc.app}"
DEVICE_ID_BASE="${VOLUMEARC_EVAL_DEVICE_ID:-coach-eval-harness}"
DEVICE_SHARD_SIZE="${VOLUMEARC_EVAL_DEVICE_SHARD_SIZE:-20}"
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

if [[ ! "$DEVICE_SHARD_SIZE" =~ ^[0-9]+$ ]] || (( DEVICE_SHARD_SIZE < 1 )); then
    die "VOLUMEARC_EVAL_DEVICE_SHARD_SIZE must be a positive integer"
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
    # Approximate sentence count without treating decimal points in numbers
    # (for example, `RPE 7.6`) as sentence boundaries.
    local text="$1"
    printf '%s' "$text" \
        | tr -d '\r' \
        | LC_ALL=C awk '
            {
                for (i = 1; i <= length($0); i++) {
                    char = substr($0, i, 1)
                    prev = i > 1 ? substr($0, i - 1, 1) : ""
                    next_char = i < length($0) ? substr($0, i + 1, 1) : ""
                    if (char !~ /[[:space:]]/) {
                        segment_has_text = 1
                    }
                    if (char ~ /[.!?]/ && !(char == "." && prev ~ /[0-9]/ && next_char ~ /[0-9]/)) {
                        if (segment_has_text) {
                            n++
                            segment_has_text = 0
                        }
                    }
                }
            }
            END {
                if (segment_has_text) n++
                print n + 0
            }'
}

# Run every expectedAssertion against the response text.
# Prints a summary + returns 0 (pass) / 1 (fail).
run_assertions() {
    local fixture_id="$1"
    local assertions_json="$2"
    local response="$3"
    local failures=()
    ASSERTION_FAILURES_NOTE="-"
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
    ASSERTION_FAILURES_NOTE=""
    for f in "${failures[@]}"; do
        printf '        - %s\n' "$f"
        if [[ -z "$ASSERTION_FAILURES_NOTE" ]]; then
            ASSERTION_FAILURES_NOTE="$f"
        else
            ASSERTION_FAILURES_NOTE="${ASSERTION_FAILURES_NOTE}; ${f}"
        fi
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

printf 'Running %d coach eval fixture(s) against %s\n' "$total" "$RELAY_BASE_URL"
printf 'Device ID base: %s  (shard size: %s fixture(s))\n' "$DEVICE_ID_BASE" "$DEVICE_SHARD_SIZE"
printf 'Output dir: %s\n\n' "$OUTPUT_DIR"

passed=0
failed=0
summary_rows=()
fixture_index=0

for fixture_path in "${fixture_files[@]}"; do
    fixture_index=$((fixture_index + 1))
    fixture_name=$(basename "$fixture_path" .json)
    fixture_id=$(jq -r '.id' "$fixture_path")
    intent=$(jq -r '.intent' "$fixture_path")
    question=$(jq -r '.question' "$fixture_path")
    context_block=$(jq -r '.contextBlock' "$fixture_path")
    style=$(jq -r '.style' "$fixture_path")
    expected=$(jq -c '.expectedAssertions' "$fixture_path")
    readiness=$(grep '^- Readiness:' <<<"$context_block" \
        | sed -E 's/.*Readiness: ([0-9]+)\/100.*/\1/' \
        | head -n 1 \
        || true)
    if [[ -n "$readiness" ]]; then
        if [[ ! "$readiness" =~ ^[0-9]+$ ]] || (( readiness < 0 || readiness > 100 )); then
            die "fixture '$fixture_id' has invalid readiness '$readiness' (expected 0-100)"
        fi
    fi

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
    shard=$(( (fixture_index - 1) / DEVICE_SHARD_SIZE + 1 ))
    fixture_device_id="${DEVICE_ID_BASE}-${shard}"
    signature=$(compute_signature "$fixture_device_id" "$VOLUMEARC_RELAY_SIGNING_KEY")
    auth_header="Authorization: Bearer ${fixture_device_id}.${signature}"
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
        summary_rows+=("$fixture_id|FAIL|HTTP $http_code|$intent|$style|$readiness")
        failed=$((failed + 1))
        continue
    fi

    # Concatenate all `data: {"text": "..."}` chunks into a single response.
    response_text=$(grep -E '^data: ' "$raw_stream_path" \
        | sed -E 's/^data: //' \
        | jq -rj '.text // empty' 2>/dev/null \
        | tr -d '\r' \
        | sed -E 's/  +/ /g')
    printf '%s\n' "$response_text" > "$response_path"

    if [[ -z "$response_text" ]]; then
        printf '  FAIL  %s (empty response)\n' "$fixture_id"
        summary_rows+=("$fixture_id|FAIL|empty response|$intent|$style|$readiness")
        failed=$((failed + 1))
        continue
    fi

    if run_assertions "$fixture_id" "$expected" "$response_text"; then
        passed=$((passed + 1))
        summary_rows+=("$fixture_id|PASS|-|$intent|$style|$readiness")
    else
        failed=$((failed + 1))
        summary_rows+=("$fixture_id|FAIL|${ASSERTION_FAILURES_NOTE:-assertion mismatch}|$intent|$style|$readiness")
    fi
done

# --- results summary ---------------------------------------------------------

printf '\n--- summary ---\n'
printf '%-60s  %-4s  %s\n' "fixture" "pass" "note"
printf -- '-%.0s' {1..100}
printf '\n'
for row in "${summary_rows[@]}"; do
    IFS='|' read -r id verdict note _intent _style _readiness <<<"$row"
    printf '%-60s  %-4s  %s\n' "$id" "$verdict" "$note"
done
printf '\n%d passed, %d failed, %d total\n' "$passed" "$failed" "$total"
printf 'Per-fixture responses saved under: %s\n' "$OUTPUT_DIR"

# Emit a machine-readable JSON summary next to the raw stream files so the
# nightly CI workflow can parse it without scraping stdout.
summary_json="$OUTPUT_DIR/summary.json"
fixtures_tmp=$(mktemp)
printf '[]' > "$fixtures_tmp"
for row in "${summary_rows[@]}"; do
    IFS='|' read -r id verdict note intent style readiness <<<"$row"
    readiness_json="null"
    if [[ "$readiness" =~ ^[0-9]+$ ]]; then
        readiness_json="$readiness"
    fi
    tmp=$(mktemp)
    jq \
        --arg id "$id" \
        --arg verdict "$verdict" \
        --arg note "$note" \
        --arg intent "$intent" \
        --arg style "$style" \
        --argjson readiness "$readiness_json" \
        '. + [{id: $id, verdict: $verdict, note: $note, intent: $intent, style: $style, readiness: $readiness}]' \
        "$fixtures_tmp" > "$tmp"
    mv "$tmp" "$fixtures_tmp"
done

jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg relay "$RELAY_BASE_URL" \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    --slurpfile fixtures "$fixtures_tmp" \
    '{timestamp: $timestamp, relay: $relay, total: $total, passed: $passed, failed: $failed, fixtures: $fixtures[0]}' \
    > "$summary_json"
rm -f "$fixtures_tmp"
printf 'Summary JSON: %s\n' "$summary_json"

if (( failed > 0 )); then
    exit 1
fi
exit 0
