#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_TREND_PATH="${COACH_EVAL_TREND_PATH:-$ROOT/docs/coach-eval-trend.json}"
MARKETING_TREND_PATH="${COACH_EVAL_MARKETING_TREND_PATH:-$ROOT/marketing/src/data/coach-eval-trend.json}"

if [[ ! -f "$DOCS_TREND_PATH" ]]; then
  echo "FAIL: coach eval trend file missing at $DOCS_TREND_PATH" >&2
  exit 1
fi

if [[ ! -f "$MARKETING_TREND_PATH" ]]; then
  echo "FAIL: marketing coach eval trend mirror missing at $MARKETING_TREND_PATH" >&2
  exit 1
fi

python3 - "$DOCS_TREND_PATH" "$MARKETING_TREND_PATH" <<'PY'
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

docs_path = Path(sys.argv[1])
marketing_path = Path(sys.argv[2])
expected_total = int(os.environ.get("COACH_EVAL_EXPECTED_TOTAL", "47"))
max_age_days = int(os.environ.get("COACH_EVAL_MAX_AGE_DAYS", "7"))
now_override = os.environ.get("COACH_EVAL_NOW")
required_sha = os.environ.get("COACH_EVAL_REQUIRED_SHA", "").strip()
fixture_dir = Path(
    os.environ.get(
        "COACH_EVAL_FIXTURE_DIR",
        str(docs_path.parent.parent / "Tests" / "Evals" / "CoachEvalFixtures"),
    )
)
failures: list[str] = []


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        failures.append(f"{path} is not valid JSON: {error}")
        return {}


def parse_timestamp(value: Any, label: str) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        failures.append(f"{label} timestamp is missing")
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        failures.append(f"{label} timestamp is invalid: {value!r}")
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


docs_data = load_json(docs_path)
marketing_data = load_json(marketing_path)

if docs_data != marketing_data:
    failures.append(
        "docs/coach-eval-trend.json and marketing/src/data/coach-eval-trend.json "
        "must be semantic mirrors"
    )

records = docs_data.get("records") if isinstance(docs_data, dict) else None
if not isinstance(records, list) or not records:
    failures.append("coach eval trend must contain a non-empty records array")
    records = []

latest_record: dict[str, Any] | None = None
latest_timestamp: datetime | None = None
for index, record in enumerate(records):
    if not isinstance(record, dict):
        failures.append(f"records[{index}] must be an object")
        continue
    timestamp = parse_timestamp(record.get("timestamp"), f"records[{index}]")
    if timestamp is not None and (latest_timestamp is None or timestamp > latest_timestamp):
        latest_timestamp = timestamp
        latest_record = record

if latest_record is None:
    failures.append("coach eval trend has no record with a parseable timestamp")
else:
    total = latest_record.get("total")
    passed = latest_record.get("passed")
    failed = latest_record.get("failed")
    if total != expected_total:
        failures.append(f"latest coach eval total must be {expected_total}, got {total!r}")
    if passed != expected_total:
        failures.append(f"latest coach eval passed must be {expected_total}, got {passed!r}")
    if failed != 0:
        failures.append(f"latest coach eval failed must be 0, got {failed!r}")

    sha = str(latest_record.get("sha", "")).strip()
    if not sha:
        failures.append("latest coach eval record must include a commit sha")
    elif required_sha and sha != required_sha:
        failures.append(
            f"latest coach eval record sha must match COACH_EVAL_REQUIRED_SHA "
            f"{required_sha}, got {sha}"
        )

    run_id = str(latest_record.get("run_id", "")).strip()
    if not run_id:
        failures.append("latest coach eval record must include a run_id")

    fixtures = latest_record.get("fixtures")
    if not isinstance(fixtures, list):
        failures.append("latest coach eval record must include a fixtures array")
        fixtures = []
    if len(fixtures) != expected_total:
        failures.append(
            f"latest coach eval fixture count must be {expected_total}, got {len(fixtures)}"
        )
    fixture_ids: set[str] = set()
    for index, fixture in enumerate(fixtures):
        if not isinstance(fixture, dict):
            failures.append(f"latest fixtures[{index}] must be an object")
            continue
        fixture_id = str(fixture.get("id", "")).strip()
        if not fixture_id:
            failures.append(f"latest fixtures[{index}] is missing id")
        elif fixture_id in fixture_ids:
            failures.append(f"latest fixture id is duplicated: {fixture_id}")
        else:
            fixture_ids.add(fixture_id)
        verdict = fixture.get("verdict")
        if verdict != "PASS":
            failures.append(
                f"latest fixture {fixture_id or index!r} verdict must be PASS, got {verdict!r}"
            )
    if not fixture_dir.is_dir():
        failures.append(f"coach eval fixture directory missing at {fixture_dir}")
    else:
        fixture_paths = sorted(fixture_dir.glob("*.json"))
        expected_fixture_ids: set[str] = set()
        if len(fixture_paths) != expected_total:
            failures.append(
                f"coach eval fixture catalog must contain {expected_total} JSON fixtures, "
                f"got {len(fixture_paths)}"
            )
        for path in fixture_paths:
            try:
                fixture_payload = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as error:
                failures.append(f"coach eval fixture {path.name} is not valid JSON: {error}")
                continue
            fixture_id = str(fixture_payload.get("id", "")).strip() if isinstance(fixture_payload, dict) else ""
            if not fixture_id:
                failures.append(f"coach eval fixture {path.name} is missing id")
                continue
            if fixture_id in expected_fixture_ids:
                failures.append(f"coach eval fixture id is duplicated: {fixture_id}")
            expected_fixture_ids.add(fixture_id)
        missing_fixture_ids = sorted(expected_fixture_ids - fixture_ids)
        unexpected_fixture_ids = sorted(fixture_ids - expected_fixture_ids)
        if missing_fixture_ids:
            failures.append(
                "latest coach eval record is missing fixture IDs: "
                + ", ".join(missing_fixture_ids)
            )
        if unexpected_fixture_ids:
            failures.append(
                "latest coach eval record contains unknown fixture IDs: "
                + ", ".join(unexpected_fixture_ids)
            )

    axes = latest_record.get("axes")
    if not isinstance(axes, dict):
        failures.append("latest coach eval record must include axes")
    else:
        for axis_name, axis_rows in axes.items():
            if not isinstance(axis_rows, list):
                failures.append(f"latest axes.{axis_name} must be an array")
                continue
            for index, row in enumerate(axis_rows):
                if not isinstance(row, dict):
                    failures.append(f"latest axes.{axis_name}[{index}] must be an object")
                    continue
                label = row.get("label", index)
                row_total = row.get("total")
                row_passed = row.get("passed")
                row_failed = row.get("failed")
                if row_failed != 0:
                    failures.append(
                        f"latest axes.{axis_name}.{label} failed must be 0, got {row_failed!r}"
                    )
                if row_total != row_passed:
                    failures.append(
                        f"latest axes.{axis_name}.{label} total/pass mismatch: "
                        f"{row_total!r}/{row_passed!r}"
                    )

    if now_override:
        now = parse_timestamp(now_override, "COACH_EVAL_NOW")
    else:
        now = datetime.now(timezone.utc)
    if now is not None and latest_timestamp is not None:
        age_seconds = (now - latest_timestamp).total_seconds()
        if age_seconds < -300:
            failures.append(
                f"latest coach eval timestamp is in the future: "
                f"{latest_timestamp.isoformat()}"
            )
        max_age_seconds = max_age_days * 24 * 60 * 60
        if age_seconds > max_age_seconds:
            age_days = age_seconds / (24 * 60 * 60)
            failures.append(
                f"latest coach eval trend is stale: {age_days:.1f} days old "
                f"(max {max_age_days})"
            )

if failures:
    print(f"FAIL: coach eval trend is not release-ready ({len(failures)} failure(s))", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)

assert latest_record is not None
assert latest_timestamp is not None
print(
    "Coach eval trend gate passed: "
    f"{expected_total}/{expected_total} fixtures, "
    f"run {latest_record.get('run_id')}, "
    f"timestamp {latest_record.get('timestamp')}."
)
PY
