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
