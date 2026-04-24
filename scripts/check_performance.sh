#!/usr/bin/env bash
# VOL-99: enforce the performance-budget gate. Consumes the `.xcresult`
# bundle produced by `scripts/test_performance.sh`, extracts per-metric
# means via `xcrun xcresulttool get test-results metrics --path ...
# --compact`, and compares each against the budgets declared in
# `docs/performance-budgets.json`. A metric that exceeds its
# `failThreshold` exits nonzero.
#
# Also appends one entry to `docs/performance-trend.json` summarizing
# the run (commit SHA, ref, measured values) so the project carries a
# visible perf-history timeline. The entry is appended whether the
# gate passes or fails so regressions are recorded in the trend file
# even when they break the build.
#
# Usage:
#   scripts/check_performance.sh
# Env:
#   PERF_XCRESULT — path to the xcresult bundle (defaults to
#                   .build/perf-results.xcresult)
#   PERF_BUDGETS  — path to the budgets JSON (defaults to
#                   docs/performance-budgets.json)
#   PERF_TREND    — path to the trend JSON (defaults to
#                   docs/performance-trend.json)
#   PERF_SKIP_TREND_WRITE — set to "1" to skip the trend-file append
#                   (useful for local dev or diagnostic runs).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PERF_XCRESULT="${PERF_XCRESULT:-$ROOT/.build/perf-results.xcresult}"
PERF_BUDGETS="${PERF_BUDGETS:-$ROOT/docs/performance-budgets.json}"
PERF_TREND="${PERF_TREND:-$ROOT/docs/performance-trend.json}"
PERF_SKIP_TREND_WRITE="${PERF_SKIP_TREND_WRITE:-0}"

if [[ ! -d "$PERF_XCRESULT" ]]; then
  echo "FAIL: No xcresult bundle at $PERF_XCRESULT — did scripts/test_performance.sh run?" >&2
  exit 1
fi
if [[ ! -f "$PERF_BUDGETS" ]]; then
  echo "FAIL: No budgets file at $PERF_BUDGETS" >&2
  exit 1
fi

# `xcresulttool get test-results metrics` returns a JSON document with
# one entry per test, each carrying an array of per-iteration
# measurements per metric. Capture it once and feed it to Python
# alongside the budgets file; the comparison logic is clearer in
# Python than in jq + bash.
metrics_json=$(xcrun xcresulttool get test-results metrics \
  --path "$PERF_XCRESULT" \
  --compact)

commit_sha="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo 'unknown')"
git_ref="${GITHUB_REF:-$(git -C "$ROOT" symbolic-ref -q HEAD 2>/dev/null || echo 'detached')}"
run_timestamp="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

PERF_BUDGETS="$PERF_BUDGETS" \
PERF_TREND="$PERF_TREND" \
PERF_SKIP_TREND_WRITE="$PERF_SKIP_TREND_WRITE" \
COMMIT_SHA="$commit_sha" \
GIT_REF="$git_ref" \
RUN_TIMESTAMP="$run_timestamp" \
METRICS_JSON="$metrics_json" \
python3 <<'PY'
"""VOL-99: compare measured XCTest metrics against performance-budgets.json.

Each budget row is keyed by the `displayName` / `identifier` fields xcresulttool
emits. XCTest doesn't surface a per-measurement percentile array directly, so
we derive P50 / P95 from the raw `measurements` samples when a budget asks for
them (identifier ending in `-p50` or `-p95`). Fractional-bounds rows
(`today_scroll_hitches`) are converted into the budget's unit before the
comparison.
"""
import json
import os
import statistics
import sys

BUDGETS_PATH = os.environ["PERF_BUDGETS"]
TREND_PATH = os.environ["PERF_TREND"]
SKIP_TREND_WRITE = os.environ.get("PERF_SKIP_TREND_WRITE", "0") == "1"
COMMIT_SHA = os.environ["COMMIT_SHA"]
GIT_REF = os.environ["GIT_REF"]
RUN_TIMESTAMP = os.environ["RUN_TIMESTAMP"]
METRICS_JSON = os.environ["METRICS_JSON"]

with open(BUDGETS_PATH, "r", encoding="utf-8") as handle:
    budgets_doc = json.load(handle)

try:
    metrics_doc = json.loads(METRICS_JSON)
except json.JSONDecodeError as exc:
    print(f"FAIL: xcresulttool metrics output is not valid JSON: {exc}", file=sys.stderr)
    print(METRICS_JSON[:512], file=sys.stderr)
    sys.exit(1)


def iterate_metrics(doc):
    """Flatten the xcresulttool envelope into a list of per-metric samples.

    The envelope shape is:
      { "testNodes": [
          { "testIdentifier": "...", "testRuns": [
              { "metrics": [ { "displayName": ..., "identifier": ...,
                                "measurements": [...] } ] }
          ] }
      ] }

    On some Xcode versions the top-level key is `tests` instead of
    `testNodes`. Be lenient: walk everything that looks like a metric
    envelope.
    """
    seen = []
    stack = [doc]
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            if "measurements" in node and "displayName" in node:
                seen.append(node)
            for value in node.values():
                stack.append(value)
        elif isinstance(node, list):
            stack.extend(node)
    return seen


def match_metric(metric, budget):
    """Return True if `metric` describes the same measurement as `budget`.

    xcresulttool emits `identifier` that varies across Xcode versions for a
    given XCTPerformanceMetric (e.g.
    `com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration` on Xcode
    26.4, `com.apple.XCTPerformanceMetric_ApplicationLaunch-WallClockTime`
    on earlier toolchains). We match on a case-insensitive substring
    basis against either the identifier or the displayName so a budget
    keyed on the stable stem (e.g. `com.apple.dt.XCTMetric_ApplicationLaunch`)
    keeps working across Xcode revisions.
    """
    candidate = (budget.get("metric") or "").strip().lower()
    if not candidate:
        return False
    hay = " ".join([
        metric.get("identifier", ""),
        metric.get("displayName", ""),
    ]).lower()
    return candidate in hay


def reduce_samples(metric, budget):
    """Collapse an array of per-iteration measurements into a single scalar
    in the budget's unit.

    The `metricReduce` field on the budget row selects the reduction:
    * unset or "mean" — arithmetic mean.
    * "median" / "p50" — median.
    * "p95" — linear-interpolation 95th percentile.
    * "frame_rate" — derived FPS from hitch-time ratio (see below).
    * "hitches_per_second" — hitches/sec from hitch-time ratio.
    """
    samples = [float(sample) for sample in metric.get("measurements", []) if sample is not None]
    if not samples:
        return None

    reduce = (budget.get("metricReduce") or "mean").lower()
    if reduce in {"median", "p50"}:
        try:
            value = statistics.median(samples)
        except statistics.StatisticsError:
            return None
    elif reduce == "p95":
        ordered = sorted(samples)
        if len(ordered) == 1:
            value = ordered[0]
        else:
            pos = 0.95 * (len(ordered) - 1)
            lower = int(pos)
            upper = min(lower + 1, len(ordered) - 1)
            value = ordered[lower] + (ordered[upper] - ordered[lower]) * (pos - lower)
    elif reduce in {"frame_rate", "hitches_per_second"}:
        # XCTOSSignpostMetric samples arrive as a hitch-time ratio —
        # (unresponsive ms) / (total sampled ms). Use the mean across
        # iterations to drive both derived metrics.
        ratio = statistics.fmean(samples)
        if reduce == "hitches_per_second":
            # 1 hitch ≈ 16.67ms (one dropped frame at 60Hz), so
            # hitches/sec ≈ ratio * 1000ms / 16.67ms.
            value = ratio * (1000.0 / 16.67)
        else:  # frame_rate
            # Frame rate falls in proportion to the hitch ratio. Start
            # from the 60Hz simulator target and subtract the hitch
            # budget: fps ≈ 60 * (1 - ratio).
            value = max(0.0, 60.0 * (1.0 - ratio))
        return value
    else:
        value = statistics.fmean(samples)

    units = (budget.get("units") or "").lower()
    # XCTest reports several units in their SI base; convert to the units
    # the budget file declares. Every conversion is a fixed constant; if a
    # new metric ships with a different raw unit, add the conversion here.
    raw_unit = (metric.get("unitOfMeasurement") or "").lower()
    if units == "megabytes" and raw_unit in {"kb", "kilobytes"}:
        value = value / 1024.0
    elif units == "megabytes" and raw_unit in {"b", "bytes"}:
        value = value / (1024.0 * 1024.0)
    elif units == "milliseconds" and raw_unit in {"s", "seconds"}:
        value = value * 1000.0
    elif units == "seconds" and raw_unit in {"ms", "milliseconds"}:
        value = value / 1000.0
    return value


metrics = iterate_metrics(metrics_doc)
rows = []
failed = False

for budget in budgets_doc["metrics"]:
    matches = [metric for metric in metrics if match_metric(metric, budget)]
    if not matches:
        rows.append({
            "id": budget["id"],
            "status": "missing",
            "measured": None,
            "budget": budget["budget"],
            "failThreshold": budget["failThreshold"],
            "units": budget.get("units"),
        })
        # Treat a missing metric as a soft failure: the gate will still
        # emit nonzero at the end, but we keep walking so the full row
        # set ends up in the trend file and step summary.
        failed = True
        continue

    measured = reduce_samples(matches[0], budget)
    if measured is None:
        rows.append({
            "id": budget["id"],
            "status": "no_samples",
            "measured": None,
            "budget": budget["budget"],
            "failThreshold": budget["failThreshold"],
            "units": budget.get("units"),
        })
        failed = True
        continue

    direction = budget.get("thresholdDirection", "higher_is_worse")
    if direction == "lower_is_worse":
        gate_passed = measured >= budget["failThreshold"]
        # For lower-is-worse metrics (e.g. frame rate), the `budget` is
        # the floor; the `failThreshold` is a lower floor. Passing the
        # budget means measured >= budget; exceeding failThreshold means
        # measured < failThreshold.
        gate_passed = measured >= budget["failThreshold"]
        budget_met = measured >= budget["budget"]
    else:
        gate_passed = measured <= budget["failThreshold"]
        budget_met = measured <= budget["budget"]

    status = "passed" if gate_passed else "failed"
    if not budget_met and gate_passed:
        status = "warning"

    if status == "failed":
        failed = True

    rows.append({
        "id": budget["id"],
        "status": status,
        "measured": round(measured, 3),
        "budget": budget["budget"],
        "failThreshold": budget["failThreshold"],
        "units": budget.get("units"),
    })

# Human-readable output.
print(f"VOL-99 performance gate — {len(rows)} metric(s), commit {COMMIT_SHA[:12]}")
for row in rows:
    measured_text = "—" if row["measured"] is None else f"{row['measured']} {row['units'] or ''}".strip()
    print(f"  [{row['status'].upper():>8}] {row['id']:<30} measured={measured_text:<18} "
          f"budget={row['budget']} {row['units'] or ''} fail>{row['failThreshold']}")

# GitHub Actions step summary if available.
if os.environ.get("GITHUB_STEP_SUMMARY"):
    summary_path = os.environ["GITHUB_STEP_SUMMARY"]
    with open(summary_path, "a", encoding="utf-8") as handle:
        handle.write("## Performance budgets (VOL-99)\n\n")
        handle.write(f"Commit: `{COMMIT_SHA[:12]}`\n\n")
        handle.write("| Metric | Status | Measured | Budget | Fail threshold |\n")
        handle.write("|---|---|---|---|---|\n")
        for row in rows:
            measured = "—" if row["measured"] is None else f"{row['measured']} {row['units'] or ''}"
            handle.write(
                f"| `{row['id']}` | {row['status']} | {measured} | "
                f"{row['budget']} {row['units'] or ''} | "
                f"{row['failThreshold']} {row['units'] or ''} |\n"
            )
        handle.write("\n")
        if failed:
            handle.write("Gate: FAILED\n")
        else:
            handle.write("Gate: passed\n")

# Append to the trend file. Each entry is append-only so the file
# grows monotonically; regressions show up as a high row in the trend.
if not SKIP_TREND_WRITE:
    try:
        with open(TREND_PATH, "r", encoding="utf-8") as handle:
            trend_doc = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError):
        trend_doc = {"runs": []}

    trend_doc.setdefault("runs", []).append({
        "timestamp": RUN_TIMESTAMP,
        "commit": COMMIT_SHA,
        "ref": GIT_REF,
        "passed": not failed,
        "metrics": [
            {
                "id": row["id"],
                "measured": row["measured"],
                "status": row["status"],
            }
            for row in rows
        ],
    })
    # Cap the file at the last 500 runs so it doesn't grow unbounded.
    trend_doc["runs"] = trend_doc["runs"][-500:]
    with open(TREND_PATH, "w", encoding="utf-8") as handle:
        json.dump(trend_doc, handle, indent=2)
        handle.write("\n")

if failed:
    print("FAIL: at least one metric breached its fail threshold", file=sys.stderr)
    sys.exit(1)

print("Performance gate passed.")
PY
