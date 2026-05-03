# Forensic Production-Readiness Audit — 2026-05-01

> **Source of truth:** [`PLATFORM.md`](PLATFORM.md) for current platform status. This doc records the audit findings and links to the [VolumeArc Production Readiness](https://linear.app/mabry-ventures/project/volumearc-production-readiness-af810008523d) Linear project that tracks burndown of every gap.

## TL;DR

**Composite production-readiness score before this project: 84/100.** VolumeArc is in the top decile of indie / small-team Apple-platform engineering. The PLATFORM/FEATURES/RELEASE doc discipline, [`scripts/validate_release_config.sh`](../scripts/validate_release_config.sh), the eval harness, the accessibility automation, and the Ruby-generated deterministic project are above the bar of teams with 10× the headcount. But specific, tractable gaps stand between "could be submitted to App Store" and "should be submitted with confidence."

| Dimension | Score | One-line verdict |
|---|---|---|
| Repo hygiene | 92 | Exemplary; one missing `Gemfile.lock`, missing root README/LICENSE/SECURITY |
| Documentation alignment | 88 | Source-of-truth pattern works; two minor doc-vs-code drifts; no SECURITY.md |
| Test coverage | 85 | 356 test functions, 80% Core gate enforced, 20-fixture eval matrix; missing snapshot tests, HK & CK mocks, dedicated Watch/Widget targets |
| CI/CD pipeline | 74 | Strong release validation; **critical fork-isolation gap on self-hosted runner**, AI review gate is advisory, no SAST/secret scanning, no dSYM auto-upload |
| Agentic UAT & automation | 80 | Best-in-class accessibility + hermetic fixture seeding + LLM eval harness; missing visual regression, response-eval CI, A/B framework, no in-app feedback |

**Three things that would change the verdict to "world-class, ship now":**
1. **Add a fork-PR guard on the self-hosted runner** — [VOL-132](https://linear.app/mabry-ventures/issue/VOL-132)
2. **Promote the AI review gate from advisory to required** — [VOL-134](https://linear.app/mabry-ventures/issue/VOL-134)
3. **Wire dSYM upload to Sentry in `fastlane ios beta`** — [VOL-133](https://linear.app/mabry-ventures/issue/VOL-133)

## Critical findings

### 🔴 Critical — must fix before TestFlight

| # | Finding | Ticket |
|---|---|---|
| 1 | No fork guard on self-hosted runner — external PR can execute arbitrary code on M4 with access to keychain, DerivedData, SSH key | [VOL-132](https://linear.app/mabry-ventures/issue/VOL-132) |
| 2 | Marketing pages at `volumearc.app/terms` and `/privacy` do not exist; paywall purchases violate Guideline 3.1.2 | [VOL-124](https://linear.app/mabry-ventures/issue/VOL-124) |

### 🟠 High — must fix before broad UAT

| # | Finding | Ticket |
|---|---|---|
| 3 | `RELEASE.md` claims dSYM upload to Sentry, but `Fastfile` does not do it | [VOL-133](https://linear.app/mabry-ventures/issue/VOL-133) |
| 4 | ~~Two-bot AI review gate is advisory only (not blocking merge)~~ — **audit error.** Verified 2026-05-03 that the `Require AI Code Reviews` ruleset (`enforcement: active`) requires `Codex Code Review` + `CodeRabbit Code Review` + `Build & Test` as merge-blocking status checks. The original audit relied on the absence of branch protection rules and missed that GitHub rulesets supersede branch protection. Bypass is `OrganizationAdmin` `pull_request`-scoped only. [VOL-134](https://linear.app/mabry-ventures/issue/VOL-134) closed as documentation update — see [`CONTRIBUTING.md`](CONTRIBUTING.md#required-status-checks-enforced-by-repository-ruleset). |
| 5 | No CodeQL / Trufflehog / Gitleaks; vulnerabilities + secret leaks caught only by Dependabot or manual review | [VOL-143](https://linear.app/mabry-ventures/issue/VOL-143) |
| 6 | Zero snapshot / visual regression coverage; Liquid Glass + paywall + onboarding + coach bubble can regress invisibly | [VOL-135](https://linear.app/mabry-ventures/issue/VOL-135) |
| 7 | No HealthKit unit tests with fake `HKHealthStore`; session lifecycle untested in isolation | [VOL-136](https://linear.app/mabry-ventures/issue/VOL-136) |
| 8 | No CloudKit fake transport; conflict-resolution paths are integration-tested only | [VOL-137](https://linear.app/mabry-ventures/issue/VOL-137) |
| 9 | iPad UX never audited despite "deepest Apple-ecosystem" positioning calling for it | [VOL-158](https://linear.app/mabry-ventures/issue/VOL-158) |
| 10 | StoreKit subscription edge cases (refund / family / grace / billing retry / ask-to-buy) untested — App Store reviewer stress test | [VOL-142](https://linear.app/mabry-ventures/issue/VOL-142) |
| 11 | Sentry config lacks profiling, session replay, ANR tuning, alert rules | [VOL-129](https://linear.app/mabry-ventures/issue/VOL-129) |
| 12 | Relay HMAC signing key threat model — static `Info.plist` value provides zero protection against reverse-engineering | [VOL-128](https://linear.app/mabry-ventures/issue/VOL-128) |
| 13 | UAT permission flows (HealthKit rationale, force-quit/resume, WatchConnectivity interruption) not validated | [VOL-127](https://linear.app/mabry-ventures/issue/VOL-127) |
| 14 | App Store metadata, screenshots, privacy nutrition not assembled | [VOL-125](https://linear.app/mabry-ventures/issue/VOL-125) |
| 15 | No proven end-to-end TestFlight deploy with new dSYM + What-To-Test + signed entitlements all in place | [VOL-126](https://linear.app/mabry-ventures/issue/VOL-126) |
| 16 | No nightly response-layer coach eval CI (template-layer is hermetic in CI; response-layer is manual only) | [VOL-147](https://linear.app/mabry-ventures/issue/VOL-147) |
| 17 | No in-app feedback channel; TestFlight surveys are insufficient | [VOL-146](https://linear.app/mabry-ventures/issue/VOL-146) |
| 18 | Coverage gate at 80% Core only; no UI gate, no per-target gate; project commitment is now 90%+ | [VOL-140](https://linear.app/mabry-ventures/issue/VOL-140) |
| 19 | No canonical user-journey catalog mapping every flow to a paired XCUITest | [VOL-141](https://linear.app/mabry-ventures/issue/VOL-141) |
| 20 | No HRV / sleep debt / training load consumed by coach prompt — Whoop owns "recovery drives prescription" | [VOL-145](https://linear.app/mabry-ventures/issue/VOL-145) |
| 21 | No curated programs library — Hevy / Fitbod / Caliber / Ladder all ship multi-week templates | [VOL-144](https://linear.app/mabry-ventures/issue/VOL-144) |

### 🟡 Medium — pre-launch polish

[VOL-138](https://linear.app/mabry-ventures/issue/VOL-138) Watch test target · [VOL-139](https://linear.app/mabry-ventures/issue/VOL-139) Widget XCUITest · [VOL-149](https://linear.app/mabry-ventures/issue/VOL-149) Telemetry-as-UAT · [VOL-150](https://linear.app/mabry-ventures/issue/VOL-150) TestFlight What-To-Test automation · [VOL-151](https://linear.app/mabry-ventures/issue/VOL-151) Pin toolchain versions · [VOL-152](https://linear.app/mabry-ventures/issue/VOL-152) Test parallelization + Slack + pre-commit · [VOL-154](https://linear.app/mabry-ventures/issue/VOL-154) Watch Vitals/Training Load · [VOL-156](https://linear.app/mabry-ventures/issue/VOL-156) Incident runbook + rollback · [VOL-159](https://linear.app/mabry-ventures/issue/VOL-159) Apple Intelligence integration · [VOL-130](https://linear.app/mabry-ventures/issue/VOL-130) CloudKit recovery contracts · [VOL-131](https://linear.app/mabry-ventures/issue/VOL-131) Device families decision

### 🟢 Low — housekeeping + exploratory

[VOL-153](https://linear.app/mabry-ventures/issue/VOL-153) `continue-on-error` audit · [VOL-155](https://linear.app/mabry-ventures/issue/VOL-155) Vision-based form check · [VOL-148](https://linear.app/mabry-ventures/issue/VOL-148) Public coach-quality page · [VOL-157](https://linear.app/mabry-ventures/issue/VOL-157) Doc reconciliation + SECURITY + README + Gemfile.lock + PR security checklist · [VOL-94](https://linear.app/mabry-ventures/issue/VOL-94) Real-device canary (hardware-blocked) · [VOL-104](https://linear.app/mabry-ventures/issue/VOL-104) Canary scaffold

## Competitive positioning

VolumeArc's wedge per [`PRODUCT_POSITIONING.md`](PRODUCT_POSITIONING.md) is **"deepest Apple-ecosystem strength coach."** The audit confirms the wedge is real and defensible:

**Where VolumeArc exceeds best-in-class today:**
- Day-one iOS 26 / watchOS 26 native (Liquid Glass, Foundation Models, App Intents, Live Activities)
- On-device LLM coach (privacy-first, works offline) — no competitor has this
- Streaming SSE LLM responses with Gemini Pro/Flash Lite tier routing
- Single-turn voice coach + duplex Realtime roadmap
- Eval harness for coach quality (20-fixture matrix) — no competitor publicly discloses anything like this
- Hard release-validation gate via `codesign -d --entitlements -`

**Where VolumeArc currently falls short vs Hevy / Fitbod / Caliber / Whoop:**
- No curated programs library (Hevy, Fitbod, Caliber ship multi-week templates) → [VOL-144](https://linear.app/mabry-ventures/issue/VOL-144)
- No HealthKit-driven recovery prescription (Whoop's entire product) → [VOL-145](https://linear.app/mabry-ventures/issue/VOL-145)
- No social / community feed (Hevy's defining moat) — explicit positioning non-goal per [`PRODUCT_POSITIONING.md`](PRODUCT_POSITIONING.md)
- No computer-vision form check (Tonal Smart View, FormLens, AiKYNETIX) → [VOL-155](https://linear.app/mabry-ventures/issue/VOL-155) (exploratory)
- No human-in-the-loop coach tier (Future, Caliber Personal Training) — explicit positioning non-goal
- Track record / installed base — eval harness mitigates engineering side; **make it visible to users** → [VOL-148](https://linear.app/mabry-ventures/issue/VOL-148)

## Project burndown

All 37 tickets (10 existing + 27 new) live in **[VolumeArc Production Readiness](https://linear.app/mabry-ventures/project/volumearc-production-readiness-af810008523d)**. The project is structured into four waves over 8 cycles (2026-05-03 → 2026-07-12):

- **Wave 1 — App Store submit-ready (cycles 4–5):** close the four critical-severity findings + external dependencies so a tag push can credibly land in TestFlight
- **Wave 2 — Hardening + 90% coverage (cycles 6–7):** snapshot regression, HK/CK fakes, watchOS + widget tests, StoreKit edge cases, journey documentation, iPad audit
- **Wave 3 — Killer-app differentiators (cycles 8–9):** programs library, HealthKit-depth coach prompt, in-app feedback, nightly eval CI
- **Wave 4 — Polish + exploratory (cycles 10–11+):** Vision form-check V1, Apple Watch Vitals + Training Load, Apple Intelligence, public coach-quality page

**Success at end of project:**
- Composite score ≥ 95/100
- VolumeArcCore line coverage ≥ 90% (current gate: 80%)
- VolumeArcUI line coverage ≥ 85% (no current gate)
- 100% of user journeys in [`USER_JOURNEYS.md`](USER_JOURNEYS.md) with paired XCUITest
- Zero P0/P1 audit findings open
- App Store submission gated only on Apple review

## Audit methodology

The audit was performed by Claude Code on 2026-05-01 via five parallel research agents covering:
- Repo hygiene (`.gitignore`, secrets, branch protection, file sizes, generated artifacts, dependency lockfiles)
- Documentation alignment (cross-checking PLATFORM.md / FEATURES.md / RELEASE.md claims against code)
- Test coverage (test inventory, per-subsystem coverage, eval harness, snapshot/visual regression)
- CI/CD pipeline (workflow inventory, secret management, fork isolation, deploy gates, observability, rollback)
- Agentic UAT & automation (LLM eval, accessibility, fixture seeding, telemetry-as-assertion, in-app feedback, A/B)

Plus competitive analysis covering Strong, Hevy, Fitbod, Future, Whoop, Apple Fitness+, Caliber, Tonal, Peloton Strength+, Strava, Ladder.

Full audit transcript: see Claude Code session 2026-05-01.
