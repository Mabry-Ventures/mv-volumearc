# VolumeArc — Product Positioning

Owner: Jared Mabry · Status: Release decision · Last updated: 2026-06-06 · Source: VolumeArc Release audit, VOL-270 through VOL-276

## TL;DR

**VolumeArc's wedge is "the deepest Apple-ecosystem strength coach."** We lean into what the product is built to do well: HealthKit-informed readiness, Watch-first strength execution, Live Activities, CloudKit continuity, widgets, Liquid Glass design, curated programs, and a coach layer that improves prescriptions without making the product feel like an AI demo.

The release bar is now higher than the original positioning decision. VolumeArc must not go to paid public launch until the [VolumeArc Release](https://linear.app/mabry-ventures/initiative/volumearc-release-68a38ea2d762) scorecard is 9.5+ in every category, every P0-P4 finding is closed or explicitly accepted, and the product has proof for speed, parity, safety, UAT, and paid conversion.

## The competitive landscape we're entering

| Competitor | Their wedge | What they have that VolumeArc must answer |
|---|---|---|
| Fitbod | Algorithmic strength planner with broad exercise media | 1000+ exercises, videos, adaptive AI plan claims, large installed base, strong App Store proof |
| WHOOP | Recovery, strain, and readiness intelligence | Wearable recovery moat, muscular-load storytelling, AI exercise linking after lifting |
| Future | Adaptive coaching around Apple Watch and HealthKit | Real-time/audio coaching claims, human-coach expectations, polished wearable-driven training narrative |
| Hevy / Strong | Fast logging and routine reuse | Very low-friction logging, known UX patterns, social/routine proof |
| TrainHeroic / Caliber | Coach-led programming | Human coach trust, plan marketplace/programming depth |

**What serious competitors still use against us:** exercise/media breadth, social proof, human coaching, long user history, and validated conversion funnels.

**What we ship that most competitors don't:**
- Native Apple watch + phone with **parity**, not a shrunken companion
- Live Activities + Dynamic Island for active workouts
- CloudKit continuity across iPhone and Apple Watch, with Sign in with Apple available to seed profile identity
- Readiness derived from actual HealthKit (HRV, sleep, recovery) feeding a real progression engine
- Liquid Glass (iOS 26) design language adoption on day one
- Private-by-default data (SwiftData + CloudKit, no third-party telemetry of training data)
- Publicly testable coach-quality infrastructure once the latest eval trend is green

## The three candidate positionings

### Option A — "Deepest Apple-ecosystem strength coach" (recommended)

The pitch: *"If you live inside the Apple ecosystem, VolumeArc is the only strength coach that actually uses it. Your watch leads the session. Your readiness comes from your real recovery data. Your history follows you across iPhone and Apple Watch."*

**Why it wins:**
- The architecture matches the promise. HealthKit, WatchConnectivity, CloudKit, widgets, Live Activities, Watch-as-primary-surface, curated programs, and readiness-aware coaching are all in the product.
- It's structurally defensible. Cross-platform competitors (Fitbod, Hevy, Strong) cannot catch up without abandoning Android / Web, which they won't.
- It's narrower than "fitness tracker" but big enough to be a business: the Apple Watch strength-training audience is real and growing (c.f. `WorkoutKit.StrengthTrainingActivityType` being a first-class Apple API).
- Our weaknesses are survivable if we are honest about them: a focused curated catalog with excellent readiness, Watch flow, speed, and coaching beats a generic thousand-exercise database for the athlete who lives on iPhone and Apple Watch.

**What still has to be proven before we can credibly hold this position:**
- Full Claude Design parity across Today, Workouts, Coach, Signals, Profile, co-design, watch previews, widgets, onboarding, paywall, settings, empty states, and errors.
- Physical iPhone plus paired Apple Watch UAT for HealthKit, WatchConnectivity, workout execution, offline/reconnect, force-quit/resume, notifications, TestFlight, purchases, and permission-deny paths.
- Performance budgets with a real green trend. The app must feel instant in cold launch, tab switch, workout start, set log, rest transition, watch update, and coach fallback.
- Readiness must visibly change the workout. The "what Apple did for you" moment belongs in the first-run and Today experience, not buried in chat.
- Coach quality must be green and current: eval trend, red-team safety, privacy redaction, model routing, fallbacks, latency, and cost.

**What we do NOT build for this positioning:**
- Video demos (or if we do, they're iOS-native AVKit + maybe StyleTransfer overlays, not YouTube embeds)
- Marketplace / social surfaces (see Options B & C)
- Cross-platform clients (Android, Web). Ever.

### Option B — "AI-personalized progression"

The pitch: *"Other apps pick your weights from a table. VolumeArc reads your history, your readiness, and your recovery and picks the weight your body is ready for today."*

**Why we shouldn't pick this as our positioning (even though it's a capability we have):**
- Fitbod already claims this and has 1000x the data to actually do it well.
- LLM-based progression is quickly going to commodity — Gemini 3.1, GPT-5, and in-device Foundation Models will all do this within a year. Our Cloudflare-relay'd Gemini will not be defensible against Fitbod-with-OpenAI in 12 months.
- Marketing "AI" to a strength-training audience is a negative signal to the serious portion. The people who pay for Strong / Hevy / Future want *precision*, not *magic*.
- "AI" as a category is being devalued rapidly (AI washing). Leaning the brand on it dates us.

**Keep it as a feature inside Option A.** The progression engine is still a major differentiator *tactically*, but it's not the banner we fly under.

### Option C — "Coach-curated plans / marketplace"

The pitch: *"Real human coaches write the programs. VolumeArc runs them."*

**Why we can't pick this pre-launch:**
- Two-sided marketplaces require supply (coaches) before demand (athletes). We have zero coaches signed up.
- Legal surface: coach-certification liability, 1099 contractor relationships, revenue share, dispute handling. Easily 6+ months of non-product work.
- TrainHeroic, Ladder, and Caliber have 5+ year head starts and deep coaching networks.
- The mandatory human-in-the-loop is fundamentally at odds with the per-unit economics that make a $10/mo consumer app work.

**Revisit post-launch if Option A's numbers plateau.** A future coach-plan-library expansion (not marketplace — curated authored plans like Strong's program catalog) might be the right second act. Not the first.

## The decision

**We go with Option A.** All pre-launch engineering, marketing, App Store copy, and product decisions should ladder up to "deepest Apple-ecosystem strength coach."

### What this changes, concretely

1. **App Store screenshots** should lead with Watch + Widget + Live Activity + Readiness card — not the logger. The logger is table stakes; what Apple gives us isn't.
2. **Onboarding copy** should mention HealthKit by name and ask for it in the first 60 seconds. Users who say no to HealthKit are not our ICP — that's fine, they can still use the app, but we don't bend the product for them.
3. **Premium tier naming** (currently "VolumeArc Pro" in VOL-91) should imply depth, not breadth. "Pro" works. "VolumeArc Elite" doesn't.
4. **Marketing site copy** (volumearc.app) should be about the Apple ecosystem, speed, readiness, and Watch execution. AI is mentioned as a capability in the body after quality proof is green.
5. **We do NOT add**: Android / Web / a YouTube channel / a coach-signup flow. If these become roadmap items post-launch, it's because Option A's numbers forced a pivot, and we re-run this decision.

## Active release work

| Ticket | Scope | Priority |
|---|---|---|
| [VOL-269](https://linear.app/mabry-ventures/issue/VOL-269) | Publish post-fix green coach response eval trends before any paid-launch coach-quality claim. | P0 launch gate |
| [VOL-270](https://linear.app/mabry-ventures/issue/VOL-270) | Add Claude Design full-surface visual parity gate. | P1 launch gate |
| [VOL-271](https://linear.app/mabry-ventures/issue/VOL-271) | Raise v1 journey coverage to 100% and complete paired Watch UAT. | P1 launch gate |
| [VOL-273](https://linear.app/mabry-ventures/issue/VOL-273) | Finalize pricing, legal, and marketing copy status. | P2 launch gate |
| [VOL-274](https://linear.app/mabry-ventures/issue/VOL-274) | Pin production AI model routing and deprecation policy. | P2 launch gate |
| [VOL-275](https://linear.app/mabry-ventures/issue/VOL-275) | Prove co-design planning persistence/scheduling. | P2 launch gate |
| [VOL-276](https://linear.app/mabry-ventures/issue/VOL-276) | Enforce release hygiene: no emojis, no stale project names, no unsupported launch claims. | P1 launch gate |

## Product-voice rule: AI strength programming coach (2026-06-11, binding)

Decided by Jared during the 2026-06-11 GA replan, after WWDC26 (Workout Buddy free and phone-less in watchOS 27; Apple's Health coach delayed to 27.1-27.4) and Google's Fitbit relaunch (Gemini Health Coach at $9.99/mo, free with Google AI Pro/Ultra, available on iOS):

**VolumeArc is "the AI strength programming coach" — the prescriptive strength specialist.** Every product surface sells programming depth: progressive overload, readiness-driven set/rep/load prescriptions, autoregulation, recovery-timed deloads, and equipment-aware substitution. Premium is programming depth, never "AI access."

Banned framings on product surfaces (app, watch, widgets, App Store metadata, selected marketing components) — enforced by `scripts/check_release_hygiene.sh` product-voice patterns so drift fails CI:

- "AI coach" / "AI-powered strength" (pre-existing rules)
- "fitness coach", "wellness coach", "personal trainer" (added with this rule — generic framings that collide head-on with free or bundled platform coaches)

Allowed: "strength programming coach", "strength coach" qualified by prescriptive language, and technical/legal/privacy disclosures that must name AI processing factually.

## Explicit non-goals for this doc

- Not a marketing plan. Marketing plan depends on this but is downstream.
- Not a pricing decision. Pricing is VOL-91 + its follow-ups.
- Not an engineering scope doc. Engineering scope is whatever VOL-103..107 turn into.
- Not an answer to "what do we build post-launch." Revisit Options B and C after paid-launch telemetry, support tickets, conversion data, and retention cohorts are real.

## Referenced audit findings

- 2026-06-06 VolumeArc Release audit in [`AUDIT.md`](AUDIT.md#2026-06-06-claude-design--launch-readiness-audit)
- VOL-91 — premium gating (pricing ties to positioning)
- [VOL-267](https://linear.app/mabry-ventures/issue/VOL-267) through [VOL-276](https://linear.app/mabry-ventures/issue/VOL-276) — active release blockers and launch gates
