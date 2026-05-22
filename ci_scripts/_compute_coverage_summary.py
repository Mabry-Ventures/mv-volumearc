"""Coverage-summary writer for VolumeArc's CI gate.

VOL-52 introduced the single-target gate on VolumeArcCore. VOL-97
added the machine-readable summary JSON. VOL-140 Phase 1 extends the
summary to include *every* non-test target xccov reports so the
sticky PR comment and metrics-branch trend can track them all — even
the ones that aren't gated yet.

Why this lives in its own file (not inlined into `check_coverage.sh`):

  The original implementation embedded the Python via
  `python3 -c "$(cat <<'PY' ... PY)"`. That pattern is fragile on
  bash 3.2 (macOS default) — bash's command-substitution parser
  pre-scans the body for balanced parens and quotes *even inside a
  single-quoted heredoc*, so any Python feature that uses `(...)`
  alternation or multi-line triple-quoted strings can trip an EOF
  parse error. Pulling the Python into a standalone file removes
  that constraint entirely and lets us write idiomatic code.

The shell wrapper invokes us as:

    xcrun xccov view --report --json "$XCRESULT" \
      | python3 scripts/_compute_coverage_summary.py

with TARGET, THRESHOLD, SUMMARY_JSON in the environment.
"""

import json
import os
import sys


# VOL-140 Phase 1: filter out test targets — their "coverage" isn't
# the kind we ship. Anything ending in these suffixes (case-insensitive)
# is dropped from the per-target rows.
TEST_TARGET_SUFFIXES = ("tests", "testsupport", "uitests-runner")


def looks_like_test_target(name: str) -> bool:
    lowered = name.lower()
    return any(lowered.endswith(suffix) for suffix in TEST_TARGET_SUFFIXES)


def normalize_target_name(raw_name: str) -> str:
    """Strip Xcode's `lib*.a` / `*.framework` decorations so per-target
    rows use the bare module name. Mirrors the lookup logic that
    matches the primary gated target."""
    if raw_name.startswith("lib") and raw_name.endswith(".a"):
        return raw_name[3:-2]
    if raw_name.endswith(".framework"):
        return raw_name[: -len(".framework")]
    return raw_name


def trim_path(path: str) -> str:
    """xccov reports absolute paths on the build host; trim to a
    stable repo-relative suffix when possible for sticky-comment
    readability."""
    marker = "/VolumeArcNative/"
    if marker in path:
        return "VolumeArcNative/" + path.split(marker, 1)[1]
    return path


def uncovered_count(entry: dict) -> int:
    executable = entry.get("executableLines", 0) or 0
    covered = entry.get("coveredLines", 0) or 0
    return max(executable - covered, 0)


def build_top_uncovered(target_entry: dict) -> list[dict]:
    files = target_entry.get("files", []) or []
    ranked = sorted(
        files,
        key=lambda entry: (
            uncovered_count(entry),
            entry.get("executableLines", 0) or 0,
        ),
        reverse=True,
    )
    rows = []
    for entry in ranked[:10]:
        executable = entry.get("executableLines", 0) or 0
        line_cov = round((entry.get("lineCoverage", 0.0) or 0.0) * 100, 2)
        raw_path = entry.get("path") or entry.get("name") or "(unknown)"
        rows.append(
            {
                "path": trim_path(raw_path),
                "uncovered": uncovered_count(entry),
                "executable": executable,
                "coverage": line_cov,
            }
        )
    return rows


def main() -> int:
    target_name = os.environ["TARGET"]
    threshold = float(os.environ["THRESHOLD"])
    summary_path = os.environ["SUMMARY_JSON"]

    # VolumeArcCore is built as a static library, so xccov reports the
    # target as 'libVolumeArcCore.a'. Accept either form so the gate
    # works whether we ever migrate to a framework target later.
    candidates = {
        target_name,
        "lib" + target_name + ".a",
        target_name + ".framework",
    }

    data = json.load(sys.stdin)

    primary_target_entry = None
    per_target_rows = []
    for entry in data.get("targets", []) or []:
        raw_name = entry.get("name", "")
        bare_name = normalize_target_name(raw_name)
        if looks_like_test_target(bare_name):
            continue

        coverage_value = entry.get("lineCoverage", 0.0) or 0.0
        executable = entry.get("executableLines", 0) or 0
        covered = entry.get("coveredLines", 0) or 0
        coverage_pct = round(coverage_value * 100, 2)

        row = {
            "target": bare_name,
            "coverage": coverage_pct,
            "executable": executable,
            "covered": covered,
            "gated": False,
        }

        if raw_name in candidates or raw_name.startswith(target_name + "."):
            primary_target_entry = entry
            row["gated"] = True
            row["threshold"] = threshold
            row["passed"] = coverage_pct + 1e-9 >= threshold

        per_target_rows.append(row)

    # Sort: gated target first, then by coverage descending so the
    # most well-tested modules surface first in tables.
    per_target_rows.sort(key=lambda r: (not r["gated"], -r["coverage"]))

    primary_coverage = 0.0
    top_uncovered = []
    if primary_target_entry is not None:
        primary_coverage = round(
            primary_target_entry.get("lineCoverage", 0.0) * 100, 2
        )
        top_uncovered = build_top_uncovered(primary_target_entry)

    passed = primary_coverage + 1e-9 >= threshold

    payload = {
        # Top-level fields — back-compat with VOL-52's single-target
        # contract. CI's sticky comment and metrics-branch ingestor
        # still read these directly.
        "target": target_name,
        "coverage": primary_coverage,
        "threshold": threshold,
        "passed": passed,
        "topUncovered": top_uncovered,
        # VOL-140 Phase 1 addition.
        "targets": per_target_rows,
    }
    with open(summary_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
