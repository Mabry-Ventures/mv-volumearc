# Contributing to VolumeArc

## Dev setup

1. Install Xcode 26.4+
2. Install Ruby with `xcodeproj` gem:
   ```bash
   gem install --user-install xcodeproj
   ```
3. Clone the repo:
   ```bash
   git clone https://github.com/Mabry-Ventures/mv-volumearc.git
   cd mv-volumearc
   ```
4. Generate the Xcode project:
   ```bash
   ruby scripts/generate_xcode_project.rb
   ```
5. Open `VolumeArcApple.xcodeproj` in Xcode

## Build commands

```bash
./scripts/build_all_targets.sh        # Debug build
./scripts/build_release_targets.sh    # Release build
./scripts/test_apple_targets.sh       # Run tests
./scripts/validate_release_config.sh  # Validate release config
```

## Branch strategy

- `main` — production branch, protected
- `feature/*` — new features
- `fix/*` — bug fixes
- `sprint/*` — larger multi-ticket efforts

## PR process

1. Create a branch from `main`
2. Make your changes
3. Push the branch
4. Open a PR with a clear title and description
5. CI must pass (build, test, lint, validate)
6. At least one code review required
7. AI Review Gate runs automatically: CodeRabbit Pro (primary reviewer, auto-invoked on PR open/update) and Codex Code Review (secondary, requested by the `Request AI Reviews` workflow step). Both must post a review signal on the current head SHA within their wait window or the gate fails.
8. Merge via squash when all checks pass

## Code style

- Follow the existing patterns in the codebase
- Use design tokens (`VA.Colors`, `VA.Typography`, etc.) — never hardcode visual values
- Use `VAHaptics.*` for all tactile feedback
- Use `String(localized:comment:)` for all user-facing strings
- Pluralized strings use `^[\(count) thing](inflect: true)` for CLDR plural agreement. Enum display labels live in `LocalizedLabels.swift`, not inline in views.
- Add accessibility labels to interactive elements
- Respect `@Environment(\.accessibilityReduceMotion)` for animations

### Lint scope

SwiftLint (`.swiftlint.yml`) covers the full first-party Swift surface: `App`, `Watch`, `Widgets`, `WatchWidgets`, `Tests`, and `VolumeArcNative/Sources`. The CI lint step runs non-strict against the whole scope — pre-existing violations are tracked in VOL-87's progressive cleanup burndown. Warning thresholds are kept intentionally tight so debt stays visible in the CI log even while error thresholds are relaxed. Do not widen thresholds or add per-file disable comments to paper over new violations; fix them instead.

## Testing

- Unit tests for business logic
- XCUITest smoke tests for launch stability and root-dashboard visibility
- Tests live in `Tests/VolumeArcAppTests/` and `Tests/VolumeArcAppUITests/`
- `./scripts/test_apple_targets.sh` runs both `VolumeArcAppTests` and `VolumeArcAppUITests`
- CI runs both schemes on every PR

## Documentation

- `docs/PLATFORM.md` — **canonical platform reference** (start here)
- Architecture decisions: `docs/ARCHITECTURE.md`
- Feature status: `docs/FEATURES.md` (update with every PR that changes feature state)
- Design system: `docs/DESIGN_SYSTEM.md`
- Release process: `docs/RELEASE.md`
- Contributor guide: this file

## Review expectations

- Review for correctness, not style (lint handles style)
- Flag any new hardcoded values that should be tokens
- Flag any missing accessibility labels
- Flag any missing haptic feedback on user actions
- Flag any `try?` or silent error swallowing
- Flag any retain cycles in async code

## Templates

- **PR template**: New pull requests auto-populate from [`.github/PULL_REQUEST_TEMPLATE.md`](../.github/PULL_REQUEST_TEMPLATE.md). Fill in the summary, linked Linear ticket, acceptance criteria, and test plan before requesting review.
- **Issue templates**: The bug report and feature request templates under [`.github/ISSUE_TEMPLATE/`](../.github/ISSUE_TEMPLATE/) exist for external bug reports and feature requests. Internal engineering work is tracked in [Linear](https://linear.app/mabry-ventures/team/VOL), not GitHub issues — blank issues are disabled to reinforce this.
- **Dependabot**: [`.github/dependabot.yml`](../.github/dependabot.yml) opens weekly PRs for Swift (SwiftPM / `Package.resolved`), GitHub Actions, and Bundler (`Gemfile`) updates. Minor and patch updates are grouped per ecosystem so we don't get flooded; majors still land as individual PRs.
- **CODEOWNERS**: [`.github/CODEOWNERS`](../.github/CODEOWNERS) currently routes every path to `@jaredmabry`. Add module-specific owners there as the team grows.
