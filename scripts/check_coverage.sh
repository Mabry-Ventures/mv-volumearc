#!/usr/bin/env bash
# VOL-52: enforce a hard 80% line-coverage gate on the VolumeArcCore
# module. Run `./scripts/test_apple_targets.sh` first so an xcresult
# exists; this script parses the bundle with `xcrun xccov view --report
# --json` and exits non-zero when the module's line coverage drops
# below the threshold. Override the threshold or target name via
# `COVERAGE_THRESHOLD` and `COVERAGE_TARGET` for diagnostic runs.
#
# VOL-97: when `GITHUB_STEP_SUMMARY` is set (GitHub Actions runs), the
# script also writes a Markdown summary — headline coverage, gate
# result, and a top-10 uncovered-files table — to the step summary file
# so coverage is visible outside the raw CI log. It also writes a
# machine-readable `.build/coverage-summary.json` for the CI workflow
# to append to the historical trend file and post the sticky PR
# comment.
#
# VOL-140 Phase 1 (2026-05-11): the summary JSON now carries a `targets`
# array with measurements for *every* non-test target xccov surfaces,
# not just the primary gated target. The gate itself is unchanged —
# only the primary `TARGET` is enforced — but downstream consumers
# (sticky PR comment, metrics-branch trend) report all targets so we
# can calibrate per-module thresholds in Phase 2. The python that
# computes the payload was factored out to
# `scripts/_compute_coverage_summary.py` to escape a bash-3.2 parser
# limitation with `python3 -c "$(cat <<'PY' ... PY)"` heredocs that
# contain alternation / parens.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
# module lives in `scripts/_compute_coverage_summary.py` (see VOL-140
# Phase 1 note in the header comment) and reads TARGET / THRESHOLD /
# SUMMARY_JSON from the environment.
#
# `export` the variables rather than using a `VAR=... cmd` prefix:
# env-var assignments preceding a *pipeline* only apply to the first
# command in that pipeline, so the python receiver on the far side of
# `|` would get `KeyError: 'TARGET'` otherwise. Caught in PR #150 CI
# run 25649937456 — a one-liner regression from inlining the python
# into a pipeline. The python module is the only consumer of these
# vars, so `export` has no other side effects.
export TARGET THRESHOLD SUMMARY_JSON
xcrun xccov view --report --json "$XCRESULT" \
  | python3 "$ROOT/scripts/_compute_coverage_summary.py"

# Re-read the JSON we just wrote so the rest of the script works in
# pure bash — easier to wire into shell output + downstream tooling.
target_coverage=$(python3 -c "import json,sys;print(json.load(open('$SUMMARY_JSON'))['coverage'])")
gate_passed=$(python3 -c "import json,sys;print('1' if json.load(open('$SUMMARY_JSON'))['passed'] else '0')")

echo "${TARGET} line coverage: ${target_coverage}% (threshold: ${THRESHOLD}%)"

# VOL-97: step summary — only when running inside GitHub Actions.
# Writes a Markdown block appended to $GITHUB_STEP_SUMMARY so reviewers
# see coverage + the worst-offender files without downloading the
# xcresult artifact.
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
    # Render the table in python to avoid shell-quoting the JSON payload.
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

    # VOL-140 Phase 1: per-target measurements. The gated target is
    # marked; everything else is "measure only" until follow-up PRs
    # calibrate per-module thresholds.
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
