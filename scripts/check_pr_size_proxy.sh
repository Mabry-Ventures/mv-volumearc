#!/usr/bin/env bash
# VOL-215 Phase 2: PR-time bundle-size proxy.
#
# This is intentionally NOT the signed release IPA gate. Pull requests do not
# archive/sign/export an IPA, so this script measures the Debug simulator build
# products that `scripts/build_all_targets.sh` already produced in the current
# job:
#   * VolumeArc.app
#   * VolumeArcWidgets.appex
#   * VolumeArcWatch.app
#   * VolumeArcWatchWidgets.appex
#
# It gives reviewers a warning-only drift signal on PRs. The release/archive
# gate remains `scripts/check_ipa_size.sh`, which measures the exported IPA.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/derived-data}"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUDGETS_PATH="${BUDGETS_PATH:-$ROOT/docs/performance-budgets.json}"

IOS_PRODUCTS_DIR="${IOS_PRODUCTS_DIR:-$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphonesimulator}"
WATCH_PRODUCTS_DIR="${WATCH_PRODUCTS_DIR:-$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-watchsimulator}"

resolve_dir() {
  local label="$1"
  shift
  for candidate in "$@"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "FAIL: ${label} bundle not found. Checked:" >&2
  for candidate in "$@"; do
    [[ -n "$candidate" ]] && echo "  - $candidate" >&2
  done
  echo "Run scripts/build_all_targets.sh first, or override ${label}_PATH." >&2
  return 1
}

APP_BUNDLE="$(resolve_dir APP_BUNDLE "${APP_BUNDLE_PATH:-}" "$IOS_PRODUCTS_DIR/VolumeArc.app")"
IOS_WIDGET_BUNDLE="$(resolve_dir IOS_WIDGET_BUNDLE \
  "${IOS_WIDGET_BUNDLE_PATH:-}" \
  "$APP_BUNDLE/PlugIns/VolumeArcWidgets.appex" \
  "$IOS_PRODUCTS_DIR/VolumeArcWidgets.appex")"
WATCH_BUNDLE="$(resolve_dir WATCH_BUNDLE "${WATCH_BUNDLE_PATH:-}" "$WATCH_PRODUCTS_DIR/VolumeArcWatch.app")"
WATCH_WIDGET_BUNDLE="$(resolve_dir WATCH_WIDGET_BUNDLE \
  "${WATCH_WIDGET_BUNDLE_PATH:-}" \
  "$WATCH_BUNDLE/PlugIns/VolumeArcWatchWidgets.appex" \
  "$WATCH_PRODUCTS_DIR/VolumeArcWatchWidgets.appex")"

if [[ ! -f "$BUDGETS_PATH" ]]; then
  echo "FAIL: performance-budgets.json not found at $BUDGETS_PATH" >&2
  exit 1
fi

export APP_BUNDLE IOS_WIDGET_BUNDLE WATCH_BUNDLE WATCH_WIDGET_BUNDLE BUDGETS_PATH

python3 - <<'PY'
import json
import os
import subprocess
import sys

paths = {
    "pr_size_proxy_iphone_app_mb": os.environ["APP_BUNDLE"],
    "pr_size_proxy_ios_widget_mb": os.environ["IOS_WIDGET_BUNDLE"],
    "pr_size_proxy_watch_app_mb": os.environ["WATCH_BUNDLE"],
    "pr_size_proxy_watch_widget_mb": os.environ["WATCH_WIDGET_BUNDLE"],
}


def disk_kb(path: str) -> int:
    output = subprocess.check_output(["/usr/bin/du", "-sk", path], text=True)
    return int(output.split()[0])


def is_descendant(child: str, parent: str) -> bool:
    child_abs = os.path.abspath(child)
    parent_abs = os.path.abspath(parent)
    try:
        return os.path.commonpath([child_abs, parent_abs]) == parent_abs and child_abs != parent_abs
    except ValueError:
        return False


unique_total_paths = []
for path in [
    paths["pr_size_proxy_iphone_app_mb"],
    paths["pr_size_proxy_ios_widget_mb"],
    paths["pr_size_proxy_watch_app_mb"],
    paths["pr_size_proxy_watch_widget_mb"],
]:
    if any(is_descendant(path, existing) for existing in unique_total_paths):
        continue
    unique_total_paths.append(path)

measured = {
    metric_id: round(disk_kb(path) / 1024, 1)
    for metric_id, path in paths.items()
}
measured["pr_size_proxy_total_mb"] = round(
    sum(disk_kb(path) for path in unique_total_paths) / 1024,
    1,
)

print("PR bundle-size proxy (VOL-215):")
print(f"  Proxy total:       {measured['pr_size_proxy_total_mb']} MB")
print(f"  VolumeArc.app:     {measured['pr_size_proxy_iphone_app_mb']} MB")
print(f"  iOS widget:        {measured['pr_size_proxy_ios_widget_mb']} MB")
print(f"  Watch app:         {measured['pr_size_proxy_watch_app_mb']} MB")
print(f"  Watch widget:      {measured['pr_size_proxy_watch_widget_mb']} MB")
print("  Unique total paths:")
for path in unique_total_paths:
    print(f"    - {path}")

with open(os.environ["BUDGETS_PATH"]) as handle:
    data = json.load(handle)

budget_by_id = {metric["id"]: metric for metric in data.get("metrics", [])}
summary_rows = []
failures = []

for metric_id in sorted(measured):
    value = measured[metric_id]
    metric = budget_by_id.get(metric_id)
    if metric is None:
        failures.append(f"budget '{metric_id}' is missing in performance-budgets.json")
        summary_rows.append((metric_id, value, None, None, "no-budget"))
        continue
    budget = metric.get("budget")
    fail_threshold = metric.get("failThreshold")
    if budget is None or fail_threshold is None:
        failures.append(f"metric '{metric_id}' is missing budget/failThreshold")
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
        "## PR bundle-size proxy (VOL-215)",
        "",
        "Measures Debug simulator build products as a PR-time drift signal. The signed IPA gate still runs from release/export artifacts.",
        "",
        "| Metric | Measured (MB) | Budget (MB) | Fail at (MB) | Status |",
        "|---|---:|---:|---:|---|",
    ]
    for metric_id, value, budget, fail_threshold, status in summary_rows:
        budget_text = f"{budget}" if budget is not None else "_(unset)_"
        fail_text = f"{fail_threshold}" if fail_threshold is not None else "_(unset)_"
        lines.append(f"| `{metric_id}` | {value} | {budget_text} | {fail_text} | **{status}** |")
    with open(step_summary_path, "a") as handle:
        handle.write("\n".join(lines) + "\n")

if failures:
    print("FAIL: PR bundle-size proxy budgets exceeded:", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)

print("PR bundle-size proxy budgets passed.")
PY
