#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_PATH="${UAT_EVIDENCE_PATH:-$ROOT/docs/RELEASE_UAT_EVIDENCE.md}"

if [[ ! -f "$EVIDENCE_PATH" ]]; then
  echo "FAIL: release UAT evidence file missing at $EVIDENCE_PATH" >&2
  exit 1
fi

python3 - "$EVIDENCE_PATH" <<'PY'
from __future__ import annotations

import re
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
failures: list[str] = []

placeholder_re = re.compile(
    r"\b(Not run|Pending|Unverified|Action required|TBD|TODO|FIXME)\b|<[^>]+>",
    re.IGNORECASE,
)
template_evidence_re = re.compile(
    r"^(Install or update from TestFlight|Fresh install,|Premium account,|"
    r"Notification prompt appears|Sign in with Apple succeeds|System, light, and dark modes|"
    r"Diagnostics opens|Purchase, cancel,|Build a workout manually,|Coach-recommended workout|"
    r"During a session,|Equipment Busy suggests|Skip and replace an exercise|"
    r"Exercise diagrams or cues|Force-quit|Watch app installs|Start workout on Watch|"
    r"Log sets on Watch|Watch renders|Increase/Hold/Decrease|Disconnect iPhone|"
    r"Reconnect iPhone|APNs/TestFlight notification|Add small widget|Add medium widget|"
    r"Start workout; Live Activity|Dynamic Island|Complete workout; Live Activity|"
    r"Live coach path|Signals explains|Required journeys pass|Light, dark, warm|"
    r"No crash, data-loss|Live eval trend|Sentry, App Attest)",
    re.IGNORECASE,
)
concrete_evidence_re = re.compile(
    r"(https?://|screenshot|screen recording|\blogs?\b|App Store Connect|ASC|"
    r"TestFlight build\s+\S+|build\s+\d+|run\s+[0-9a-f-]{8,}|"
    r"\b20\d{2}-\d{2}-\d{2}\b)",
    re.IGNORECASE,
)

required_build_fields = [
    "TestFlight build",
    "App version",
    "Commit SHA",
    "TestFlight processing timestamp",
    "Tester",
    "iPhone model",
    "iOS version",
    "Apple Watch model",
    "watchOS version",
    "Pairing state",
    "Apple ID / tester group",
    "Sentry release",
    "UAT date",
]

required_journeys = [
    "testflight.install-update",
    "onboard.healthkit-grant",
    "onboard.healthkit-deny",
    "onboard.healthkit-skip",
    "onboard.voice-mic",
    "permissions.notifications-explicit",
    "profile.sign-in-with-apple",
    "profile.appearance-toggle",
    "settings.diagnostics",
    "premium.purchase-restore",
    "workouts.builder-manual",
    "workouts.builder-coach",
    "workouts.active-edit",
    "workouts.equipment-busy",
    "workouts.skip-replace",
    "workouts.exercise-diagram",
    "resilience.force-quit-onboarding",
    "resilience.force-quit-active-workout",
    "resilience.force-quit-coach-turn",
    "watch.install-launch",
    "watch.start-workout",
    "watch.log-set",
    "watch.coach-cue",
    "watch.action-decision",
    "resilience.wc-interrupt-midpayload",
    "resilience.wc-reconnect-replay",
    "notifications.delivery-tap",
    "widget.add-small",
    "widget.add-medium",
    "liveactivity.start",
    "liveactivity.dynamic-island",
    "liveactivity.end",
    "coach.safety-redflag-live",
    "coach.recovery-live",
    "signals.readiness-prescription",
]

required_signoffs = [
    "Product",
    "Design",
    "Engineering",
    "AI safety",
    "Security/privacy",
]


def split_markdown_row(line: str) -> list[str]:
    cells = [cell.strip() for cell in line.split("|")]
    if cells and cells[0] == "":
        cells = cells[1:]
    if cells and cells[-1] == "":
        cells = cells[:-1]
    return cells


build_values: dict[str, str] = {}
journey_rows: dict[str, tuple[str, str]] = {}
signoff_rows: dict[str, tuple[str, str, str]] = {}


def evidence_is_incomplete(value: str) -> bool:
    if not value or placeholder_re.search(value) is not None:
        return True
    return template_evidence_re.search(value) is not None and concrete_evidence_re.search(value) is None


def expected_commit_sha() -> str | None:
    explicit = os.environ.get("VOLUMEARC_RELEASE_CANDIDATE_SHA", "").strip()
    if explicit:
        return explicit
    if os.environ.get("VOLUMEARC_RELEASE_READY", "").strip() == "1":
        failures.append(
            "VOLUMEARC_RELEASE_CANDIDATE_SHA must be set in release-ready mode "
            "so UAT evidence is bound to the exact TestFlight build under review"
        )
    return None

for line_number, raw_line in enumerate(text.splitlines(), start=1):
    line = raw_line.strip()
    if not line.startswith("|"):
        continue
    if re.match(r"^\|\s*-+\s*\|", line):
        continue

    cells = split_markdown_row(line)
    if len(cells) < 2:
        continue

    if len(cells) == 2 and cells[0] in required_build_fields:
        build_values[cells[0]] = cells[1]
        continue

    first = cells[0].strip()
    if first.startswith("`") and first.endswith("`") and len(cells) >= 3:
        journey_id = first.strip("`")
        journey_rows[journey_id] = (cells[1], cells[2])
        continue

    if first in required_signoffs and len(cells) >= 4:
        signoff_rows[first] = (cells[1], cells[2], cells[3])

for field in required_build_fields:
    value = build_values.get(field)
    if value is None:
        failures.append(f"missing build evidence field '{field}'")
    elif not value or placeholder_re.search(value):
        failures.append(f"build evidence field '{field}' is incomplete: {value!r}")

commit_value = build_values.get("Commit SHA", "").strip()
expected_commit = expected_commit_sha()
if commit_value and expected_commit and not placeholder_re.search(commit_value):
    if commit_value != expected_commit and not expected_commit.startswith(commit_value):
        failures.append(
            "build evidence field 'Commit SHA' does not match this release candidate: "
            f"{commit_value!r} != {expected_commit!r}"
        )

for journey_id in required_journeys:
    row = journey_rows.get(journey_id)
    if row is None:
        failures.append(f"missing required UAT journey '{journey_id}'")
        continue
    status, evidence = row
    if status != "Pass":
        failures.append(f"journey '{journey_id}' status must be Pass, got {status!r}")
    if evidence_is_incomplete(evidence):
        failures.append(f"journey '{journey_id}' evidence is incomplete: {evidence!r}")

for area in required_signoffs:
    row = signoff_rows.get(area)
    if row is None:
        failures.append(f"missing signoff area '{area}'")
        continue
    status, owner, evidence = row
    if status != "Approved":
        failures.append(f"signoff '{area}' status must be Approved, got {status!r}")
    if not owner or placeholder_re.search(owner):
        failures.append(f"signoff '{area}' owner is incomplete: {owner!r}")
    if evidence_is_incomplete(evidence):
        failures.append(f"signoff '{area}' evidence is incomplete: {evidence!r}")

if failures:
    print(f"FAIL: release UAT evidence is incomplete ({len(failures)} failure(s))", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)

print(
    "Release UAT evidence gate passed: "
    f"{len(required_build_fields)} build fields, "
    f"{len(required_journeys)} journeys, "
    f"{len(required_signoffs)} signoffs."
)
PY
