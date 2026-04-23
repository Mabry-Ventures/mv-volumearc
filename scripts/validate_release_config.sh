#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby "scripts/generate_xcode_project.rb" >/dev/null

PROJECT="VolumeArcApple.xcodeproj/project.pbxproj"

for path in \
  "App/VolumeArc.entitlements" \
  "Watch/VolumeArcWatch.entitlements" \
  "WatchWidgets/VolumeArcWatchWidgets.entitlements" \
  "Widgets/VolumeArcWidgets.entitlements"; do
  [[ -f "$path" ]] || {
    echo "Missing required entitlement file: $path" >&2
    exit 1
  }
done

for path in \
  "App/PrivacyInfo.xcprivacy" \
  "Watch/PrivacyInfo.xcprivacy" \
  "WatchWidgets/PrivacyInfo.xcprivacy" \
  "Widgets/PrivacyInfo.xcprivacy"; do
  [[ -f "$path" ]] || {
    echo "Missing required privacy manifest: $path" >&2
    exit 1
  }
done

if ! grep -q "aps-environment" "App/VolumeArc.entitlements"; then
  echo "WARNING: aps-environment not found in App/VolumeArc.entitlements — push notifications will not work" >&2
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

tmp_settings="$(mktemp)"
trap 'rm -f "$tmp_settings"' EXIT

xcodebuild \
  -project "VolumeArcApple.xcodeproj" \
  -target "VolumeArcApp" \
  -configuration Release \
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
  "CODE_SIGN_ENTITLEMENTS = App/VolumeArc.entitlements"
  "INFOPLIST_FILE = App/Info.plist"
  "INFOPLIST_KEY_NSHealthShareUsageDescription = VolumeArc reads your completed workouts from Apple Health to show your training history and calculate readiness."
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
  -target "VolumeArcWatch" \
  -configuration Release \
  -showBuildSettings >"$tmp_settings"

watch_required=(
  "PRODUCT_BUNDLE_IDENTIFIER = com.mabryventures.VolumeArc.watchkitapp"
  "CODE_SIGN_ENTITLEMENTS = Watch/VolumeArcWatch.entitlements"
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
  -target "VolumeArcWidgets" \
  -configuration Release \
  -showBuildSettings >"$tmp_settings"

widget_required=(
  "PRODUCT_BUNDLE_IDENTIFIER = com.mabryventures.VolumeArc.widgets"
  "CODE_SIGN_ENTITLEMENTS = Widgets/VolumeArcWidgets.entitlements"
  "INFOPLIST_KEY_NSExtension_NSExtensionPointIdentifier = com.apple.widgetkit-extension"
)

for required in "${widget_required[@]}"; do
  if ! grep -F "$required" "$tmp_settings" >/dev/null; then
    echo "Missing required widget build setting: $required" >&2
    exit 1
  fi
done

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
  -target "VolumeArcApp" \
  -configuration Release \
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
