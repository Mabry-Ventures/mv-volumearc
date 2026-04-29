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

if [[ -n "${GITHUB_PATH:-}" ]]; then
  {
    echo "$ruby_bin"
    echo "$gem_user_bin"
    echo "$gem_bindir"
  } >> "$GITHUB_PATH"
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
