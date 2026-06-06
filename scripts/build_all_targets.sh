#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby "scripts/generate_xcode_project.rb"

# VOL-88: pinning DerivedData to the workspace keeps local developer
# runs and CI runner jobs isolated from global Xcode caches. Overridable
# via `DERIVED_DATA_PATH` env var.
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/derived-data}"
mkdir -p "$DERIVED_DATA_PATH"

# SwiftPM binary targets such as Sentry keep downloaded XCFrameworks under
# SourcePackages/artifacts. Deleting that directory immediately before
# `xcodebuild build` can leave the resolved package graph pointing at a
# missing XCFramework path, so keep it by default and make destructive cache
# cleanup an explicit operator action.
SPM_ARTIFACTS_PATH="$DERIVED_DATA_PATH/SourcePackages/artifacts"
if [ "${VOLUMEARC_CLEAR_SPM_ARTIFACTS:-0}" = "1" ] && [ -d "$SPM_ARTIFACTS_PATH" ]; then
  echo "Clearing SwiftPM binary artifacts at $SPM_ARTIFACTS_PATH"
  rm -rf "$SPM_ARTIFACTS_PATH"
fi

"$ROOT/scripts/hydrate_sentry_artifact.sh"

run_xcodebuild() {
  # Xcode 26.5 can briefly report hydrated SwiftPM binary artifacts as
  # missing when the first build runs from the same shell that regenerated the
  # project. A fresh shell keeps the generated-project build path deterministic.
  /usr/bin/env bash -lc 'cd "$1"; shift; xcodebuild "$@"' _ "$ROOT" "$@"
}

source "$ROOT/scripts/simulators.sh"
IOS_BUILD_DEVICE="$(resolve_ios_test_device)"

run_xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcApp" \
  -destination "platform=iOS Simulator,name=$IOS_BUILD_DEVICE" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  build

run_xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcWidgets" \
  -destination "platform=iOS Simulator,name=$IOS_BUILD_DEVICE" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  build

run_xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcWatchWidgets" \
  -sdk watchsimulator \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  build

run_xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcWatch" \
  -sdk watchsimulator \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO \
  build
