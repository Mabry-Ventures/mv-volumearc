#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby <<'RUBY'
tracked_files = `git ls-files`.split("\n")

emoji_regex = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]/
current_docs = %w[
  README.md
  CLAUDE.md
  docs/PLATFORM.md
  docs/FEATURES.md
  docs/MARKETING.md
  docs/PRODUCT_POSITIONING.md
  docs/AUDIT.md
  docs/USER_JOURNEYS.md
  marketing/README.md
  fastlane/metadata/README.md
]
markdown_files = (current_docs + Dir["docs/**/*.md"]).uniq
stale_active_terms = [
  "Go-Live Readiness",
  "Production Launch Quality",
  "VolumeArc Production Readiness"
]
launch_claim_patterns = [
  /\bVolumeArc is production-ready\b/i,
  /\bfully production-ready\b/i,
  /\bpaid-launch-ready\b/i,
  /\bsubmit-ready\b/i
]
placeholder_patterns = [
  /\bTBD\b/i,
  /ACTION REQUIRED/i,
  /TODO\(VOL-91/i,
  /confirm final pricing/i,
  /pending legal review/i,
  /placeholder structure/i,
  /lorem ipsum/i,
  /<strong>Draft<\/strong>/i
]
placeholder_checked_files = %w[
  marketing/src/components/Pricing.tsx
  marketing/src/app/(main)/terms/page.tsx
  marketing/src/app/(main)/privacy/page.tsx
  fastlane/metadata/en-US/description.txt
  fastlane/metadata/en-US/promotional_text.txt
  fastlane/metadata/en-US/release_notes.txt
  fastlane/metadata/en-US/subtitle.txt
  fastlane/metadata/en-US/keywords.txt
  fastlane/metadata/en-US/review_information/notes.txt
]
product_voice_checked_files = Dir[
  "App/**/*.swift",
  "VolumeArcNative/Sources/VolumeArcUI/**/*.swift",
  "Watch/**/*.swift",
  "Widgets/**/*.swift"
] + %w[
  marketing/src/app/layout.tsx
  marketing/src/components/Faqs.tsx
  marketing/src/components/Pricing.tsx
  marketing/src/components/PrimaryFeatures.tsx
  fastlane/metadata/en-US/description.txt
  fastlane/metadata/en-US/promotional_text.txt
  fastlane/metadata/en-US/release_notes.txt
  fastlane/metadata/en-US/subtitle.txt
]
product_voice_patterns = [
  /AI-powered strength/i,
  /AI coach/i,
  /AI coaching may use/i,
  /Google Gemini when you're online/i,
  # VOL-279/VOL-281 positioning rule (docs/PRODUCT_POSITIONING.md):
  # VolumeArc is the AI strength programming coach — generic coach
  # framings collide with free/bundled platform coaches and must not
  # drift back into product surfaces.
  /fitness coach/i,
  /wellness coach/i,
  /personal trainer/i,
]

failures = []

tracked_files.each do |path|
  next unless File.file?(path)
  next if path.start_with?("marketing/node_modules/", "marketing/.next/", "marketing/test-results/", "marketing/playwright-report/")

  data = File.binread(path)
  text = data.force_encoding("UTF-8")
  next unless text.valid_encoding?

  text.each_line.with_index(1) do |line, line_number|
    failures << "#{path}:#{line_number}: emoji character is not allowed in tracked source/docs/scripts" if line.match?(emoji_regex)
  end
end

current_docs.each do |path|
  next unless File.file?(path)

  text = File.read(path, encoding: "UTF-8")
  stale_active_terms.each do |term|
    next unless text.include?(term)

    failures << "#{path}: stale active project term '#{term}' must point at VolumeArc Release instead"
  end

  text.each_line.with_index(1) do |line, line_number|
    launch_claim_patterns.each do |pattern|
      next unless line.match?(pattern)
      next if line.match?(/\b(not|no|cannot|do not|until)\b/i)

      failures << "#{path}:#{line_number}: unsupported launch-readiness claim must be release-gated"
    end
  end
end

placeholder_checked_files.each do |path|
  unless File.file?(path)
    failures << "#{path}: required placeholder/legal/App Store check input is missing"
    next
  end

  text = File.read(path, encoding: "UTF-8")
  placeholder_patterns.each do |pattern|
    next unless text.match?(pattern)

    failures << "#{path}: placeholder pricing/legal/App Store marker matched #{pattern.inspect}"
  end
end

product_voice_checked_files.each do |path|
  unless File.file?(path)
    failures << "#{path}: required product-voice check input is missing"
    next
  end

  text = File.read(path, encoding: "UTF-8")
  text.each_line.with_index(1) do |line, line_number|
    product_voice_patterns.each do |pattern|
      next unless line.match?(pattern)

      failures << "#{path}:#{line_number}: user-facing product copy should say coach/cloud/safety, not AI/provider branding"
    end
  end
end

markdown_files.each do |path|
  next unless File.file?(path)

  text = File.read(path, encoding: "UTF-8")
  text.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |target|
    target = target.strip
    target = target[1..-2] if target.start_with?("<") && target.end_with?(">")
    next if target.empty?
    next if target.start_with?("#")
    next if target.match?(/\A[a-z][a-z0-9+.-]*:/i)

    link_path = target.split("#", 2).first
    link_path = link_path.split("?", 2).first
    next if link_path.empty?

    absolute = File.expand_path(link_path, File.dirname(path))
    failures << "#{path}: broken local markdown link '#{target}'" unless File.exist?(absolute)
  end
end

if failures.any?
  warn "check_release_hygiene: #{failures.length} failure(s)"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "check_release_hygiene: no emoji, stale release terms, or product-voice drift found."
RUBY
