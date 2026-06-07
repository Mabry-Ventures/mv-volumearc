# VolumeArc Platform — Canonical Reference

[![CI](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml/badge.svg)](https://github.com/Mabry-Ventures/mv-volumearc/actions/workflows/ci.yml)
[![coverage trend](https://img.shields.io/badge/coverage-trend%20on%20metrics-blue)](TESTING.md#coverage-artifacts)

This is the canonical source of truth for the VolumeArc Apple platform. AI-powered strength training coach for iOS and watchOS. Tracks workouts, provides real-time coaching via voice and text, syncs across devices with CloudKit, and surfaces training signals through widgets and Live Activities.

**Owner:** Mabry Ventures (`com.mabryventures.VolumeArc`)

> **How to keep this current:** Whenever a PR changes the implementation status of a system (a stub becomes real, a feature ships, scope changes), update the relevant row in the [Implementation Status](#implementation-status) table and the matching system description below in the same PR. The status table here is the single source of truth — `CLAUDE.md` is just a pointer at this file. Topic-specific deep dives live in their own siblings: [`ARCHITECTURE.md`](ARCHITECTURE.md), [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md), [`TESTING.md`](TESTING.md), [`USER_JOURNEYS.md`](USER_JOURNEYS.md), [`RELEASE.md`](RELEASE.md), [`CONTRIBUTING.md`](CONTRIBUTING.md), [`AUDIT.md`](AUDIT.md).

## Table of contents

- [Implementation Status](#implementation-status)
- [Targets](#targets)
- [Key Components](#key-components)
- [Data Models](#data-models-swiftdata)
- [Telemetry](#telemetry)
- [Notifications](#notifications)
- [Feature Flags](#feature-flags)
- [Network Reachability](#network-reachability)
- [Subscriptions](#subscriptions)
- [Configuration](#configuration)
- [Build System](#build-system)
- [Code Conventions](#code-conventions)

## Implementation Status

> **Status: VolumeArc Release phase.** Active launch work now lives in the [VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762) initiative and [`VOLUMEARC_RELEASE.md`](VOLUMEARC_RELEASE.md). The release bar is intentionally higher than prior readiness sweeps: no paid public launch until every P0-P4 finding is closed, explicitly accepted by Jared, or proven stale, and every world-class scorecard category is at least 9.5/10.
>
> The 2026-06-06 Claude Design + launch-readiness audit in [`AUDIT.md`](AUDIT.md#2026-06-06-claude-design--launch-readiness-audit) currently scores the platform at **84/100** and keeps a **no-launch** verdict. Current hard gates are tracked in Linear as VOL-267 through VOL-276, covering Apple build reliability, Release binary hardening, coach eval trend proof, remaining Claude visual parity across watch/marketing/widget surfaces and tab-chrome drift signoff, paired iPhone/Watch UAT proof, CI/tag + physical-device performance confirmation, security/supply-chain blocking, pricing/legal/copy finalization, AI model routing, remaining co-design template/dedicated-screen/Watch proof, and repo hygiene.
>
> Historical launch blockers from April and May remain valuable audit context in [`AUDIT.md`](AUDIT.md), but they no longer define the active program. Do not describe VolumeArc as production-ready, submit-ready, or paid-launch-ready until the VolumeArc Release scorecard is green.
>
> The status table below reflects current implementation reality. Do not flip any row from a gap to Implemented without (a) a PR that wires the code and tests and (b) the corresponding Linear issue transition.

| System | Status | Notes |
|--------|--------|-------|
| iPhone UI | Implemented | Full tab bar (Today, Workouts, Coach, Signals, Profile). `RootDashboardView` presents `OnboardingView` via `fullScreenCover` on first launch. `ProfileView` presents `PaywallView` via sheet on upgrade tap. Localized, accessible, Dynamic Type, hero transitions, toast presenter all working |
| AI coaching | Implemented (streaming — VOL-66; tier-gated — VOL-91) | Three-provider chain works end-to-end. All three providers (`AIRelayCoachProvider`, `LocalHeuristicAICoachProvider`, `FoundationModelCoachProvider`) route their outbound prompts through `CoachPromptTemplate.render(intent:contextBlock:question:style:)` so the system prompt, intent envelope, structured context block, and template marker are identical across the cloud, on-device, and offline paths. `AIRelayCoachProvider.streamCoachResponse` consumes `text/event-stream` from the `volumearc-ai-relay` Cloudflare Worker and yields Gemini 3.1 tokens progressively (VOL-66 / PR #57); the synthetic word-chunking default is retained for providers without native streaming. `CoachSafetyFilter` enforces a last-mile recovery and medical-safety boundary after generation: symptom prompts and current symptom context are buffered before streaming, unsafe push/heavy/grind language is replaced with a rest-first light-training answer, and red-flag prompts return medical escalation copy. A relay 401 now clears the local App Attest relay session, resets pending bootstrap state, records `relay.session_refreshed`, retries the cloud request once, and falls back to the local heuristic provider if the refreshed retry is also unauthorized. If the app is killed while a coach turn is streaming, `CoachStreamRecoveryStore` preserves an in-flight marker, relaunch consumes it, records `coach.stream.aborted`, drops the partial turn, and lets the user ask again. Cloud tier is entitlement-gated: `VolumeArcAIRuntimeFactory.makeCoachProvider(subscriptionStore:)` installs `AIRelayCoachProvider` with `tier: .pro` (`X-Coach-Tier: pro` → Gemini Pro on the Worker) for premium users, `tier: .flashLite` (→ Gemini Flash Lite) for free. On-device FM and local heuristic fallback are the same for both tiers |
| Voice coaching | Implemented (single-turn) | `AIRelayVoiceTransport` delegates to the same coach-provider chain; `LiveVoiceCoachOrchestrator` exposes `speak(prompt:context:)` and lifecycle hooks. `WorkoutDashboardModel` now retains the injected `VoicePermissionStore`, publishes microphone/speech permission state, records `voice.enabled` / `voice.session_started` / `voice.session_completed`, and `CoachView` exposes a premium-gated mic affordance that sends the current typed or dictated transcript through the single-turn voice path. Live duplex audio capture remains explicit future work |
| Cloud sync | Implemented (entitlement-gated at runtime) | CloudKit container ID is a compile-time constant (`App/VolumeArcCloudConfiguration.swift`). `CKModifyRecordsOperation` push + `CKFetchRecordZoneChangesOperation` pull + cursor persistence work on device/TestFlight builds with entitlements. Every repository write path calls `stageUpsert` into `OutboundSyncQueue`, which `CloudSyncCoordinator` drains on `syncCycle`. Simulator Debug builds fall back to `UnavailableCloudSyncTransport` because they lack the entitlement, and the dashboard records `cloudsync.unavailable` once per launch when the active sync engine cannot sync |
| Watch app | Implemented | HealthKit `HKWorkoutSession` + `HKLiveWorkoutBuilder`, WorkoutKit prescription export to Apple's Workouts app, watch-side TTS coach cues, Apple Watch Ultra Action Button start/log-next-set intents, rest timer, decisions, "Vitals say" training insight, watch-triggered form-check start/stop/results, accessibility, offline payload queue with telemetry category `watch` and names `payload.queued` / `payload.replayed` plus user-facing queued/replayed notices on iPhone, real phone/watch sync via WCSession |
| Widgets | Implemented | `NextWorkoutWidget` + `WatchWidgets` extension read real shared state via `PlatformSurfaceDefaultsReader`, design-system-tokened, accessibility-labelled. Small and medium iOS widget families have light/dark snapshot baselines, and `VolumeArcWidgetUITests` verifies host app embedding plus WidgetKit timeline reload safety |
| Live Activities | Implemented | `ActiveWorkoutLiveActivity` provides real workout-state updates across the iPhone lock screen, Dynamic Island, and Apple Watch supplemental Live Activity family, including the watch-face `.small` layout that pairs a circular rest countdown with current-set progress. `WorkoutDashboardModel` emits `liveactivity.started` / `liveactivity.ended` when publishing and clearing shared ActivityKit state; the lock-screen, expanded Dynamic Island, and watch supplemental layouts have committed light/dark snapshot baselines. |
| Notifications | Implemented | Scheduler wired into rest timer completion and training plan reminders, actionable categories (REST_TIMER, WORKOUT_REMINDER) |
| Background tasks | Implemented | `App/VolumeArcBackgroundTasks.swift` registers `appRefresh` + `appProcessing`. `App/Info.plist` declares `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes` so iOS accepts the registrations. App refresh records `bgtask.fired`, `background/refresh_started`, and `background/refresh_completed`; app processing routes through `WorkoutDashboardModel.performBackgroundProcessing()` and records `bgtask.fired`, `background/processing_started`, and `background/processing_completed` around sync work |
| Persistence | Implemented | Four-tier fallback chain, seed data, schema, real repository CRUD all work. `VolumeArcSchemaMigrationPlan` bridges the legacy V1 training-plan shape through V2 to V3, with on-disk round-trip migration tests |
| Secure storage | Implemented | Keychain with fallback, device ID stability |
| Relay auth | Implemented (App Attest only — VOL-226) | `VolumeArcAppAttestRelaySessionProvider` attaches App Attest assertions for cloud-coach requests. The Worker validates Apple App Attest certificate chains, app ID hash, credential ID/key ID binding, per-request nonce, signature, and monotonic counter before forwarding to Gemini; App Attest state lives in a Durable Object so nonce consume and counter updates are strongly consistent. Missing `X-VA-Attest-*` headers return 410 and invalid or incomplete headers return 401; the shared client HMAC fallback is retired |
| Telemetry | Implemented | Fanout sink architecture. `SentryTelemetrySink` forwards events as breadcrumbs and captures `.error` severity as Sentry messages. `UserDefaultsTelemetrySink` and `OSLogTelemetrySink` persist/log for diagnostics. PII scrubbing via `VolumeArcSentryPIIScrubber` is installed as Sentry `beforeSend` / `beforeBreadcrumb` (VOL-72 / PR #46) — redacts user identifiers, emails, phone numbers, and drops deny-listed categories before any payload leaves the device |
| Feature flags | Implemented | `LocalFeatureFlagProvider` is wired through `FlagGateTelemetry` into `VolumeArcAIRuntimeFactory.makeVoiceCoach`, `CloudSyncCoordinator.syncCycle`, the Live Activity controller, and the Foundation Models provider selection (VOL-61 / PR #56). First resolution per flag per launch emits a `feature.flag.applied` `.info` telemetry event |
| Subscriptions | Implemented (entitlement gating — VOL-91) | StoreKit 2 store and `PaywallView` are wired, presented from `ProfileView`, and drive entitlement state. `StoreKitSubscriptionStore` conforms to `PremiumEntitlementProviding` and threads through `VolumeArcAIRuntimeFactory` at launch: premium unlocks Gemini Pro (coach tier) and live voice (gated AND on `.voiceCoaching` flag); free stays on Flash Lite + `UnavailableVoiceTransport`. Cloud sync, Foundation Models, and Live Activities are currently free for all — gating decision parked in the VOL-91 PR for product to revise. One-shot `premium.entitlement.gated` telemetry event per feature per launch records which tier/transport was installed. Terms/Privacy links open live marketing URLs (`https://volumearc.app/terms`, `/privacy`) via `LegalLinks` (VOL-71 / PR #44); `marketing/scripts/check-legal-pages.mjs` now verifies those pages contain no placeholder tokens, while legal-counsel content review remains a launch-readiness gate. Guideline 3.1.2 auto-renewal disclosure present |
| Build pipeline | Implemented | Ruby-generated Xcode project (byte-identical output across regens — VOL-95 / PR #61), CI on the dedicated M4 self-hosted runner label `mv-shared` (VOL-88), Fastlane, archive script, hard-failing `validate_release_config.sh` on Info.plist keys/URL schemes/BGTask IDs + Release `aps-environment = production` (VOL-70 / PR #43) and on signed entitlements in the built `.xcarchive` — iCloud container identifier, HealthKit, App Groups — via `codesign -d --entitlements -` (VOL-92). The Fastlane `beta` lane runs the validator after `gym` but before `upload_to_testflight` so entitlement regressions fail the lane before anything hits App Store Connect. SwiftLint is pre-flight-checked on the runner and hard-fails on errors (VOL-77 / PR #47). `CI_TAG_BUILD=1` is set in the deploy job so `VERSION`-bump enforcement fires on tag builds. Package.resolved is tracked at repo root as the canonical SPM lockfile (PR #60) |
| Testing | Implemented (staged per-target coverage gates — VOL-52 / VOL-140 / VOL-205) | 735+ test functions (audited 2026-05-26 — VOL-260), including onboarding, paywall, StoreKit Test purchase, active workout completion, HealthKit prompt simulation, Coach voice permission/session proof, Dynamic Type/pseudo-locale, Watch payload simulation, feedback submission journey (VOL-176), force-quit recovery for onboarding/active workout/coach streaming, and bundled snapshot baselines. `VolumeArcLaunchArguments` are live and wire into `VolumeArcLaunchBootstrapper`. Dashboard integration tests cover the create → log → complete chain against in-memory SwiftData. CI blocks merges that drop `VolumeArcCore` below 80%, `VolumeArcUI` below the 18% staged floor ratcheted by VOL-135 snapshots, or `VolumeArcCoreWatch` below the 25% Phase A floor. The 90%+ / 85%+ end-state coverage targets remain the ratchet path tracked by [VOL-140](https://linear.app/mabry-ventures/issue/VOL-140) / [VOL-205](https://linear.app/mabry-ventures/issue/VOL-205); widget line-coverage gating remains pending a dedicated target after [VOL-139](https://linear.app/mabry-ventures/issue/VOL-139). Visual regression coverage is **partial** (150 baseline PNGs as of 2026-06-06): VAButton, the next-workout widget, core VAUI card/toast surfaces, the active-workout Live Activity lock-screen/banner, expanded Dynamic Island, and watch surfaces, coach transcript bubbles, the Premium paywall loaded-empty/failure shell, the full onboarding flow, and `DashboardSurfaceSnapshotTests` coverage for Today, Workouts idle, Workouts active, Coach planning, Signals, and Profile in light/dark/warm-brand plus light `.accessibility5` and light/dark/warm-brand reduce-transparency-off glass variants. `VADesignTokenParityTests` verifies Claude warm-personality brand colors against native `VA.Colors` in light/dark. Profile editor variants, Settings, native tab chrome accepted drift, watch-face/runtime watch parity, widgets beyond next-workout, and the remaining Live Activity matrices are still launch gaps tracked under [VOL-135](https://linear.app/mabry-ventures/issue/VOL-135), [VOL-201](https://linear.app/mabry-ventures/issue/VOL-201), and [VOL-270](https://linear.app/mabry-ventures/issue/VOL-270). VOL-260 reconciled the prior "Visual regression coverage is active for ..." framing which implied broader coverage than what's actually shipped. User-journey catalog ([`USER_JOURNEYS.md`](USER_JOURNEYS.md)) is 72/72 automated for v1 simulator-safe rows, while physical iPhone + paired Watch UAT remains the launch gate under [VOL-271](https://linear.app/mabry-ventures/issue/VOL-271). Nightly exploratory UAT ([VOL-169](https://linear.app/mabry-ventures/issue/VOL-169)) runs through an LLM-driven XCUITest bridge with screenshot/accessibility-tree reports. Coverage artifacts (xcresult bundle, step summary, sticky PR comment, `docs/coverage-trend.json`) published per run (VOL-97 / PR #62). See [`docs/TESTING.md`](TESTING.md#coverage-expectations) for the per-target gate map |
| Performance testing (VOL-99) | Implemented (tag-gated + PR warnings) | Five simulator budget rows (cold launch, Today scroll duration, workout memory, coach first-token P50, coach first-token P95) in `VolumeArcAppPerfTests` are enforced by `scripts/check_performance.sh` against `docs/performance-budgets.json`. The 2026-06-06 release-branch baseline in `docs/performance-trend.json` passes with cold launch 0.913s, Today scroll 2.48s, workout memory 77.013 MB, coach P50 702.071ms, and coach P95 777.378ms. Tag-gated `perf-regression` job in `.github/workflows/ci.yml` runs the suite on `v*` tags, blocks TestFlight deploy on budget breach, and appends each run to `docs/performance-trend.json`; same-repo PRs run the perf suite warning-only. PRs also run a separate non-required `PR bundle size proxy (VOL-215)` job to surface bundle-size drift before release archive/export, while `scripts/check_ipa_size.sh` remains the signed IPA/archive measurement. Physical iPhone + paired Watch speed/UAT proof remains a VolumeArc Release gate. See [`docs/PERFORMANCE.md`](PERFORMANCE.md) for the budget table |
| AI coach eval harness | Implemented (template-layer hermetic; response-layer staging broker) | 47 JSON fixtures under `Tests/Evals/CoachEvalFixtures/` cover readiness (45/60/72/82/88) × intent (progression, deload, form, recovery, substitution, planning, free) × history (empty/1/5 sessions) × style (motivational, analytical, minimal), plus medical red flags and prompt-injection attempts. `CoachEvalTests` (iOS test bundle) asserts template-layer invariants — template marker, intent envelope, system prompt persona per style, context preservation, sanitized question embedding, per-intent envelope fragment, renderer determinism — against every fixture and fails if any axis loses coverage. `scripts/run_coach_evals.sh` runs the response layer through a staging-only eval attestation broker that bootstraps an ephemeral P-256 key, signs each fixture request with one-time nonce + monotonic counter headers, stores challenge/counter state in a Durable Object, and keeps production relay auth App Attest-only through an explicit broker host allowlist. Response-layer checks include `maxEnumeratedPlanDays`, `mustEscalateMedicalCare`, and `mustRejectPromptInjection` so planning outputs stay inside the requested horizon and safety boundaries remain intact. See [`docs/COACH_EVALS.md`](COACH_EVALS.md) |
| App Store readiness | Release-gated | `aps-environment = production` for Release (VOL-70 / PR #43), paywall Terms/Privacy routed through `LegalLinks` (VOL-71 / PR #44), privacy manifest completeness verified (VOL-73 / PR #45), Sentry PII scrubbing live (VOL-72 / PR #46). Marketing `/terms` and `/privacy` pages exist and pass the placeholder-token guard; final legal counsel review, App Store Connect metadata, screenshots, TestFlight review, and purchase/UAT evidence remain tracked in VolumeArc Release |
| Marketing site | Live ([volumearc.app](https://volumearc.app)) | Next.js 16 + Tailwind CSS v4 + shadcn/ui app under [`marketing/`](../marketing). Adapted from Tailwind Plus Pocket and refreshed to match the iOS app's design language: real `AppIcon-Light.png` rendered in `Logo.tsx` + favicon/apple-touch/OG via Next.js conventions; sunrise palette ported from `VA.Colors` (peach → orange → coral) as `--color-sunrise-*` and `--color-coral-*` Tailwind tokens; Liquid Glass approximated via `va-glass` utility (backdrop-blur). Pages: `/`, `/terms`, `/privacy`, `/support`, `/quality`; `/api/support` is a server-only Resend transactional email route for the support form (`RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `SUPPORT_EMAIL_TO`). Deployed to Vercel at `volumearc.app` (apex canonical) with `volumearc.com`, `www.*` 308-redirecting (VOL-160 done). Cloudflare DNS-only, Let's Encrypt via Vercel. CI build/lint gate at [`.github/workflows/marketing.yml`](../.github/workflows/marketing.yml). Legal-counsel content review (VOL-124) and copywriting polish (VOL-161) ongoing. See [`MARKETING.md`](MARKETING.md) for architecture and deploy flow |

## Targets

| Target | Type | Platform | Bundle ID |
|--------|------|----------|-----------|
| VolumeArcApp | iOS Application | iOS 26.0 | `com.mabryventures.VolumeArc` |
| VolumeArcWatch | watchOS Application | watchOS 26.4 | `com.mabryventures.VolumeArc.watchkitapp` |
| VolumeArcWidgets | Widget Extension | iOS 26.0 | `com.mabryventures.VolumeArc.widgets` |
| VolumeArcWatchWidgets | Widget Extension | watchOS 26.4 | `com.mabryventures.VolumeArc.watchwidgets` |
| VolumeArcAppTests | Unit Test Bundle | iOS 26.0 | `com.mabryventures.VolumeArc.tests` |
| VolumeArcAppUITests | UI Test Bundle | iOS 26.0 | `com.mabryventures.VolumeArc.uitests` |
| VolumeArcAppPerfTests | UI Test Bundle | iOS 26.0 | `com.mabryventures.VolumeArc.perftests` |
| VolumeArcCore | Static Library | iOS 26.0 | -- (from `VolumeArcNative/`) |
| VolumeArcCoreWatch | Static Library | watchOS 26.4 | -- (same `VolumeArcCore` module, built for watchOS from `VolumeArcNative/`) |
| VolumeArcUI | Static Library | iOS 26.0 | -- (from `VolumeArcNative/`) |

### Supported device families (VOL-131)

| Family | v1.0 TestFlight + App Store | Rationale |
|---|---|---|
| **iPhone** (iOS 26.0+) | Supported (primary surface) | Full feature set: tab bar, onboarding, paywall, coach, Live Activity, widgets, watch pairing. `TARGETED_DEVICE_FAMILY = 1`. |
| **Apple Watch** (watchOS 26.4+) | Supported (paired with iPhone) | Watch app + widgets ship in the same iPhone build per the iOS / watchOS pairing requirement. Documented in App Store description. |
| **iPad** | Not supported in v1.0 | [VOL-131](https://linear.app/mabry-ventures/issue/VOL-131) made the v1.0 product decision explicit: VolumeArc launches as an iPhone app with paired Apple Watch support. iPad remains a post-v1 product expansion, not a pre-submit blocker. `TARGETED_DEVICE_FAMILY` is `1` (iPhone only), and the App Store listing will be set to "iPhone only". |
| **visionOS** | Explicitly not supported | App Store metadata sets the platform compatibility flag to exclude visionOS. Revisit post-launch once we have iPhone telemetry to validate the form-factor strategy. |
| **macOS Catalyst** | Explicitly not supported | The coaching surfaces depend on touch + haptics + a paired Apple Watch; Catalyst doesn't deliver that experience cleanly. Revisit per [VOL-159](https://linear.app/mabry-ventures/issue/VOL-159) (Apple Intelligence) and platform sales data. |

**TestFlight + App Store screenshot matrix** (`fastlane/Snapfile`) is intentionally iPhone-only (`iPhone 17`, `iPhone 17 Pro Max`, `Apple Watch Series 11 (46mm)`) to match the supported-device declaration. Adding iPad later requires a fresh product decision, a new iPad UX audit, flipping `TARGETED_DEVICE_FAMILY` to `1,2`, adding iPad devices to Snapfile, regenerating screenshots, and updating the App Store description.

**Dependency graph:** `VolumeArcUI -> VolumeArcCore`. iOS app, iOS widgets, and tests depend on the iOS `VolumeArcCore` target. The watch app and watch widgets depend on `VolumeArcCoreWatch`, which compiles the same sources as module `VolumeArcCore` for watchOS so archive builds do not cross-link the iOS static library. The iOS app and tests also depend on `VolumeArcUI`. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full module breakdown and data flow.

## Key Components

**App entry point** (`VolumeArcApp.swift`): Wires all dependencies into `WorkoutDashboardModel` and installs `RootDashboardView`. Handles deep links, Watch Connectivity payloads, HealthKit background updates, widget snapshot changes, and Live Activity lifecycle.

**Persistence** (`VolumeArcPersistenceController.swift`): SwiftData with cascading fallback -- CloudSynced -> LocalFallback -> InMemoryFallback -> Unavailable. Seeds default `UserProfileRecord` and `TrainingPlanRecord` on first launch.

**Onboarding force-quit recovery.** The first-run onboarding surface persists the last reached step through `OnboardingProgressStore`, clears that marker on deterministic test reset, skip-onboarding launches, and successful onboarding completion, and emits `onboarding.resumed` when a relaunch restores a non-welcome step. This prevents a new athlete from losing progress if the app is killed before the profile is committed.

**Active-workout crash recovery (VOL-256).** A `WorkoutRecord` whose `completedAt` is `nil` is treated as the in-progress session. SwiftData persists this across crashes and force-quits, so on the next dashboard refresh `DashboardRefreshLoader.loadActiveWorkout(in:)` finds the unfinished record and `WorkoutDashboardModel.refresh()` rehydrates `isSessionActive`, `activeWorkoutID`, `activeWorkoutTitle`, and `loggedSetCountThisSession`. The Today tab's quick-actions row then surfaces "Continue Session" instead of "Start Workout" via the existing `model.isSessionActive` gate. Restoration is **silent** — no "Resume / Discard?" prompt, because a strength athlete who lost a set to a crash wants their workout back, not a one-tap risk of accidentally discarding it. Each restoration emits a `workout.active_session.recovered` `.info` telemetry event (deduplicated against the polling refresh loop so only the genuine "appeared from nowhere" transition counts) so we can observe crash-recovery rate in `UserDefaultsTelemetrySink` + Sentry breadcrumbs.

**AI coaching** (`VolumeArcAIRuntimeFactory.swift`): Three-tier provider chain with `AsyncThrowingStream` streaming, memory append via `CoachMemoryRepository`, stream-abort recovery via `CoachStreamRecoveryStore`, and structured output parsing. Every provider routes its outbound prompt through `CoachPromptTemplate.render(...)` so the system prompt, per-intent envelope, structured context block, and template marker are identical across the cloud, on-device, and offline paths — a regression that bypasses the template drops the marker and trips `VolumeArcCoachPromptTemplateTests`:
1. `FoundationModelCoachProvider` (on-device, iOS 26.0+ only)
2. `AIRelayCoachProvider` (cloud relay), wrapped with a one-shot 401 session-refresh retry before fallback
3. `LocalHeuristicAICoachProvider` (offline fallback)

When a coach turn starts, the dashboard marks the stream in flight before appending the empty response bubble. Successful completion and handled provider failures clear that marker; process termination or task cancellation leaves it for the next launch. `VolumeArcApp.rootContent` consumes the marker after the telemetry probe is mounted, records `coach.stream.aborted`, and resumes Coach in an idle state so a truncated partial response is never treated as a completed memory entry.

**Voice coaching** (`VolumeArcCore/AI/VoiceCoach.swift`, `VolumeArcAIRuntimeFactory.swift`, `CoachView.swift`): `LiveVoiceCoachOrchestrator` backed by `AIRelayVoiceTransport` (single-turn — delegates to the same provider chain used by the text coach) or `UnavailableVoiceTransport` when relay/entitlement/flag gates are unavailable. The dashboard owns `VoicePermissionStore` state, emits voice journey telemetry, and the Coach composer exposes a premium mic affordance that sends the current typed or dictated transcript through `speak(prompt:context:)`. Lifecycle hooks (`start`, `interrupt`, `end`) remain no-ops for the single-turn transport. A future feature will introduce persistent duplex audio capture/streaming; the protocol shape supports that without rework.

**Cloud sync** (`VolumeArcCloudConfiguration.swift`): `CloudSyncCoordinator` drives `CloudKitSyncTransport` using zone `VolumeArcSyncZone` in container `iCloud.com.mabryventures.VolumeArc`. Push uses `CKModifyRecordsOperation`; pull uses `CKFetchRecordZoneChangesOperation` with cursor persistence in `FileSyncStateStore`. `DefaultSyncPayloadApplier` writes changes into SwiftData with conflict resolution. Falls back to `UnavailableCloudSyncTransport` if unconfigured, and `WorkoutDashboardModel.recordCloudSyncUnavailableIfNeeded()` emits `cloudsync.unavailable` from the root dashboard lifecycle when the active engine is unavailable.

**Relay auth** (`VolumeArcAppAttestRelaySessionProvider.swift`): App Attest-capable devices bootstrap a Secure Enclave key with `/v1/attest/challenge` + `/v1/attest/bootstrap`, then attach `X-VA-Attest-*` assertion headers to coach requests. Missing App Attest headers return 410, while invalid or incomplete attestation fails closed with 401.

**Secure storage** (`VolumeArcSecureStore.swift`): Keychain wrapper with `UserDefaults` fallback in Debug/Simulator builds.

**Watch app** (`WatchWorkoutView.swift`, `WatchActionButtonIntents.swift`): `WatchWorkoutModel` manages `HKWorkoutSession` + `HKLiveWorkoutBuilder` for real HealthKit workout tracking, rest timers (90s default), coach cue requests, set decisions (increase/hold/decrease), and a wrist-level "Vitals say" training insight that falls back gracefully to readiness-based variants (high/moderate/low) when live HR is not available. It can export the current VolumeArc prescription through WorkoutKit so the session appears in Apple's Workouts app; that bridge sends only structural workout data (workout/exercise identifiers, exercise display name, HealthKit activity category, target weight/unit/rep range, set count, and rest interval). It intentionally excludes coach prompt text, readiness factors, and athlete profile fields. Apple Watch Ultra Action Button App Intents register start-active-workout and log-next-set handlers, record `watch.action_button.fired` with the action name, queue durable watch commands, and drain them through the model so prerequisite failures return haptic + spoken "No active workout." feedback instead of crashing. watchOS Double Tap assigns the active workout's "Log Set" control as SwiftUI's primary hand gesture action, records `watch.double_tap.set_logged`, and offers a persisted Settings -> Gestures toggle; on unsupported watches the button remains a normal on-screen control and the system has no Double Tap shortcut to deliver. The in-app Settings -> Action Button hint is shown only on watches that are detected as Ultra models. Watch-side voice coaching uses AVSpeechSynthesizer for playback-only spoken set/rest/cue events, with a persisted Watch toggle mirrored over `voiceCoachToggle` WatchConnectivity payloads, AOD suppression for automatic cues, a one-time 30-second rest alert that can fire through AOD, and AVAudioSession ducking so music is lowered instead of being abruptly interrupted. During an active workout, the watch can trigger iPhone form-check capture hands-free: `formCheckStart` arms the iPhone camera, `formCheckStop` finalizes the on-device Vision analysis, and `formCheckResult` returns a short verdict, cue text, and haptic code; queued start/stop/result payloads replay through the same offline queue and low watch battery suppresses spoken cues in favor of haptics. Communicates with iPhone via `WatchConnectivityCoordinator` with real `WCSession` transfer and offline payload queue replay when the phone is unreachable; the iPhone dashboard now surfaces "Watch update queued" and "Watch back in sync" notices when form-check result payloads are retained or replayed across reconnect.

**Phone-less workout completion (VOL-235).** The watch app is designed so an Apple Watch user can leave the iPhone at home and complete a full strength session from the wrist alone. The contract:

| Capability | Phone unreachable | Notes |
| --- | --- | --- |
| Next prescribed set | Works locally | `autopilot` is built from `VolumeArcProductDefaults` at `WatchWorkoutModel.init` -- no phone roundtrip required for the prescription. |
| Log a set decision (`increase` / `hold` / `decrease`) | Works locally | `choose(_:)` updates `selectedAction` immediately; the `liveState` payload queues for replay. |
| Rest timer | Works locally | `restEndsAt` is a `@Published` local property; `resetRestTimer()` updates it before attempting the `restTimer` payload send. |
| Start / end / complete session | Works locally | Each method updates `sessionActive` regardless of send success; payload queues for replay. |
| Coach cue (live response) | Degraded | The watch sends a `coachCue` payload, but the LLM response comes back via the iPhone's relay. With no phone, the prompt queues; the user sees a "queued on watch until phone reconnects" status. |
| Pending-payload replay | Works on reconnect | `refreshConnectivity()` calls `flushPendingIfReachable()`, which drains every queued payload in original order and records telemetry category `watch`, name `payload.replayed`. A partial replay failure requeues the failed payload plus every untouched payload in original order. The queue is `UserDefaults`-backed so it survives a watch process restart. |

Verified by `Tests/VolumeArcWatchTests/WatchPhonelessJourneyTests.swift` (3 tests: full-session-then-drain, coach-cue queue, queue survives process restart). The model's `do/catch`-around-send pattern across `startSession()`, `choose(_:)`, `resetRestTimer()`, `requestCoachCue()`, `endSession()`, and `completeWorkout()` is what makes the phone-less path work — a regression that removes any of those wrappers would surface as a `WatchPhonelessJourneyTests` failure.

**Widgets** (`VolumeArcWidgets.swift`, `WatchWidgets/`): `NextWorkoutWidget` (systemSmall, systemMedium, systemLarge, accessoryCircular, accessoryRectangular, accessoryInline) and the watchOS widget extension read from `PlatformSurfaceDefaultsReader` which returns real snapshots written by the app on state changes. `ActiveWorkoutLiveActivity` shows exercise, target, set progress, and rest timer on lock screen and Dynamic Island with real updates driven by the workout session controller. Its ActivityKit supplemental `.small` family renders the Apple Watch surface, pairing a circular rest countdown with the current set line (for example, `Set 3/5 · 225 lb`) so active sessions remain glanceable from the watch face.

**App Intents** (`VolumeArcIntents.swift`, `WatchActionButtonIntents.swift`): Six iOS Siri Shortcuts -- StartNextWorkout, AskCoach, OpenSignals, StartWorkoutSession, LogRecommendedSet, SyncVolumeArc -- open the app via `VolumeArcDeepLink` and `RootDashboardView` consumes `DashboardNavigationModel.selectedTab` + `coachPrompt` to route to the correct destination. Dashboard action methods drive real state changes through the repository layer. The watch app also exposes Action Button intents for starting the next VolumeArc workout and logging the next set from the wrist.

## Data Models (SwiftData)

Schema: current `VolumeArcSchemaV3` with `VolumeArcSchemaMigrationPlan` bridging `VolumeArcSchemaV1 -> VolumeArcSchemaV2 -> VolumeArcSchemaV3` (migration-tested).

- `UserProfileRecord` -- coaching style, privacy mode, advancement level, equipment, rep ranges, time budget, training days, via `SwiftDataUserProfileRepository`
- `WorkoutRecord` -- via `SwiftDataWorkoutRepository` (create, append set with aggregate update, complete, fetch recent, history projection)
- `TrainingPlanRecord` -- weekly schedule, via `SwiftDataTrainingPlanRepository` (upsert, fetch)
- `CoachMemoryRecord` -- AI coach context, via `SwiftDataCoachMemoryRepository` (append, fetch recent)

## Telemetry

Fanout sink: `InMemoryTelemetrySink` (bootstrap) + `UserDefaultsTelemetrySink` (persistent, NSLock-guarded) + `OSLogTelemetrySink` + `SentryTelemetrySink` (when configured). Startup signals surface degraded persistence, missing AI relay, missing CloudKit config, or missing Sentry DSN. `SentryTelemetrySink` forwards events as breadcrumbs and captures `.error` severity as Sentry messages.

**MetricKit (VOL-255).** `VolumeArcMetricKitSubscriber` (in `App/`) registers as an `MXMetricManagerSubscriber` at launch and routes Apple's daily metric payloads (CPU / GPU / memory / animation / scroll hitches / app launch / responsiveness / disk I/O / cellular / network) and per-incident diagnostic payloads (crashes / hangs / CPU exceptions / disk-write exceptions / app-launch diagnostics) into the same fanout. Metric payloads record as `metrickit.metric_payload.received` at `.info` severity; diagnostic payloads as `metrickit.diagnostic_payload.received` at `.error` severity, with `kinds` metadata enumerating the per-record counts. This is the VolumeArc-internal mirror of Sentry's `enableMetricKit = true` forwarding — Sentry still gets a copy in its UI; VolumeArc gets one in `UserDefaultsTelemetrySink`, `OSLogTelemetrySink`, and the in-app diagnostics overlay.

## Notifications

**Notification scheduler** (`VolumeArcNotificationScheduler.swift`): Schedules local notifications for rest timer expiration and workout reminders from the training plan. Registers actionable notification categories (`REST_TIMER` with Dismiss, `WORKOUT_REMINDER` with Start Workout / Dismiss). Called from rest timer completion handlers and the training plan scheduler.

## Feature Flags

`FeatureFlagProvider` protocol in `VolumeArcCore` with `LocalFeatureFlagProvider` (UserDefaults-backed). Flags: `voiceCoaching`, `cloudSync`, `liveActivities`, `foundationModelCoach`. Overridable per-flag for development. Wired into feature gates on the paywall, runtime factory, and live activity controller.

## Network Reachability

`NetworkReachabilityMonitor` in `VolumeArcCore` wraps `NWPathMonitor` for connectivity detection. Exposes `isReachable`, `isCellular`, and `isConstrained` properties with a `start(onChange:)` callback. Used by `WatchConnectivityCoordinator` offline queue replay and `CloudSyncCoordinator` back-off logic.

## Subscriptions

StoreKit 2 with two products and `@Published` entitlement state:
- `com.mabryventures.VolumeArc.premium.monthly`
- `com.mabryventures.VolumeArc.premium.yearly`

`StoreKitSubscriptionStore` drives a full `PaywallView` (plans, features, restore, terms/privacy links) and exposes `isPremium: Bool` via the `PremiumEntitlementProviding` protocol that `VolumeArcAIRuntimeFactory` reads at launch.

**Premium unlocks (VOL-91):**
- **AI coach tier.** Premium users get Gemini Pro (`AIRelayCoachProvider(tier: .pro)` → `X-Coach-Tier: pro` header → Worker routes to Pro). Free users get Gemini Flash Lite.
- **Live voice coaching.** `AIRelayVoiceTransport` installs only when `isPremium == true` AND the `.voiceCoaching` flag is on; production also requires a configured relay. Deterministic/perf launches use the local coach provider when premium and the flag are enabled so XCUITests can prove the same app boundary without network. Every other combination falls through to `UnavailableVoiceTransport` so `LiveVoiceCoachOrchestrator.speak` throws `AIRuntimeIntegrationError.relayUnavailable`.

**Not gated (currently free for all):** cloud sync, Foundation Models (on-device coach), Live Activities. This decision is parked in the VOL-91 PR body for product to revise — switching any of these to premium is a one-line change at the factory / coordinator call site that threads the `subscriptionStore` in.

**Telemetry.** `PremiumGateTelemetry` (mirrors the VOL-61 `FlagGateTelemetry` pattern) emits one `.info` event per premium-gated feature per launch: category `premium.entitlement.gated`, name `coach_tier` | `live_voice`, metadata `{"premium": "true" | "false"}`. Dedupe is NSLock-guarded so multiple factory invocations inside `VolumeArcApp.init` don't double-count.

## Configuration

### Environment / Info.plist Keys

| Key | Source | Purpose |
|-----|--------|---------|
| `VOLUMEARC_AI_RELAY_URL` | Env var or `VolumeArcAIRelayURL` in Info.plist | AI relay base URL for cloud coach + voice |
| `VolumeArcCloudKitContainer` | Info.plist | CloudKit container identifier (`iCloud.com.mabryventures.VolumeArc`) |
| `VOLUMEARC_SENTRY_DSN` | Env var or `VolumeArcSentryDSN` in Info.plist | Sentry DSN for crash reporting and telemetry |

The AI relay URL is bootstrapped into Keychain at launch. If neither source provides it, cloud AI and live voice are disabled with a startup warning.

### Crash Reporting

Sentry (`sentry-cocoa`) is integrated via `VolumeArcSentryConfiguration`. It follows the same pattern as the AI relay — DSN loaded from Keychain, environment variable, or Info.plist. A `SentryTelemetrySink` is added to the telemetry fanout when configured, forwarding telemetry events as Sentry breadcrumbs and capturing `.error` severity events as Sentry messages. If unconfigured, the app runs without crash reporting and surfaces a startup warning.

### Entitlements

**iOS App:** HealthKit, CloudKit, iCloud Containers (`iCloud.com.mabryventures.VolumeArc`), App Groups (`group.com.mabryventures.volumearc`), Push Notifications (`aps-environment`), App Attest (`com.apple.developer.devicecheck.appattest-environment`)

**watchOS:** HealthKit, App Groups (`group.com.mabryventures.volumearc`)

**Widgets:** App Groups (`group.com.mabryventures.volumearc`)

### Deep Link Scheme

URL scheme: `volumearc://`

Routes: `.today`, `.nextWorkout`, `.coach(prompt:)`, `.signals`, `.action(.startWorkoutSession)`, `.action(.logRecommendedSet)`, `.action(.syncNow)`

## Build System

The Xcode project is **generated** -- do not edit `project.pbxproj` by hand. Run `ruby scripts/generate_xcode_project.rb` to regenerate.

**Requirements:** Ruby with the `xcodeproj` gem, Xcode 26.4+

**Swift version:** 6.0

### Versioning

`MARKETING_VERSION` is read from the `VERSION` file at the repo root (e.g., `1.0.0`). `CURRENT_PROJECT_VERSION` (build number) is pinned to `1` in the committed pbxproj so `ruby scripts/generate_xcode_project.rb` is a true no-op against `main` (VOL-106 — prior behavior derived it from `git rev-list --count HEAD`, which bumped on every merge and cascaded 300-line UUID churn through `predictabilize_uuids`). Release tooling overrides it at build time: `scripts/archive_for_distribution.sh` exports `BUILD_NUMBER=$(git rev-list --count HEAD)` into the generator and passes `CURRENT_PROJECT_VERSION=$BUILD_NUMBER` to `xcodebuild archive`; Fastlane's `ios beta` lane calls `increment_build_number` with the same count before `build_app`; Xcode Cloud's `ci_post_clone.sh` patches the throwaway checked-out project to `CI_BUILD_NUMBER` before archive because Xcode Cloud exposes that value only as a shell environment variable. So TestFlight/App Store uploads still ship monotonic build numbers; only local dev builds see `CURRENT_PROJECT_VERSION = 1`. The `DEVELOPMENT_TEAM` can be passed as an env var for signing builds.

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/generate_xcode_project.rb` | Generates `VolumeArcApple.xcodeproj` from scratch, configuring all targets, dependencies, and build settings |
| `scripts/build_all_targets.sh` | Debug build of all targets (iOS simulator + watchOS simulator) |
| `scripts/build_release_targets.sh` | Release build of all targets |
| `scripts/test_apple_targets.sh` | Runs both `VolumeArcAppTests` (unit + integration) and `VolumeArcAppUITests` (XCUITest smoke) on iPhone 17 simulator |
| `scripts/test_performance.sh` | VOL-99. Runs the `VolumeArcAppPerfTests` suite on iPhone 17 simulator and writes an xcresult bundle to `.build/perf-results.xcresult`. Tag-gated in CI |
| `scripts/run_uat_agent.sh` | VOL-169. Runs the gated exploratory UAT XCUITest bridge, producing `.build/uat-agent/report.json` and an xcresult bundle for the nightly workflow |
| `scripts/check_performance.sh` | VOL-99. Parses the perf xcresult bundle, compares each metric against `docs/performance-budgets.json`, fails on any `failThreshold` breach, and appends to `docs/performance-trend.json` |
| `scripts/check_pr_size_proxy.sh` | VOL-215. PR-time warning-only bundle-size proxy that measures Debug simulator build products from `.build/derived-data` and compares `pr_size_proxy_*` budgets. |
| `scripts/check_ipa_size.sh` | VOL-215. Release/archive IPA size gate that measures the exported signed IPA and embedded app/watch bundles against `ipa_size_*` / `app_size_*` budgets. |
| `scripts/validate_release_config.sh` | Hard-fails on `ENABLE_TESTABILITY = YES` in Release, `DEBUG_INFORMATION_FORMAT` ≠ `dwarf-with-dsym`, missing entitlements, leaked demo symbols, missing privacy manifests, or unchanged `VERSION` on tag builds |
| `scripts/archive_for_distribution.sh` | Archives and exports a signed IPA for App Store / TestFlight. Requires `DEVELOPMENT_TEAM` |

All build scripts call `generate_xcode_project.rb` first, so the project is always fresh.

### CI / CD

GitHub Actions CI runs on the dedicated Apple Silicon self-hosted runner currently registered with the `mv-shared` label (`runs-on: [self-hosted, mv-shared]`). The workflow (`.github/workflows/ci.yml`) triggers on pushes to `main`, pull requests, and version tags (`v*`).

**CI pipeline:** Checkout → Pre-flight (Xcode / Ruby / xcodeproj / SwiftLint / disk headroom) → Generate Xcode project → Xcode project determinism gate (regenerate twice, diff SHA256 — VOL-95) → Xcode project no-op regen gate (regenerate over committed state, fail on any drift — VOL-106) → Seed SPM lockfile → Clear stale DerivedData → Build all targets (Debug) → Run unit + integration tests → XCUITest smoke suite → Coverage gate (VolumeArcCore ≥ 80% — VOL-52) → Upload xcresult + coverage-summary artifacts → Sticky PR coverage comment → Trend-append on main push → SwiftLint hard-fail → Validate release config. The AI review gate runs in a separate workflow (`.github/workflows/ai-review-gate.yml`). **As of VOL-172, CodeRabbit Pro and Codex Code Review are both active again**: the gate posts current-head `@coderabbitai review` and `@codex review` requests, waits for both bots to signal on the current head SHA, and filters known non-review bot messages (Codex/CodeRabbit rate-limit notices, trigger acknowledgements, actions-only comments) so they cannot satisfy a required check.

**TestFlight deploy:** On version tags (`v*`), a second job runs `fastlane ios beta` to archive, sign, and upload to TestFlight. Requires `DEVELOPMENT_TEAM`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_PATH` secrets. The key path points to the raw `.p8`; Fastlane builds the API key object in memory and refuses group/world-readable key files.

**Fastlane:** `Gemfile` + `fastlane/Fastfile` with three lanes: `test` (run tests with coverage), `beta` (build + upload to TestFlight), `release` (submit to App Store review).

### Privacy Manifests

Each target includes a `PrivacyInfo.xcprivacy` declaring required reason API usage (UserDefaults, FileTimestamp). These are added to targets by `generate_xcode_project.rb` and validated by `validate_release_config.sh`.

### Localization

Every user-facing string in `VolumeArcUI/Screens/` and `Watch/` goes through `String(localized:comment:)` with a translator comment. Currently English-only, but the full catalog is extractable to a String Catalog (`.xcstrings`) without code changes. Plural-bearing strings use Apple's `^[\(count) thing](inflect: true)` syntax for CLDR plural agreement. Enum display labels live in `VolumeArcNative/Sources/VolumeArcUI/LocalizedLabels.swift` as extensions on `AdvancementLevel`, `CoachingStyle`, `Equipment`, and `PrivacyMode` so translators see all enum-derived labels in one place.

### Accessibility

- `VA.Typography` tokens use `Font.system(TextStyle, design:, weight:)` so every text style scales with Dynamic Type from `.xSmall` through `.accessibility5`.
- `VAButton`, `VACoachBubble`, `VACard`, and metric displays expose combined accessibility elements with VoiceOver labels, hints, and the `.isButton` trait where interactive.
- Readiness hero, rest timer, coach bubbles, and recent session rows all announce meaningful values (e.g., "Readiness score 82 out of 100", "42 seconds remaining").
- `VAToastPresenter` toasts announce their kind prefix ("Success: Set logged").
- Hero transitions respect `@Environment(\.accessibilityReduceMotion)` and fall back to cross-fade.

### Building

```bash
# Generate project + debug build
./scripts/build_all_targets.sh

# Run tests
./scripts/test_apple_targets.sh

# Validate release config
./scripts/validate_release_config.sh

# Archive for App Store / TestFlight
export DEVELOPMENT_TEAM=A886EMZZW6
./scripts/archive_for_distribution.sh
```

## Code Conventions

- **Conditional compilation everywhere:** All platform-specific APIs guarded with `#if canImport(...)` and `#available(...)` for graceful degradation across platforms and OS versions.
- **Factory pattern for runtime dependencies:** Platform-specific implementations chosen at init time via static factory methods on the app or model types.
- **Unavailable stubs:** Each integration has an `Unavailable*` fallback (e.g., `UnavailableHealthStore`, `UnavailableCloudSyncTransport`, `UnavailableVoiceTransport`) so the app always launches.
- **Actor isolation:** Network-bound providers (`VolumeArcAppAttestRelaySessionProvider`, `VolumeArcVoicePermissionStore`) use Swift actors for thread safety.
- **No Package.swift at root:** The Xcode project is Ruby-generated, not SPM-based. `VolumeArcNative/` contains the Swift package structure for shared frameworks.
- **Localized strings:** All user-facing strings use `String(localized:comment:)` for future translation support. Plural-bearing strings use `^[count thing](inflect: true)`. Enum labels live in `LocalizedLabels.swift`.
- **Accessibility:** All interactive and data-display elements in Watch and Widget views have VoiceOver labels, hints, and values. Design system components carry built-in accessibility so screens that use them inherit it.
- **Codable payloads:** Watch-to-phone payloads use `Codable` structs encoded via `SyncPayloadCodec` rather than ad-hoc string formatting.
