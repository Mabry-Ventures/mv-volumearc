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
#                       `project:releases` scopes.
#   SENTRY_ORG        — defaults to `mabry-ventures-llc`
#   SENTRY_PROJECT    — defaults to `volumearc-ios`
#
# Failure here fails the workflow: a silent dSYM-upload miss is
# exactly the bug VOL-133 was created to prevent.

set -euo pipefail

echo "VOL-126: ci_post_xcodebuild.sh starting"
echo "CI_WORKFLOW = ${CI_WORKFLOW:-<unset>}"
echo "CI_XCODEBUILD_ACTION = ${CI_XCODEBUILD_ACTION:-<unset>}"
echo "CI_ARCHIVE_PATH = ${CI_ARCHIVE_PATH:-<unset>}"

# Only run on archive workflows. For test/build workflows there's no
# .xcarchive to extract dSYMs from.
if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
  echo "VOL-126: not an archive workflow (action=${CI_XCODEBUILD_ACTION:-none}); skipping dSYM upload"
  exit 0
fi

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  echo "::warning::SENTRY_AUTH_TOKEN unset — skipping dSYM upload. Crashes from this build will arrive in Sentry as obfuscated frames."
  echo "  Set SENTRY_AUTH_TOKEN as a secret env var in the Xcode Cloud workflow to fix."
  exit 0
fi

if [[ -z "${CI_ARCHIVE_PATH:-}" || ! -d "${CI_ARCHIVE_PATH}" ]]; then
  echo "::error::VOL-133: CI_ARCHIVE_PATH unset or not a directory: ${CI_ARCHIVE_PATH:-<empty>}"
  exit 1
fi

DSYM_DIR="${CI_ARCHIVE_PATH}/dSYMs"
if [[ ! -d "${DSYM_DIR}" ]] || [[ -z "$(ls -A "${DSYM_DIR}" 2>/dev/null)" ]]; then
  echo "::error::VOL-133: dSYM directory missing or empty at ${DSYM_DIR}"
  exit 1
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "::error::sentry-cli not on PATH — ci_post_clone.sh should have installed it"
  exit 1
fi

SENTRY_ORG="${SENTRY_ORG:-mabry-ventures-llc}"
SENTRY_PROJECT="${SENTRY_PROJECT:-volumearc-ios}"

echo "VOL-133: uploading dSYMs from ${DSYM_DIR} → ${SENTRY_ORG}/${SENTRY_PROJECT}"
sentry-cli debug-files upload \
  --org "${SENTRY_ORG}" \
  --project "${SENTRY_PROJECT}" \
  --include-sources \
  --wait \
  --log-level=info \
  "${DSYM_DIR}"

echo "VOL-133: dSYM upload complete"
