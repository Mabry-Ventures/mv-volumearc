# Marketing Site

The VolumeArc marketing site (`volumearc.app`) is a Next.js 16 app under [`marketing/`](../marketing). It serves the public landing page, legal pages (Terms, Privacy), Support, and the public coach-quality eval-trend page.

> **Status:** Scaffold landed (Wave 1 of [VolumeArc Production Readiness](https://linear.app/mabry-ventures/project/volumearc-production-readiness-af810008523d)). Custom-domain DNS, Vercel project linking, legal-counsel review of `/terms` + `/privacy`, and final copywriting are pending — see [VOL-124](https://linear.app/mabry-ventures/issue/VOL-124), [VOL-160](https://linear.app/mabry-ventures/issue/VOL-160), [VOL-161](https://linear.app/mabry-ventures/issue/VOL-161).

## Why this lives in the same repo

The legal pages (`/terms`, `/privacy`) are hard-linked from the iOS paywall via [`App/LegalLinks.swift`](../App/LegalLinks.swift). Keeping them in the same repo means:
- Any change to `LegalLinks` URLs and the marketing pages they point at lands in the same PR
- The CI gate that prevents placeholder URLs from shipping in the iOS app (VOL-124 contract test) can verify the marketing pages exist as a CI step
- Subscription pricing, feature claims, and coach-quality evidence stay in lockstep with the app's actual behavior — `docs/FEATURES.md` is the source of truth and the marketing site reflects it

The trade-off: every iOS engineer needs Node 22 / npm to build the marketing site locally. We accept that — the marketing site builds in 30s and most engineers won't touch it day-to-day.

## Stack

| Layer | Choice | Why |
|---|---|---|
| Framework | Next.js 16 (App Router, RSC) | Static-first marketing, can host the dynamic `/quality` eval-trend page later |
| Styling | Tailwind CSS v4 | Matches the design discipline in the iOS app's design tokens; required by Tailwind Plus assets |
| Components | Headless UI + Framer Motion + shadcn/ui (with Shadcnblocks registry) | Mix of Tailwind Plus templates and on-demand premium blocks |
| Hosting | Vercel | Native Next.js, GitHub integration, preview URLs per PR, edge runtime where needed |
| Region | `sfo1` (set in `vercel.json`) | Matches the team's primary timezone |

## Page tree

```
marketing/src/app/
├── layout.tsx                      Root metadata + fonts
├── (main)/
│   ├── layout.tsx                  Header + Footer chrome (delegates to components/Layout.tsx)
│   ├── page.tsx                    Landing — Hero, PrimaryFeatures, SecondaryFeatures, CallToAction, Pricing, FAQs
│   ├── terms/page.tsx              Terms of Service (DRAFT — VOL-124)
│   ├── privacy/page.tsx            Privacy Policy (DRAFT — VOL-124)
│   ├── support/page.tsx            Contact, common issues, press
│   └── quality/page.tsx            Public coach-quality eval-trend (scaffold — VOL-148)
└── not-found.tsx                   Fallback 404
```

## Component inventory (after VolumeArc adaptation)

Inherited from Pocket and customized for VolumeArc:

| Component | Purpose | Notes |
|---|---|---|
| `Hero.tsx` | Headline + subhead + CTAs + phone-frame demo + platform chips | "Built day-one on Apple's newest platform stack" chips replace stock-press logos |
| `PrimaryFeatures.tsx` | 3-up tabbed feature panels with phone-frame in-app mockups | AI coach / Watch parity / Readiness — replaced Pocket's stock-trading mockups |
| `SecondaryFeatures.tsx` | 6-card feature grid | Live Activities, Watch parity, Privacy-first AI, CloudKit, App Intents, Liquid Glass |
| `Pricing.tsx` | Free vs Pro plan toggle | StoreKit product IDs from `docs/PLATFORM.md`; Monthly/Annually toggle |
| `Faqs.tsx` | 9-item FAQ in 3 columns | Privacy, AI quality, Watch, Premium, platform decisions |
| `CallToAction.tsx` | Centered CTA with App Store link | Above pricing/FAQs |
| `AppDemo.tsx` | Phone-frame chart + recent-sessions list | 30-day readiness trend chart (replaced Pocket's stock chart) |
| `Header.tsx` / `Footer.tsx` / `NavLinks.tsx` / `Logo.tsx` | Chrome | Footer cross-links Product / Company / Legal sections |

Removed from the Pocket template:
- `(auth)/` route group — no web auth, app is App Store-only
- `AuthLayout.tsx` / `Fields.tsx` — auth UI primitives
- `Reviews.tsx` — pre-launch we don't have real reviews; remove the section rather than ship fake ones
- `StockLogos.tsx` — Pocket's stock-trading logo set, no longer referenced

## Deployment flow

1. **Vercel project** is provisioned for `mv-volumearc` (root: `marketing/`). Production branch: `main`.
2. **Custom domain** `volumearc.app` is configured in Vercel and DNS-pointed via the registrar (apex + www).
3. **Environment variables** set in the Vercel project:
   - `SHADCNBLOCKS_API_KEY` (mirrors the GitHub secret of the same name)
   - `NEXT_PUBLIC_SITE_URL=https://volumearc.app` (production), preview branches inherit Vercel's auto value
4. **Push to `main`** → Vercel builds and deploys to production within ~1 minute.
5. **Open a PR** → Vercel posts a preview URL to the PR.

The CI gate at [`.github/workflows/marketing.yml`](../.github/workflows/marketing.yml) runs `npm ci && npm run lint && npm run check:legal && npm run build` on every PR touching `marketing/**`.

**Where it runs (VOL-213 — updated 2026-05-18):** the workflow targets the privileged `mv-volumearc-runner` self-hosted macOS host alongside the Apple toolchain, not `ubuntu-latest`. The previous docs claim of "ubuntu-latest, fork-safe via `pull_request` semantics" was wrong — secret theft isn't the only attack surface, and `npm` postinstall scripts on the self-hosted runner have access to the same Keychain, signing identity, and DerivedData as the Apple builds. VOL-193 (closed 2026-05-18) added the explicit fork-PR guard: same-repo PRs and pushes to `main` run as normal, fork PRs are skipped. Fork contributors should ask a maintainer to push their branch into the upstream so CI can execute against trusted code. `SHADCNBLOCKS_API_KEY` was also removed from the PR job env in VOL-193 — it's only needed at install-time, not for `next build`.

**Typecheck (VOL-213 — updated 2026-05-18):** `next build` runs the TypeScript compiler as part of the production build step, so a separate `tsc --noEmit` step would be redundant (and fails on a fresh checkout because `next build` is what generates `next-env.d.ts`). Local contributors run `npm run typecheck` after one initial build. The previous docs claim that CI ran `npm run typecheck` separately was wrong.

**Legal-page check (VOL-195 — added 2026-05-18):** `npm run check:legal` runs `marketing/scripts/check-legal-pages.mjs` against `/terms` and `/privacy` to fail the build if either page regresses to a placeholder state (`TBD`, `pending legal review`, `placeholder structure`, `lorem ipsum`, `<strong>Draft</strong>` banner). App Review Guideline 3.1.2 requires final legal copy at submission.

## Pulling Shadcnblocks blocks

The Shadcnblocks registry is mounted in [`marketing/components.json`](../marketing/components.json) under the `@shadcnblocks` namespace. To install a block:

```bash
cd marketing
cp .env.example .env.local
# Fill SHADCNBLOCKS_API_KEY from the approved credential source
SHADCNBLOCKS_API_KEY=$(grep SHADCNBLOCKS_API_KEY .env.local | cut -d= -f2) \
  npx shadcn@latest add @shadcnblocks/<block-name>
```

Reference: [`mv-design/docs/shadcnblocks.md`](../../mv-design/docs/shadcnblocks.md). The same `SHADCNBLOCKS_API_KEY` GitHub secret used in `mv-design` should be mirrored in `mv-volumearc` for CI/Vercel installs.

## Content ownership

| Section | Owner | Updates when |
|---|---|---|
| Hero copy + landing-page positioning | Founder + Marketing | `docs/PRODUCT_POSITIONING.md` changes |
| Feature copy | Marketing + Engineering | `docs/FEATURES.md` row flips status |
| Pricing | Founder | App Store Connect StoreKit products change |
| FAQs | Support + Engineering | New common issue surfaces in TestFlight feedback |
| `/quality` page | Engineering | Auto-published from `docs/coach-eval-trend.json` (VOL-148) |
| `/terms` + `/privacy` | Legal counsel | After every material data-flow change in the app |

## Tooling notes (Next 16 + ESLint 9)

The Tailwind Plus Pocket template ships with the legacy ESLint 8 + `next lint` setup that Next.js 16 has deprecated. After copy-in we adapted:

- **`marketing/eslint.config.mjs`** — native ESLint 9 flat config that imports `@next/eslint-plugin-next` directly and layers `typescript-eslint` recommended rules. Replaces the old `.eslintrc.json`.
- **`package.json` scripts** — `"lint": "eslint ."` (Next 16 removed `next lint` as a binary command).
- **CI step** — `marketing.yml` runs lint then build only; the standalone `npm run typecheck` is omitted because `next build` runs the TS compiler and `tsc --noEmit` requires `next-env.d.ts` (a build artifact).
- **`favicon.ico`** — Pocket's bundled favicon trips Next 16's Turbopack ICO decoder ("ICO image entry has too many color planes"). It was removed; a real favicon export from `App/Assets.xcassets/AppIcon.appiconset/` is part of [VOL-161](https://linear.app/mabry-ventures/issue/VOL-161).

## Cross-references

| The marketing site touches | Single source of truth |
|---|---|
| `LegalLinks` Swift wrapper | [`App/LegalLinks.swift`](../App/LegalLinks.swift) — keep `/terms` and `/privacy` URL paths in sync |
| Pricing / StoreKit IDs | [`docs/PLATFORM.md`](PLATFORM.md) Subscriptions section |
| Feature claims | [`docs/FEATURES.md`](FEATURES.md) — canonical per-feature status |
| Coach quality narrative | [`docs/COACH_EVALS.md`](COACH_EVALS.md) — eval harness mechanics |
| Privacy claims | [`App/VolumeArcSentryPIIScrubber.swift`](../App/VolumeArcSentryPIIScrubber.swift) — code is the truth on what's redacted |
| Privacy manifest | [`App/PrivacyInfo.xcprivacy`](../App) and per-target privacy manifests |

If the marketing site ever claims something the app doesn't actually do, that's a bug — the app and the docs are the source of truth, the marketing site reflects them.
