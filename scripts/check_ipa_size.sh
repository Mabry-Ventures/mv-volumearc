#!/usr/bin/env bash
# VOL-215 Phase 1: IPA / app-bundle size budget.
#
# Run after `xcodebuild -exportArchive` produces a release `.ipa`.
# Reads the on-disk byte size of:
#   * the IPA archive itself
#   * `VolumeArc.app` (top-level iOS payload)
#   * the embedded watch app (`VolumeArc.app/Watch/VolumeArcWatch.app`)
#   * each embedded extension (watch widget, etc.)
# Compares each against `docs/performance-budgets.json` budgets keyed
# on `id` (ipa_size_*, app_size_iphone_*, app_size_watch_*,
# app_size_widget_extension_*). Exit non-zero if any metric exceeds
# its `failThreshold`.
#
# Designed to run on the post-merge tag-build job alongside the
# existing `check_performance.sh` perf-budget gate. Keeps the audit
# F-M-006 (now sharpened by VOL-215) signal flowing without the
# heavyweight perf-suite tag gate.
#
# Override paths for diagnostic runs:
#   IPA_PATH=/path/to/VolumeArc.ipa ./scripts/check_ipa_size.sh
#   BUDGETS_PATH=/path/to/budgets.json ./scripts/check_ipa_size.sh
#
# Initial floors (VOL-215 Phase 1 baseline, 2026-05-18):
# Conservative starter values; subsequent PRs ratchet down as the
# IPA shrinks. Same pattern as VOL-205 per-target coverage gate.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IPA_PATH="${IPA_PATH:-$ROOT/build/exports/VolumeArc.ipa}"
BUDGETS_PATH="${BUDGETS_PATH:-$ROOT/docs/performance-budgets.json}"

if [[ ! -f "$IPA_PATH" ]]; then
  echo "FAIL: IPA not found at $IPA_PATH — did 'xcodebuild -exportArchive' run?" >&2
  exit 1
fi
if [[ ! -f "$BUDGETS_PATH" ]]; then
  echo "FAIL: performance-budgets.json not found at $BUDGETS_PATH" >&2
  exit 1
fi

# Unpack the IPA into a temp dir so we can stat each bundle.
TMPDIR_PAYLOAD=$(mktemp -d)
trap 'rm -rf "$TMPDIR_PAYLOAD"' EXIT
/usr/bin/unzip -qq "$IPA_PATH" -d "$TMPDIR_PAYLOAD"

APP_BUNDLE="$TMPDIR_PAYLOAD/Payload/VolumeArc.app"
WATCH_BUNDLE="$APP_BUNDLE/Watch/VolumeArcWatch.app"
WATCH_WIDGET_BUNDLE="$WATCH_BUNDLE/PlugIns/VolumeArcWatchWidgets.appex"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "FAIL: VolumeArc.app not found in Payload — IPA layout unexpected" >&2
  exit 1
fi

# `du -sk` returns size-on-disk in KB; we report MB for budgets.
size_mb_of() {
  local target="$1"
  if [[ ! -e "$target" ]]; then
    echo "0"
    return
  fi
  # `du -sk` is KB on macOS + Linux. Divide by 1024 for MB. Use bc
  # for a one-decimal MB value (budgets are in MB integers but we
  # report finer for the step summary).
  local kb
  kb=$(/usr/bin/du -sk "$target" | /usr/bin/awk '{print $1}')
  /usr/bin/awk -v kb="$kb" 'BEGIN { printf "%.1f", kb / 1024 }'
}

ipa_size_mb=$(/usr/bin/awk -v bytes="$(/usr/bin/stat -f%z "$IPA_PATH")" 'BEGIN { printf "%.1f", bytes / 1048576 }')
app_size_mb=$(size_mb_of "$APP_BUNDLE")
watch_size_mb=$(size_mb_of "$WATCH_BUNDLE")
widget_size_mb=$(size_mb_of "$WATCH_WIDGET_BUNDLE")

echo "IPA size sweep (VOL-215):"
echo "  IPA archive:     ${ipa_size_mb} MB"
echo "  VolumeArc.app:   ${app_size_mb} MB"
echo "  Watch app:       ${watch_size_mb} MB"
echo "  Watch widget:    ${widget_size_mb} MB"

# Pass through python so we can read JSON budgets cleanly. Each metric
# id in performance-budgets.json that starts with `ipa_size_` or
# `app_size_` gets matched to the value above. Missing budget keys are
# skipped with a warning; failed budgets exit non-zero.
export IPA_SIZE_MB=$ipa_size_mb
export APP_SIZE_IPHONE_MB=$app_size_mb
export APP_SIZE_WATCH_MB=$watch_size_mb
export APP_SIZE_WATCH_WIDGET_MB=$widget_size_mb
export BUDGETS_PATH

python3 - <<'PY'
import json
import os
import sys

path = os.environ["BUDGETS_PATH"]
measured = {
    "ipa_size_total_mb": float(os.environ["IPA_SIZE_MB"]),
    "app_size_iphone_mb": float(os.environ["APP_SIZE_IPHONE_MB"]),
    "app_size_watch_mb": float(os.environ["APP_SIZE_WATCH_MB"]),
    "app_size_watch_widget_mb": float(os.environ["APP_SIZE_WATCH_WIDGET_MB"]),
}

with open(path) as f:
    data = json.load(f)

failures = []
summary_rows = []
known_ids = {m["id"] for m in data.get("metrics", [])}

for metric_id, value in measured.items():
    if metric_id not in known_ids:
        print(f"INFO: budget '{metric_id}' not in performance-budgets.json yet; skipping (add it to enforce).")
        summary_rows.append((metric_id, value, None, None, "no-budget"))
        continue
    metric = next(m for m in data["metrics"] if m["id"] == metric_id)
    budget = metric.get("budget")
    fail_threshold = metric.get("failThreshold")
    if budget is None or fail_threshold is None:
        print(f"WARN: metric '{metric_id}' missing budget/failThreshold; skipping")
        summary_rows.append((metric_id, value, budget, fail_threshold, "malformed"))
        continue
    over_budget = value > budget
    over_fail = value > fail_threshold
    status = "FAIL" if over_fail else ("WARN" if over_budget else "OK")
    summary_rows.append((metric_id, value, budget, fail_threshold, status))
    if over_fail:
        failures.append(
            f"{metric_id}: {value} MB exceeds failThreshold {fail_threshold} MB (budget {budget} MB)"
        )

step_summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if step_summary_path:
    lines = [
        "## IPA size budgets (VOL-215)",
        "",
        "| Metric | Measured (MB) | Budget (MB) | Fail at (MB) | Status |",
        "|---|---:|---:|---:|---|",
    ]
    for row in summary_rows:
        metric_id, value, budget, fail_threshold, status = row
        b = f"{budget}" if budget is not None else "_(unset)_"
        f = f"{fail_threshold}" if fail_threshold is not None else "_(unset)_"
        lines.append(f"| `{metric_id}` | {value} | {b} | {f} | **{status}** |")
    with open(step_summary_path, "a") as fh:
        fh.write("\n".join(lines) + "\n")

if failures:
    print("FAIL: IPA size budgets exceeded:", file=sys.stderr)
    for f in failures:
        print(f"  - {f}", file=sys.stderr)
    sys.exit(1)

print("IPA size budgets passed.")
PY
