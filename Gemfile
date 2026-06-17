source "https://rubygems.org"

# VOL-151: pinned with `~>` so patch updates flow through but minor/major
# bumps require an explicit decision. The Gemfile.lock (when present)
# pins exact versions for reproducible installs. Update tactic:
# 1. Bump the version in this Gemfile to the new minor (e.g. ~> 2.234)
# 2. `bundle update fastlane` locally on a runner-matched Ruby (.ruby-version)
# 3. Commit the updated Gemfile.lock alongside this Gemfile
gem "fastlane", "~> 2.236"
gem "xcodeproj", "~> 1.27"
