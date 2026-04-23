#!/usr/bin/env bash
# VOL-52: enforce a hard 80% line-coverage gate on the VolumeArcCore
# module. Run `./scripts/test_apple_targets.sh` first so an xcresult
# exists; this script parses the bundle with `xcrun xccov view --report
# --json` and exits non-zero when the module's line coverage drops
# below the threshold. Override the threshold or target name via
# `COVERAGE_THRESHOLD` and `COVERAGE_TARGET` for diagnostic runs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/derived-data}"
XCRESULT="${XCRESULT:-$DERIVED_DATA_PATH/TestResults.xcresult}"
THRESHOLD="${COVERAGE_THRESHOLD:-80}"
TARGET="${COVERAGE_TARGET:-VolumeArcCore}"

if [[ ! -d "$XCRESULT" ]]; then
  echo "FAIL: No xcresult bundle at $XCRESULT — did tests run with -enableCodeCoverage YES?" >&2
  exit 1
fi

coverage_json=$(xcrun xccov view --report --json "$XCRESULT")

target_coverage=$(echo "$coverage_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
target_name = '$TARGET'
# VolumeArcCore is built as a static library, so xccov reports the
# target as 'libVolumeArcCore.a' rather than the bare module name.
# Accept either form so the gate works whether we ever migrate to a
# framework target later.
candidates = {target_name, f'lib{target_name}.a', f'{target_name}.framework'}
for target in data.get('targets', []):
    name = target.get('name', '')
    if name in candidates or name.startswith(target_name + '.'):
        print(round(target.get('lineCoverage', 0) * 100, 2))
        sys.exit(0)
print('0')
sys.exit(1)
")

echo "VolumeArcCore line coverage: ${target_coverage}% (threshold: ${THRESHOLD}%)"

awk -v cov="$target_coverage" -v thr="$THRESHOLD" 'BEGIN { exit (cov + 0 < thr + 0) ? 1 : 0 }' || {
  echo "FAIL: Coverage ${target_coverage}% is below required ${THRESHOLD}%" >&2
  exit 1
}

echo "Coverage gate passed."
