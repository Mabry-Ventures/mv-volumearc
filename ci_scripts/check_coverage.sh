#!/usr/bin/env bash
# VOL-246: Xcode Cloud test-machine copy of scripts/check_coverage.sh.
#
# Xcode Cloud's `test-without-building` action runs on a SEPARATE machine
# from `build-for-testing`. That machine receives `ci_scripts/` but does NOT
# receive the full repository source tree — `scripts/` is absent. This file
# is a verbatim copy of `scripts/check_coverage.sh` with one change: the
# `_compute_coverage_summary.py` path is computed relative to THIS script's
# own directory (`ci_scripts/`) rather than `$ROOT/scripts/`, so the
# companion module is always found regardless of which machine is executing.
#
# Keep this file in sync with `scripts/check_coverage.sh`. The only
# intentional diff is the SCRIPT_DIR vs ROOT/scripts path for the python
# module (see the `xcrun xccov` pipeline below).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/derived-data}"
XCRESULT="${XCRESULT:-$DERIVED_DATA_PATH/TestResults.xcresult}"
THRESHOLD="${COVERAGE_THRESHOLD:-80}"
TARGET="${COVERAGE_TARGET:-VolumeArcCore}"
SUMMARY_JSON="${COVERAGE_SUMMARY_JSON:-$ROOT/.build/coverage-summary.json}"

if [[ ! -d "$XCRESULT" ]]; then
  echo "FAIL: No xcresult bundle at $XCRESULT — did tests run with -enableCodeCoverage YES?" >&2
  exit 1
fi

mkdir -p "$(dirname "$SUMMARY_JSON")"

# Stream xccov's JSON straight to the summary writer. The python
# module lives next to this script in `ci_scripts/` so it is always
# present on the Xcode Cloud test machine.
export TARGET THRESHOLD SUMMARY_JSON
xcrun xccov view --report --json "$XCRESULT" \
  | python3 "$SCRIPT_DIR/_compute_coverage_summary.py"

# Re-read the JSON we just wrote so the rest of the script works in
# pure bash.
target_coverage=$(python3 -c "import json,sys;print(json.load(open('$SUMMARY_JSON'))['coverage'])")
gate_passed=$(python3 -c "import json,sys;print('1' if json.load(open('$SUMMARY_JSON'))['passed'] else '0')")

echo "${TARGET} line coverage: ${target_coverage}% (threshold: ${THRESHOLD}%)"

# VOL-97: step summary — only when running inside GitHub Actions.
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Coverage"
    echo ""
    echo "**${TARGET}**: ${target_coverage}% (threshold: ${THRESHOLD}%)"
    echo ""
    if [[ "$gate_passed" == "1" ]]; then
      echo "Gate: passed"
    else
      echo "Gate: FAILED"
    fi
    echo ""
    echo "### Top 10 files by uncovered lines"
    echo ""
    SUMMARY_JSON="$SUMMARY_JSON" python3 - <<'PY'
import json, os
data = json.load(open(os.environ["SUMMARY_JSON"]))
rows = data.get("topUncovered") or []
if not rows:
    print("_No per-file breakdown available (target not found in xcresult)._")
else:
    print("| File | Uncovered | Executable | Coverage |")
    print("|---|---:|---:|---:|")
    for row in rows:
        print(f"| `{row['path']}` | {row['uncovered']} | {row['executable']} | {row['coverage']}% |")
PY

    echo ""
    echo "### All measured targets"
    echo ""
    SUMMARY_JSON="$SUMMARY_JSON" python3 - <<'PY'
import json, os
data = json.load(open(os.environ["SUMMARY_JSON"]))
rows = data.get("targets") or []
if not rows:
    print("_No per-target measurements available._")
else:
    print("| Target | Coverage | Executable | Covered | Gate |")
    print("|---|---:|---:|---:|---|")
    for row in rows:
        if row.get("gated"):
            if row.get("passed"):
                gate = f"passed (>= {row['threshold']:g}%)"
            else:
                gate = f"FAILED (< {row['threshold']:g}%)"
        else:
            gate = "_(measure only)_"
        print(
            f"| `{row['target']}` | {row['coverage']}% | "
            f"{row['executable']} | {row['covered']} | {gate} |"
        )
PY
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [[ "$gate_passed" != "1" ]]; then
  echo "FAIL: Coverage ${target_coverage}% is below required ${THRESHOLD}%" >&2
  exit 1
fi

echo "Coverage gate passed."
