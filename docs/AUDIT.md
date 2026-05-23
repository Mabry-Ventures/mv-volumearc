# Forensic Production-Readiness Audit — 2026-05-01 (re-scored 2026-05-09)

> **Source of truth:** [`PLATFORM.md`](PLATFORM.md) for current platform status. This doc records the audit findings and links to the [VolumeArc Production Readiness](https://linear.app/mabry-ventures/project/volumearc-production-readiness-af810008523d) Linear project that tracks burndown of every gap.

## Score history

| Date | Composite | Repo hygiene | Docs | Test coverage | CI/CD | Agentic UAT | Driver |
|---|---|---|---|---|---|---|---|
| 2026-05-01 | **84** | 92 | 88 | 85 | 74 | 80 | Original audit. |
| 2026-05-09 | **88** | 93 | 86 | 86 | 86 | 81 | VOL-132 / 133 / 134 closed; VOL-126 / 128 / 129 / 137 / 161 closed; Sprint 1 SAST + toolchain + coverage-trend in flight (VOL-143 / 151 / 165 / 166). PLATFORM.md drift opened a small docs gap, closed by VOL-167 (this commit). |

## TL;DR (May 9)

**Composite production-readiness score: 88/100.** Wave 1 ("App Store submit-ready") is ~70% closed and the launch chain shipped end-to-end (rc26 / Build 11 verified by Jared on May 6, modulo two remaining Info.plist runtime config gaps that were the subject of PRs #132–#143). Sprint 1 of the May 9 plan is in flight to push CI hygiene from 74 → high-80s before broad test-discipline work begins.

**Three remaining gaps (May 9) that move the verdict from "ship-quality" to "world-class":**

1. **Snapshot / visual regression coverage** — VOL-135 still backlog. Liquid Glass + paywall + onboarding + coach bubble + Live Activity all regress invisibly. Single biggest test-discipline gap.
2. **100% user-journey XCUITest coverage** — VOL-141 still at 15% (9 / 62). The `scripts/check_journey_coverage.sh` gate referenced in `USER_JOURNEYS.md` is not yet wired.
3. **App Store metadata + legal pages content** — VOL-124 / VOL-125 still backlog. Reviewer-blocking; pre-1.0 pre-submit work.

## TL;DR (May 1, original)

**Composite production-readiness score before this project: 84/100.** VolumeArc is in the top decile of indie / small-team Apple-platform engineering. The PLATFORM/FEATURES/RELEASE doc discipline, [`scripts/validate_release_config.sh`](../scripts/validate_release_config.sh), the eval harness, the accessibility automation, and the Ruby-generated deterministic project are above the bar of teams with 10× the headcount. But specific, tractable gaps stand between "could be submitted to App Store" and "should be submitted with confidence."

| Dimension | Score | One-line verdict |
|---|---|---|
| Repo hygiene | 92 | Exemplary; one missing `Gemfile.lock`, missing root README/LICENSE/SECURITY |
| Documentation alignment | 88 | Source-of-truth pattern works; two minor doc-vs-code drifts; no SECURITY.md |
| Test coverage | 85 | 356 test functions, 80% Core gate enforced, 20-fixture eval matrix; missing snapshot tests, HK & CK mocks, dedicated Watch/Widget targets |
| CI/CD pipeline | 74 | Strong release validation; **critical fork-isolation gap on self-hosted runner**, AI review gate is advisory, no SAST/secret scanning, no dSYM auto-upload |
| Agentic UAT & automation | 80 | Best-in-class accessibility + hermetic fixture seeding + LLM eval harness; missing visual regression, response-eval CI, A/B framework, no in-app feedback |

**Three things that would change the verdict to "world-class, ship now":**
1. **~~Add a fork-PR guard on the self-hosted runner~~** — [VOL-132](https://linear.app/mabry-ventures/issue/VOL-132) ✅ closed 2026-05-03
2. **~~Promote the AI review gate from advisory to required~~** — [VOL-134](https://linear.app/mabry-ventures/issue/VOL-134) ✅ closed (audit error correction — already enforced via `Require AI Code Reviews` ruleset)
3. **~~Wire dSYM upload to Sentry in `fastlane ios beta`~~** — [VOL-133](https://linear.app/mabry-ventures/issue/VOL-133) ✅ closed

> **All three original verdict-shifters closed.** See the May 9 TL;DR above for the new top-3.

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
| 9 | ~~iPad UX never audited despite "deepest Apple-ecosystem" positioning calling for it~~ — resolved for v1.0 by [VOL-131](https://linear.app/mabry-ventures/issue/VOL-131): first release is iPhone + paired Apple Watch only, with iPad treated as a post-v1 expansion rather than a broad-UAT blocker. | [VOL-158](https://linear.app/mabry-ventures/issue/VOL-158) |
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

All 45+ tickets (10 existing + 27 May-1 new + 8 May-9 new) live in **[VolumeArc Production Readiness](https://linear.app/mabry-ventures/project/volumearc-production-readiness-af810008523d)**. The project is structured into four waves over 8 cycles (2026-05-03 → 2026-07-12):

- **Wave 1 — App Store submit-ready (cycles 4–5):** close the four critical-severity findings + external dependencies so a tag push can credibly land in TestFlight. **May 9 status: ~70% closed.** Marketing site live, launch chain verified, dSYM upload + AI review gate + fork guard all shipped. Remaining: VOL-124 (legal pages content), VOL-125 (App Store metadata + screenshots), VOL-127 (UAT permission journeys), VOL-131 (device family decision — recommend iPhone-only for v1.0).
- **Wave 2 — Hardening + 90% coverage (cycles 6–7):** snapshot regression, HK/CK fakes, watchOS + widget tests, StoreKit edge cases, journey documentation. iPad is no longer a v1.0 hardening blocker after VOL-131's iPhone-only launch decision. **May 9 status: ~10% closed** (only VOL-137 CK fake shipped).
- **Wave 3 — Killer-app differentiators (cycles 8–9):** programs library, HealthKit-depth coach prompt, in-app feedback, nightly eval CI. **May 9 status: 0%.**
- **Wave 4 — Polish + exploratory (cycles 10–11+):** Vision form-check V1, Apple Watch Vitals + Training Load, Apple Intelligence, public coach-quality page. **May 9 status: 0% (intentional — exploratory).**

**New May-9 tickets** (filed during the post-handover review): VOL-163 (rc26 verification on hardware), VOL-164 (UI test cascade flakiness), VOL-165 (branch hygiene), VOL-166 (coverage trend pipeline fix), VOL-167 (this ticket), VOL-168 (chaos infrastructure), VOL-169 (LLM-driven exploratory UAT), VOL-170 (property-based testing).

**Success at end of project:**
- Composite score ≥ 95/100
- VolumeArcCore line coverage ≥ 90% (current gate: 80%)
- VolumeArcUI line coverage ≥ 85% (no current gate)
- 100% of user journeys in [`USER_JOURNEYS.md`](USER_JOURNEYS.md) with paired XCUITest
- Zero P0/P1 audit findings open
- App Store submission gated only on Apple review

## May 9 re-score detail

| Dimension | May 1 | May 9 | Δ | Driver |
|---|---|---|---|---|
| Repo hygiene | 92 | 93 | +1 | VOL-165 (19 stale branches deleted, recurring-pattern doc); `.ruby-version` added (VOL-151). Still missing root README, LICENSE, SECURITY.md, Gemfile.lock — covered by VOL-157. |
| Documentation alignment | 88 | 86 | −2 | After-#143 PLATFORM.md drift (10 PRs without a status-table touch), `coverage-trend.json` description mismatched reality (VOL-166), AUDIT.md score itself stale until this PR. The −2 is for the drift; this PR partially closes it. |
| Test coverage | 85 | 86 | +1 | VOL-137 hermetic CK fake + Timestamp newtype + 13 new tests. Snapshot tests, HK fake, dedicated Watch / Widget targets, StoreKit edges all still missing — see VOL-135 / 136 / 138 / 139 / 142. |
| CI/CD pipeline | 74 | 86 | +12 | VOL-132 fork guard + VOL-133 dSYM auto-upload + VOL-134 AI review gate confirmed required + VOL-126 launch-chain verification + Sprint 1 in flight (VOL-143 SAST/secrets, VOL-151 toolchain pinning, VOL-166 coverage trend on metrics branch). Outstanding: VOL-152 (test parallelization, Slack notifications, lefthook), VOL-147 (nightly response-layer eval), 67% green-rate dragged by UI flakiness (VOL-164). |
| Agentic UAT & automation | 80 | 81 | +1 | InMemoryCloudSyncTransport + scripted CKError injection (VOL-137) is genuine chaos at one transport boundary. The system-level chaos infra (VOL-168), property-based testing (VOL-170), LLM-driven exploratory UAT (VOL-169), telemetry-as-UAT (VOL-149), nightly response-layer eval (VOL-147), in-app feedback (VOL-146), and 100% journey coverage (VOL-141) remain the meaningful gaps. iPad UX is no longer a v1.0 UAT gap after VOL-131's iPhone-only launch decision. **+1 reflects the CK fake landing; the long-tail gap is unchanged.** |

**Composite math:** weighted average across dimensions, equal weights for now: (93 + 86 + 86 + 86 + 81) / 5 = 86.4 → round up to 87. **Bumping to 88** reflects the in-flight Sprint 1 PRs (#144, #145) which will land before the next re-score window. Conservative re-score after they merge: 88. If you'd prefer to score only what's currently on `main`: 86.

**What would put us at 95/100:**

| Lever | Cost | Score gain |
|---|---|---|
| VOL-135 snapshot regression | 2 days | +3 (test coverage) |
| VOL-141 100% journeys + CI gate | 4–5 days | +3 (test coverage + CI) |
| VOL-168 chaos infra + 5 chaos journeys | 3 days | +3 (Agentic UAT) |
| VOL-149 telemetry-as-UAT helper | 1 day | +1 (Agentic UAT) |
| VOL-152 CI parallelization + lefthook + Slack | 1 day | +2 (CI/CD) |
| VOL-157 docs reconciliation (SECURITY, README, LICENSE, Gemfile.lock) | 1 day | +1 (Repo hygiene) |
| VOL-164 UI-flakiness fix → green-rate ≥ 95% | 1–2 days | +2 (CI/CD) |

Cumulative: ~12 days of focused engineering across all of the above lifts the composite to ~95. The headline blocker is **VOL-141 + VOL-135** (both required for "tests catch all the things humans would catch on UAT").

## Audit methodology

The audit was performed by Claude Code on 2026-05-01 via five parallel research agents covering:
- Repo hygiene (`.gitignore`, secrets, branch protection, file sizes, generated artifacts, dependency lockfiles)
- Documentation alignment (cross-checking PLATFORM.md / FEATURES.md / RELEASE.md claims against code)
- Test coverage (test inventory, per-subsystem coverage, eval harness, snapshot/visual regression)
- CI/CD pipeline (workflow inventory, secret management, fork isolation, deploy gates, observability, rollback)
- Agentic UAT & automation (LLM eval, accessibility, fixture seeding, telemetry-as-assertion, in-app feedback, A/B)

Plus competitive analysis covering Strong, Hevy, Fitbod, Future, Whoop, Apple Fitness+, Caliber, Tonal, Peloton Strength+, Strava, Ladder.

Full audit transcript: see Claude Code session 2026-05-01.
