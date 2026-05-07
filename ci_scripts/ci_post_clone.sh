#!/usr/bin/env bash
# VOL-126: Xcode Cloud post-clone hook.
#
# Xcode Cloud invokes this script after cloning the repo and before
# resolving Swift packages or running `xcodebuild`. We use it to
# install `sentry-cli`, which is consumed by `ci_post_xcodebuild.sh`
# to upload dSYMs to Sentry.
#
# Apple's hosted Xcode Cloud Macs run a clean image per build — no
# persistent state between runs — so every install is a fresh install.
# The Homebrew tap below is the canonical install path per
# https://docs.sentry.io/cli/installation/.
#
# Failure here halts the workflow before the build even starts, which
# is the right behavior: a missing sentry-cli would otherwise cause
# `ci_post_xcodebuild.sh` to fail silently after a long archive.

set -euo pipefail

echo "VOL-126: ci_post_clone.sh starting"
echo "CI_WORKFLOW = ${CI_WORKFLOW:-<unset>}"
echo "CI_XCODEBUILD_ACTION = ${CI_XCODEBUILD_ACTION:-<unset>}"
echo "CI_BUILD_NUMBER = ${CI_BUILD_NUMBER:-<unset>}"

# Resolve the repo root regardless of where Xcode Cloud invokes the
# script from. `CI_WORKSPACE` / `CI_PRIMARY_REPOSITORY_PATH` are
# documented but not always populated identically across workflow
# kinds, so derive from the script's own location as the safe default.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

normalize_ai_relay_url() {
  local raw="$1"
  local normalized
  local host

  if [[ "$raw" =~ ^[[:space:]] || "$raw" =~ [[:space:]]$ ]]; then
    echo "ERROR: VOLUMEARC_AI_RELAY_URL has leading/trailing whitespace" >&2
    return 1
  fi

  case "$raw" in
    https://*)
      normalized="$raw"
      ;;
    *://*)
      echo "ERROR: VOLUMEARC_AI_RELAY_URL must use https" >&2
      return 1
      ;;
    *)
      normalized="https://$raw"
      ;;
  esac

  host="${normalized#https://}"
  host="${host%%/*}"
  host="${host%%:*}"
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"

  case "$host" in
    relay.volumearc.app|volumearc-ai-relay.jared-b6b.workers.dev|relay.mabryventures.com)
      printf '%s' "$normalized"
      ;;
    *)
      echo "ERROR: VOLUMEARC_AI_RELAY_URL host is not allowlisted: $host" >&2
      return 1
      ;;
  esac
}

# Patch runtime config from Xcode Cloud env vars into the bundle's
# Info.plist BEFORE xcodebuild runs. Xcode Cloud's environment
# variables don't propagate to `xcodebuild` as build settings, so the
# `$(SENTRY_DSN)` / `$(VOLUMEARC_AI_RELAY_URL)` placeholders in
# `App/Info.plist` would otherwise resolve to the empty-string defaults
# baked into the project (verified on rc14 / Build 11 — the keys were
# present but empty, even though both env vars were configured on the
# workflow).
#
# `plutil -replace` adds the key if it doesn't already exist and
# replaces if it does, so this is idempotent against the source plist's
# existing placeholder values. Empty env vars fall through to the
# placeholder (which xcodebuild then resolves to empty), which the
# Swift `resolveDSN()` / `relayConfiguration()` paths already treat as
# "not configured".
INFO_PLIST="$REPO_ROOT/App/Info.plist"
if [[ -f "$INFO_PLIST" ]]; then
  if [[ -n "${SENTRY_DSN:-}" ]]; then
    plutil -replace VolumeArcSentryDSN -string "$SENTRY_DSN" "$INFO_PLIST"
    echo "Patched VolumeArcSentryDSN into Info.plist (len=${#SENTRY_DSN})"
  else
    echo "SENTRY_DSN env var unset; leaving Info.plist placeholder"
  fi
  if [[ -n "${VOLUMEARC_AI_RELAY_URL:-}" ]]; then
    normalized_ai_relay_url="$(normalize_ai_relay_url "$VOLUMEARC_AI_RELAY_URL")"
    plutil -replace VolumeArcAIRelayURL -string "$normalized_ai_relay_url" "$INFO_PLIST"
    echo "Patched VolumeArcAIRelayURL into Info.plist: $normalized_ai_relay_url"
  else
    echo "VOLUMEARC_AI_RELAY_URL env var unset; leaving Info.plist placeholder"
  fi
else
  echo "WARNING: Info.plist not found at $INFO_PLIST — runtime config not patched"
fi

# Xcode Cloud assigns a monotonically increasing CI_BUILD_NUMBER, but that
# value is only a shell environment variable. Regenerate the committed Xcode
# project for archive workflows so CURRENT_PROJECT_VERSION is baked into every
# app/extension target before Xcode Cloud invokes xcodebuild. Without this,
# the generated project defaults to build 1 even when the Xcode Cloud run is
# Build 14, which can make TestFlight/App Store processing drift from the run
# users see in Xcode Cloud.
if [[ "${CI_XCODEBUILD_ACTION:-}" == "archive" && -n "${CI_BUILD_NUMBER:-}" ]]; then
  echo "Regenerating Xcode project with Xcode Cloud build number ${CI_BUILD_NUMBER}"
  (
    cd "$REPO_ROOT"
    DEVELOPMENT_TEAM="${CI_TEAM_ID:-A886EMZZW6}" \
      BUILD_NUMBER="${CI_BUILD_NUMBER}" \
      ruby scripts/generate_xcode_project.rb
  )
fi

# Only install sentry-cli for archive workflows; tests and PR builds
# don't need it. CI_XCODEBUILD_ACTION is set by Xcode Cloud per
# https://developer.apple.com/documentation/xcode/environment-variable-reference.
if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
  echo "VOL-126: not an archive workflow (action=${CI_XCODEBUILD_ACTION:-none}); skipping sentry-cli install"
  exit 0
fi

if command -v sentry-cli >/dev/null 2>&1; then
  echo "sentry-cli already on PATH: $(sentry-cli --version)"
  exit 0
fi

echo "Installing sentry-cli via the official installer"
# The curl-pipe-bash installer is what Sentry recommends for non-Homebrew
# environments and is faster than `brew install` on a clean Xcode Cloud
# image (no Homebrew cache). Pinning a version would be cleaner but the
# installer always pulls the latest stable, which is what Sentry signs.
curl -sL https://sentry.io/get-cli/ | bash
echo "sentry-cli installed: $(sentry-cli --version)"
