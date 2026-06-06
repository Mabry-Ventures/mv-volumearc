#!/usr/bin/env bash
set -euo pipefail

command -v brew >/dev/null || { echo "::error::Homebrew missing on runner"; exit 1; }

if ! brew list ruby >/dev/null 2>&1; then
  brew install ruby
fi

ruby_prefix="$(brew --prefix ruby)"
ruby_bin="$ruby_prefix/bin"
export PATH="$ruby_bin:$PATH"

gem_user_bin="$(ruby -e 'print Gem.user_dir')/bin"
gem_bindir="$(ruby -e 'print Gem.bindir')"
export PATH="$ruby_bin:$gem_user_bin:$gem_bindir:$PATH"
workspace_root="${GITHUB_WORKSPACE:-$PWD}"
bundle_path="$workspace_root/vendor/bundle"
bundle_user_home="$workspace_root/.bundle"

export BUNDLE_PATH="$bundle_path"
export BUNDLE_USER_HOME="$bundle_user_home"
export BUNDLE_APP_CONFIG="$bundle_user_home/config"
export BUNDLE_USER_CACHE="$bundle_user_home/cache"
export BUNDLE_JOBS="${BUNDLE_JOBS:-4}"
export BUNDLE_RETRY="${BUNDLE_RETRY:-3}"

if [[ -n "${GITHUB_PATH:-}" ]]; then
  {
    echo "$ruby_bin"
    echo "$gem_user_bin"
    echo "$gem_bindir"
  } >> "$GITHUB_PATH"
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "BUNDLE_PATH=$BUNDLE_PATH"
    echo "BUNDLE_USER_HOME=$BUNDLE_USER_HOME"
    echo "BUNDLE_APP_CONFIG=$BUNDLE_APP_CONFIG"
    echo "BUNDLE_USER_CACHE=$BUNDLE_USER_CACHE"
    echo "BUNDLE_JOBS=$BUNDLE_JOBS"
    echo "BUNDLE_RETRY=$BUNDLE_RETRY"
  } >> "$GITHUB_ENV"
fi

ruby --version

if [[ "$#" -gt 0 ]]; then
  gem install --user-install "$@" -N
fi

for gem_name in "$@"; do
  if [[ "$gem_name" == -* || "$gem_name" == *[~\<\>=:]* || ! "$gem_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "::warning::Skipping Ruby gem verification for non-gem argument '$gem_name'"
    continue
  fi

  gem list --installed "$gem_name" >/dev/null
done
