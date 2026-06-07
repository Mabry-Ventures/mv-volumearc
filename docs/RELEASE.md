# Release Process

## Pre-release checklist

- [ ] `VERSION` file bumped appropriately (semver)
- [ ] `CHANGELOG.md` updated (if we have one)
- [ ] All P0/P1 tickets for this version are closed
- [ ] Local build passes: `./scripts/build_release_targets.sh`
- [ ] Tests pass: `./scripts/test_apple_targets.sh`
- [ ] Release config validates: `./scripts/validate_release_config.sh`
- [ ] Release-ready validation passes: `VOLUMEARC_RELEASE_READY=1 ./scripts/validate_release_config.sh`
- [ ] Coach response eval trend is current, mirrored to marketing, and passes `./scripts/check_coach_eval_trend.sh` at 47/47
- [ ] Physical/TestFlight UAT evidence in `docs/RELEASE_UAT_EVIDENCE.md` is complete and passes `./scripts/check_release_uat_evidence.sh`
- [ ] Review `docs/FEATURES.md` for honest feature status
- [ ] Marketing site (`marketing/`) builds clean and the live `volumearc.app/terms` + `/privacy` URLs that `App/LegalLinks.swift` references resolve to non-placeholder content (VOL-124)

## Versioning

- **Marketing version** (`1.2.3`): read from `VERSION` file at repo root
- **Build number**: pinned to `1` in the committed pbxproj; release tooling (`scripts/archive_for_distribution.sh`, Fastlane `ios beta`) overrides `CURRENT_PROJECT_VERSION` to `git rev-list --count HEAD` at `xcodebuild archive` time, so TestFlight/App Store uploads keep a monotonic build number. Xcode Cloud uses `ci_scripts/ci_post_clone.sh` to patch the throwaway checked-out project to `CI_BUILD_NUMBER` before archive because that value is only available to the hook shell environment. Pass `BUILD_NUMBER=<n>` explicitly to force a specific value in local release tooling. (VOL-106 pinned the generator default; the prior behavior baked the git count into the pbxproj on every regen and cascaded UUID churn through `predictabilize_uuids`.)
- Bump `VERSION` in a dedicated PR before tagging

## TestFlight release

**As of 2026-05-04 (VOL-126), TestFlight deploys are owned by Xcode Cloud.** Apple-managed signing eliminates the cert/profile management overhead that blocked the earlier self-hosted Fastlane path. GitHub Actions still owns the substantive validation gates (build, tests, perf-regression, lint) — Xcode Cloud only owns archive + sign + upload.

### Current Xcode Cloud workflows

Live App Store Connect state checked on 2026-06-06:

| Workflow | Trigger | Actions | Distribution |
|---|---|---|---|
| `VolumeArc PR` | Pull requests into `main` | Build `VolumeArcApp`; test `VOL-PR` on iPhone 17 / iOS 26.5 | None |
| `VolumeArc Main` | Branch updates to `main` | Test `VOL-Main` | None |
| `Internal Testing` | Manual branch run, source `main` only | Archive `VolumeArcApp` | TestFlight internal only |

There is **no live tag-triggered TestFlight workflow** in App Store Connect today. Treat any older `Tag -> TestFlight` references as stale until a new Xcode Cloud workflow with a `v*` tag trigger is intentionally created and verified.

### Main → Internal TestFlight flow

1. Merge all changes to `main` after required GitHub and Xcode Cloud PR gates pass.
2. Bump `VERSION` if needed.
3. Run the live staging response eval suite against the selected relay/model routing, publish the resulting green trend to `docs/coach-eval-trend.json`, mirror it to `marketing/src/data/coach-eval-trend.json`, and verify:

   ```bash
   ./scripts/check_coach_eval_trend.sh
   ```

4. Run the local/static release config preflight:

   ```bash
   ./scripts/validate_release_config.sh --no-build
   ```

5. In App Store Connect, open Apps → VolumeArc → Xcode Cloud → `Internal Testing`.
6. Start a manual run from branch `main`.
7. Xcode Cloud archives the app with Apple-managed signing and uploads to internal TestFlight.
8. After archive, `ci_scripts/ci_post_xcodebuild.sh` verifies the archived app has `VolumeArcSentryDSN` and `VolumeArcAIRelayURL`, generates a matching `Sentry.framework.dSYM` from the archived framework binary, then runs `sentry-cli debug-files upload --include-sources --wait` against the archive's `dSYMs/` (VOL-133). Apple's auto-symbolication for App Store crashes still happens in parallel; this provides the same data to Sentry so our own crash reports symbolicate.
9. **TestFlight processing** usually takes 5-15 minutes. Watch in App Store Connect.
10. dSYMs must be visible in Sentry under https://mabry-ventures-llc.sentry.io/settings/projects/volumearc-ios/debug-symbols/ tagged with release `com.mabryventures.VolumeArc@<version>+<build>`.
11. Fill out `docs/RELEASE_UAT_EVIDENCE.md` for the exact TestFlight build and run `./scripts/check_release_uat_evidence.sh`.
12. Run the release-ready gate after TestFlight processing and physical UAT evidence exist:

   ```bash
   VOLUMEARC_RELEASE_READY=1 ./scripts/validate_release_config.sh --no-build
   ```

### Xcode Cloud setup target state

The current manual `Internal Testing` workflow is enough for controlled internal TestFlight builds from `main`, but it is not the desired long-term automation. Before GA, either:

- keep `Internal Testing` as a deliberate manual release step and document the operator, build number, and ASC run URL in `docs/RELEASE_UAT_EVIDENCE.md`; or
- create a separate `Tag -> TestFlight` workflow with a `v*` tag trigger, Archive action, Release configuration, and TestFlight internal distribution, then update this section after the first successful tag-driven build.

Every TestFlight-capable workflow must keep these Xcode Cloud environment variables configured:

- `SENTRY_DSN` — public client DSN for `mabry-ventures-llc/volumearc-ios`; required so TestFlight builds initialize Sentry.
- `SENTRY_AUTH_TOKEN` — mark as **secret**. Same token as the GitHub `SENTRY_AUTH_TOKEN` secret (Sentry user token with `project:write` on `mabry-ventures-llc/volumearc-ios`).
- `SENTRY_ORG` — `mabry-ventures-llc` (optional; script defaults to this).
- `SENTRY_PROJECT` — `volumearc-ios` (optional; script defaults to this).
- `VOLUMEARC_AI_RELAY_URL` — `https://relay.volumearc.app`.

Post-actions should remain empty because the dSYM upload runs from `ci_scripts/ci_post_xcodebuild.sh`, which Xcode Cloud invokes automatically after each archive.

### Local archive fallback

`fastlane ios beta` still works for local archive — useful for hotfixes or for pushing a build before Xcode Cloud picks up the tag. Requires:
- A local Apple Developer login in Xcode (Apple Distribution cert in keychain)
- The provisioning profile installed in `~/Library/MobileDevice/Provisioning Profiles/`
- `SENTRY_DSN` or `VOLUMEARC_SENTRY_DSN` env var set so the archived app initializes Sentry
- `VOLUMEARC_AI_RELAY_URL=https://relay.volumearc.app` env var set so the archived app uses the production coach relay
- `SENTRY_AUTH_TOKEN` env var set; the lane refuses to upload without Sentry dSYMs
- `DEVELOPMENT_TEAM` env var set
- `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_PATH` env vars set for App Store Connect access. `APP_STORE_CONNECT_API_KEY_PATH` points to the raw `.p8`; the Fastlane lane builds the API key object in memory and refuses group/world-readable key files.

```bash
export SENTRY_DSN=<public project DSN>
export VOLUMEARC_AI_RELAY_URL=https://relay.volumearc.app
export SENTRY_AUTH_TOKEN=<token>
export DEVELOPMENT_TEAM=A886EMZZW6
export APP_STORE_CONNECT_KEY_ID=YR7UQCU7GN
export APP_STORE_CONNECT_ISSUER_ID=69a6de72-e4ca-47e3-e053-5b8c7c11a4d1
export APP_STORE_CONNECT_API_KEY_PATH=/Users/jaredmabry/Downloads/AuthKey_YR7UQCU7GN.p8
chmod 600 "$APP_STORE_CONNECT_API_KEY_PATH"
bundle exec fastlane ios beta
```

Local archive uses your keychain certs directly; no fastlane match infrastructure required. Relay auth is App Attest-only; local archive tooling no longer patches client relay secrets into `App/Info.plist`.

### Required GitHub secrets (for the validation gates)

- `SENTRY_AUTH_TOKEN` — for the Sentry SDK init in dev/staging builds (separate concern from dSYM upload)
- `VOLUMEARC_PAT` — personal access token (only needed if cross-repo checkout returns)
- `VOLUMEARC_NATIVE_DEPLOY_KEY` — SSH key for the runner's git operations

Secrets that were previously required for the old GitHub Actions deploy path but are no longer used by CI (kept in case local devs use them or we add another integration):
- `DEVELOPMENT_TEAM`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_PATH`

### Marketing site

The public marketing site (`marketing/` directory) deploys independently to Vercel on every push to `main` and previews on every PR. See [`MARKETING.md`](MARKETING.md) for the full architecture.

The site hosts the legal pages that the iOS paywall links to via `App/LegalLinks.swift`:
- `volumearc.app/terms`
- `volumearc.app/privacy`

Until those pages are live with legal-counsel-reviewed content (VOL-124), App Store submission is blocked under Guideline 3.1.2.

### What-To-Test note (VOL-150)

Every `fastlane ios beta` invocation now generates a tester-facing What-To-Test note from `git log --pretty=format:"- %s" <previous-v-tag>..HEAD` and passes it to `upload_to_testflight` via the `changelog:` parameter. Testers see the bulleted list in the TestFlight app under "What to Test" instead of a generic "internal build" placeholder.

- **Source granularity**: per-commit. Squash-merged PRs land as one commit each, so the list is effectively per-PR. The subject is whatever the squash commit message reads — keep PR titles human-friendly so the auto-generated note doesn't leak `chore: ...` boilerplate to testers.
- **Length cap**: 3800 characters with a `...` truncation suffix on a line boundary. Apple's documented ceiling is 4000; the 200-char headroom absorbs any footer ASC appends.
- **No-previous-tag fallback**: a fresh checkout with no prior `v*` tag (or a `git describe` failure) falls back to a generic "see the PR list" message rather than blocking the upload. Same for any `git log` failure.
- **Manual override**: not currently exposed as a lane flag. If you need to override for a hotfix, run `bundle exec fastlane ios beta` with `changelog:` passed via `--changelog "..."` on the CLI — fastlane's auto-lane-arg shadowing wins over the helper's return value.

Slack notification on a successful TestFlight upload (`#testflight-builds @beta-testers` per VOL-150 AC #4) and the rejection variant (`#dev-alerts`) are deferred to VOL-177 Phase 2B which carries the `SLACK_BOT_TOKEN` repo-secret setup. Until then the workflow log + GitHub Actions email is the notification surface.

### Wait-for-processing behavior (VOL-96)

`fastlane ios beta` no longer sets `skip_waiting_for_build_processing`. After the `.ipa` is uploaded, Fastlane polls App Store Connect every 30 seconds until the build finishes processing or the **30-minute timeout** elapses (`wait_processing_timeout_duration: 1800`).

- **Success:** the lane captures `SharedValues::LATEST_TESTFLIGHT_BUILD_NUMBER` and, when running under GitHub Actions, appends `build_number=<N>` to `$GITHUB_OUTPUT`. Downstream workflow steps can read it via `${{ steps.<id>.outputs.build_number }}` — e.g. for release-notes, Slack notifications, or tagging the processed build back on the commit.
- **Failure:** if App Store Connect rejects processing (ITMS-xxxxx error) or the 30-minute timeout is reached, the lane calls `UI.user_error!` with a clean message. This replaces the old silent-success behavior where a rejected upload looked green in CI. Tag builds now fail loudly; fix the reported issue and re-tag to retry.

Reading the GitHub Actions output:

```yaml
- name: Upload to TestFlight
  id: testflight
  run: bundle exec fastlane ios beta

- name: Echo processed build number
  run: echo "Processed build ${{ steps.testflight.outputs.build_number }}"
```

### Signing & entitlements (VOL-70)

The iOS app ships **two** entitlements files, swapped per build configuration by `scripts/generate_xcode_project.rb`:

- `App/VolumeArc.Debug.entitlements` — `aps-environment = development` (APNs sandbox, used by Debug and simulator builds)
- `App/VolumeArc.Release.entitlements` — `aps-environment = production` (APNs production, required for Release-signed IPAs)

HealthKit, CloudKit, iCloud containers, and App Groups are identical across both files. Keep them in sync when adding capabilities. `scripts/validate_release_config.sh` hard-fails if the Release file drifts back to `development`, and the Xcode build settings assertion confirms `CODE_SIGN_ENTITLEMENTS = App/VolumeArc.Release.entitlements` for the Release configuration.

End-to-end verification (that the production APS token works end-to-end with APNs) only happens on a signed archive and TestFlight build — local simulator runs always use the Debug entitlements.

### Built-bundle validation (VOL-85, VOL-92)

`scripts/validate_release_config.sh` runs two complementary layers of built-artifact checks:

**Info.plist (VOL-85):** after a build, the script glob-searches `~/Library/Developer/Xcode/DerivedData/VolumeArcApple-*/Build/Products/{Release-iphoneos,Debug-iphonesimulator}/VolumeArc.app/Info.plist` and asserts `CFBundleURLTypes` still registers the `volumearc://` scheme, `BGTaskSchedulerPermittedIdentifiers` still lists both the `appRefresh` and `appProcessing` identifiers, and `UIBackgroundModes` survived. Catches Xcode's `ProcessInfoPlistFile` step dropping or rewriting a key at build time, independent of what's on disk in git.

**Signed entitlements (VOL-92):** for the same built `.app`, the script runs `codesign -d --entitlements - --xml` and asserts the embedded entitlements include:

- `aps-environment = production` (hard-fail on `development` — a Release IPA with sandbox APS silently drops every APNs push on TestFlight/App Store)
- `com.apple.developer.icloud-container-identifiers` contains `iCloud.com.mabryventures.VolumeArc`
- `com.apple.developer.healthkit` is boolean `true`
- `com.apple.security.application-groups` contains `group.com.mabryventures.volumearc`
- Signed `aps-environment` matches `App/VolumeArc.Release.entitlements` (catches stale-build-settings drift)

The watch bundle (`VolumeArcWatch.app`) is validated for HealthKit and App Groups only (it ships with a slimmer entitlements file). Widget and watchWidget extensions are intentionally out of scope for this pass — follow-up.

**When it runs:**
- Locally, any time you invoke `./scripts/validate_release_config.sh`. Without a built `.app` in DerivedData, the built-bundle sections log an `INFO: ...` message and skip gracefully — devs running the validator without archiving aren't forced to.
- In the `fastlane ios beta` lane (tag builds), the validator runs after `build_app` (gym) but before `upload_to_testflight`, with `VOLUMEARC_BUILT_APP_PATH` and `VOLUMEARC_BUILT_WATCH_PATH` pointing at the signed bundle inside the `.xcarchive`. A regression fails the lane before anything hits App Store Connect.
- Debug simulator builds are unsigned, so `codesign -d --entitlements -` returns empty output. The script detects this and logs `INFO: Built app bundle is unsigned (likely Debug simulator); skipping signed-entitlement assertions.` — no false positives.

**To exercise the signed-entitlement section locally**, produce a signed `.app` first. Either:
- Run a full archive: `./scripts/archive_for_distribution.sh` (requires the team's Apple Developer signing identity), or
- Adhoc-sign an existing Debug bundle for manual testing: `codesign -s - --entitlements App/VolumeArc.Release.entitlements --force <path-to-VolumeArc.app>`, then `VOLUMEARC_BUILT_APP_PATH=<path> ./scripts/validate_release_config.sh`.

## Dependency lockfile

VolumeArc tracks its SPM lockfile at **`Package.resolved`** in the repo root. This is the source of truth for every dependency the app links — right now that's just `sentry-cocoa`, but the same discipline applies to anything added via `scripts/generate_xcode_project.rb`.

**Why the root path and not the Xcode default?** Xcode writes its workspace copy to `VolumeArcApple.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, but the whole `project.xcworkspace/` directory is gitignored because the Xcode project is regenerated by `ruby scripts/generate_xcode_project.rb`. Tracking only the workspace copy meant every dev and CI run could resolve a different commit without anyone noticing until a build broke. The root copy is outside the ignored directory, so git sees it.

Flow:
1. `ruby scripts/generate_xcode_project.rb` builds the project and seeds `project.xcworkspace/.../Package.resolved` from the root copy if present (new-clone case).
2. CI's "Seed SPM lockfile into workspace" step also copies `Package.resolved` into the workspace before the build runs, belt-and-suspenders.
3. `xcodebuild -resolvePackageDependencies` (driven by the build step) reads the seeded workspace copy and resolves against the pinned revisions instead of the upstream index.
4. `scripts/validate_release_config.sh` compares the two copies and fails if the `sentry-cocoa` pin drifts.

**When Dependabot bumps Sentry** (VOL-78 wiring), the PR must update both the version pin in `scripts/generate_xcode_project.rb` and the tracked `Package.resolved` at repo root. CI refuses to pass a PR where those disagree.

**To refresh the lockfile manually** (after changing a dependency in the generator):

```bash
ruby scripts/generate_xcode_project.rb
xcodebuild -resolvePackageDependencies -project VolumeArcApple.xcodeproj
cp VolumeArcApple.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved Package.resolved
```

Commit the updated `Package.resolved` alongside the generator change.

## App Store release

1. Verify TestFlight build is stable with at least 3 testers
2. Tag with `-rc` suffix if doing a release candidate
3. Run `fastlane ios release` which:
   - Runs the `beta` lane (waits for processing, fails loudly on rejection)
   - Runs the `screenshots` lane (see below) to regenerate App Store listing assets
   - Submits for review via `deliver` with `skip_screenshots: false` so the fresh artifacts upload with the metadata
4. Monitor App Store Connect for review status
5. Release manually when approved

### Screenshots lane (VOL-96)

`fastlane ios screenshots` drives `snapshot` against the device matrix declared in [`fastlane/Snapfile`](../fastlane/Snapfile). Output lives in `fastlane/screenshots/` and is picked up automatically by `deliver` during the `release` lane. Screenshot capture uses the dedicated `VolumeArcScreenshots` scheme, whose TestAction sets `VOLUMEARC_RUN_SCREENSHOT_CAPTURE=1`; the ordinary UI-test schemes omit that variable so release screenshots never run during routine CI.

The screenshot test class is compiled in `VolumeArcAppUITests` but explicitly excluded from the normal `scripts/test_apple_targets.sh` UI shards. This keeps routine CI from reporting a permanent skip while preserving the release-lane capture path.

Current matrix:

| Device | App Store class |
| --- | --- |
| iPhone 17 | 6.3" |
| iPhone 17 Pro Max | 6.9" |
| Apple Watch Series 11 (46mm) | watchOS |

Current languages: `en-US`.

#### Adding a new locale

1. Add the locale code to the `languages([...])` array in `fastlane/Snapfile` (e.g. `"de-DE"`).
2. Ensure the UI test flows launch the app with the matching `-AppleLanguages` / `-AppleLocale` arguments so `snapshot("name")` captures the localized screens.
3. Run `fastlane ios screenshots` locally to confirm the new folder appears under `fastlane/screenshots/<locale>/`.
4. Commit the Snapfile change alongside any App Store metadata (`fastlane/metadata/<locale>/`) that accompanies the launch.

#### Screenshot capture flow

`VolumeArcScreenshotTests` launches seeded app states, calls `setupSnapshot(app)`, and attaches named screenshots with `snapshot("name")`. The UI test target includes the local `SnapshotHelper.swift`, and `scripts/generate_xcode_project.rb` picks up both files through the existing UI test source glob.

### Xcode Cloud wait gate

Before cutting or submitting a build from a new main SHA, wait for both authoritative Xcode Cloud signals on that exact commit:

- `VolumeArc | VolumeArc Main | VOL-Main - iOS`
- `VolumeArc | Internal Testing - Archive - iOS`

The self-hosted GitHub Actions `Build & Test` job is still useful diagnostic signal, but it is not a required merge check while the self-hosted simulator runner is unstable. Simulator/XCTRunner infrastructure flakes are classified through [`docs/TESTING.md`](TESTING.md#ci-runner-flake-taxonomy-vol-227-cluster). Xcode Cloud remains the release gate of record; the branch ruleset requires CodeRabbit, Codex, Repo Hygiene, and the Xcode Cloud PR context.

## Rollback

If a release introduces a regression:

1. Revert the offending commit on `main`
2. Bump `VERSION` patch number
3. Tag and push — CI will build and deploy the fix
4. File a ticket with the incident postmortem

For the full incident-response runbook — severity ladder, Sentry alert routing, postmortem template, and per-subsystem failure-shape runbooks — see [`docs/INCIDENTS.md`](INCIDENTS.md). The `fastlane ios rollback` lane is VOL-156 Phase 2.

## Hotfix process

For critical production issues:

1. Branch from the last released tag: `git checkout -b hotfix/v1.2.4 v1.2.3`
2. Apply the minimum necessary fix
3. Bump `VERSION` to patch
4. Tag and push
5. Cherry-pick the fix back to `main` afterward
