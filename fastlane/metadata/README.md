# App Store Connect metadata — source of truth

This directory is the in-repo source of truth for everything in the App Store Connect listing that is not the binary itself: subtitle, full description, keywords, promotional text, support / privacy / marketing URLs, App Review notes, demo credentials, and screenshot manifest.

The pattern follows the fastlane `deliver` convention: one file per ASC field, with `en-US/` as the primary locale and `default/` reserved for any locale-independent overrides we add later. `deliver` picks these up automatically from `fastlane/metadata/` when `fastlane ios release` runs.

Closes the in-repo half of VOL-216 (the 2026-05-18 audit found that App Store Connect may have draft state, but the local source of truth had nothing — meaning a fresh clone could not tell the difference between "ASC is done" and "ASC has never been touched").

## Draft-blocker policy

Files containing the literal token `TBD` or `ACTION REQUIRED` are scaffolded placeholders waiting for product / marketing / reviewer-contact input. `scripts/validate_release_config.sh` fails when running in release-readiness mode (`VOLUMEARC_RELEASE_READY=1`) and any metadata file still contains either marker. The gate is intentionally non-blocking on a normal regen / unit-test run so contributors can land partial drafts.

To check current readiness:

```
VOLUMEARC_RELEASE_READY=1 bash scripts/validate_release_config.sh
```

## Files in `en-US/`

| File | Status | Notes |
|---|---|---|
| `name.txt` | ✅ Done | "VolumeArc" |
| `subtitle.txt` | ✅ Done | Max 30 chars |
| `description.txt` | ✅ Drafted | Max 4000 chars; matched to v1.0 iPhone + Apple Watch scope |
| `keywords.txt` | ✅ Drafted | Comma-separated, max 100 bytes |
| `promotional_text.txt` | ✅ Drafted | Max 170 chars; updatable without a new build |
| `release_notes.txt` | ✅ Drafted | App Store-facing "what's new" (separate from TestFlight What-To-Test) |
| `marketing_url.txt` | ✅ Done | `https://volumearc.app` |
| `privacy_url.txt` | ✅ Done | `https://volumearc.app/privacy` (subject to VOL-195 legal copy finalization) |
| `support_url.txt` | ✅ Done | `https://volumearc.app/support` |
| `copyright.txt` | ✅ Done | "© 2026 Mabry Ventures LLC" |
| `primary_category.txt` | ✅ Done | `HEALTH_AND_FITNESS` |
| `review_information/notes.txt` | ✅ Drafted | HealthKit, AI relay, subscription, diagnostics, and reviewer test notes |
| `review_information/demo_user.txt` | ✅ Done | No login required |
| `review_information/demo_password.txt` | ✅ Done | No login required |
| `review_information/email_address.txt` | ✅ Done | `jared@mabryventures.com` |
| `review_information/first_name.txt` | ✅ Done | "Jared" |
| `review_information/last_name.txt` | ✅ Done | "Mabry" |
| `review_information/phone_number.txt` | 🟥 Action required | Escalation phone for App Review |

## Screenshots

`fastlane snapshot` captures screenshots into `fastlane/screenshots/` (per the existing `Snapfile`). That output is intentionally gitignored — the binary screenshots are regenerated on every release. The screenshot **manifest** (which screens / which devices / which order in ASC) is implicit in the `Snapfile` device list and the `VolumeArcScreenshotTests` test order. VOL-125 keeps premium pricing deterministic in screenshots with the Debug-only `-UseScreenshotStoreKitFixtures` launch argument, so simulator StoreKit product-list flakiness cannot silently drop the Premium screen.

## When the source of truth diverges

If ASC drifts from this directory (someone edits in the ASC web UI directly), the next `fastlane ios release` will overwrite ASC with whatever is here. The reverse — pulling ASC state back into this directory — is done with `fastlane deliver download_metadata`, but treat that as a recovery action, not a normal sync.

## Related

* VOL-125 (parent ticket — ASC metadata + screenshots + privacy nutrition)
* VOL-216 (this scaffolding, F-M-007 from the 2026-05-18 audit)
* VOL-150 (TestFlight What-To-Test automation — separate from `release_notes.txt`)
* VOL-195 (legal pages — privacy_url destination must be finalized)
