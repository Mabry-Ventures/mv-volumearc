#!/usr/bin/env bash
# VOL-200 Phase 1: journey-coverage gate.
#
# Parses `docs/USER_JOURNEYS.md`, counts the journey rows whose `Test`
# column is `[ ]` (uncovered) vs. paired with a test method, and fails
# the build when coverage drops below `JOURNEY_COVERAGE_THRESHOLD`.
#
# The default threshold is **100**. The release branch reached 72/72
# simulator-safe v1 rows on 2026-06-06 (VOL-271), so this gate is now
# a launch-grade regression block rather than the older staged floor.
# The pattern is:
#
#   * Every PR must preserve 100% journey-row coverage.
#   * Hardware-only proof lives in physical UAT, not uncovered rows.
#   * No silent regression.
#
# Mirrors the per-target ratchet pattern from `scripts/check_coverage.sh`
# (VOL-205). Step summary written to $GITHUB_STEP_SUMMARY when set.
#
# Override via env vars for diagnostic runs:
#   JOURNEY_COVERAGE_THRESHOLD=100 ./scripts/check_journey_coverage.sh
#   USER_JOURNEYS_PATH=/path/to/USER_JOURNEYS.md ./scripts/check_journey_coverage.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOURNEYS_PATH="${USER_JOURNEYS_PATH:-$ROOT/docs/USER_JOURNEYS.md}"
THRESHOLD="${JOURNEY_COVERAGE_THRESHOLD:-100}"

if [[ ! -f "$JOURNEYS_PATH" ]]; then
  echo "FAIL: docs/USER_JOURNEYS.md not found at $JOURNEYS_PATH" >&2
  exit 1
fi

# Parse: a journey row starts with a backticked ID in column 1 and has
# 6 pipe-separated columns. The Test column is the last one (column 6).
# Header rows + separator rows are filtered by the leading-backtick
# check (only data rows start with `\``). The Coverage summary table
# at the top of the doc uses bold IDs like `**Total**` and is not
# backtick-prefixed, so it's naturally excluded.
#
# A row is "covered" when its Test column contains a backticked test
# method name (matches `\`[A-Za-z]`) — i.e. anything that's NOT the
# `[ ]` uncovered marker. Some covered rows have parenthetical notes
# (e.g. ``VolumeArcAppJourneyTests.testFoo` (start phase)`); those are
# still legitimate coverage.
python3 - "$JOURNEYS_PATH" "$THRESHOLD" <<'PY'
import re
import sys
import os
from pathlib import Path

journeys_path = Path(sys.argv[1])
threshold = int(sys.argv[2])

# Match table rows that start with `| ` then a backticked ID then `|`.
# Captures the full row so we can split into columns.
row_re = re.compile(r"^\|\s*`[a-z][a-z0-9._-]*`\s*\|")

total = 0
covered = 0
uncovered_ids: list[str] = []

with journeys_path.open() as f:
    for raw_line in f:
        line = raw_line.rstrip("\n")
        if not row_re.match(line):
            continue
        # Split on `|` and trim; first cell is empty (leading `|`),
        # last is empty (trailing `|`). Strip both.
        cells = [c.strip() for c in line.split("|")]
        if cells and cells[0] == "":
            cells = cells[1:]
        if cells and cells[-1] == "":
            cells = cells[:-1]
        if len(cells) < 6:
            # Defensive: malformed row, skip.
            continue
        journey_id = cells[0].strip("`")
        test_cell = cells[5]
        total += 1
        # `[ ]` (with or without surrounding ``) means uncovered.
        # Strip any leading/trailing backticks for the check; some
        # rows have ``[ ]`` with backticks, some have a bare `[ ]`.
        normalized = test_cell.replace("`", "").strip()
        if normalized.startswith("[ ]"):
            uncovered_ids.append(journey_id)
        else:
            covered += 1

if total == 0:
    print("FAIL: no journey rows parsed from USER_JOURNEYS.md — table format may have changed.", file=sys.stderr)
    sys.exit(1)

percent = round((covered / total) * 100, 1)
percent_int = int(percent)
print(f"User-journey coverage: {covered}/{total} ({percent}%, threshold: {threshold}%)")

step_summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if step_summary_path:
    lines = [
        "## User-journey coverage (VOL-200)",
        "",
        f"**{covered}/{total} journeys covered ({percent}%, threshold: {threshold}%)**",
        "",
    ]
    if percent_int >= threshold:
        lines.append("Gate: passed.")
    else:
        lines.append("Gate: **FAILED**.")
    if uncovered_ids:
        # Cap to 25 in the step summary so the table stays readable;
        # full list still gets printed to stderr below for grep-ability.
        lines.append("")
        lines.append("### Uncovered journeys (first 25)")
        lines.append("")
        for j_id in uncovered_ids[:25]:
            lines.append(f"- `{j_id}`")
        if len(uncovered_ids) > 25:
            lines.append(f"- _…and {len(uncovered_ids) - 25} more._")
    with open(step_summary_path, "a") as fh:
        fh.write("\n".join(lines) + "\n")

if percent_int < threshold:
    print(f"FAIL: journey coverage {percent_int}% is below required {threshold}%", file=sys.stderr)
    print("Uncovered journeys (full list):", file=sys.stderr)
    for j_id in uncovered_ids:
        print(f"  - {j_id}", file=sys.stderr)
    sys.exit(1)

print("Journey coverage gate passed.")
PY
