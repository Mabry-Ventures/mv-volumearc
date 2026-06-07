# Chaos / fault-injection UAT (VOL-168)

> **Status:** Phase 1 (HealthKit) shipped 2026-05-11. AIRelay 5xx, offline, 401 safe fallback, 401 session-refresh retry proof, and deterministic slow coach stream recovery proof shipped under VOL-141/VOL-168 and VolumeArc Release. Foundation Models unavailable fallback proof shipped under VolumeArc Release. Remaining Phase 2 (WatchConnectivity, StoreKit, BGTaskScheduler, timeout/malformed/rate-limit AIRelay faults) tracked under VOL-168.

VolumeArc's XCUITest journeys cover the happy path. Most reported "weird bugs we can't repro" happen on the unhappy paths — HealthKit denial mid-onboarding, BLE drop during a watch workout, a purchase that got cancelled by Apple's fraud-prevention layer. Hardware-paired regression devices catch some of this (VOL-94's canary suite), but those tests are slow and hardware-blocked.

Chaos infrastructure closes the gap: a single launch argument flips a subsystem's runtime implementation from "real" to "deterministically faulty," and a paired XCUITest journey asserts the app degrades gracefully — no crash, sensible user-visible state, useful diagnostic telemetry.

## How it works

1. `App/Debug/ChaosController.swift` exposes one `public static var` per fault. Each accessor is `#if DEBUG`-gated so it returns `false` unconditionally in Release builds. The symbol exists in all configs so call sites don't need their own preprocessor gates.

2. App factory code consults `ChaosController` and, when a flag is set, wraps the real implementation in a decorator or deterministic failing provider (e.g. `ChaosHealthStore` around `HealthKitRuntimeStore`, or `ChaosAICoachProvider` through `VolumeArcAIRuntimeFactory`).

3. The decorator injects the modeled fault — a thrown error, a dropped payload, a delayed completion — on the call the test cares about.

4. The paired XCUITest journey in `VolumeArcChaosJourneyTests` (`Tests/VolumeArcAppUITests/`) launches the app with the matching `-CHAOS_*` launch argument, drives the user flow, and asserts the expected graceful-degradation behavior plus the diagnostic telemetry event (via the VOL-149 telemetry probe).

## Production safety

Every chaos accessor on `ChaosController` has a single `#if DEBUG` gate inside it. Release builds compile each accessor down to `return false`. The factory wiring that consumes those accessors is also `#if DEBUG`-bracketed for belt-and-suspenders. Net result: **no `ChaosHealthStore` (or any other decorator) is ever instantiated in shipping binaries**, even if an attacker somehow injected a `-CHAOS_*` argv at launch.

The implementation files themselves (`ChaosHealthStore.swift`, etc.) DO ship in Release because excluding them from the build would create configuration drift. Their contents are dead code in Release; the Swift compiler's dead-code stripping under release-mode `-O` removes the implementations from the final binary, and even if it didn't, the only entry point is via the never-true `ChaosController` flag.

## Current flag list

| Flag | Subsystem | Effect | Test |
|---|---|---|---|
| `-CHAOS_HEALTH_AUTH_DENIED` | HealthKit | Next `requestAuthorization` throws `ChaosError(.authorizationDenied)`. The dashboard model's `auth_failed` telemetry branch fires; the Profile health row stays in "Connect" state. | `VolumeArcChaosJourneyTests.testHealthAuthDenialIsHandledGracefully` |
| `-CHAOS_AIRELAY_5XX` | AIRelay | Coach primary provider throws a deterministic 503 before yielding any token. `FallbackCoachProvider` switches to the local heuristic path and emits `coach.fallback_used`. | `VolumeArcCoachJourneyTests.testCoachRelay5xxFallsBackToLocalHeuristic` |
| `-CHAOS_AIRELAY_OFFLINE` | AIRelay | Coach primary provider reports the relay unavailable before yielding any token. `FallbackCoachProvider` switches to the local heuristic path, the Coach tab shows the offline fallback banner, and `coach.fallback_used` fires. | `VolumeArcCoachJourneyTests.testCoachOfflineFallsBackToLocalHeuristicAndShowsBanner` |
| `-CHAOS_AIRELAY_401` | AIRelay | Coach primary provider throws a deterministic 401 before yielding any token. The runtime refreshes the relay session, retries once, then falls back to the local heuristic response if the retry is also unauthorized. | `VolumeArcCoachJourneyTests.testCoachRelay401FallsBackToLocalHeuristic` |
| `-CHAOS_AIRELAY_401_THEN_SUCCESS` | AIRelay | Coach primary provider throws a deterministic 401 on the first attempt, the runtime refreshes relay session credentials, and the retried request succeeds without showing fallback UI. | `VolumeArcCoachJourneyTests.testCoachRelay401RefreshesSessionAndRetries` |
| `-CHAOS_COACH_SLOW_STREAM` | Coach | Installs a deterministic slow streaming provider so the app can be killed after `coach.first_token_received` and before completion. Relaunch consumes the in-flight marker, drops the partial turn, emits `coach.stream.aborted`, and accepts a fresh prompt. | `VolumeArcCoachJourneyTests.testForceQuitCoachTurnDropsPartialAndEmitsAbortedOnRelaunch` |
| `-CHAOS_FM_UNAVAILABLE` | Foundation Models | App coach factory records `ai.fm.unavailable` and routes to relay or local fallback without exposing model-provider copy in the Coach UI. | `VolumeArcCoachJourneyTests.testCoachFoundationModelsUnavailableFallsBackQuietly` |

## Current debug fixture list

These flags install deterministic healthy state rather than a fault. They are still DEBUG-gated in `ChaosController` so Release builds ignore them.

| Flag | Subsystem | Effect | Test |
|---|---|---|---|
| `-UseAuthorizedHealthFixture` | HealthKit | Installs a debug-only `HealthStore` that reports Apple Health as connected, so connected-state journeys can run without the system Health permission sheet. | `VolumeArcTodayJourneyTests.testTodayReadinessTapOpensSignals` |
| `-UseAuthorizedVoiceFixture` | Voice permissions | Installs a debug-only `VoicePermissionStore` that reports microphone and speech recognition as authorized, so Coach voice journeys can run without simulator permission sheets. | `VolumeArcCoachJourneyTests.testVoicePromptUsesPremiumPermissionFixtureAndEmitsTelemetry` |
| `-VoicePromptTranscriptFixture <text>` | Coach voice | Supplies the transcript a speech-recognition pass would produce during deterministic `-UITestMode 1` launches. Used with the premium entitlement and authorized voice fixtures to prove the single-turn voice coach path. | `VolumeArcCoachJourneyTests.testVoicePromptUsesPremiumPermissionFixtureAndEmitsTelemetry` |
| `-RestTimerDurationSeconds 3` | Workouts | Shortens the active-session rest timer during `-UITestMode 1` launches only, so expiry UI and telemetry can be proven without waiting for the production 90-second default. | `VolumeArcAppJourneyTests.testWorkoutRestTimerExpiryEmitsTelemetryAndShowsCompletionToast` |
| `-PreserveUITestPersistence` | Persistence | Keeps SwiftData state across a deterministic relaunch when fixture seeding is off, so force-quit recovery journeys can prove production persistence behavior without the normal UI-test reset. | `VolumeArcAppJourneyTests.testForceQuitActiveWorkoutRestoresLoggedSetOnRelaunch` |

## Phase 2+ roadmap

| Flag (proposed) | Subsystem | Fault | Tracked |
|---|---|---|---|
| `-CHAOS_WC_DROP_NEXT_N` | WatchConnectivity | Drop the next N payloads bidirectionally | VOL-168 P2 |
| `-CHAOS_WC_SESSION_INTERRUPTED` | WatchConnectivity | Simulate BLE drop mid-session | VOL-168 P2 |
| `-CHAOS_STOREKIT_USER_CANCELLED` | StoreKit | Purchase resolves to `userCancelled` | VOL-168 P2 |
| `-CHAOS_STOREKIT_NOT_ENTITLED` | StoreKit | Entitlement check returns `notEntitled` mid-session | VOL-168 P2 |
| `-CHAOS_BGTASK_UNSUBMIT` | BGTaskScheduler | Submitted task is cancelled before execution | VOL-168 P2 |
| `-CHAOS_AIRELAY_TIMEOUT` | AIRelay | Coach SSE request times out at the first chunk | VOL-168 P2 |
| `-CHAOS_AIRELAY_MALFORMED_SSE` | AIRelay | SSE delivers a corrupt chunk mid-stream | VOL-168 P2 |
| `-CHAOS_AIRELAY_RATE_LIMIT` | AIRelay | Coach receives a 429 with retry-after header | VOL-168 P2 |

Each follow-up PR lands a single subsystem's chaos wrapper + one or more XCUITest journeys, mirroring this Phase 1 shape.

## Adding a new chaos flag

1. Add a `public static var` to `ChaosController` with a `#if DEBUG` gate and a comment naming the launch argument it reads and the test that exercises it.
2. Add a decorator implementing the subsystem's protocol that wraps the real implementation and injects the fault on the relevant call. Put it next to the protocol in `VolumeArcNative/Sources/VolumeArcCore/<Subsystem>/`.
3. Wire the decorator into the matching app factory path behind `#if DEBUG && ChaosController.<flag>`.
4. Add a journey to `VolumeArcChaosJourneyTests` that launches with the flag, drives the relevant user flow, and asserts:
   - the app reaches a stable post-fault state;
   - the expected user-visible UI is shown (error toast, fallback state, etc.);
   - the diagnostic telemetry event fired (use `VolumeArcAppUITestSupport.assertTelemetryFired` — VOL-149).
5. Update this doc's "Current flag list" table.

## Cross-references

- `docs/TESTING.md` — overall testing architecture; the "Chaos / fault injection (VOL-168)" subsection links back here.
- `docs/AUDIT.md` — May 9 re-review identified this as the highest-leverage missing piece for the agentic-UAT story.
- VOL-149 (`docs/TESTING.md` "Telemetry-as-UAT") — every chaos journey assertion uses the telemetry probe to verify the right diagnostic event fired.
