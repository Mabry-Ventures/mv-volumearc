# Feature Status

> **Warning: Pre-launch release phase.** Historical readiness work closed many early blockers, but active launch work is now tracked by the [VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762) initiative and [`VOLUMEARC_RELEASE.md`](VOLUMEARC_RELEASE.md). See [`PLATFORM.md`](PLATFORM.md#implementation-status) for authoritative system-level status.

This is the granular per-feature checklist. For high-level system status, see [`PLATFORM.md`](PLATFORM.md). Update this file with every PR that changes feature completeness.

## Legend
- Done **Shipped** — feature is complete and tested for its documented scope
- In progress **In progress** — feature exists and partially works, but has known gaps
- Scaffold **Scaffold** — types and wiring exist but concrete implementation is stub
- Planned **Planned** — not yet started (see [VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762) for active release tickets)

## Platform surfaces

| Feature | Status | Notes |
|---------|--------|-------|
| iPad UX parity (iPad 11" + iPad Pro 13") | Not v1.0 | [VOL-131](https://linear.app/mabry-ventures/issue/VOL-131) scopes v1.0 to iPhone + paired Apple Watch. A future iPad launch will need a new audit pass, iPad-specific layouts where compact split-view breaks, an updated Snapfile, and App Store metadata changes. |
| In-app feedback channel (Sentry user-feedback widget) | Done | Profile → Send feedback opens a navigation-backed feedback surface. Captures recent telemetry events + build context, redacts PII via `VolumeArcSentryPIIScrubber`, forwards to Sentry via `SentrySDK.capture(feedback:)`. `VolumeArcFeedbackSubmitter` + `FeedbackView` + `VolumeArcFeedbackJourneyTests` live since VOL-176. Tracked completion in [VOL-146](https://linear.app/mabry-ventures/issue/VOL-146). |
| Apple Watch Vitals + Training Load (watchOS 26.4+) | Done | Reads Apple Workout Effort via `HKWorkoutEffortRelationshipQuery`, uses estimated Workout Effort as fallback, reads wrist-temperature + respiratory-rate Vitals trends, surfaces "Vitals say" on Today from `RecoveryContext` and on Watch as a live HR/readiness training insight, and passes the HealthKit aggregates into `RecoveryContext`. Apple's Vitals composite score is not public HealthKit API yet, so the implementation uses the public underlying metrics. Shipped in [VOL-154](https://linear.app/mabry-ventures/issue/VOL-154). |
| Public coach-quality page (volumearc.app/quality) | Done | Renders the coach-eval trend from [`docs/coach-eval-trend.json`](coach-eval-trend.json), including latest nightly status, 30-run axis pass-rate chart, fixture-level last-run table, GitHub Actions run/commit links, and an honest empty state until the first scheduled record lands. Tracked in [VOL-148](https://linear.app/mabry-ventures/issue/VOL-148). |
| iOS navigation shell (5 tabs) | Done | Full tab bar with Today, Workouts, Coach, Signals, and Profile, routed by `DashboardNavigationModel`. |
| Today dashboard | Done | Readiness hero, next workout hero card, quick actions, recent sessions, and zoom hero transitions. |
| Workouts tab | Done | Active session flow, rest timer, log set, session summary, and workout detail surfaces are live. |
| Coach chat | Done | Real text coach, streaming response UX, memory-backed prompts, and relay/local/on-device fallback chain. |
| Co-design planning schedule | In progress | Today `Plan tomorrow` opens the Coach plan draft; `Schedule` persists tomorrow's edited co-designed prescription into the SwiftData weekly plan, refreshes the dashboard, emits `coach.plan_scheduled`, and shows the scheduled card in Workouts with an exercise preview. Template saving, dedicated-screen parity, and Watch start/sync proof remain open under VOL-275. |
| Signals / readiness | Done | Readiness breakdown, volume chart, and frequency heatmap ship in the Signals surface. |
| Profile / settings | Done | Profile header, training settings, edit profile flow, diagnostics entry point, and subscription gating surfaces are live. |
| Onboarding flow | Done | `RootDashboardView` presents `OnboardingView` via `fullScreenCover` on first launch, keyed off `DashboardNavigationModel.showOnboarding`. |
| watchOS workout UI | Done | Real HealthKit workout session, rest timer, coach cues, action decisions, "Vitals say" training insight, Apple Watch Ultra Action Button intents for start/log-next-set, and watchOS Double Tap primary-action set logging with haptic + spoken feedback, accessibility labels, and offline replay. |
| Widgets (systemSmall/systemMedium/watchOS) | Done | `NextWorkoutWidget` and watch widgets read real shared snapshots via `PlatformSurfaceDefaultsReader`. |
| Live Activities | Done | `ActiveWorkoutLiveActivity` publishes real session state with lock screen, Dynamic Island, and Apple Watch supplemental layouts for active-session rest timer + set-progress presence. |

## AI & coaching

| Feature | Status | Notes |
|---------|--------|-------|
| HealthKit depth in coach prompt (HRV / sleep debt / training load) | Done | Killer-app differentiator. `RecoveryContext` value type (VOL-145 Phase 1A) + `HealthKitRecoveryReader` (VOL-145 Phase 1B / [VOL-181](https://linear.app/mabry-ventures/issue/VOL-181), expanded by [VOL-154](https://linear.app/mabry-ventures/issue/VOL-154)) feed `CoachPromptTemplate` with 7-day HRV mean vs 28-day baseline, sleep debt, weekly strength load, Apple Workout Effort, wrist-temperature trend, and respiratory-rate trend. HK-aware intent envelopes for `.recovery` / `.deload` / `.progression` reference the recovery signals when present. `WorkoutDashboardModel` injects the reader and caches the snapshot on every dashboard refresh. |
| Today-tab recovery chip ("Vitals say") | Done | `VARecoveryChip` surfaces the dominant recovery signal from the cached `RecoveryContext` — HRV trend if absolute delta > 5%, else sleep debt if absolute debt > 2h, else Apple Watch Vitals score when Apple exposes one, else wrist-temperature / respiratory-rate trends, else Apple Workout Effort, else "all systems normal." Tap opens a detail sheet with the full breakdown. Self-suppresses when HK has no data. Shipped in [VOL-181](https://linear.app/mabry-ventures/issue/VOL-181), expanded in [VOL-154](https://linear.app/mabry-ventures/issue/VOL-154). |
| Curated programs library (5/3/1, PPL, Starting Strength) | Done | Six-program V1 library with SwiftData assignment, Workouts-tab entry point, schedule replacement, and program-aware coach prompt context. Tracked in [VOL-144](https://linear.app/mabry-ventures/issue/VOL-144). |
| Apple Intelligence — Writing Tools + Image Playground | Done | Profile → Coach Memory uses a Writing Tools-enabled `TextEditor` for user-authored training context; next-workout detail opens Image Playground for form-cue illustrations when supported and stores the generated image locally per exercise. iOS 26+. Shipped in [VOL-159](https://linear.app/mabry-ventures/issue/VOL-159). |
| Vision-based form check V1 (bench / squat / deadlift) | In progress | Prototype shipped behind the Workouts-tab active-session action for supported movements, with Apple Watch hands-free start/stop/result control added in [VOL-242](https://linear.app/mabry-ventures/issue/VOL-242). Uses `VNDetectHumanBodyPoseRequest` on-device only, keeps camera frames in memory, emits rep count / tempo / lateral-drift verdicts, feeds derived metrics into the coach prompt context, and documents the privacy boundary. Real-lift accuracy validation remains before this can be called production-complete. Tracked in [VOL-155](https://linear.app/mabry-ventures/issue/VOL-155). |
| AI provider chain (Foundation Models → Relay → Local) | Done | Runtime factory selects the three-provider chain with graceful fallback. |
| Coach safety filter | Done | Last-mile response filtering buffers symptom prompts and current symptom context before streaming, replaces unsafe push/heavy/grind language with rest-first light-training guidance, and escalates medical red flags before any model wording reaches the athlete. |
| `AIRelayCoachProvider` | Done | Real HTTP relay-backed coach provider in production use. Routes outbound prompts through `CoachPromptTemplate.render(...)`. |
| `LocalHeuristicAICoachProvider` | Done | Real rule-based offline fallback grounded in readiness and recent-session context. Dispatches against the templated prompt so its intent classification stays in lockstep with the cloud path. |
| `FoundationModelCoachProvider` | Done | On-device provider is wired and falls back cleanly when unavailable or failing. Hands the on-device session the same templated prompt the relay sees. |
| `CoachPromptTemplate` adoption | Done | Single `render(intent:contextBlock:question:style:)` entry point. System prompt + per-intent envelope + structured context block + template marker land in every outbound prompt across all three providers. Verified by `VolumeArcCoachPromptTemplateTests`. |
| Voice transport | Done | `AIRelayVoiceTransport` is live for single-turn voice → text → spoken response. Live duplex/WebRTC audio remains future work. |
| Coach memory | Done | `CoachMemoryRepository` persists recent context and is appended during coaching turns. |
| Streaming response UX | Done | `AIRelayCoachProvider.streamCoachResponse` consumes `text/event-stream` from the `volumearc-ai-relay` Cloudflare Worker, parses `data: {"text":"..."}` frames, and yields Gemini tokens as they arrive. Non-streaming callers join the stream to a single string. Synthetic word-chunking is kept as the default-impl fallback for providers without native streaming. |
| Evaluation harness | Done | Template-layer hermetic `CoachEvalTests` asserts marker, system prompt persona, intent envelope, context preservation, and prompt-boundary sanitization against 47 fixtures under `Tests/Evals/CoachEvalFixtures/`, including medical red flags and prompt-injection attempts. Response-layer live relay evals run nightly against the staging relay through the VOL-244 eval attestation broker, gated by an explicit host allowlist and Durable Object counter store, preserving production App Attest-only auth while restoring model-output regression failures. |
| Privacy mode enforcement | Done | Standard/Strict mode is available during onboarding and Profile editing. Strict mode redacts free-text PII and strips identifying coach context before outbound coach prompts leave the device. |

## Data & progression

| Feature | Status | Notes |
|---------|--------|-------|
| SwiftData schema V1 | Done | `UserProfileRecord`, `WorkoutRecord`, `TrainingPlanRecord`, and `CoachMemoryRecord` ship with migration coverage. |
| Persistence fallback chain | Done | Cloud-synced → local fallback → in-memory fallback → unavailable, with telemetry and bootstrap metadata. |
| `SwiftDataWorkoutRepository` | Done | Create, append set, complete, delete, recent/history projection, and aggregate updates are real. |
| `SwiftDataUserProfileRepository` | Done | Upsert, load, onboarding completion, and athlete profile projection are live. |
| `SwiftDataTrainingPlanRepository` | Done | Upsert weekly plan and query next workout are live. |
| `SwiftDataCoachMemoryRepository` | Done | Append, fetch recent, and pruning behavior ship. |
| `ProgressionEngine` | Done | Progression, substitution, and recommendation logic are exercised by production code and tests. |
| `ReadinessModel` | Done | Five-factor readiness scoring is live in the dashboard and coach context. |
| Exercise catalog | Done | VOL-105 Phase 1 (#77) scales the catalog 11 → 133 entries with extended schema (`MuscleGroup` 22-case taxonomy, `DifficultyTier`, `HKActivityTypeMapping`, `aliases`, `unilateral`, `lengthenedPositionEmphasis`). Sources: ~95 entries derived from [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db) (The Unlicense — text only, no images), ~25 hand-authored modern hypertrophy movements (Bulgarian split squat, pendulum squat, pec deck, leaning lateral raise, single-leg/B-stance hip thrust, Nordic, Pendlay, Meadows, seal row, PJR pullover, tibialis raise, paused/pin/block variants). VOL-105 Phase 2 ships a per-exercise illustration for every catalog entry under `App/Assets.xcassets/ExerciseIllustrations/<id>.imageset/`, generated via Codex CLI's `image_generation` tool from a single style canon (`Tools/exercise-art/STYLE.md`). `ExerciseDefinition.illustrationAssetName` resolves to `ExerciseIllustrations/<id>` for `Image(_:bundle:)` consumers. `ExerciseIllustrationCoverageTests` pins the catalog ↔ illustration coverage in both directions. |

## Sync & connectivity

| Feature | Status | Notes |
|---------|--------|-------|
| `CloudSyncCoordinator` | Done | Push/pull cycle with outbound queue drain, cursor persistence, and apply path ship. Entitlement-gated via `VolumeArcCloudConfiguration.hasCloudKitEntitlement` so simulator Debug builds fall back cleanly. |
| `CloudKitSyncTransport` | Done | `CKModifyRecordsOperation` push and `CKFetchRecordZoneChangesOperation` pull are wired against the hardcoded container identifier in `VolumeArcCloudConfiguration`. |
| `FileSyncStateStore` | Done | Real disk-backed sync cursor persistence across launches. |
| `DefaultSyncPayloadApplier` | Done | Round-trips workout records, sets, RPE, and aggregate updates (Phase 3b burndown in [PR #27](https://github.com/Mabry-Ventures/mv-volumearc/pull/27)). |
| Outbound sync record generation | Done | Every repository write path (`create`, `appendSet`, `complete`, profile upsert, training plan upsert, coach memory append) calls `stageUpsert` into `OutboundSyncQueue` which `CloudSyncCoordinator.syncCycle` drains. |
| `WatchConnectivityCoordinator` | Done | Real `WCSession` transport plus offline pending-payload queue and replay behavior, including watch-triggered form-check start/stop/result payloads. |
| `NetworkReachabilityMonitor` | Done | Real `NWPathMonitor` wrapper and app startup wiring for sync/connectivity decisions. |
| Background sync (`BGAppRefreshTask` + `BGProcessingTask`) | Done | Task registration code in `App/VolumeArcBackgroundTasks.swift`; `App/Info.plist` declares both task identifiers and the `UIBackgroundModes` iOS requires. |

## Observability

| Feature | Status | Notes |
|---------|--------|-------|
| Telemetry fanout | Done | Fanout sink combines in-memory, UserDefaults, OSLog, and Sentry sinks. |
| `OSLogTelemetrySink` | Done | Unified logging integration is live. |
| `UserDefaultsTelemetrySink` | Done | Rolling persistent event buffer ships for diagnostics. |
| `InMemoryTelemetrySink` | Done | Bootstrap/runtime in-memory sink ships. |
| `SentryTelemetrySink` | Done | Breadcrumb forwarding and error message capture are live. |
| Startup signals | Done | Missing/degraded persistence, relay, CloudKit, and Sentry conditions surface operational signals. |
| Feature-flag runtime gating | Done | `FeatureFlagProvider` + `FlagGateTelemetry` wire all four flags (`voiceCoaching`, `cloudSync`, `liveActivities`, `foundationModelCoach`) into the factory, cloud-sync coordinator, and live-activity controller. Off-state drops the relevant capability to its `Unavailable*` / no-op fallback. First resolution per flag per launch emits a `feature.flag.applied` `.info` telemetry event. |
| Premium entitlement gating (VOL-91) | Done | `PremiumEntitlementProviding` protocol + `StoreKitSubscriptionStore.isPremium` thread through `VolumeArcAIRuntimeFactory.makeCoachProvider(subscriptionStore:)` and `makeVoiceCoach(subscriptionStore:)`. Premium users get `AIRelayCoachProvider(tier: .pro)` and the live-voice transport (still AND-gated on `.voiceCoaching`); free users fall back to Flash Lite + `UnavailableVoiceTransport`. `PremiumGateTelemetry` emits one-shot `premium.entitlement.gated` `.info` events per feature (`coach_tier`, `live_voice`) per launch with `{"premium": "true|false"}` metadata. Cloud sync, Foundation Models, and Live Activities stay free for all — decision parked in the VOL-91 PR body for product to revise. |

## Infrastructure

| Feature | Status | Notes |
|---------|--------|-------|
| Marketing site (`marketing/` → `volumearc.app`) | In progress | Next.js 16 + Tailwind v4 + shadcn/ui site adapted from Tailwind Plus Pocket. Pages: `/`, `/terms`, `/privacy`, `/support`, `/quality`; `/quality` is wired to the public coach-eval trend file. CI build gate live. Vercel project link + custom domain + legal counsel review pending. See [`docs/MARKETING.md`](MARKETING.md). |
| Generated Xcode project | Done | `scripts/generate_xcode_project.rb` remains the only source of truth for the Xcode project. |
| CI pipeline (M4 self-hosted runners) | Done | Build, unit/integration tests, UI smoke tests, lint, and validation run on the dedicated Apple Silicon PR and main runner. |
| Exploratory UAT agent | Done | Nightly workflow drives a gated XCUITest bridge with screenshots + accessibility trees, bounded model-selected actions, JSON/Markdown reports, and a sticky GitHub issue summary. Tracked in [VOL-169](https://linear.app/mabry-ventures/issue/VOL-169). |
| Fastlane (test/beta/release) | Done | TestFlight automation and App Store submission lanes ship. |
| Archive script | Done | `archive_for_distribution.sh` produces signed distribution archives. |
| Privacy manifests | Done | Required manifests ship for all relevant targets and are validated. |
| SwiftLint | Done | Installed on the runner and enforced in CI. |
| Versioning from git | Done | `VERSION` + git-derived build number flow ships. |
| Localization (`String(localized:)`) | Done | Every user-facing string is localized with translator comments. No `.xcstrings` catalog file is generated yet, but the codebase is fully extractable. |
| Accessibility labels | Done | Data displays, interactive controls, widgets, watch surfaces, and toast announcements have shipped accessibility coverage. |
| Hard-failing release validation | Done | `scripts/validate_release_config.sh` hard-checks the checked-in `App/Info.plist` via `plutil -extract` for `CFBundleURLTypes`, `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes`, the `volumearc` URL scheme, and both BGTask identifiers (VOL-85), and validates signed entitlements on the built `.app` via `codesign -d --entitlements -` for `aps-environment = production`, iCloud container identifier, HealthKit, and App Groups (VOL-92). Fastlane runs it against the archived bundle before TestFlight upload. |
| Checked-in `App/Info.plist` (vs `INFOPLIST_KEY_*`) | Done | `App/Info.plist` is checked in and wired via `INFOPLIST_FILE`. Array-valued keys that `INFOPLIST_KEY_*` silently drops now live in the plist file. |
| AI review gate (CodeRabbit Pro + Codex) on PRs | Done | Two-bot review gate is part of the protected-branch merge contract. `Request AI Reviews` posts current-head review requests for CodeRabbit Pro and Codex Code Review, then waits for both bots to signal on that head SHA. |

## Design

| Feature | Status | Notes |
|---------|--------|-------|
| Design tokens | Done | `VA.Colors`, `VA.Typography`, `VA.Space`, `VA.Radius`, and `VA.Shadow` define the visual system. |
| Core components | Done | Shared cards, buttons, metric displays, progress rings, states, and coach bubbles ship in `VolumeArcUI`. |
| Liquid Glass materials | Done | Real iOS 26 Liquid Glass APIs (`SwiftUI.Glass`, `View.glassEffect`, `GlassEffectContainer`) ship across `VACard`, `VAToast`, `VACoachBubble`, the next-workout hero, paywall plan rows, onboarding rows, coach prompts/composer, and session metric grid. Routed through `VA.Materials.glass / glassInteractive / tintedGlass(_:)` design tokens with a solid-fill fallback for `accessibilityReduceTransparency`. |
| Haptics system | Done | Centralized `VAHaptics` patterns ship across training interactions. |
| Motion system | Done | Shared spring tokens and motion helpers ship. |
| Dark mode | Done | Tokens adapt correctly in light and dark appearance. |
| Dynamic Type | Done | Typography tokens scale and screens were updated for Dynamic Type support. |
| Reduced Motion | Done | Motion-sensitive surfaces respect `@Environment(\.accessibilityReduceMotion)`. |
| `VAToast` notification system | Done | `VAToast`, `VAToastPresenter`, and overlay presentation ship with accessibility announcements. |
| Hero transitions (`.navigationTransition(.zoom)`) | Done | Today next-workout and recent-session navigation use iOS 18+ zoom hero transitions with reduce-motion fallback. |
| Pluralization (Apple inflection syntax) | Done | Count-bearing strings use `^[\(count) thing](inflect: true)` for CLDR-aware plural agreement. |
| Shared `LocalizedLabels` extensions | Done | Enum display strings for `AdvancementLevel`, `CoachingStyle`, `Equipment`, and `PrivacyMode` live in one translator-friendly file. |
