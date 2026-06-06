#!/usr/bin/env bash
# VOL-126 / VOL-133: Xcode Cloud post-xcodebuild hook.
#
# Xcode Cloud invokes this after `xcodebuild` finishes. For archive
# workflows, we use it to upload the dSYM bundle to Sentry so
# production crash reports symbolicate.
#
# This is the Xcode-Cloud-native equivalent of the previous Fastlane
# `beta` lane's sentry-cli step (see `fastlane/Fastfile`). Keeping
# the sentry-cli call in CI rather than relying on Sentry's
# auto-upload from the build phase guarantees we capture dSYMs even
# when the build is archived from a CI environment that doesn't
# auto-instrument.
#
# Required env vars (set in the Xcode Cloud workflow's "Environment
# Variables" panel — the SENTRY_AUTH_TOKEN should be marked as a
# secret):
#
#   SENTRY_AUTH_TOKEN — Sentry auth token with `project:read` and
#                       `project:write` scopes.
#   SENTRY_ORG        — defaults to `mabry-ventures-llc`
#   SENTRY_PROJECT    — defaults to `volumearc-ios`
#
# Failure here fails the workflow: a silent dSYM-upload miss is
# exactly the bug VOL-133 was created to prevent.

set -euo pipefail

echo "VOL-126: ci_post_xcodebuild.sh starting"
echo "CI_WORKFLOW = ${CI_WORKFLOW:-<unset>}"
echo "CI_XCODEBUILD_ACTION = ${CI_XCODEBUILD_ACTION:-<unset>}"
echo "CI_XCODEBUILD_EXIT_CODE = ${CI_XCODEBUILD_EXIT_CODE:-<unset>}"
echo "CI_ARCHIVE_PATH = ${CI_ARCHIVE_PATH:-<unset>}"
echo "CI_RESULT_BUNDLE_PATH = ${CI_RESULT_BUNDLE_PATH:-<unset>}"

# VOL-246: action-correct gating.
#
# `CI_XCODEBUILD_ACTION` is never literally "test". A Test action runs
# `build-for-testing` then `test-without-building`; the latter is the
# phase where the result bundle (with coverage) exists. `archive` is the
# release path. Everything else (build, build-for-testing, analyze) has
# nothing for this hook to do.
case "${CI_XCODEBUILD_ACTION:-}" in
  test-without-building)
    # Coverage gate. On Xcode Cloud's test machine, `ci_scripts/` is the
    # ONLY part of the repository that is guaranteed to be present — the
    # `test-without-building` step runs on a separate machine from
    # `build-for-testing` and does NOT receive the full source tree.
    # `scripts/check_coverage.sh` and its Python companion are therefore
    # copied into `ci_scripts/` (see ci_scripts/check_coverage.sh and
    # ci_scripts/_compute_coverage_summary.py) so they are always available
    # on the test machine.
    #
    # For local / self-hosted runs where ci_scripts/ and scripts/ live
    # together in the same tree, this script first checks for the
    # ci_scripts/-local copy and falls back to REPO_ROOT/scripts/ so no
    # workflow breaks during the transition.
    COVERAGE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    if [[ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]]; then
      REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH}"
    else
      REPO_ROOT="$(cd "$COVERAGE_SCRIPT_DIR/.." && pwd)"
    fi
    echo "VOL-246: REPO_ROOT=$REPO_ROOT"

    if [[ -z "${CI_RESULT_BUNDLE_PATH:-}" || ! -d "${CI_RESULT_BUNDLE_PATH}" ]]; then
      echo "VOL-246: no result bundle at CI_RESULT_BUNDLE_PATH=${CI_RESULT_BUNDLE_PATH:-<unset>}; nothing to gate"
      exit 0
    fi
    if [[ -n "${CI_XCODEBUILD_EXIT_CODE:-}" && "${CI_XCODEBUILD_EXIT_CODE}" != "0" ]]; then
      echo "VOL-246: test action already failed (exit=${CI_XCODEBUILD_EXIT_CODE}); the RED test result is the signal — skipping coverage gate"
      exit 0
    fi

    # Prefer the ci_scripts/-local copy (guaranteed on the Xcode Cloud test
    # machine). Fall back to scripts/ for self-hosted / local runs.
    if [[ -f "$COVERAGE_SCRIPT_DIR/check_coverage.sh" ]]; then
      CHECK_COVERAGE="$COVERAGE_SCRIPT_DIR/check_coverage.sh"
    else
      CHECK_COVERAGE="$REPO_ROOT/scripts/check_coverage.sh"
    fi
    if [[ ! -f "$CHECK_COVERAGE" ]]; then
      echo "::error::VOL-246: check_coverage.sh not found in $COVERAGE_SCRIPT_DIR or $REPO_ROOT/scripts/"
      exit 1
    fi
    echo "VOL-246: using $CHECK_COVERAGE"

    COVERAGE_TMP="$(mktemp -d)"
    export XCRESULT="${CI_RESULT_BUNDLE_PATH}"

    # VolumeArcCore: enforced (80%) on VOL-Main. On VOL-PR, Xcode Cloud
    # builds tests in Release configuration (to catch release-only regressions),
    # whereas the self-hosted CI builds in Debug. Release-mode optimizations
    # (function inlining, dead-code elimination) consistently lower xccov's
    # measured line coverage by ~5–8 percentage points, so the 80% floor is
    # not reliably achievable in the PR workflow. Measuring without gating on
    # VOL-PR keeps the signal visible while the hard gate lives on VOL-Main.
    if [[ "${CI_WORKFLOW:-}" == "VOL Main" ]]; then
      echo "VOL-246: enforcing VolumeArcCore >= 80% coverage from $XCRESULT"
      COVERAGE_TARGET="VolumeArcCore" COVERAGE_THRESHOLD="80" \
        COVERAGE_SUMMARY_JSON="$COVERAGE_TMP/volumearccore.json" \
        bash "$CHECK_COVERAGE"
    else
      echo "VOL-246: measuring VolumeArcCore coverage (non-blocking on 'VOL PR'; hard gate on 'VOL Main')"
      COVERAGE_TARGET="VolumeArcCore" COVERAGE_THRESHOLD="0" \
        COVERAGE_SUMMARY_JSON="$COVERAGE_TMP/volumearccore.json" \
        bash "$CHECK_COVERAGE"
    fi

    # VolumeArcUI (2% guard-rail): exercised mostly via UI journeys, so
    # the floor is only meaningful against the full suite. Enforce it on
    # the VOL-Main workflow; measure-only on the VOL-PR smoke subset.
    # Gated on CI_WORKFLOW (the workflow's display name in App Store
    # Connect) — the workflows MUST be named exactly "VOL PR" / "VOL Main".
    if [[ "${CI_WORKFLOW:-}" == "VOL Main" ]]; then
      echo "VOL-246: enforcing VolumeArcUI >= 2% coverage (full suite)"
      COVERAGE_TARGET="VolumeArcUI" COVERAGE_THRESHOLD="2" \
        COVERAGE_SUMMARY_JSON="$COVERAGE_TMP/volumearcui.json" \
        bash "$CHECK_COVERAGE"
    else
      echo "VOL-246: VolumeArcUI floor enforced on 'VOL Main' only (CI_WORKFLOW=${CI_WORKFLOW:-<unset>}); skipping on subset/other workflow"
    fi

    echo "VOL-246: coverage gate passed"
    exit 0
    ;;
  archive)
    # Fall through to the VOL-133 archive contract + dSYM upload below.
    :
    ;;
  *)
    echo "VOL-126: action '${CI_XCODEBUILD_ACTION:-none}' has no post-build work; exiting 0"
    exit 0
    ;;
esac

if [[ -n "${CI_XCODEBUILD_EXIT_CODE:-}" && "${CI_XCODEBUILD_EXIT_CODE}" != "0" ]]; then
  echo "VOL-126: xcodebuild already failed (exit=${CI_XCODEBUILD_EXIT_CODE}); skipping post-archive validation/upload"
  exit 0
fi

resolve_archive_path() {
  if [[ -n "${CI_ARCHIVE_PATH:-}" && -d "${CI_ARCHIVE_PATH}" ]]; then
    printf '%s\n' "${CI_ARCHIVE_PATH}"
    return 0
  fi

  local roots=()
  local root
  for root in \
    "${CI_DERIVED_DATA_PATH:-}" \
    "${CI_WORKSPACE_PATH:-}" \
    "${CI_PRIMARY_REPOSITORY_PATH:-}" \
    "$PWD" \
    "$HOME/Library/Developer/Xcode/Archives" \
    "/Volumes/workspace"; do
    if [[ -n "$root" && -d "$root" ]]; then
      roots+=("$root")
    fi
  done

  if [[ "${#roots[@]}" -eq 0 ]]; then
    return 1
  fi

  /usr/bin/find "${roots[@]}" -type d -name '*.xcarchive' -maxdepth 8 -print0 2>/dev/null |
    /usr/bin/xargs -0 /usr/bin/stat -f '%m %N' 2>/dev/null |
    /usr/bin/sort -rn |
    /usr/bin/awk 'NR == 1 { $1=""; sub(/^ /, ""); print; exit }'
}

ARCHIVE_PATH="$(resolve_archive_path || true)"
if [[ -z "$ARCHIVE_PATH" || ! -d "$ARCHIVE_PATH" ]]; then
  echo "::error::VOL-133: could not resolve Xcode archive path (CI_ARCHIVE_PATH=${CI_ARCHIVE_PATH:-<empty>})"
  exit 1
fi
echo "Resolved archive path = ${ARCHIVE_PATH}"

plist_value() {
  local key="$1"
  local plist="$2"
  /usr/bin/plutil -extract "$key" raw "$plist" 2>/dev/null || true
}

require_dir() {
  local path="$1"
  local label="$2"
  if [[ ! -d "$path" ]]; then
    echo "::error::VOL-133: missing ${label} at ${path}"
    exit 1
  fi
}

require_plist_value() {
  local key="$1"
  local expected="$2"
  local plist="$3"
  local actual
  actual="$(plist_value "$key" "$plist")"
  if [[ "$actual" != "$expected" ]]; then
    echo "::error::VOL-133: expected ${key}=${expected} in ${plist}, got ${actual:-<empty>}"
    exit 1
  fi
}

require_plist_nonempty() {
  local key="$1"
  local plist="$2"
  local actual
  actual="$(plist_value "$key" "$plist")"
  if [[ -z "$actual" ]]; then
    echo "::error::VOL-133: expected non-empty ${key} in ${plist}"
    exit 1
  fi
}

require_plist_sentry_dsn() {
  local key="$1"
  local plist="$2"
  local actual
  actual="$(plist_value "$key" "$plist")"
  if [[ -z "$actual" || "$actual" == *'$('* ]]; then
    echo "::error::VOL-133: expected configured Sentry DSN in ${plist}, got ${actual:-<empty>}"
    exit 1
  fi
  if [[ ! "$actual" =~ ^https://[^/@]+@[^/]+/.+ ]]; then
    echo "::error::VOL-133: expected HTTPS Sentry DSN URL with public key and project path in ${plist}, got ${actual}"
    exit 1
  fi
}

require_watch_assets_car() {
  local assets_car="$1"
  if [[ ! -f "$assets_car" ]]; then
    echo "::error::VOL-133: missing compiled watch Assets.car at ${assets_car}"
    exit 1
  fi

  local asset_info
  if ! asset_info="$(xcrun assetutil --info "$assets_car" 2>&1)"; then
    echo "::error::VOL-133: unable to inspect compiled watch Assets.car at ${assets_car}"
    printf "%s\n" "$asset_info"
    exit 1
  fi

  if ! printf "%s" "$asset_info" |
    /usr/bin/ruby -rjson -e '
      begin
        records = JSON.parse(STDIN.read)
      rescue JSON::ParserError => error
        warn "::error::VOL-133: unable to parse assetutil output for #{ARGV.fetch(0)}: #{error.message}"
        exit 1
      end
      icons = records.select { |record| record["AssetType"] == "Icon Image" && record["Name"] == "AppIcon" }
      required = {
        "marketing 1024x1024" => ->(record) { record["Idiom"] == "marketing" && record["PixelWidth"] == 1024 && record["PixelHeight"] == 1024 },
        "watch 48x48" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 48 && record["PixelHeight"] == 48 },
        "watch 55x55" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 55 && record["PixelHeight"] == 55 },
        "watch 58x58" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 58 && record["PixelHeight"] == 58 },
        "watch 80x80" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 80 && record["PixelHeight"] == 80 },
        "watch 87x87" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 87 && record["PixelHeight"] == 87 },
        "watch 88x88" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 88 && record["PixelHeight"] == 88 },
        "watch 100x100" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 100 && record["PixelHeight"] == 100 },
        "watch 172x172" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 172 && record["PixelHeight"] == 172 },
        "watch 196x196" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 196 && record["PixelHeight"] == 196 },
        "watch 216x216" => ->(record) { record["Idiom"] == "watch" && record["PixelWidth"] == 216 && record["PixelHeight"] == 216 }
      }
      missing = required.keys.reject { |name| icons.any? { |record| required.fetch(name).call(record) } }
      if missing.any?
        warn "::error::VOL-133: compiled watch Assets.car missing AppIcon renditions: #{missing.join(", ")}"
        exit 1
      end
    ' "$assets_car"; then
    exit 1
  fi
}

require_extension_entry_point() {
  local bundle="$1"
  local label="$2"
  local executable_name
  executable_name="$(plist_value "CFBundleExecutable" "${bundle}/Info.plist")"
  if [[ -z "$executable_name" ]]; then
    echo "::error::VOL-133: ${label} missing CFBundleExecutable in ${bundle}/Info.plist"
    exit 1
  fi

  local executable_path="${bundle}/${executable_name}"
  if [[ ! -f "$executable_path" ]]; then
    echo "::error::VOL-133: ${label} missing executable at ${executable_path}"
    exit 1
  fi

  local symbols
  local nm_bin="${NM_BIN:-/usr/bin/nm}"
  if ! symbols="$("$nm_bin" -m "$executable_path" 2>&1)"; then
    echo "::error::VOL-133: unable to inspect ${label} symbols at ${executable_path}"
    printf "%s\n" "$symbols"
    exit 1
  fi

  # Avoid a grep -q pipeline under pipefail: grep exits as soon as it finds the
  # symbol, which can make the producer report SIGPIPE on large nm output.
  if ! /usr/bin/grep -Eq '(^|[[:space:]])_NSExtensionMain($|[[:space:]])' <<<"$symbols"; then
    echo "::error::VOL-133: ${label} executable must link with -e _NSExtensionMain; App Store Connect rejects extension binaries that enter through _main"
    exit 1
  fi
}

generate_sentry_framework_dsym() {
  local sentry_binary="${APP_BUNDLE}/Frameworks/Sentry.framework/Sentry"
  local sentry_dsym="${DSYM_DIR}/Sentry.framework.dSYM"
  local binary_uuid
  local dsym_uuid

  if [[ ! -f "$sentry_binary" ]]; then
    echo "::error::VOL-133: bundled Sentry.framework binary missing at ${sentry_binary}"
    exit 1
  fi

  rm -rf "$sentry_dsym"
  if ! xcrun dsymutil "$sentry_binary" -o "$sentry_dsym"; then
    echo "::error::VOL-133: failed to generate Sentry.framework dSYM from archived binary"
    exit 1
  fi

  binary_uuid="$(xcrun dwarfdump --uuid "$sentry_binary" | awk 'NR == 1 {print $2}')"
  dsym_uuid="$(xcrun dwarfdump --uuid "$sentry_dsym" | awk 'NR == 1 {print $2}')"
  if [[ -z "$binary_uuid" || "$binary_uuid" != "$dsym_uuid" ]]; then
    echo "::error::VOL-133: generated Sentry.framework dSYM UUID mismatch (binary=${binary_uuid:-<empty>}, dSYM=${dsym_uuid:-<empty>})"
    exit 1
  fi

  echo "VOL-133: generated archived Sentry.framework dSYM (${binary_uuid})"
}

APP_BUNDLE="${ARCHIVE_PATH}/Products/Applications/VolumeArc.app"
WATCH_BUNDLE="${APP_BUNDLE}/Watch/VolumeArcWatch.app"
WATCH_WIDGET_BUNDLE="${WATCH_BUNDLE}/PlugIns/VolumeArcWatchWidgets.appex"

require_dir "$APP_BUNDLE" "VolumeArc app bundle"
require_dir "$WATCH_BUNDLE" "embedded watch app"
require_dir "$WATCH_WIDGET_BUNDLE" "embedded watch widget extension"

require_plist_sentry_dsn "VolumeArcSentryDSN" "${APP_BUNDLE}/Info.plist"
require_plist_value "VolumeArcAIRelayURL" "https://relay.volumearc.app" "${APP_BUNDLE}/Info.plist"
require_plist_nonempty "CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName" "${WATCH_BUNDLE}/Info.plist"
require_plist_nonempty "CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles.0" "${WATCH_BUNDLE}/Info.plist"
require_plist_value "CFBundleDisplayName" "VolumeArc" "${WATCH_WIDGET_BUNDLE}/Info.plist"
require_plist_value "NSExtension.NSExtensionPointIdentifier" "com.apple.widgetkit-extension" "${WATCH_WIDGET_BUNDLE}/Info.plist"
require_extension_entry_point "${WATCH_WIDGET_BUNDLE}" "watch widget extension"
require_watch_assets_car "${WATCH_BUNDLE}/Assets.car"

if [[ -n "${CI_BUILD_NUMBER:-}" ]]; then
  require_plist_value "CFBundleVersion" "$CI_BUILD_NUMBER" "${APP_BUNDLE}/Info.plist"
  require_plist_value "CFBundleVersion" "$CI_BUILD_NUMBER" "${WATCH_BUNDLE}/Info.plist"
  require_plist_value "CFBundleVersion" "$CI_BUILD_NUMBER" "${WATCH_WIDGET_BUNDLE}/Info.plist"
fi

echo "VOL-133: archive contract OK (watch app, watch icon renditions, watch widget entry point, build numbers, relay config)"

DSYM_DIR="${ARCHIVE_PATH}/dSYMs"
if [[ ! -d "${DSYM_DIR}" ]] || [[ -z "$(ls -A "${DSYM_DIR}" 2>/dev/null)" ]]; then
  echo "::error::VOL-133: dSYM directory missing or empty at ${DSYM_DIR}"
  exit 1
fi

generate_sentry_framework_dsym

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  echo "::error::SENTRY_AUTH_TOKEN unset — refusing to ship a TestFlight/App Store archive without Sentry dSYM upload."
  echo "  Set SENTRY_AUTH_TOKEN as a secret env var in the Xcode Cloud workflow to fix."
  exit 1
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "::error::sentry-cli not on PATH — ci_post_clone.sh should have installed it"
  exit 1
fi

SENTRY_ORG="${SENTRY_ORG:-mabry-ventures-llc}"
SENTRY_PROJECT="${SENTRY_PROJECT:-volumearc-ios}"

echo "VOL-133: uploading dSYMs from ${DSYM_DIR} → ${SENTRY_ORG}/${SENTRY_PROJECT}"
for attempt in 1 2 3; do
  if sentry-cli debug-files upload \
    --org "${SENTRY_ORG}" \
    --project "${SENTRY_PROJECT}" \
    --include-sources \
    --wait \
    --log-level=info \
    "${DSYM_DIR}"; then
    echo "VOL-133: dSYM upload complete"
    exit 0
  fi
  echo "::warning::VOL-133: sentry-cli dSYM upload attempt ${attempt} failed"
  if [[ "$attempt" -lt 3 ]]; then
    sleep $((attempt * 10))
  fi
done

echo "::error::VOL-133: dSYM upload failed after 3 attempts"
exit 1
