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

# Resolve the repo root regardless of where Xcode Cloud invokes the
# script from. `CI_WORKSPACE` / `CI_PRIMARY_REPOSITORY_PATH` are
# documented but not always populated identically across workflow
# kinds, so derive from the script's own location as the safe default.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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
    plutil -replace VolumeArcAIRelayURL -string "$VOLUMEARC_AI_RELAY_URL" "$INFO_PLIST"
    echo "Patched VolumeArcAIRelayURL into Info.plist: $VOLUMEARC_AI_RELAY_URL"
  else
    echo "VOLUMEARC_AI_RELAY_URL env var unset; leaving Info.plist placeholder"
  fi
else
  echo "WARNING: Info.plist not found at $INFO_PLIST — runtime config not patched"
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
