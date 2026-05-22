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
# VOL-246: fail-fast hygiene gate (Xcode Cloud).
#
# Runs BEFORE xcodebuild for every workflow (PR, Main, archive). A
# non-zero exit aborts the Xcode Cloud build before the expensive
# compile/test phase — so a lint regression turns the workflow's check
# RED at the cheapest possible point. This is the gate the migration's
# negative-control test exercises: a deliberate `swiftlint --strict`
# violation must fail the "VOL PR" check here.
#
# Scope note: only checks that are (a) workspace-safe (do NOT regenerate
# the Xcode project) and (b) runnable on Apple's clean Xcode Cloud image
# (no `xcodeproj` gem) live here — currently `swiftlint --strict` and
# `validate_release_config.sh --no-build`. The four generator-shape /
# watch gates that need the `xcodeproj` gem and/or a project regen
# (test_xcode_project_determinism, test_xcode_project_regen_idempotent,
# test_watch_app_embedding, validate_watch_app_icon_asset) still run in
# the self-hosted `ci.yml` "Build & Test" job. They MUST be rehomed
# before that job is disabled at cutover — see the cutover checklist on
# the migration PR (the "rehome project-shape gates" blocker).
echo "VOL-246: running fail-fast hygiene gate"
if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint not on PATH; installing via Homebrew (available on Xcode Cloud images)"
  brew install swiftlint
fi
swiftlint_version="$(swiftlint version 2>/dev/null | head -n1 | awk '{print $NF}')"
swiftlint_major="$(printf '%s\n' "$swiftlint_version" | cut -d. -f1)"
swiftlint_minor="$(printf '%s\n' "$swiftlint_version" | cut -d. -f2)"
# Match the >= 0.62 floor the self-hosted `ci.yml` enforces — the repo's
# `.swiftlint.yml` rule config is tuned against that minor.
if [[ "$swiftlint_major" -eq 0 && "$swiftlint_minor" -lt 62 ]]; then
  echo "::error::SwiftLint $swiftlint_version is below the 0.62 floor (rule config tuned against >= 0.62)"
  exit 1
fi
echo "SwiftLint $swiftlint_version: running --strict from $REPO_ROOT"
( cd "$REPO_ROOT" && swiftlint --strict )

# Release-config static checks (entitlements, privacy manifests,
# app-group / CloudKit container constants). `--no-build` skips the
# project regen + SPM resolve + xcodebuild, so it's workspace-safe and
# needs neither the `xcodeproj` gem nor a build — just `plutil`, which
# is present on the Xcode Cloud macOS image. The regen-dependent project
# gates run in `project-hygiene.yml` on GitHub-hosted Linux instead.
echo "VOL-246: running validate_release_config.sh --no-build"
( cd "$REPO_ROOT" && ./scripts/validate_release_config.sh --no-build )
echo "VOL-246: hygiene gate passed"

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
  # VOL-196: relay signing key release-time injection. Without this,
  # release builds carry a relay URL but no auth material, and the
  # `AIRelayCoachProvider` factory installs the relay path while the
  # provider throws `relayUnavailable` on every request — cloud AI
  # and live voice silently degrade in TestFlight/App Store builds.
  # The companion validator at `scripts/validate_exported_ipa_contract.sh`
  # fails the archive if the URL is present but the signing key is
  # missing, so a release build can't ship with this configuration
  # error undetected. The medium-term plan (VOL-206) is App Attest —
  # see this PR's `App/VolumeArcAppAttestSessionProvider.swift` for the
  # Phase A scaffolding that runs alongside the HMAC path during rollout.
  if [[ -n "${VOLUMEARC_RELAY_SIGNING_KEY:-}" ]]; then
    plutil -replace VolumeArcRelaySigningKey -string "$VOLUMEARC_RELAY_SIGNING_KEY" "$INFO_PLIST"
    echo "Patched VolumeArcRelaySigningKey into Info.plist (len=${#VOLUMEARC_RELAY_SIGNING_KEY})"
  else
    echo "VOLUMEARC_RELAY_SIGNING_KEY env var unset; leaving Info.plist placeholder. Release builds without this set will fail validate_exported_ipa_contract.sh."
  fi
else
  echo "WARNING: Info.plist not found at $INFO_PLIST — runtime config not patched"
fi

# Xcode Cloud assigns a monotonically increasing CI_BUILD_NUMBER, but that
# value is only a shell environment variable. Patch the checked-out generated
# project for archive workflows so CURRENT_PROJECT_VERSION is baked into every
# app/extension target before Xcode Cloud invokes xcodebuild. Do this directly
# instead of regenerating the project: Apple's clean Xcode Cloud image does not
# include the Ruby xcodeproj gem.
if [[ "${CI_XCODEBUILD_ACTION:-}" == "archive" && -n "${CI_BUILD_NUMBER:-}" ]]; then
  if [[ ! "$CI_BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "ERROR: CI_BUILD_NUMBER must be numeric: $CI_BUILD_NUMBER" >&2
    exit 1
  fi

  PROJECT_FILE="$REPO_ROOT/VolumeArcApple.xcodeproj/project.pbxproj"
  if [[ ! -f "$PROJECT_FILE" ]]; then
    echo "ERROR: Xcode project file not found at $PROJECT_FILE" >&2
    exit 1
  fi

  /usr/bin/perl -0pi -e "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};/g" "$PROJECT_FILE"
  patched_count="$(grep -c "CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};" "$PROJECT_FILE" || true)"
  if [[ "$patched_count" -eq 0 ]]; then
    echo "ERROR: Failed to patch CURRENT_PROJECT_VERSION in $PROJECT_FILE" >&2
    exit 1
  fi
  echo "Patched CURRENT_PROJECT_VERSION to ${CI_BUILD_NUMBER} in Xcode project (${patched_count} build settings)"
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
