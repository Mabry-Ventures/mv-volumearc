#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# VOL-177 Phase 2A: `--no-build` mode skips the SPM resolve + xcodebuild
# `-showBuildSettings` block (the bottom half of this script) and only
# runs the static plist/entitlement/source-grep assertions. The full
# CI lane still runs without the flag. Wired into lefthook's
# `release-config` pre-commit slot so `git commit` runs the static
# subset in <2s. Anything that needs a real build setting (signing
# identity, deployment target, Sentry SPM version) stays in the CI-only
# set.
NO_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --no-build) NO_BUILD=1 ;;
    --help|-h)
      cat <<HELP
Usage: $(basename "$0") [--no-build]

  (default)   Full check: static assertions + SPM resolve + xcodebuild
              -showBuildSettings drift checks. Used by CI. Takes ~45-60s
              on a warm runner.
  --no-build  Static-only subset (entitlements, PrivacyInfo, Info.plist,
              app-group, CloudKit container source-grep). Skips xcodebuild,
              the ruby project regen, and the SPM resolve. Used by the
              lefthook pre-commit slot. Targets <2s.
HELP
      exit 0
      ;;
    *)
      echo "FAIL: unknown argument: $arg (use --help)" >&2
      exit 64
      ;;
  esac
done

# VOL-75 P2: match per-job DerivedData used by build_all_targets.sh and
# test_apple_targets.sh so xcodebuild -showBuildSettings can reach the
# SPM artifacts those builds resolved. Without this, -showBuildSettings
# falls back to system DerivedData (empty in CI) and fails with "file
# not found at path: .../sentry-cocoa/.../xcframework.zip".
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/.build/derived-data}"
mkdir -p "$DERIVED_DATA_PATH"

# VOL-177: in --no-build mode, skip the regen — the static checks below
# read source-tree files directly (entitlements, PrivacyInfo, app-group,
# the CloudKit container constant) and don't depend on a freshly
# generated pbxproj. Saves the 1-2s regen cost.
if [ "$NO_BUILD" -eq 0 ]; then
  ruby "scripts/generate_xcode_project.rb" >/dev/null
fi

PROJECT="VolumeArcApple.xcodeproj/project.pbxproj"

for path in \
  "App/VolumeArc.Debug.entitlements" \
  "App/VolumeArc.Release.entitlements" \
  "Watch/VolumeArcWatch.entitlements" \
  "WatchWidgets/VolumeArcWatchWidgets.entitlements" \
  "Widgets/VolumeArcWidgets.entitlements"; do
  [[ -f "$path" ]] || {
    echo "Missing required entitlement file: $path" >&2
    exit 1
  }
done

# VOL-73: every target must ship a well-formed PrivacyInfo.xcprivacy
# with at minimum a non-empty NSPrivacyAccessedAPITypes array (even
# widget extensions touch UserDefaults via the shared app-group
# snapshot, so every target has at least one declared reason).
# Apple rejects submissions on missing or malformed manifests, so this
# check is hard-failing.
for path in \
  "App/PrivacyInfo.xcprivacy" \
  "Watch/PrivacyInfo.xcprivacy" \
  "WatchWidgets/PrivacyInfo.xcprivacy" \
  "Widgets/PrivacyInfo.xcprivacy"; do
  [[ -f "$path" ]] || {
    echo "FAIL: Missing required privacy manifest: $path" >&2
    exit 1
  }
  if ! plutil -lint "$path" >/dev/null; then
    echo "FAIL: $path is not a valid plist" >&2
    exit 1
  fi
  api_count="$(plutil -extract NSPrivacyAccessedAPITypes raw -o - "$path" 2>/dev/null || echo "")"
  if [[ -z "$api_count" || "$api_count" -lt 1 ]]; then
    echo "FAIL: $path missing or empty NSPrivacyAccessedAPITypes" >&2
    exit 1
  fi
  # NSPrivacyCollectedDataTypes must exist (may be an empty array for
  # passive extensions like widgets) so App Store Connect doesn't
  # reject on a missing key. plutil returns the array count on success.
  if ! plutil -extract NSPrivacyCollectedDataTypes raw -o - "$path" >/dev/null 2>&1; then
    echo "FAIL: $path missing NSPrivacyCollectedDataTypes key" >&2
    exit 1
  fi
done

for ent_path in "App/VolumeArc.Debug.entitlements" "App/VolumeArc.Release.entitlements"; do
  if ! grep -q "aps-environment" "$ent_path"; then
    echo "WARNING: aps-environment not found in $ent_path — push notifications will not work" >&2
  fi
done

# VOL-70: Release entitlements must use production APS environment so
# Release-signed IPAs don't get rejected by App Store Connect or
# silently drop remote notifications. Debug stays `development` so
# APNs sandbox tokens still work locally.
if [[ -f "App/VolumeArc.Release.entitlements" ]]; then
  APS_ENV=$(plutil -extract "aps-environment" raw -o - "App/VolumeArc.Release.entitlements" 2>/dev/null || echo "")
  if [[ "$APS_ENV" != "production" ]]; then
    echo "FAIL: App/VolumeArc.Release.entitlements must declare aps-environment = production (got '$APS_ENV')" >&2
    exit 1
  fi
fi

if [[ -f "App/VolumeArc.Debug.entitlements" ]]; then
  APS_ENV_DEBUG=$(plutil -extract "aps-environment" raw -o - "App/VolumeArc.Debug.entitlements" 2>/dev/null || echo "")
  if [[ "$APS_ENV_DEBUG" != "development" ]]; then
    echo "FAIL: App/VolumeArc.Debug.entitlements must declare aps-environment = development (got '$APS_ENV_DEBUG')" >&2
    exit 1
  fi
fi

for forbidden in "DemoFixtures" "DemoServices" "VolumeArcDemoSupport"; do
  if grep -F -n "$forbidden" "$PROJECT" >/dev/null; then
    echo "Generated Xcode project unexpectedly references demo-only symbol: $forbidden" >&2
    exit 1
  fi
done

# VOL-55: the CloudKit container identifier now lives as a compile-time
# constant in `App/VolumeArcCloudConfiguration.swift` instead of an
# Info.plist key. `INFOPLIST_KEY_*` silently drops custom keys that
# aren't Apple-recognized, so the plist-based approach never worked.
# Confirm the constant is present so no one silently deletes it.
if ! grep -F 'static let containerIdentifier: String = "iCloud.com.mabryventures.VolumeArc"' \
  App/VolumeArcCloudConfiguration.swift >/dev/null; then
  echo "FAIL: VolumeArcCloudConfiguration.containerIdentifier constant is missing or changed" >&2
  exit 1
fi

# VOL-233: the watch app starts an `HKWorkoutSession` with
# `HKLiveWorkoutDataSource`. Without workout-processing background mode,
# live capture can pass simulator tests but stop behaving correctly on
# a real watch as soon as the app backgrounds during an active session.
if ! plutil -extract WKBackgroundModes xml1 -o - Watch/Info.plist 2>/dev/null |
  grep -q '<string>workout-processing</string>'; then
  echo "FAIL: Watch/Info.plist must declare WKBackgroundModes = workout-processing for live HealthKit workouts" >&2
  exit 1
fi

# VOL-125: App Store Connect rejects Siri/App Intent descriptions that
# include "Apple" trademark wording. Build 255 hit ITMS-90626 for
# "Apple Watch Ultra Action Button" in an Action Button intent
# description. Keep this in the cheap static gate so release builds
# fail before another binary upload.
if ! ruby <<'RUBY'
paths = [
  "App/Intents/VolumeArcIntents.swift",
  "Watch/WatchActionButtonIntents.swift",
]

failures = []

paths.each do |path|
  next unless File.file?(path)

  lines = File.readlines(path)
  line_index = 0
  while line_index < lines.length
    line = lines[line_index]
    unless line.include?("IntentDescription(")
      line_index += 1
      next
    end

    start_line = line_index + 1
    block = +""
    depth = 0

    begin
      current = lines[line_index]
      block << current
      depth += current.count("(")
      depth -= current.count(")")
      line_index += 1
    end while line_index < lines.length && depth.positive?

    failures << "#{path}:#{start_line}" if block.match?(/apple/i)
  end
end

if failures.any?
  warn "FAIL: App Intent descriptions must not contain Apple trademark wording (ITMS-90626):"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end
RUBY
then
  exit 1
fi

# VOL-216 / VOL-125: ASC metadata readiness gate. Soft-warns by default so a
# regen / smoke run during everyday development doesn't trip on
# in-progress metadata drafts. When `VOLUMEARC_RELEASE_READY=1` is
# set (release readiness check, `fastlane ios release` precondition,
# or operator manually proving "we're submission-ready"), any file under
# `fastlane/metadata/en-US/` that still contains `TBD` or `ACTION REQUIRED`
# becomes a hard fail with the file list.
metadata_dir="fastlane/metadata/en-US"
if [[ -d "$metadata_dir" ]]; then
  draft_blocker_files=$(/usr/bin/grep -Erl "TBD|ACTION REQUIRED" "$metadata_dir" 2>/dev/null || true)
  if [[ -n "$draft_blocker_files" ]]; then
    if [[ "${VOLUMEARC_RELEASE_READY:-0}" == "1" ]]; then
      echo "FAIL: App Store Connect metadata still contains draft blockers (VOLUMEARC_RELEASE_READY=1 active):" >&2
      while IFS= read -r draft_blocker_file; do
        echo "  - $draft_blocker_file" >&2
      done <<<"$draft_blocker_files"
      echo "Resolve every TBD/ACTION REQUIRED marker before running 'fastlane ios release' or marking the submission as ready." >&2
      exit 1
    else
      echo "INFO: $metadata_dir has $(echo "$draft_blocker_files" | wc -l | tr -d ' ') file(s) with draft blockers. Set VOLUMEARC_RELEASE_READY=1 to enforce."
    fi
  else
    echo "App Store Connect metadata: no TBD/ACTION REQUIRED markers remaining in $metadata_dir."
  fi
fi

# Physical-device and TestFlight-only evidence is intentionally separate
# from simulator journey coverage. In everyday development this remains
# informational; in release-ready mode it becomes a hard stop so a GA
# candidate cannot be called ready without paired iPhone/Watch UAT,
# TestFlight, purchase, notification, widget, Live Activity, and live coach
# safety proof on the exact build under review.
if [[ "${VOLUMEARC_RELEASE_READY:-0}" == "1" ]]; then
  # Bind the eval evidence to the release candidate: the latest trend
  # record must have been produced on the exact commit under review, not
  # merely be fresh and green on some other commit.
  COACH_EVAL_REQUIRED_SHA="${COACH_EVAL_REQUIRED_SHA:-${VOLUMEARC_RELEASE_CANDIDATE_SHA:-}}" \
    "$ROOT/scripts/check_coach_eval_trend.sh"
  "$ROOT/scripts/check_release_uat_evidence.sh"
else
  echo "INFO: coach eval trend freshness/green-state not enforced. Set VOLUMEARC_RELEASE_READY=1 to require a current per-tier 55-fixture trend mirror."
  echo "INFO: release UAT evidence not enforced. Set VOLUMEARC_RELEASE_READY=1 to require docs/RELEASE_UAT_EVIDENCE.md."
fi

# VOL-177: --no-build exits here. Everything above is static file/text
# assertions that match what pre-commit can afford to run. Everything
# below shells to xcodebuild (5-10s per call) and is CI-only.
if [ "$NO_BUILD" -eq 1 ]; then
  echo "validate_release_config.sh --no-build: static assertions OK"
  exit 0
fi

# VOL-90: the canonical SPM lockfile lives at repo root; the workspace
# copy is seeded from it (by the ruby generator on every run and by CI
# before the build). If someone bumps a dependency version in the
# generator but forgets to refresh the tracked `Package.resolved` (or
# vice versa), this catches the drift before a build silently resolves
# a different version. Runs before the `-showBuildSettings` calls below
# because those fail opaquely on lockfile/requirement conflicts — this
# check surfaces the real reason.
ROOT_LOCKFILE="Package.resolved"
WORKSPACE_LOCKFILE="VolumeArcApple.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

[[ -f "$ROOT_LOCKFILE" ]] || {
  echo "FAIL: Missing root Package.resolved (canonical SPM lockfile, per VOL-90)" >&2
  exit 1
}

# Force a resolve after the generator seeded the workspace copy from
# root. If the generator's requirement conflicts with the root pin
# (e.g. someone bumped `sentry_requirement` in the generator but didn't
# refresh the tracked lockfile), xcodebuild will rewrite the workspace
# copy — which we then catch with the drift check below.
xcodebuild \
  -resolvePackageDependencies \
  -project "VolumeArcApple.xcodeproj" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  >/dev/null 2>&1 || true

if [[ ! -f "$WORKSPACE_LOCKFILE" ]]; then
  echo "FAIL: Workspace Package.resolved was not generated — xcodebuild -resolvePackageDependencies failed" >&2
  exit 1
fi

extract_sentry_field() {
  # $1 = file, $2 = field (version|revision)
  python3 -c "
import json, sys
with open('$1') as f:
    data = json.load(f)
pins = [p for p in data.get('pins', []) if p.get('identity') == 'sentry-cocoa']
if not pins:
    sys.exit(1)
print(pins[0]['state'].get('$2', ''))
" 2>/dev/null || echo ""
}

root_sentry_ver=$(extract_sentry_field "$ROOT_LOCKFILE" version)
root_sentry_rev=$(extract_sentry_field "$ROOT_LOCKFILE" revision)
ws_sentry_ver=$(extract_sentry_field "$WORKSPACE_LOCKFILE" version)
ws_sentry_rev=$(extract_sentry_field "$WORKSPACE_LOCKFILE" revision)

if [[ -z "$root_sentry_rev" || -z "$root_sentry_ver" ]]; then
  echo "FAIL: Root $ROOT_LOCKFILE missing sentry-cocoa pin" >&2
  exit 1
fi
if [[ -z "$ws_sentry_rev" || -z "$ws_sentry_ver" ]]; then
  echo "FAIL: Workspace $WORKSPACE_LOCKFILE missing sentry-cocoa pin" >&2
  exit 1
fi
if [[ "$root_sentry_ver" != "$ws_sentry_ver" || "$root_sentry_rev" != "$ws_sentry_rev" ]]; then
  echo "FAIL: sentry-cocoa pin drifted between root and workspace Package.resolved (VOL-90)" >&2
  echo "  root:      $root_sentry_ver @ $root_sentry_rev" >&2
  echo "  workspace: $ws_sentry_ver @ $ws_sentry_rev" >&2
  echo "  Refresh with:" >&2
  echo "    xcodebuild -resolvePackageDependencies -project VolumeArcApple.xcodeproj" >&2
  echo "    cp $WORKSPACE_LOCKFILE $ROOT_LOCKFILE" >&2
  exit 1
fi
echo "Package.resolved: root and workspace agree on sentry-cocoa $root_sentry_ver"

tmp_settings="$(mktemp)"
trap 'rm -f "$tmp_settings"' EXIT

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcApp" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  -skipPackagePluginValidation \
  -showBuildSettings >"$tmp_settings"

# VOL-56 (PR #24): `INFOPLIST_FILE = App/Info.plist` must stay wired so
# the plist on disk is actually merged into the built bundle. Without
# this assertion, removing the `INFOPLIST_FILE` line from
# `generate_xcode_project.rb` would silently fall back to the generated
# plist, drop CFBundleURLTypes/BGTaskSchedulerPermittedIdentifiers/
# UIBackgroundModes, and ship a broken app even though the source
# file on disk still has every key.
required_build_settings=(
  "PRODUCT_BUNDLE_IDENTIFIER = com.mabryventures.VolumeArc"
  "CODE_SIGN_ENTITLEMENTS = App/VolumeArc.Release.entitlements"
  "INFOPLIST_FILE = App/Info.plist"
  "INFOPLIST_KEY_NSHealthShareUsageDescription = VolumeArc reads your completed workouts, heart-rate variability, sleep, Workout Effort, wrist temperature, and respiratory rate from Apple Health to show your training history, calculate readiness, and ground your coach's strength prescriptions in your recovery trend (HRV vs baseline, sleep debt, weekly strength load, Vitals trends, and Training Load)."
  "INFOPLIST_KEY_NSHealthUpdateUsageDescription = VolumeArc writes completed workouts so your training history stays in sync with Apple Health."
  "INFOPLIST_KEY_NSMicrophoneUsageDescription = VolumeArc uses the microphone for voice coaching requests and voice workout logging."
  "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = VolumeArc uses speech recognition to understand live coaching requests and voice workout notes."
)

for required in "${required_build_settings[@]}"; do
  if ! grep -F "$required" "$tmp_settings" >/dev/null; then
    echo "Missing required app build setting: $required" >&2
    exit 1
  fi
done

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcWatch" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  -skipPackagePluginValidation \
  -showBuildSettings >"$tmp_settings"

watch_required=(
  "PRODUCT_BUNDLE_IDENTIFIER = com.mabryventures.VolumeArc.watchkitapp"
  "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon"
  "CODE_SIGN_ENTITLEMENTS = Watch/VolumeArcWatch.entitlements"
  "INFOPLIST_FILE = Watch/Info.plist"
  "INFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.mabryventures.VolumeArc"
)

for required in "${watch_required[@]}"; do
  if ! grep -F "$required" "$tmp_settings" >/dev/null; then
    echo "Missing required watch build setting: $required" >&2
    exit 1
  fi
done

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcWidgets" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  -skipPackagePluginValidation \
  -showBuildSettings >"$tmp_settings"

widget_required=(
  "PRODUCT_BUNDLE_IDENTIFIER = com.mabryventures.VolumeArc.widgets"
  "CODE_SIGN_ENTITLEMENTS = Widgets/VolumeArcWidgets.entitlements"
  "INFOPLIST_FILE = Widgets/Info.plist"
)

for required in "${widget_required[@]}"; do
  if ! grep -F "$required" "$tmp_settings" >/dev/null; then
    echo "Missing required widget build setting: $required" >&2
    exit 1
  fi
done

for widget_plist in "Widgets/Info.plist" "WatchWidgets/Info.plist"; do
  display_name="$(plutil -extract CFBundleDisplayName raw -o - "$widget_plist" 2>/dev/null || echo "")"
  if [[ "$display_name" != "VolumeArc" ]]; then
    echo "Missing CFBundleDisplayName=VolumeArc in $widget_plist" >&2
    exit 1
  fi

  extension_point="$(plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$widget_plist" 2>/dev/null || echo "")"
  if [[ "$extension_point" != "com.apple.widgetkit-extension" ]]; then
    echo "Missing WidgetKit extension point in $widget_plist" >&2
    exit 1
  fi
done

for watch_icon_asset in \
  "Watch/Info.plist" \
  "Watch/Assets.xcassets/Contents.json" \
  "Watch/Assets.xcassets/AccentColor.colorset/Contents.json" \
  "Watch/Assets.xcassets/AppIcon.appiconset/Contents.json" \
  "Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png"; do
  if [[ ! -f "$watch_icon_asset" ]]; then
    echo "FAIL: Missing watch app icon asset $watch_icon_asset" >&2
    exit 1
  fi
done

ruby scripts/validate_watch_app_icon_asset.rb

watch_icon_name="$(plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw -o - "Watch/Info.plist" 2>/dev/null || echo "")"
if [[ "$watch_icon_name" != "AppIcon" ]]; then
  echo "FAIL: Watch/Info.plist must declare CFBundleIconName=AppIcon" >&2
  exit 1
fi

watch_icon_file="$(plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles.0 raw -o - "Watch/Info.plist" 2>/dev/null || echo "")"
if [[ "$watch_icon_file" != "AppIcon" ]]; then
  echo "FAIL: Watch/Info.plist must declare CFBundleIconFiles with AppIcon" >&2
  exit 1
fi

# VolumeArcAppTests scheme has no build target (tests-only), so -scheme +
# -derivedDataPath would resolve against nothing. The tests target has no
# direct SPM deps of its own, so plain -target works and doesn't need the
# artifact cache.
xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -target "VolumeArcAppTests" \
  -configuration Debug \
  -showBuildSettings >"$tmp_settings"

test_required=(
  "PRODUCT_BUNDLE_IDENTIFIER = com.mabryventures.VolumeArc.tests"
)

for required in "${test_required[@]}"; do
  if ! grep -F "$required" "$tmp_settings" >/dev/null; then
    echo "Missing required app-test build setting: $required" >&2
    exit 1
  fi
done

# --- Deep release checks (hard-failing per VOL-45) ---

# Re-read app Release build settings for deeper checks
xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -scheme "VolumeArcApp" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA_PATH/SourcePackages" \
  -skipPackagePluginValidation \
  -showBuildSettings >"$tmp_settings"

# ENABLE_TESTABILITY must be NO in Release (allows debugger injection if YES).
if grep -F "ENABLE_TESTABILITY = YES" "$tmp_settings" >/dev/null 2>&1; then
  echo "FAIL: ENABLE_TESTABILITY is YES in Release — production builds cannot enable testability" >&2
  exit 1
fi

# Verify dSYM generation for crash reporting.
if ! grep -F "DEBUG_INFORMATION_FORMAT = dwarf-with-dsym" "$tmp_settings" >/dev/null 2>&1; then
  echo "FAIL: DEBUG_INFORMATION_FORMAT must be dwarf-with-dsym in Release for crash reporting" >&2
  exit 1
fi

# VOL-249: binary-hardening Release-only build-setting assertions.
#
# Each check fails on an *explicit unsafe override*, not on the setting's
# absence. The Xcode 26 defaults for a Release configuration are all safe
# (STRIP_INSTALLED_PRODUCT=YES, SWIFT_OPTIMIZATION_LEVEL=-O,
# GCC_OPTIMIZATION_LEVEL=s, ONLY_ACTIVE_ARCH=NO, DEAD_CODE_STRIPPING=YES,
# COPY_PHASE_STRIP=YES, ENABLE_BITCODE absent / NO), so the project
# generator doesn't currently set them explicitly. These assertions catch
# the regression where a future contributor adds an explicit unsafe value
# in `generate_xcode_project.rb` or a target-level override slips in.
#
# `tmp_settings` is the `xcodebuild -showBuildSettings -configuration Release`
# dump captured above; each setting appears as `    KEY = VALUE` with
# resolved value.

# ENABLE_BITCODE must not be YES. Apple deprecated bitcode in Xcode 14; a
# YES setting re-enables Apple-side recompilation of the binary, which is
# a supply-chain risk surface.
if grep -F "ENABLE_BITCODE = YES" "$tmp_settings" >/dev/null 2>&1; then
  echo "FAIL: ENABLE_BITCODE is YES in Release — Apple deprecated bitcode in Xcode 14; re-enabling it is a supply-chain risk" >&2
  exit 1
fi

# STRIP_INSTALLED_PRODUCT must not be NO. Debug symbols belong in the
# dSYM (kept separately for symbolication, never shipped with the app);
# leaving them in the installed binary inflates IPA size and makes
# reverse engineering trivial.
if grep -F "STRIP_INSTALLED_PRODUCT = NO" "$tmp_settings" >/dev/null 2>&1; then
  echo "FAIL: STRIP_INSTALLED_PRODUCT is NO in Release — debug symbols belong in dSYM, not in the shipped binary" >&2
  exit 1
fi

# SWIFT_OPTIMIZATION_LEVEL must not be -Onone in Release. -Onone produces
# unoptimized code with full debug symbols; this is correct for Debug,
# never for Release. Allowed values: -O, -Owholemodule, -Osize.
if grep -E "^[[:space:]]+SWIFT_OPTIMIZATION_LEVEL = -Onone" "$tmp_settings" >/dev/null 2>&1; then
  echo "FAIL: SWIFT_OPTIMIZATION_LEVEL is -Onone in Release — must be -O, -Owholemodule, or -Osize" >&2
  exit 1
fi

# GCC_OPTIMIZATION_LEVEL must not be 0 in Release. Same reasoning as
# Swift: 0 disables compiler optimizations, expanding binary size and
# the reverse-engineering surface.
if grep -E "^[[:space:]]+GCC_OPTIMIZATION_LEVEL = 0" "$tmp_settings" >/dev/null 2>&1; then
  echo "FAIL: GCC_OPTIMIZATION_LEVEL is 0 in Release — must be s or 3" >&2
  exit 1
fi

# ONLY_ACTIVE_ARCH must not be YES in Release. The archive needs every
# device architecture (arm64 / arm64e) so the signed IPA is universal.
# ONLY_ACTIVE_ARCH=YES is correct for Debug iterations on a single
# device but ships a single-arch binary if leaked into Release.
if grep -F "ONLY_ACTIVE_ARCH = YES" "$tmp_settings" >/dev/null 2>&1; then
  echo "FAIL: ONLY_ACTIVE_ARCH is YES in Release — Release archives must include every device architecture" >&2
  exit 1
fi

# DEAD_CODE_STRIPPING must not be NO. Removes unreachable symbols at
# link time, shrinking IPA size and reducing the function-graph surface
# available for ROP/JOP attacks.
if grep -F "DEAD_CODE_STRIPPING = NO" "$tmp_settings" >/dev/null 2>&1; then
  echo "FAIL: DEAD_CODE_STRIPPING is NO in Release — must be YES" >&2
  exit 1
fi

# COPY_PHASE_STRIP must not be NO. The strip phase needs to run on
# copied resources / nested frameworks during Release builds so debug
# symbols don't leak in through dependencies.
if grep -F "COPY_PHASE_STRIP = NO" "$tmp_settings" >/dev/null 2>&1; then
  echo "FAIL: COPY_PHASE_STRIP is NO in Release — must be YES" >&2
  exit 1
fi

# VERSION file must exist
[[ -f "VERSION" ]] || {
  echo "FAIL: Missing VERSION file at repo root" >&2
  exit 1
}

# VOL-56 / VOL-56b (PR #24): App/Info.plist is the only place we can express
# array-valued keys that INFOPLIST_KEY_* silently drops. If anyone deletes
# the file, reverts the INFOPLIST_FILE setting, or removes one of the three
# required keys, production builds silently lose deep-link handling and/or
# background task scheduling. Hard-fail so the regression is visible.
APP_INFO_PLIST="App/Info.plist"
[[ -f "$APP_INFO_PLIST" ]] || {
  echo "FAIL: Missing $APP_INFO_PLIST (required for CFBundleURLTypes, BGTaskSchedulerPermittedIdentifiers, UIBackgroundModes)" >&2
  exit 1
}

for required_key in \
  "CFBundleURLTypes" \
  "BGTaskSchedulerPermittedIdentifiers" \
  "UIBackgroundModes"; do
  if ! plutil -extract "$required_key" raw -o - "$APP_INFO_PLIST" >/dev/null 2>&1; then
    echo "FAIL: $APP_INFO_PLIST missing required key: $required_key" >&2
    exit 1
  fi
done

# Confirm the scheme is the one VolumeArcDeepLink expects.
if ! plutil -extract "CFBundleURLTypes.0.CFBundleURLSchemes.0" raw -o - "$APP_INFO_PLIST" 2>/dev/null | grep -qx "volumearc"; then
  echo "FAIL: $APP_INFO_PLIST CFBundleURLTypes must register the 'volumearc' scheme" >&2
  exit 1
fi

# Confirm both BGTask identifiers are permitted.
for required_task in \
  "com.mabryventures.VolumeArc.appRefresh" \
  "com.mabryventures.VolumeArc.appProcessing"; do
  if ! plutil -convert xml1 -o - "$APP_INFO_PLIST" 2>/dev/null | grep -qF "<string>$required_task</string>"; then
    echo "FAIL: $APP_INFO_PLIST BGTaskSchedulerPermittedIdentifiers missing: $required_task" >&2
    exit 1
  fi
done

# VOL-85: Built-bundle Info.plist validation (hardening)
#
# The source App/Info.plist check above catches human-visible regressions
# (someone deleting a required key in git). This check catches build-time
# regressions (ProcessInfoPlistFile dropping or rewriting a key during
# the Xcode build). Only runs when a built .app bundle exists in DerivedData,
# so local devs who only run this script without building aren't forced
# to archive.

BUILT_APP_PLIST=""
# Look in the standard DerivedData location for the app bundle Info.plist.
for candidate in \
  "$HOME/Library/Developer/Xcode/DerivedData"/VolumeArcApple-*/Build/Products/Release-iphoneos/VolumeArc.app/Info.plist \
  "$HOME/Library/Developer/Xcode/DerivedData"/VolumeArcApple-*/Build/Products/Debug-iphonesimulator/VolumeArc.app/Info.plist; do
  for match in $candidate; do
    if [[ -f "$match" ]]; then
      BUILT_APP_PLIST="$match"
      break 2
    fi
  done
done

if [[ -n "$BUILT_APP_PLIST" ]]; then
  echo "Validating built bundle Info.plist at $BUILT_APP_PLIST"
  for required_key in \
    "CFBundleURLTypes" \
    "BGTaskSchedulerPermittedIdentifiers" \
    "UIBackgroundModes"; do
    if ! plutil -extract "$required_key" raw -o - "$BUILT_APP_PLIST" >/dev/null 2>&1; then
      echo "FAIL: Built bundle Info.plist missing required key: $required_key" >&2
      echo "       ($BUILT_APP_PLIST)" >&2
      exit 1
    fi
  done
  # Confirm both BGTask identifiers survived the build.
  for required_task in \
    "com.mabryventures.VolumeArc.appRefresh" \
    "com.mabryventures.VolumeArc.appProcessing"; do
    if ! plutil -convert xml1 -o - "$BUILT_APP_PLIST" 2>/dev/null | grep -qF "<string>$required_task</string>"; then
      echo "FAIL: Built bundle Info.plist missing BGTask identifier: $required_task" >&2
      exit 1
    fi
  done
  # Confirm the URL scheme survived.
  if ! plutil -extract "CFBundleURLTypes.0.CFBundleURLSchemes.0" raw -o - "$BUILT_APP_PLIST" 2>/dev/null | grep -qx "volumearc"; then
    echo "FAIL: Built bundle Info.plist CFBundleURLTypes missing 'volumearc' scheme" >&2
    exit 1
  fi
else
  echo "INFO: No built .app bundle found in DerivedData; skipping built-bundle plist check. Run an xcodebuild first to exercise this validation."
fi

# VOL-92: Built-bundle signed entitlement validation
#
# The VOL-85 plist check above catches Info.plist regressions. This catches
# entitlement regressions in the signed .app: aps-environment drifting from
# production back to development, missing iCloud container ID, missing
# HealthKit / App Groups entitlement — any of which silently ship a broken
# TestFlight build (remote notifications stop, CloudKit writes fail,
# HealthKit queries return empty). `codesign -d --entitlements -` prints
# the entitlements embedded in the signed binary to stdout; Debug
# simulator builds are unsigned and produce empty stdout, which we skip
# gracefully so devs who never archive locally aren't forced to.
#
# Discovery mirrors VOL-85 — prefer the Release iphoneos bundle first,
# then fall back to debug-iphonesimulator (which will skip gracefully).
# Widget / watchWidget extensions are intentionally out of scope
# (follow-up per VOL-92 PR).

BUILT_APP_BUNDLE=""
for candidate in \
  "$HOME/Library/Developer/Xcode/DerivedData"/VolumeArcApple-*/Build/Products/Release-iphoneos/VolumeArc.app \
  "$HOME/Library/Developer/Xcode/DerivedData"/VolumeArcApple-*/Build/Products/Debug-iphoneos/VolumeArc.app \
  "$HOME/Library/Developer/Xcode/DerivedData"/VolumeArcApple-*/Build/Products/Release-iphonesimulator/VolumeArc.app \
  "$HOME/Library/Developer/Xcode/DerivedData"/VolumeArcApple-*/Build/Products/Debug-iphonesimulator/VolumeArc.app; do
  for match in $candidate; do
    if [[ -d "$match" ]]; then
      BUILT_APP_BUNDLE="$match"
      break 2
    fi
  done
done

# Allow explicit override from Fastlane (post-gym) — point at the freshly
# archived .app so validation runs against the exact artifact we're about
# to upload, not whatever DerivedData leftover happens to be around.
if [[ -n "${VOLUMEARC_BUILT_APP_PATH:-}" && -d "$VOLUMEARC_BUILT_APP_PATH" ]]; then
  BUILT_APP_BUNDLE="$VOLUMEARC_BUILT_APP_PATH"
fi

# Extract entitlements XML to stdout (stderr = the `Executable=...` noise).
# Returns empty string for unsigned bundles (Debug sim). Wrapped in a
# function so we can reuse for the watch bundle.
extract_entitlements_xml() {
  local bundle_path="$1"
  codesign -d --entitlements - --xml "$bundle_path" 2>/dev/null || true
}

# plutil uses `.` as a keypath separator, so any entitlement key containing
# dots (e.g. `com.apple.developer.healthkit`) must have those dots escaped
# when passed to -extract. Without this, plutil walks a non-existent nested
# key path and reports "No value at that key path" for every Apple-domain
# entitlement.
escape_plutil_keypath() {
  printf '%s' "$1" | sed 's/\./\\./g'
}

validate_signed_entitlement_bool_true() {
  # $1 = xml, $2 = entitlement key, $3 = bundle label (for error)
  local xml="$1" key="$2" label="$3"
  local tmp escaped
  tmp="$(mktemp)"
  printf '%s' "$xml" >"$tmp"
  escaped="$(escape_plutil_keypath "$key")"
  if ! plutil -extract "$escaped" raw -o - "$tmp" 2>/dev/null | grep -qx "true"; then
    rm -f "$tmp"
    echo "FAIL: $label signed entitlements missing or false for '$key' (expected boolean true)" >&2
    exit 1
  fi
  rm -f "$tmp"
}

validate_signed_entitlement_contains_string() {
  # $1 = xml, $2 = array key, $3 = expected string, $4 = bundle label
  # Arrays are awkward to index via plutil -extract (depends on the
  # element position), so just round-trip the XML and grep for the literal
  # <string>value</string>. False positives across keys are a non-concern
  # because the entitlement file has a small, well-known shape.
  local xml="$1" key="$2" expected="$3" label="$4"
  local tmp
  tmp="$(mktemp)"
  printf '%s' "$xml" >"$tmp"
  if ! plutil -convert xml1 -o - "$tmp" 2>/dev/null | grep -qF "<string>$expected</string>"; then
    rm -f "$tmp"
    echo "FAIL: $label signed entitlements '$key' missing required value '$expected'" >&2
    exit 1
  fi
  rm -f "$tmp"
}

if [[ -n "$BUILT_APP_BUNDLE" ]]; then
  echo "Validating built bundle signed entitlements at $BUILT_APP_BUNDLE"
  app_entitlements_xml="$(extract_entitlements_xml "$BUILT_APP_BUNDLE")"
  if [[ -z "$app_entitlements_xml" ]]; then
    # Unsigned bundle (typical for Debug iphonesimulator). Not a failure —
    # the VOL-85 plist section already ran against this bundle; entitlement
    # validation only applies to signed archives.
    echo "INFO: Built app bundle is unsigned (likely Debug simulator); skipping signed-entitlement assertions. Run ./scripts/archive_for_distribution.sh or a Release device build to exercise this validation."
  else
    # Hard-fail: aps-environment MUST be production in the signed Release
    # bundle. Shipping a TestFlight build with `development` means the
    # relay's production APNs tokens silently won't reach the device.
    signed_aps="$(printf '%s' "$app_entitlements_xml" | plutil -extract "aps-environment" raw -o - - 2>/dev/null || echo "")"
    if [[ -z "$signed_aps" ]]; then
      echo "FAIL: Built bundle signed entitlements missing aps-environment key" >&2
      exit 1
    fi
    if [[ "$signed_aps" != "production" ]]; then
      echo "FAIL: Built bundle signed aps-environment must be 'production' (got '$signed_aps'). Release IPAs with 'development' silently drop APNs traffic on TestFlight/App Store." >&2
      exit 1
    fi

    built_sentry_dsn="$(plutil -extract "VolumeArcSentryDSN" raw -o - "$BUILT_APP_BUNDLE/Info.plist" 2>/dev/null || echo "")"
    if [[ -z "$built_sentry_dsn" || "$built_sentry_dsn" == *'$('* ]]; then
      echo "FAIL: Built production-signed app missing configured VolumeArcSentryDSN. TestFlight/App Store builds must initialize Sentry." >&2
      exit 1
    fi
    if [[ ! "$built_sentry_dsn" =~ ^https://[^/@]+@[^/]+/.+ ]]; then
      echo "FAIL: Built production-signed app VolumeArcSentryDSN must be an HTTPS Sentry DSN URL with public key and project path." >&2
      exit 1
    fi
    built_relay_url="$(plutil -extract "VolumeArcAIRelayURL" raw -o - "$BUILT_APP_BUNDLE/Info.plist" 2>/dev/null || echo "")"
    if [[ "$built_relay_url" != "https://relay.volumearc.app" ]]; then
      echo "FAIL: Built production-signed app must use VolumeArcAIRelayURL=https://relay.volumearc.app (got '${built_relay_url:-<empty>}')." >&2
      exit 1
    fi

    # Must match the Release entitlements file on disk — catches the case
    # where someone edits the source file to `production` but the signed
    # bundle was built from stale settings (or the wrong entitlements
    # file was picked up during CODE_SIGN_ENTITLEMENTS resolution).
    if [[ -f "App/VolumeArc.Release.entitlements" ]]; then
      file_aps="$(plutil -extract "aps-environment" raw -o - "App/VolumeArc.Release.entitlements" 2>/dev/null || echo "")"
      if [[ "$signed_aps" != "$file_aps" ]]; then
        echo "FAIL: Signed aps-environment ('$signed_aps') disagrees with App/VolumeArc.Release.entitlements ('$file_aps')" >&2
        exit 1
      fi
    fi

    # iCloud container identifier — losing this means CloudKit writes
    # silently fail (transport falls back to Unavailable at runtime).
    validate_signed_entitlement_contains_string \
      "$app_entitlements_xml" \
      "com.apple.developer.icloud-container-identifiers" \
      "iCloud.com.mabryventures.VolumeArc" \
      "app bundle"

    # HealthKit — losing this means every HKWorkoutSession / HKHealthStore
    # request throws authorization errors at runtime.
    validate_signed_entitlement_bool_true \
      "$app_entitlements_xml" \
      "com.apple.developer.healthkit" \
      "app bundle"

    # App Groups — losing this means the widget and watch extension can't
    # read the shared defaults the iOS app writes, so widgets render empty.
    validate_signed_entitlement_contains_string \
      "$app_entitlements_xml" \
      "com.apple.security.application-groups" \
      "group.com.mabryventures.volumearc" \
      "app bundle"

    echo "Built bundle signed entitlements: aps-environment=production, iCloud container present, HealthKit present, App Groups present."
  fi
fi

# Watch bundle — scoped to entitlements HealthKit + App Groups per
# VOL-92 (extensions/widget checks are explicit follow-ups).
BUILT_WATCH_BUNDLE=""
for candidate in \
  "$HOME/Library/Developer/Xcode/DerivedData"/VolumeArcApple-*/Build/Products/Release-watchos/VolumeArcWatch.app \
  "$HOME/Library/Developer/Xcode/DerivedData"/VolumeArcApple-*/Build/Products/Debug-watchos/VolumeArcWatch.app \
  "$HOME/Library/Developer/Xcode/DerivedData"/VolumeArcApple-*/Build/Products/Release-watchsimulator/VolumeArcWatch.app \
  "$HOME/Library/Developer/Xcode/DerivedData"/VolumeArcApple-*/Build/Products/Debug-watchsimulator/VolumeArcWatch.app; do
  for match in $candidate; do
    if [[ -d "$match" ]]; then
      BUILT_WATCH_BUNDLE="$match"
      break 2
    fi
  done
done

if [[ -n "${VOLUMEARC_BUILT_WATCH_PATH:-}" && -d "$VOLUMEARC_BUILT_WATCH_PATH" ]]; then
  BUILT_WATCH_BUNDLE="$VOLUMEARC_BUILT_WATCH_PATH"
fi

if [[ -n "$BUILT_WATCH_BUNDLE" ]]; then
  echo "Validating built watch bundle signed entitlements at $BUILT_WATCH_BUNDLE"
  watch_entitlements_xml="$(extract_entitlements_xml "$BUILT_WATCH_BUNDLE")"
  if [[ -z "$watch_entitlements_xml" ]]; then
    echo "INFO: Built watch bundle is unsigned; skipping signed-entitlement assertions."
  else
    validate_signed_entitlement_bool_true \
      "$watch_entitlements_xml" \
      "com.apple.developer.healthkit" \
      "watch bundle"

    validate_signed_entitlement_contains_string \
      "$watch_entitlements_xml" \
      "com.apple.security.application-groups" \
      "group.com.mabryventures.volumearc" \
      "watch bundle"

    echo "Built watch bundle signed entitlements: HealthKit present, App Groups present."
  fi
fi

if [[ -z "$BUILT_APP_BUNDLE" && -z "$BUILT_WATCH_BUNDLE" ]]; then
  echo "INFO: No built .app bundles found in DerivedData; skipping signed-entitlement checks. Run ./scripts/archive_for_distribution.sh (or \`fastlane ios beta\`) to exercise this validation."
fi

# Version bump check: if building for a tag, fail when VERSION matches the latest tag.
# On branch/PR builds this stays a warning since it only matters at release time.
if git describe --tags --abbrev=0 >/dev/null 2>&1; then
  latest_tag="$(git describe --tags --abbrev=0)"
  current_version="$(cat VERSION | tr -d '[:space:]')"
  tag_version="${latest_tag#v}"
  if [[ "$current_version" == "$tag_version" ]]; then
    if [[ "${CI_TAG_BUILD:-0}" == "1" ]]; then
      echo "FAIL: VERSION ($current_version) matches latest tag ($latest_tag) — bump VERSION before shipping a tag build" >&2
      exit 1
    else
      echo "WARNING: VERSION ($current_version) matches latest tag ($latest_tag) — bump VERSION before tagging" >&2
    fi
  fi
fi

echo "Release configuration validation passed."
