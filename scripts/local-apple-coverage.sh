#!/usr/bin/env bash
# Preserve the former native CI ratchets after local build/test qualification.
set -euo pipefail
cd "$(dirname "$0")/.."
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/.build/derived-data}"
export DERIVED_DATA_PATH
COVERAGE_TARGET=VolumeArcCore COVERAGE_THRESHOLD=80 \
  COVERAGE_SUMMARY_JSON=.build/coverage-summary.json scripts/check_coverage.sh
COVERAGE_TARGET=VolumeArcUI COVERAGE_THRESHOLD=18 \
  COVERAGE_SUMMARY_JSON=.build/coverage-summary-volumearcui.json scripts/check_coverage.sh
XCRESULT="$DERIVED_DATA_PATH/TestResults-watch.xcresult" \
  COVERAGE_TARGET=VolumeArcCoreWatch COVERAGE_THRESHOLD=25 \
  COVERAGE_SUMMARY_JSON=.build/coverage-summary-volumearcwatch.json scripts/check_coverage.sh
COVERAGE_TARGET=VolumeArcWidgets COVERAGE_THRESHOLD=5 \
  COVERAGE_FILE_CONTAINS=Widgets/VolumeArcWidgets.swift \
  COVERAGE_SUMMARY_JSON=.build/coverage-summary-volumearcwidgets.json scripts/check_coverage.sh
JOURNEY_COVERAGE_THRESHOLD=56 scripts/check_journey_coverage.sh
