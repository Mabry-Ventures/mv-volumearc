# Feature Status

> **⚠ Pre-production, hygiene phase.** The post-95/95 audit blockers (VOL-55, 56, 57, 58, 59, 62, 63, 65, 67) shipped in PRs [#23](https://github.com/Mabry-Ventures/mv-volumearc/pull/23)–[#31](https://github.com/Mabry-Ventures/mv-volumearc/pull/31). Remaining work (App Store submission blockers, CI hygiene, synthetic streaming, coverage gate) is tracked in the Linear **Go-Live Readiness** project on the VolumeArc team. See [`PLATFORM.md`](PLATFORM.md#implementation-status) for the authoritative system-level status.

This is the granular per-feature checklist. For high-level system status, see [`PLATFORM.md`](PLATFORM.md). Update this file with every PR that changes feature completeness.

## Legend
- ✅ **Shipped** — feature is complete, tested, and production-ready
- 🚧 **In progress** — feature exists and partially works, but has known gaps
- 🏗️ **Scaffold** — types and wiring exist but concrete implementation is stub
- 📋 **Planned** — not yet started

## Platform surfaces

| Feature | Status | Notes |
|---------|--------|-------|
| iOS navigation shell (5 tabs) | ✅ | Full tab bar with Today, Workouts, Coach, Signals, and Profile, routed by `DashboardNavigationModel`. |
| Today dashboard | ✅ | Readiness hero, next workout hero card, quick actions, recent sessions, and zoom hero transitions. |
| Workouts tab | ✅ | Active session flow, rest timer, log set, session summary, and workout detail surfaces are live. |
| Coach chat | ✅ | Real text coach, streaming response UX, memory-backed prompts, and relay/local/on-device fallback chain. |
| Signals / readiness | ✅ | Readiness breakdown, volume chart, and frequency heatmap ship in the Signals surface. |
| Profile / settings | ✅ | Profile header, training settings, edit profile flow, diagnostics entry point, and subscription gating surfaces are live. |
| Onboarding flow | ✅ | `RootDashboardView` presents `OnboardingView` via `fullScreenCover` on first launch, keyed off `DashboardNavigationModel.showOnboarding`. |
| watchOS workout UI | ✅ | Real HealthKit workout session, rest timer, coach cues, action decisions, accessibility labels, and offline replay. |
| Widgets (systemSmall/systemMedium/watchOS) | ✅ | `NextWorkoutWidget` and watch widgets read real shared snapshots via `PlatformSurfaceDefaultsReader`. |
| Live Activities | ✅ | `ActiveWorkoutLiveActivity` publishes real session state with lock screen and Dynamic Island layouts. |

## AI & coaching

| Feature | Status | Notes |
|---------|--------|-------|
| AI provider chain (Foundation Models → Relay → Local) | ✅ | Runtime factory selects the three-provider chain with graceful fallback. |
| `OpenAIRelayCoachProvider` | ✅ | Real HTTP relay-backed coach provider in production use. Routes outbound prompts through `CoachPromptTemplate.render(...)`. |
| `LocalHeuristicAICoachProvider` | ✅ | Real rule-based offline fallback grounded in readiness and recent-session context. Dispatches against the templated prompt so its intent classification stays in lockstep with the cloud path. |
| `FoundationModelCoachProvider` | ✅ | On-device provider is wired and falls back cleanly when unavailable or failing. Hands the on-device session the same templated prompt the relay sees. |
| `CoachPromptTemplate` adoption | ✅ | Single `render(intent:contextBlock:question:style:)` entry point. System prompt + per-intent envelope + structured context block + template marker land in every outbound prompt across all three providers. Verified by `VolumeArcCoachPromptTemplateTests`. |
| Voice transport | ✅ | `OpenAIRelayVoiceTransport` is live for single-turn voice → text → spoken response. Live duplex/WebRTC audio remains future work. |
| Coach memory | ✅ | `CoachMemoryRepository` persists recent context and is appended during coaching turns. |
| Streaming response UX | ✅ | `OpenAIRelayCoachProvider.streamCoachResponse` consumes `text/event-stream` from the `volumearc-ai-relay` Cloudflare Worker, parses `data: {"text":"..."}` frames, and yields Gemini tokens as they arrive. Non-streaming callers join the stream to a single string. Synthetic word-chunking is kept as the default-impl fallback for providers without native streaming. |
| Evaluation harness | 📋 | Prompt-quality regression tooling is still planned. |
| Privacy mode enforcement | 📋 | Privacy mode is modeled and surfaced in UI, but strict-mode prompt enforcement is not yet consistently applied in the dashboard coach path. |

## Data & progression

| Feature | Status | Notes |
|---------|--------|-------|
| SwiftData schema V1 | ✅ | `UserProfileRecord`, `WorkoutRecord`, `TrainingPlanRecord`, and `CoachMemoryRecord` ship with migration coverage. |
| Persistence fallback chain | ✅ | Cloud-synced → local fallback → in-memory fallback → unavailable, with telemetry and bootstrap metadata. |
| `SwiftDataWorkoutRepository` | ✅ | Create, append set, complete, delete, recent/history projection, and aggregate updates are real. |
| `SwiftDataUserProfileRepository` | ✅ | Upsert, load, onboarding completion, and athlete profile projection are live. |
| `SwiftDataTrainingPlanRepository` | ✅ | Upsert weekly plan and query next workout are live. |
| `SwiftDataCoachMemoryRepository` | ✅ | Append, fetch recent, and pruning behavior ship. |
| `ProgressionEngine` | ✅ | Progression, substitution, and recommendation logic are exercised by production code and tests. |
| `ReadinessModel` | ✅ | Five-factor readiness scoring is live in the dashboard and coach context. |
| Exercise catalog | ✅ | Shipping catalog supports the current training flows; future expansion is additive, not a blocker. |

## Sync & connectivity

| Feature | Status | Notes |
|---------|--------|-------|
| `CloudSyncCoordinator` | ✅ | Push/pull cycle with outbound queue drain, cursor persistence, and apply path ship. Entitlement-gated via `VolumeArcCloudConfiguration.hasCloudKitEntitlement` so simulator Debug builds fall back cleanly. |
| `CloudKitSyncTransport` | ✅ | `CKModifyRecordsOperation` push and `CKFetchRecordZoneChangesOperation` pull are wired against the hardcoded container identifier in `VolumeArcCloudConfiguration`. |
| `FileSyncStateStore` | ✅ | Real disk-backed sync cursor persistence across launches. |
| `DefaultSyncPayloadApplier` | ✅ | Round-trips workout records, sets, RPE, and aggregate updates (Phase 3b burndown in [PR #27](https://github.com/Mabry-Ventures/mv-volumearc/pull/27)). |
| Outbound sync record generation | ✅ | Every repository write path (`create`, `appendSet`, `complete`, profile upsert, training plan upsert, coach memory append) calls `stageUpsert` into `OutboundSyncQueue` which `CloudSyncCoordinator.syncCycle` drains. |
| `WatchConnectivityCoordinator` | ✅ | Real `WCSession` transport plus offline pending-payload queue and replay behavior. |
| `NetworkReachabilityMonitor` | ✅ | Real `NWPathMonitor` wrapper and app startup wiring for sync/connectivity decisions. |
| Background sync (`BGAppRefreshTask` + `BGProcessingTask`) | ✅ | Task registration code in `App/VolumeArcBackgroundTasks.swift`; `App/Info.plist` declares both task identifiers and the `UIBackgroundModes` iOS requires. |

## Observability

| Feature | Status | Notes |
|---------|--------|-------|
| Telemetry fanout | ✅ | Fanout sink combines in-memory, UserDefaults, OSLog, and Sentry sinks. |
| `OSLogTelemetrySink` | ✅ | Unified logging integration is live. |
| `UserDefaultsTelemetrySink` | ✅ | Rolling persistent event buffer ships for diagnostics. |
| `InMemoryTelemetrySink` | ✅ | Bootstrap/runtime in-memory sink ships. |
| `SentryTelemetrySink` | ✅ | Breadcrumb forwarding and error message capture are live. |
| Startup signals | ✅ | Missing/degraded persistence, relay, CloudKit, and Sentry conditions surface operational signals. |
| Feature-flag runtime gating | ✅ | `FeatureFlagProvider` + `FlagGateTelemetry` wire all four flags (`voiceCoaching`, `cloudSync`, `liveActivities`, `foundationModelCoach`) into the factory, cloud-sync coordinator, and live-activity controller. Off-state drops the relevant capability to its `Unavailable*` / no-op fallback. First resolution per flag per launch emits a `feature.flag.applied` `.info` telemetry event. |

## Infrastructure

| Feature | Status | Notes |
|---------|--------|-------|
| Generated Xcode project | ✅ | `scripts/generate_xcode_project.rb` remains the only source of truth for the Xcode project. |
| CI pipeline (self-hosted M4) | ✅ | Build, unit/integration tests, UI smoke tests, lint, and validation run on PRs and main pushes. |
| Fastlane (test/beta/release) | ✅ | TestFlight automation and App Store submission lanes ship. |
| Archive script | ✅ | `archive_for_distribution.sh` produces signed distribution archives. |
| Privacy manifests | ✅ | Required manifests ship for all relevant targets and are validated. |
| SwiftLint | ✅ | Installed on the runner and enforced in CI. |
| Versioning from git | ✅ | `VERSION` + git-derived build number flow ships. |
| Localization (`String(localized:)`) | ✅ | Every user-facing string is localized with translator comments. No `.xcstrings` catalog file is generated yet, but the codebase is fully extractable. |
| Accessibility labels | ✅ | Data displays, interactive controls, widgets, watch surfaces, and toast announcements have shipped accessibility coverage. |
| Hard-failing release validation | ✅ | `scripts/validate_release_config.sh` hard-checks the checked-in `App/Info.plist` via `plutil -extract` for `CFBundleURLTypes`, `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes`, the `volumearc` URL scheme, and both BGTask identifiers (VOL-85), and validates signed entitlements on the built `.app` via `codesign -d --entitlements -` for `aps-environment = production`, iCloud container identifier, HealthKit, and App Groups (VOL-92). Fastlane runs it against the archived bundle before TestFlight upload. |
| Checked-in `App/Info.plist` (vs `INFOPLIST_KEY_*`) | ✅ | `App/Info.plist` is checked in and wired via `INFOPLIST_FILE`. Array-valued keys that `INFOPLIST_KEY_*` silently drops now live in the plist file. |
| AI review gate (CodeRabbit Pro + Codex) on PRs | ✅ | Two-bot review gate is part of the protected-branch merge contract. CodeRabbit Pro is primary (server-side, auto-invoked on PR open/update); Codex Code Review is secondary (requested by `Request AI Reviews` workflow step). |

## Design

| Feature | Status | Notes |
|---------|--------|-------|
| Design tokens | ✅ | `VA.Colors`, `VA.Typography`, `VA.Space`, `VA.Radius`, and `VA.Shadow` define the visual system. |
| Core components | ✅ | Shared cards, buttons, metric displays, progress rings, states, and coach bubbles ship in `VolumeArcUI`. |
| Liquid Glass materials | ✅ | Real iOS 26 Liquid Glass APIs (`SwiftUI.Glass`, `View.glassEffect`, `GlassEffectContainer`) ship across `VACard`, `VAToast`, `VACoachBubble`, the next-workout hero, paywall plan rows, onboarding rows, coach prompts/composer, and session metric grid. Routed through `VA.Materials.glass / glassInteractive / tintedGlass(_:)` design tokens with a solid-fill fallback for `accessibilityReduceTransparency`. |
| Haptics system | ✅ | Centralized `VAHaptics` patterns ship across training interactions. |
| Motion system | ✅ | Shared spring tokens and motion helpers ship. |
| Dark mode | ✅ | Tokens adapt correctly in light and dark appearance. |
| Dynamic Type | ✅ | Typography tokens scale and screens were updated for Dynamic Type support. |
| Reduced Motion | ✅ | Motion-sensitive surfaces respect `@Environment(\.accessibilityReduceMotion)`. |
| `VAToast` notification system | ✅ | `VAToast`, `VAToastPresenter`, and overlay presentation ship with accessibility announcements. |
| Hero transitions (`.navigationTransition(.zoom)`) | ✅ | Today next-workout and recent-session navigation use iOS 18+ zoom hero transitions with reduce-motion fallback. |
| Pluralization (Apple inflection syntax) | ✅ | Count-bearing strings use `^[\(count) thing](inflect: true)` for CLDR-aware plural agreement. |
| Shared `LocalizedLabels` extensions | ✅ | Enum display strings for `AdvancementLevel`, `CoachingStyle`, `Equipment`, and `PrivacyMode` live in one translator-friendly file. |
