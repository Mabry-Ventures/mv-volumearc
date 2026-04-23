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

## Versioning

- **Marketing version** (`1.2.3`): read from `VERSION` file at repo root
- **Build number**: derived from `git rev-list --count HEAD` or `BUILD_NUMBER` env var
- Bump `VERSION` in a dedicated PR before tagging

## TestFlight release

Automated via Fastlane on tag push.

1. Merge all changes to `main`
2. Tag the release:
   ```bash
   git tag v1.2.3
   git push --tags
   ```
3. CI automatically runs `fastlane ios beta` which:
   - Regenerates the Xcode project with `BUILD_NUMBER` set
   - Archives with `CODE_SIGNING_ALLOWED=YES`
   - Exports to `.ipa`
   - Uploads to TestFlight via App Store Connect API
   - Uploads dSYMs to Sentry

Required CI secrets:
- `DEVELOPMENT_TEAM` — Apple team ID (e.g., A886EMZZW6)
- `APP_STORE_CONNECT_API_KEY_PATH` — path to the `.p8` key file on the runner
- `VOLUMEARC_PAT` — personal access token (only needed if cross-repo checkout returns)

### Signing & entitlements (VOL-70)

The iOS app ships **two** entitlements files, swapped per build configuration by `scripts/generate_xcode_project.rb`:

- `App/VolumeArc.Debug.entitlements` — `aps-environment = development` (APNs sandbox, used by Debug and simulator builds)
- `App/VolumeArc.Release.entitlements` — `aps-environment = production` (APNs production, required for Release-signed IPAs)

HealthKit, CloudKit, iCloud containers, and App Groups are identical across both files. Keep them in sync when adding capabilities. `scripts/validate_release_config.sh` hard-fails if the Release file drifts back to `development`, and the Xcode build settings assertion confirms `CODE_SIGN_ENTITLEMENTS = App/VolumeArc.Release.entitlements` for the Release configuration.

End-to-end verification (that the production APS token works end-to-end with APNs) only happens on a signed archive and TestFlight build — local simulator runs always use the Debug entitlements.

## App Store release

1. Verify TestFlight build is stable with at least 3 testers
2. Tag with `-rc` suffix if doing a release candidate
3. Run `fastlane ios release` which submits for review
4. Monitor App Store Connect for review status
5. Release manually when approved

## Rollback

If a release introduces a regression:

1. Revert the offending commit on `main`
2. Bump `VERSION` patch number
3. Tag and push — CI will build and deploy the fix
4. File a ticket with the incident postmortem

## Hotfix process

For critical production issues:

1. Branch from the last released tag: `git checkout -b hotfix/v1.2.4 v1.2.3`
2. Apply the minimum necessary fix
3. Bump `VERSION` to patch
4. Tag and push
5. Cherry-pick the fix back to `main` afterward
