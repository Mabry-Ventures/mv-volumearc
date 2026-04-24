# VolumeArc — Product Positioning

Owner: Jared Mabry · Status: Decision · Last updated: 2026-04-22 · Source: Codex audit 2026-04-23, VOL-102

## TL;DR

**VolumeArc's wedge is "the deepest Apple-ecosystem strength coach."** We lean into what we've actually built — HealthKit-driven readiness, first-class watchOS, Live Activities, CloudKit cross-device sync, Liquid Glass design — rather than chase breadth (Fitbod's 1000+ exercise catalog) or marketplace plays (TrainHeroic, Caliber) we can't ship pre-launch. AI-personalized progression is a feature, not a positioning; we treat it as a capability inside the Apple-ecosystem wedge.

This is a decision-gate ticket (VOL-102), not a work order. Downstream tactical tickets are listed at the bottom.

## The competitive landscape we're entering

| Competitor | Their wedge | What they have that we don't |
|---|---|---|
| Fitbod | Algorithmic plan generator w/ massive exercise library | ~1000 exercises, video demos, established user base |
| Hevy | Social + shared routines | Public feed, routine sharing, 6M+ users |
| Strong | Simple, ubiquitous tracker | Broad reach, cross-platform, clean UX |
| TrainHeroic | Coach → athlete marketplace | Supply side of certified coaches |
| Ladder / Caliber | Human-coach subscription tier | Stripe for coaches, live programming |
| Future | AI + wearable-driven coaching (Apple Watch focus) | ~direct competitor — real human coaches + generative progression |

**What every serious competitor ships that we don't:** video demos, 100+ exercise catalog, social proof surface, proven freemium funnel, a human in the loop somewhere (either marketplace coaches or in-house).

**What we ship that most competitors don't:**
- Native Apple watch + phone with **parity**, not a shrunken companion
- Live Activities + Dynamic Island for active workouts
- CloudKit cross-device sync without user-visible account setup
- Readiness derived from actual HealthKit (HRV, sleep, recovery) feeding a real progression engine
- Liquid Glass (iOS 26) design language adoption on day one
- Private-by-default data (SwiftData + CloudKit, no third-party telemetry of training data)

## The three candidate positionings

### Option A — "Deepest Apple-ecosystem strength coach" (recommended)

The pitch: *"If you live inside the Apple ecosystem, VolumeArc is the only strength coach that actually uses it. Your watch leads the session. Your readiness comes from your real recovery data. Your history follows you across every Apple device."*

**Why it wins:**
- We've already built 80% of the rails. HealthKit, WatchConnectivity, CloudKit, Widgets, Live Activities, Watch-as-primary-surface are all shipped or in flight. The sunk cost matches the positioning.
- It's structurally defensible. Cross-platform competitors (Fitbod, Hevy, Strong) cannot catch up without abandoning Android / Web, which they won't.
- It's narrower than "fitness tracker" but big enough to be a business: the Apple Watch strength-training audience is real and growing (c.f. `WorkoutKit.StrengthTrainingActivityType` being a first-class Apple API).
- Our weaknesses (small exercise library, no video) are survivable: a focused 100-exercise catalog with great HealthKit integration beats a 1000-exercise catalog with generic UX, for this audience.

**What we'd need to still ship to credibly hold this position:**
- Exercise catalog: scale from ~11 to 100+ (not 1000 — curated, not exhaustive). Tracked in a new VOL ticket (see downstream below).
- HealthKit depth: move beyond the minimal reads to actually consume HRV trend, sleep debt, training load from Apple's derived metrics. Partially in flight via Readiness but needs pre-launch polish.
- Cross-device UX proof: every feature needs to feel as good on iPad as on Watch. Currently untested on iPad.
- A "what Apple did for you" moment: surface real HealthKit-derived insights on the home tab. The coach's voice needs to reference data only Apple can give us.

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
4. **Marketing site copy** (volumearc.app) — headline should be about the Apple ecosystem, not about AI. AI is mentioned as a capability in the body.
5. **We do NOT add**: Android / Web / a YouTube channel / a coach-signup flow. If these become roadmap items post-launch, it's because Option A's numbers forced a pivot, and we re-run this decision.

## Downstream work the decision unlocks (file as separate tickets)

| New ticket | Scope | Priority |
|---|---|---|
| VOL-103 (TBD) | Scale exercise catalog 11 → 100+ (curated, not exhaustive). Include HealthKit-supported movements first. | P1 pre-launch |
| VOL-104 (TBD) | HealthKit depth pass — consume HRV trend, sleep debt, training load in readiness card UI | P1 pre-launch |
| VOL-105 (TBD) | iPad UX audit — every feature validated on iPad 11" and iPad Pro 13" | P2 pre-launch |
| VOL-106 (TBD) | App Store copy + screenshots refresh aligned to Option A positioning | P1 pre-launch |
| VOL-107 (TBD) | Marketing site copy (volumearc.app) — headline/subhead/feature tiles aligned to Option A | P2 pre-launch |
| VOL-108 (TBD) | Post-launch decision gate — revisit Options B/C after first 90 days of usage data | P4 post-launch |

Tickets above are placeholders; file the real Linear issues when VOL-102 closes.

## Explicit non-goals for this doc

- Not a marketing plan. Marketing plan depends on this but is downstream.
- Not a pricing decision. Pricing is VOL-91 + its follow-ups.
- Not an engineering scope doc. Engineering scope is whatever VOL-103..107 turn into.
- Not an answer to "what do we build post-launch." That's VOL-108, after real data.

## Referenced audit findings

- Codex audit 2026-04-23, "Competitive Position" section — the prompt for this doc
- VOL-91 — premium gating (pricing ties to positioning)
- VOL-1 through VOL-53 (Go-Live Readiness) — the rails we lean on for Option A
