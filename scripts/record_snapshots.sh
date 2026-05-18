#!/usr/bin/env bash
# VOL-201 Phase 1: snapshot-baseline record helper.
#
# Runs the snapshot-test suite in record mode so every `assertSnapshot`
# call writes (or overwrites) its baseline PNG under
# `Tests/VolumeArcAppTests/Snapshots/__Snapshots__/`. Commit the
# regenerated PNGs in the same PR that touched the surface being
# snapshotted.
#
# Usage:
#
#   # Record every snapshot in the suite (use on a fresh checkout):
#   ./scripts/record_snapshots.sh
#
#   # Record only one test class:
#   SNAPSHOT_TEST_FILTER=VolumeArcPaywallSnapshotTests ./scripts/record_snapshots.sh
#
# Important: this script pins the simulator OS to the value in
# `SNAPSHOT_SIMULATOR_OS` (default 26.5) because pointfreeco
# SnapshotTesting captures pixel-identical baselines that drift
# between simulator OS minor versions. The same OS must be used
# for CI runs that assert against the committed baselines. CI's
# `.github/workflows/ci.yml` pins the same value via the
# `xcodebuild -destination` argument.
#
# Why a helper script vs. a one-liner:
#
# `swift-snapshot-testing` toggles record mode in two ways:
#   1. The `SNAPSHOT_TESTING_RECORD_MODE=all` env var.
#   2. Per-call `record: .all` arguments in the test source.
# Option 1 is global + non-invasive; option 2 leaks into source
# and gets accidentally committed. This script uses option 1.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="${SNAPSHOT_TEST_SCHEME:-VolumeArcAppTests}"
SIMULATOR_NAME="${SNAPSHOT_SIMULATOR_NAME:-iPhone 17}"
SIMULATOR_OS="${SNAPSHOT_SIMULATOR_OS:-26.5}"
TEST_FILTER="${SNAPSHOT_TEST_FILTER:-}"

destination="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=${SIMULATOR_OS}"

echo "Recording snapshot baselines:"
echo "  scheme:      $SCHEME"
echo "  destination: $destination"
echo "  filter:      ${TEST_FILTER:-<all>}"
echo "  output dir:  Tests/VolumeArcAppTests/Snapshots/__Snapshots__/"
echo ""

xcodebuild_args=(
  -project VolumeArcApple.xcodeproj
  -scheme "$SCHEME"
  -destination "$destination"
  test
)
if [[ -n "$TEST_FILTER" ]]; then
  xcodebuild_args+=(-only-testing:"$SCHEME/$TEST_FILTER")
fi

# `SNAPSHOT_TESTING_RECORD_MODE=all` writes a baseline for every
# `assertSnapshot` call, overwriting any existing one. Use `missing`
# to write only baselines that don't yet exist (safer for incremental
# additions); the helper defaults to `all` because the common case
# for invoking this is "I just touched a UI surface, regenerate
# everything for that family."
SNAPSHOT_TESTING_RECORD_MODE="${SNAPSHOT_TESTING_RECORD_MODE:-all}" \
  xcodebuild "${xcodebuild_args[@]}"

echo ""
echo "Done. Review the changes under Tests/VolumeArcAppTests/Snapshots/__Snapshots__/"
echo "and commit them in the same PR as the surface change."
