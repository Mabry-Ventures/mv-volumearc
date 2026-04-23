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

# Capture xccov JSON to a variable, then feed it to Python via a here
# string. We can't do `xcrun ... | python3 <<'PY' ... PY` because
# bash's heredoc-stdin redirect wins over the pipe — Python would read
# the heredoc as script source but see empty stdin for
# `sys.stdin.read()`. Writing the script body inline with `python3 -c`
# + command substitution avoids that entirely: `-c` takes the code as
# an argument, leaving stdin free for the xccov payload passed via
# `<<<`.
coverage_json=$(xcrun xccov view --report --json "$XCRESULT")

TARGET="$TARGET" THRESHOLD="$THRESHOLD" SUMMARY_JSON="$SUMMARY_JSON" \
  python3 -c "$(cat <<'PY'
"""VOL-52 + VOL-97: compute the coverage gate outcome and emit the
machine-readable summary JSON downstream steps consume."""
import json, os, sys

target_name = os.environ["TARGET"]
threshold = float(os.environ["THRESHOLD"])
summary_path = os.environ["SUMMARY_JSON"]

# VolumeArcCore is built as a static library, so xccov reports the
# target as 'libVolumeArcCore.a' rather than the bare module name.
# Accept either form so the gate works whether we ever migrate to a
# framework target later.
candidates = {target_name, f"lib{target_name}.a", f"{target_name}.framework"}

data = json.load(sys.stdin)
target = None
for candidate in data.get("targets", []):
    name = candidate.get("name", "")
    if name in candidates or name.startswith(target_name + "."):
        target = candidate
        break

coverage_pct = 0.0
files_table = []
if target is not None:
    coverage_pct = round(target.get("lineCoverage", 0.0) * 100, 2)
    files = target.get("files", []) or []

    def uncovered_count(entry):
        executable = entry.get("executableLines", 0) or 0
        covered = entry.get("coveredLines", 0) or 0
        return max(executable - covered, 0)

    ranked = sorted(
        files,
        key=lambda entry: (
            uncovered_count(entry),
            entry.get("executableLines", 0) or 0,
        ),
        reverse=True,
    )
    for entry in ranked[:10]:
        executable = entry.get("executableLines", 0) or 0
        line_cov = round((entry.get("lineCoverage", 0.0) or 0.0) * 100, 2)
        path = entry.get("path") or entry.get("name") or "(unknown)"
        # xccov paths are absolute on the build host — trim to a stable
        # repo-relative suffix when possible for readability in the
        # step summary.
        marker = "/VolumeArcNative/"
        if marker in path:
            path = "VolumeArcNative/" + path.split(marker, 1)[1]
        files_table.append(
            {
                "path": path,
                "uncovered": uncovered_count(entry),
                "executable": executable,
                "coverage": line_cov,
            }
        )

passed = coverage_pct + 1e-9 >= threshold
payload = {
    "target": target_name,
    "coverage": coverage_pct,
    "threshold": threshold,
    "passed": passed,
    "topUncovered": files_table,
}
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
PY
)" <<<"$coverage_json"

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
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [[ "$gate_passed" != "1" ]]; then
  echo "FAIL: Coverage ${target_coverage}% is below required ${THRESHOLD}%" >&2
  exit 1
fi

echo "Coverage gate passed."
