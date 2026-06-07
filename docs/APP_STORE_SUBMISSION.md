# App Store Submission Package

> Source of truth for VOL-125. Do not submit or mutate App Store Connect from automation without an explicit operator go-ahead.

## Current ASC State

Read-only App Store Connect check on 2026-05-25:

| Field | Value |
|---|---|
| App | VolumeArc |
| Apple ID | 6766344915 |
| Bundle ID | com.mabryventures.VolumeArc |
| SKU | mvvolarc2026 |
| Primary locale | en-US |
| App Store version | 1.0 |
| App Store state | Prepare for Submission |
| en-US version metadata | Blank in ASC; use `fastlane/metadata/en-US/` |
| App Review detail | Not created in ASC yet |

## Metadata

Local source of truth:

| ASC field | Local file | Status |
|---|---|---|
| Name | `fastlane/metadata/en-US/name.txt` | Ready |
| Subtitle | `fastlane/metadata/en-US/subtitle.txt` | Drafted |
| Description | `fastlane/metadata/en-US/description.txt` | Drafted |
| Keywords | `fastlane/metadata/en-US/keywords.txt` | Drafted |
| Promotional text | `fastlane/metadata/en-US/promotional_text.txt` | Drafted |
| What's New | `fastlane/metadata/en-US/release_notes.txt` | Drafted |
| Category | `fastlane/metadata/en-US/primary_category.txt` | Ready |
| Marketing URL | `fastlane/metadata/en-US/marketing_url.txt` | Ready |
| Privacy URL | `fastlane/metadata/en-US/privacy_url.txt` | Ready |
| Support URL | `fastlane/metadata/en-US/support_url.txt` | Ready |
| Review notes | `fastlane/metadata/en-US/review_information/notes.txt` | Drafted |
| Review contact phone | `fastlane/metadata/en-US/review_information/phone_number.txt` | Ready |

Apple limits checked against App Store Connect Help:

| Field | Apple limit | Local value |
|---|---:|---:|
| App name | 2-30 characters | 9 |
| Subtitle | 30 characters | 28 |
| Promotional text | 170 characters | 138 |
| Description | 4000 characters | Under limit |
| Keywords | 100 bytes | 92 bytes |

## Screenshot Package

Apple requires 1-10 screenshots per supported display size/localization. VolumeArc v1.0 is iPhone-only with a bundled Apple Watch app, so the release matrix remains:

| Device in `fastlane/Snapfile` | App Store class | Status |
|---|---|---|
| iPhone 17 Pro Max | 6.9-inch iPhone | Generated locally: 6 PNGs at `1320x2868` |
| iPhone 17 | 6.3-inch iPhone | Generated locally: 6 PNGs at `1206x2622` |
| Apple Watch Series 11 (46mm) | Apple Watch | Generated locally: 1 PNG at `416x496` |

Generated iPhone screenshots are in `fastlane/screenshots/en-US/`:

- `iPhone 17 Pro Max-01_today_dashboard.png` through `iPhone 17 Pro Max-06_premium.png`
- `iPhone 17-01_today_dashboard.png` through `iPhone 17-06_premium.png`
- `Apple Watch Series 11-01_watch_workout.png`

Screenshot order from `VolumeArcScreenshotTests`:

1. `01_today_dashboard`
2. `02_live_workout`
3. `03_coach`
4. `04_signals`
5. `05_profile`
6. `06_premium`

Preferred generation command once the local Ruby toolchain matches `Gemfile.lock`:

```sh
bundle exec fastlane ios screenshots
```

Verified fallback used on 2026-05-25:

```sh
VOLUMEARC_RUN_SCREENSHOT_CAPTURE=1 xcodebuild test \
  -project VolumeArcApple.xcodeproj \
  -scheme VolumeArcScreenshots \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:VolumeArcAppUITests/VolumeArcScreenshotTests/testCaptureAppStoreScreenshots \
  CODE_SIGNING_ALLOWED=NO
```

The binary screenshot output is intentionally gitignored. Before final submission, regenerate the set locally, inspect every PNG, and upload via `fastlane ios release` only after an explicit App Store submission go-ahead.

Current blockers:

- Full screenshot/upload lanes still require explicit App Store submission approval before mutating ASC.
- Final human visual approval is still required before uploading screenshots to ASC.

Local tooling note: on 2026-06-06 this Mac was provisioned with Homebrew Ruby 4 and Bundler 4.0.10, and `bundle exec fastlane lanes` parses successfully with usage analytics disabled in `fastlane/Fastfile`.

## Recent ASC Upload Rejection

Build 255 for version 1.0.2 was rejected by App Store Connect with ITMS-90626 because an App Intent description contained "Apple Watch Ultra Action Button" wording. Current `main` resolves that in commit `687950b` ("Fix Action Button intent description for ASC") by changing the watch Action Button intent description to avoid the forbidden Apple trademark term.

`scripts/validate_release_config.sh --no-build` now includes a static guard for `IntentDescription(...)` blocks in the iOS and watch intent sources so this does not regress before the next binary upload.

## Privacy Nutrition Worksheet

Use this as the App Store Connect privacy questionnaire source. It is derived from `App/PrivacyInfo.xcprivacy`, the bundled Sentry privacy manifest, `docs/SECURITY.md`, and the live privacy policy at `https://volumearc.app/privacy`.

| Data type | Collected? | Linked to user? | Tracking? | Purpose | Notes |
|---|---|---|---|---|---|
| Health & Fitness | Yes | No | No | App Functionality | Computed recovery aggregates may leave device in cloud-coach prompts. Raw HealthKit samples stay on device. |
| Other User Content | Yes | No | No | App Functionality | Coach questions, feedback text, workout notes, and derived form-check context may be included in app functionality flows. |
| Audio Data | Yes | No | No | App Functionality | Voice coach / voice prompt input. The app does not retain raw audio. |
| Crash Data | Yes | No | No | App Functionality | Sentry crash diagnostics, scrubbed before send. |
| Performance Data | Yes | No | No | App Functionality | Sentry performance diagnostics. |
| Other Diagnostic Data | Yes | No | No | App Functionality | Scrubbed operational breadcrumbs and feedback diagnostic context. |
| Contact Info | No | No | No | N/A | No account system; support contact is outside the app or user-entered feedback text that is scrubbed. |
| Identifiers for tracking | No | No | No | N/A | No ad SDK, no tracking domains, no ATT tracking. App Attest is operational auth for the relay. |
| Location | No | No | No | N/A | Not requested or collected. |
| Financial Info | No | No | No | N/A | StoreKit handles subscription purchase and receipt state. |

## Final Human Checklist

- Confirm the App Review contact phone in `fastlane/metadata/en-US/review_information/phone_number.txt`.
- Confirm ASC app version string matches the binary selected for review.
- Regenerate `fastlane/screenshots/` from a passing screenshot lane.
- Inspect all iPhone and Apple Watch screenshots before upload.
- Confirm privacy nutrition answers in ASC match this worksheet.
- Confirm age rating and encryption/export-compliance answers in ASC.
- Select the processed TestFlight build for review.
- Submit only after explicit operator approval.
