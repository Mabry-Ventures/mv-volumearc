# Contributing to VolumeArc

## Dev setup

1. Install Xcode 26.4+
2. Install the pinned Ruby (see `.ruby-version`, currently `4.0`):
   ```bash
   brew install ruby           # Homebrew currently provides 4.0.3
   ```
3. Install gems (versions pinned in `Gemfile`, exact pins in `Gemfile.lock` when present):
   ```bash
   gem install bundler
   bundle install              # installs fastlane + xcodeproj at pinned versions
   # Or, if you don't want bundler in the loop:
   gem install --user-install xcodeproj -v '~> 1.27'
   ```
4. Install SwiftLint (≥ 0.62; CI asserts):
   ```bash
   brew install swiftlint
   ```
5. Clone the repo:
   ```bash
   git clone https://github.com/Mabry-Ventures/mv-volumearc.git
   cd mv-volumearc
   ```
6. Generate the Xcode project:
   ```bash
   ruby scripts/generate_xcode_project.rb
   ```
7. Open `VolumeArcApple.xcodeproj` in Xcode

### Toolchain pinning (VOL-151)

The repo declares its expected versions in three places so a Homebrew or RubyGems bump doesn't silently break CI:

| Tool | Pin file | Constraint |
|---|---|---|
| Xcode | CI assertion in `ci.yml` | ≥ 26.4 |
| Ruby | `.ruby-version` | major.minor (currently `4.0`) — CI warns on drift |
| `xcodeproj` gem | `Gemfile` | `~> 1.27` |
| `fastlane` gem | `Gemfile` | `~> 2.233` |
| SwiftLint | CI assertion in `ci.yml` | ≥ 0.62; warns on 1.x major |

When updating a pin: bump the constraint, run the relevant tool locally, verify CI green on a small PR before bulk work depends on the change.

## Build commands

```bash
./scripts/build_all_targets.sh        # Debug build
./scripts/build_release_targets.sh    # Release build
./scripts/test_apple_targets.sh       # Run tests
./scripts/validate_release_config.sh  # Validate release config
```

## Build system: the Xcode project is generated

`VolumeArcApple.xcodeproj` is produced from scratch by `ruby scripts/generate_xcode_project.rb`. **Never edit `project.pbxproj` or the scheme files by hand** — your change will be overwritten on the next regeneration. Add/remove targets, files, frameworks, build settings, and schemes in `scripts/generate_xcode_project.rb` and re-run the generator.

### Deterministic output (VOL-95, VOL-106)

Running the generator twice in a row produces **byte-identical** output, *and* running it over the committed `VolumeArcApple.xcodeproj` produces **zero diff**. Both properties are load-bearing for merge hygiene: without the first, every regen would randomize all ~360 pbxproj object UUIDs plus every `xcscheme` `BlueprintIdentifier`; without the second, a volatile input (originally `git rev-list --count HEAD` for `CURRENT_PROJECT_VERSION`) would cascade ~300 lines of UUID churn onto every PR branch through `predictabilize_uuids`.

The determinism comes from three pieces in `scripts/generate_xcode_project.rb`:

1. A monkey-patch on `Xcodeproj::Project::UUIDGenerator#uuid_for_path` that truncates the gem's MD5-based UUID to 24 chars (matching Xcode's native 12-byte convention).
2. Two consecutive calls to `project.predictabilize_uuids` immediately before `project.save`, so all object UUIDs — and the subsequent scheme `BlueprintIdentifier` references — are hash-derived from the object graph, not from `SecureRandom`.
3. Zero git-derived inputs: `BUILD_NUMBER` defaults to the static string `'1'` when the env var is unset. Release tooling (`archive_for_distribution.sh`, Fastlane `ios beta`) passes `BUILD_NUMBER` explicitly before archiving, and `xcodebuild archive` also overrides `CURRENT_PROJECT_VERSION` at build time — so TestFlight/App Store uploads still get the monotonic git count while the committed pbxproj stays stable.

Two CI gates enforce these properties:

- **`scripts/test_xcode_project_determinism.sh`** (VOL-95): regenerates twice from empty and diffs the SHA256 hashes. Catches a regression where the generator produces nondeterministic output (e.g., a Hash with Symbol keys that breaks `predictabilize_uuids`' tree-hash walk — stick to String keys for attributes like `XCRemoteSwiftPackageReference.requirement`).
- **`scripts/test_xcode_project_regen_idempotent.sh`** (VOL-106): regenerates over the committed project and fails on any `git diff`. Catches drift between the committed pbxproj and what the generator produces — usually because a contributor added a source file without regenerating, or a volatile input leaked back into the generator.

Practical consequences:

- You don't have to hand-commit pbxproj churn. After you change the generator or add/remove source files, run `ruby scripts/generate_xcode_project.rb` and commit the result. If the no-op regen gate fails on your PR, that's what it's asking you to do.

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
7. AI Review Gate runs automatically: CodeRabbit Pro (primary reviewer) and Codex Code Review (secondary reviewer) are both requested by the `Request AI Reviews` workflow step. Both must post a review signal on the current head SHA within their wait window or the gate fails.
8. Merge via squash when all checks pass

### Branch cleanup after merge

`gh pr merge --squash --delete-branch` deletes the remote branch automatically — but only when no local worktree has that branch checked out. The common interaction failure is: an open `mv-volumearc` worktree is on `main`, and `gh pr merge` tries to remove the merged branch locally first, which fails with `'main' is already used by worktree at ...`. The remote branch stays around even though main got the squash commit.

To clean up the accumulated drift periodically:

```bash
gh pr list --state merged --limit 200 --json headRefName --jq '.[].headRefName' | sort -u > /tmp/merged.txt
git ls-remote --heads origin 'claude/*' 'jared/*' 'codex/*' 'feature/*' 'fix/*' 'sprint/*' \
  | awk '{print $2}' | sed 's|refs/heads/||' | sort -u > /tmp/remote.txt
comm -12 /tmp/merged.txt /tmp/remote.txt | while read -r ref; do
  git push origin --delete "$ref"
done
```

`comm -12` outputs only lines present in both files (i.e. branches that are squash-merged AND still on origin). Running this once per cycle keeps the remote tidy. VOL-165 captured this as a one-time cleanup; the loop above is the recurring fix.

### Required status checks (enforced by repository ruleset)

The `Require AI Code Reviews` ruleset on `main` requires the following checks to pass before merge — there is no "advisory" mode:

- `Build & Test` — full iOS/watchOS pipeline on the `mv-shared` self-hosted runner
- `CodeRabbit Code Review` — wait-for-signal job (20-minute window) in `ai-review-gate.yml`
- `Codex Code Review` — wait-for-signal job (15-minute window) in `ai-review-gate.yml`

`strict_required_status_checks_policy: true` is set, meaning the PR branch must be up-to-date with `main` before merge. Stale PRs need a rebase or merge from main to retrigger CI.

### Bypass / emergency hotfix

The ruleset's `bypass_actors` list grants Organization Admins a `pull_request`-scoped bypass — i.e. an org admin can merge a PR without all required checks passing, but must still go through a pull request (no direct push to `main`). This exists for genuine emergencies only:

- A SEV1 production incident requiring an immediate hotfix
- A CI infrastructure outage that's blocking valid PRs

Every bypass should be documented in `docs/incident-log.md` with the reason and a follow-up ticket to fix whatever forced the bypass.

### Forked PRs

The `mv-shared` self-hosted CI runner is privileged (Apple Developer signing identity, Keychain, decoded SSH key, persistent DerivedData) so PRs from external forks **do not run CI** (VOL-132). The `Build & Test`, `Performance budgets`, and `Deploy to TestFlight` jobs all carry an `if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository` guard that skips them on fork PRs.

External contributors should ask a maintainer to push their branch directly into the upstream repo — that branch then triggers CI normally. Until then the AI review gate will time out (no `Build & Test` signal), which is the correct behavior.

## Code style

- Follow the existing patterns in the codebase
- Use design tokens (`VA.Colors`, `VA.Typography`, etc.) — never hardcode visual values
- Use `VAHaptics.*` for all tactile feedback
- Use `String(localized:comment:)` for all user-facing strings
- Pluralized strings use `^[\(count) thing](inflect: true)` for CLDR plural agreement. Enum display labels live in `LocalizedLabels.swift`, not inline in views.
- Add accessibility labels to interactive elements
- Respect `@Environment(\.accessibilityReduceMotion)` for animations

### Lint scope

SwiftLint (`.swiftlint.yml`) covers the full first-party Swift surface: `App`, `Watch`, `Widgets`, `WatchWidgets`, `Tests`, and `VolumeArcNative/Sources` — the expanded scope landed in VOL-89 / PR #59. The CI lint step runs non-strict against the whole scope and hard-fails on any error-level violation (VOL-77 / PR #47). Pre-existing violations are tracked in VOL-87's progressive cleanup burndown. Warning thresholds are kept intentionally tight so debt stays visible in the CI log even while error thresholds are relaxed. Do not widen thresholds or add per-file disable comments to paper over new violations; fix them instead.

A `Tests/.swiftlint.yml` override disables `implicitly_unwrapped_optional`, `force_unwrapping`, and length rules inside the test directory — the `var sut: SUT!` + `URL(string:)!` patterns are intentional contracts in XCTestCase code, not production bugs.

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

<!-- VOL-89 lint scope expansion landed via this PR -->
