# Release Process

## Pre-release checklist

- [ ] `VERSION` file bumped appropriately (semver)
- [ ] `CHANGELOG.md` updated (if we have one)
- [ ] All P0/P1 tickets for this version are closed
- [ ] Local build passes: `./scripts/build_release_targets.sh`
- [ ] Tests pass: `./scripts/test_apple_targets.sh`
- [ ] Release config validates: `./scripts/validate_release_config.sh`
- [ ] Smoke test on physical device (iOS + watchOS)
- [ ] Review `docs/FEATURES.md` for honest feature status
- [ ] Marketing site (`marketing/`) builds clean and the live `volumearc.app/terms` + `/privacy` URLs that `App/LegalLinks.swift` references resolve to non-placeholder content (VOL-124)

## Versioning

- **Marketing version** (`1.2.3`): read from `VERSION` file at repo root
- **Build number**: pinned to `1` in the committed pbxproj; release tooling (`scripts/archive_for_distribution.sh`, Fastlane `ios beta`) overrides `CURRENT_PROJECT_VERSION` to `git rev-list --count HEAD` at `xcodebuild archive` time, so TestFlight/App Store uploads keep a monotonic build number. Xcode Cloud uses `ci_scripts/ci_post_clone.sh` to patch the throwaway checked-out project to `CI_BUILD_NUMBER` before archive because that value is only available to the hook shell environment. Pass `BUILD_NUMBER=<n>` explicitly to force a specific value in local release tooling. (VOL-106 pinned the generator default; the prior behavior baked the git count into the pbxproj on every regen and cascaded UUID churn through `predictabilize_uuids`.)
- Bump `VERSION` in a dedicated PR before tagging

## TestFlight release

**As of 2026-05-04 (VOL-126), TestFlight deploys are owned by Xcode Cloud.** Apple-managed signing eliminates the cert/profile management overhead that blocked the earlier self-hosted Fastlane path. GitHub Actions still owns the substantive validation gates (build, tests, perf-regression, lint) — Xcode Cloud only owns archive + sign + upload.

### Tag → TestFlight flow

1. Merge all changes to `main` (GitHub Actions runs the full validation suite on every push).
2. Bump `VERSION` if needed.
3. Tag the release:
   ```bash
   git tag v1.2.3
   git push --tags
   ```
4. **GitHub Actions** runs `Build & Test` + `Performance budgets (VOL-99)` against the tag commit. These must pass.
5. **Xcode Cloud workflow** (configured per [Xcode Cloud setup](#xcode-cloud-setup) below) triggers in parallel on the tag push, archives the app with Apple-managed signing, and uploads to TestFlight.
6. After archive, `ci_scripts/ci_post_xcodebuild.sh` runs `sentry-cli debug-files upload --include-sources --wait` against the archive's `dSYMs/` (VOL-133). Apple's auto-symbolication for App Store crashes still happens in parallel; this provides the same data to Sentry so our own crash reports symbolicate.
7. **TestFlight processing** (5-15 min usually). Watch in App Store Connect.
8. dSYMs visible in Sentry under https://mabry-ventures-llc.sentry.io/settings/projects/volumearc-ios/debug-symbols/ tagged with release `com.mabryventures.VolumeArc@<version>+<build>`.

### Xcode Cloud setup

One-time setup, done in App Store Connect's web UI (cannot be done via CLI / API as of 2026-05).

1. https://appstoreconnect.apple.com → Apps → VolumeArc → Xcode Cloud
2. Click "Get Started" or "Create Workflow".
3. **Workflow name**: `Tag → TestFlight`
4. **Project**: `VolumeArcApple.xcodeproj` (the generated project at the repo root — Xcode Cloud needs this checked into git, which it is via `scripts/generate_xcode_project.rb`'s pbxproj output)
5. **Scheme**: `VolumeArcApp`
6. **Branch / Tag triggers**:
   - Add a **Tag Changes** trigger
   - Pattern: `v*` (matches `v1.0.2`, `v1.0.2-rc1`, etc.)
7. **Actions**: add an **Archive** action
   - Configuration: `Release`
   - Distribution: **TestFlight (Internal Testing Only)** initially; once we trust the pipeline, optionally add an external test group.
8. **Environment variables** (settings cog → Environment):
   - `SENTRY_AUTH_TOKEN` — mark as **secret**. Same token as the GitHub `SENTRY_AUTH_TOKEN` secret (Sentry user token with `project:write` on `mabry-ventures-llc/volumearc-ios`).
   - `SENTRY_ORG` — `mabry-ventures-llc` (optional; script defaults to this)
   - `SENTRY_PROJECT` — `volumearc-ios` (optional; script defaults to this)
9. **Post-Actions**: leave empty — the dSYM upload runs from `ci_scripts/ci_post_xcodebuild.sh` which Xcode Cloud invokes automatically after each archive.
10. **Test grouping** (optional): add a "Test" action with the `VolumeArcAppTests` scheme if you want Xcode Cloud to run unit tests too. Not required since GitHub Actions already runs them.

After setup, push a tag and verify:
- The Xcode Cloud workflow appears in App Store Connect within ~30s of the tag push.
- Build completes (typically 25-40 min on hosted Macs).
- TestFlight build is visible.
- Sentry's debug-symbols page shows dSYMs for the build.

### Local archive fallback

`fastlane ios beta` still works for local archive — useful for hotfixes or for pushing a build before Xcode Cloud picks up the tag. Requires:
- A local Apple Developer login in Xcode (Apple Distribution cert in keychain)
- The provisioning profile installed in `~/Library/MobileDevice/Provisioning Profiles/`
- `SENTRY_AUTH_TOKEN` env var set if you want dSYMs uploaded
- `DEVELOPMENT_TEAM` env var set
- `APP_STORE_CONNECT_API_KEY_PATH` env var pointing to a `.p8` key file (for upload_to_testflight)

```bash
export SENTRY_AUTH_TOKEN=<token>
export DEVELOPMENT_TEAM=E896WB332K
export APP_STORE_CONNECT_API_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
bundle exec fastlane ios beta
```

Local archive uses your keychain certs directly; no fastlane match infrastructure required.

### Required GitHub secrets (for the validation gates)

- `SENTRY_AUTH_TOKEN` — for the Sentry SDK init in dev/staging builds (separate concern from dSYM upload)
- `VOLUMEARC_PAT` — personal access token (only needed if cross-repo checkout returns)
- `VOLUMEARC_NATIVE_DEPLOY_KEY` — SSH key for the runner's git operations

Secrets that were previously required for the old GitHub Actions deploy path but are no longer used by CI (kept in case local devs use them or we add another integration):
- `DEVELOPMENT_TEAM`, `APP_STORE_CONNECT_API_KEY_PATH`

### Marketing site

The public marketing site (`marketing/` directory) deploys independently to Vercel on every push to `main` and previews on every PR. See [`MARKETING.md`](MARKETING.md) for the full architecture.

The site hosts the legal pages that the iOS paywall links to via `App/LegalLinks.swift`:
- `volumearc.app/terms`
- `volumearc.app/privacy`

Until those pages are live with legal-counsel-reviewed content (VOL-124), App Store submission is blocked under Guideline 3.1.2.

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

`fastlane ios screenshots` drives `snapshot` against the device matrix declared in [`fastlane/Snapfile`](../fastlane/Snapfile). Output lives in `fastlane/screenshots/` and is picked up automatically by `deliver` during the `release` lane.

Current matrix:

| Device | App Store class |
| --- | --- |
| iPhone 17 | 6.1" |
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
