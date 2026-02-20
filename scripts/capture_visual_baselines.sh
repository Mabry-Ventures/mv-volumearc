#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:4173}"

if ! command -v npx >/dev/null 2>&1; then
  echo "npx is required to run Playwright CLI." >&2
  exit 1
fi

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PWCLI="$CODEX_HOME/skills/playwright/scripts/playwright_cli.sh"

if [ ! -x "$PWCLI" ]; then
  echo "Playwright wrapper not found at: $PWCLI" >&2
  exit 1
fi

OUTPUT_DIR="output/playwright/visual-baselines"
mkdir -p "$OUTPUT_DIR"

capture() {
  local route="$1"
  local name="$2"
  local width="$3"
  local height="$4"
  local label="$5"

  "$PWCLI" goto "${BASE_URL}${route}" >/tmp/pw_${name}_${label}_goto.log
  "$PWCLI" resize "$width" "$height" >/tmp/pw_${name}_${label}_resize.log

  local out
  out=$("$PWCLI" screenshot)

  local src
  src=$(printf "%s" "$out" | sed -n 's/.*\(\.playwright-cli\/page-[^ ]*\.png\).*/\1/p' | tail -n 1)

  if [ -z "$src" ] || [ ! -f "$src" ]; then
    echo "Failed to capture ${name}-${label} screenshot." >&2
    echo "$out" >&2
    exit 1
  fi

  cp "$src" "$OUTPUT_DIR/${name}-${label}.png"
}

"$PWCLI" close >/dev/null 2>&1 || true
"$PWCLI" open "$BASE_URL" >/tmp/pw_open.log

capture "/" "home" 1440 900 "desktop"
capture "/workout" "workout" 1440 900 "desktop"
capture "/history" "history" 1440 900 "desktop"
capture "/stats" "stats" 1440 900 "desktop"
capture "/settings" "settings" 1440 900 "desktop"

capture "/" "home" 390 844 "mobile"
capture "/workout" "workout" 390 844 "mobile"
capture "/history" "history" 390 844 "mobile"
capture "/stats" "stats" 390 844 "mobile"
capture "/settings" "settings" 390 844 "mobile"

"$PWCLI" close >/dev/null 2>&1 || true

echo "Saved visual baselines to $OUTPUT_DIR"
