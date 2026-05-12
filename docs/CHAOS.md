# Chaos / fault-injection UAT (VOL-168)

> **Status:** Phase 1 (HealthKit) shipped 2026-05-11. Phase 2 (WatchConnectivity, StoreKit, BGTaskScheduler, AIRelay) tracked under VOL-168.

VolumeArc's XCUITest journeys cover the happy path. Most reported "weird bugs we can't repro" happen on the unhappy paths — HealthKit denial mid-onboarding, BLE drop during a watch workout, a purchase that got cancelled by Apple's fraud-prevention layer. Hardware-paired regression devices catch some of this (VOL-94's canary suite), but those tests are slow and hardware-blocked.

Chaos infrastructure closes the gap: a single launch argument flips a subsystem's runtime implementation from "real" to "deterministically faulty," and a paired XCUITest journey asserts the app degrades gracefully — no crash, sensible user-visible state, useful diagnostic telemetry.

## How it works

1. `App/Debug/ChaosController.swift` exposes one `public static var` per fault. Each accessor is `#if DEBUG`-gated so it returns `false` unconditionally in Release builds. The symbol exists in all configs so call sites don't need their own preprocessor gates.

2. `App/VolumeArcAppFactories.swift`'s subsystem makers consult `ChaosController` and, when a flag is set, wrap the real implementation in a decorator (e.g. `ChaosHealthStore` wrapping `HealthKitRuntimeStore`).

3. The decorator injects the modeled fault — a thrown error, a dropped payload, a delayed completion — on the call the test cares about.

4. The paired XCUITest journey in `VolumeArcChaosJourneyTests` (`Tests/VolumeArcAppUITests/`) launches the app with the matching `-CHAOS_*` launch argument, drives the user flow, and asserts the expected graceful-degradation behavior plus the diagnostic telemetry event (via the VOL-149 telemetry probe).

## Production safety

Every chaos accessor on `ChaosController` has a single `#if DEBUG` gate inside it. Release builds compile each accessor down to `return false`. The factory wiring that consumes those accessors is also `#if DEBUG`-bracketed for belt-and-suspenders. Net result: **no `ChaosHealthStore` (or any other decorator) is ever instantiated in shipping binaries**, even if an attacker somehow injected a `-CHAOS_*` argv at launch.

The implementation files themselves (`ChaosHealthStore.swift`, etc.) DO ship in Release because excluding them from the build would create configuration drift. Their contents are dead code in Release; the Swift compiler's dead-code stripping under release-mode `-O` removes the implementations from the final binary, and even if it didn't, the only entry point is via the never-true `ChaosController` flag.

## Current flag list

| Flag | Subsystem | Effect | Test |
|---|---|---|---|
| `-CHAOS_HEALTH_AUTH_DENIED` | HealthKit | Next `requestAuthorization` throws `ChaosError(.authorizationDenied)`. The dashboard model's `auth_failed` telemetry branch fires; the Profile health row stays in "Connect" state. | `VolumeArcChaosJourneyTests.testHealthAuthDenialIsHandledGracefully` |

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
3. Wire the decorator into `App/VolumeArcAppFactories.swift`'s factory method behind `#if DEBUG && ChaosController.<flag>`.
4. Add a journey to `VolumeArcChaosJourneyTests` that launches with the flag, drives the relevant user flow, and asserts:
   - the app reaches a stable post-fault state;
   - the expected user-visible UI is shown (error toast, fallback state, etc.);
   - the diagnostic telemetry event fired (use `VolumeArcAppUITestSupport.assertTelemetryFired` — VOL-149).
5. Update this doc's "Current flag list" table.

## Cross-references

- `docs/TESTING.md` — overall testing architecture; the "Chaos / fault injection (VOL-168)" subsection links back here.
- `docs/AUDIT.md` — May 9 re-review identified this as the highest-leverage missing piece for the agentic-UAT story.
- VOL-149 (`docs/TESTING.md` "Telemetry-as-UAT") — every chaos journey assertion uses the telemetry probe to verify the right diagnostic event fired.
