# VolumeArc Marketing Site

Public marketing site for VolumeArc, deployed at [volumearc.app](https://volumearc.app).

Adapted from the [Tailwind Plus Pocket](https://tailwindui.com/templates/pocket) mobile-app marketing template. Design assets and shared design-system docs live in the sibling [`mv-design`](https://github.com/Mabry-Ventures/mv-design) repository.

## Stack

- **Next.js 16** (App Router, React 19, RSC)
- **Tailwind CSS v4**
- **Headless UI** + **Framer Motion** for interactive components
- **shadcn/ui** registry with the [Shadcnblocks](https://shadcnblocks.com) extension mounted (requires `SHADCNBLOCKS_API_KEY`)
- **TypeScript** strict mode
- **Vercel** for hosting (see [`vercel.json`](vercel.json))

## Local development

```bash
cd marketing
npm install
cp .env.example .env.local       # fill SHADCNBLOCKS_API_KEY if pulling new blocks
npm run dev                       # http://localhost:3000
```

Lint + type-check + production build smoke:

```bash
npm run lint
npm run typecheck
npm run build
```

## Page tree

```
/                       Landing — Hero, PrimaryFeatures, SecondaryFeatures, CallToAction, Pricing, FAQs
/terms                  Terms of Service (DRAFT — pending legal review, VOL-124)
/privacy                Privacy Policy (DRAFT — pending legal review, VOL-124)
/support                Support, Resend-backed contact form, common issues, press
/quality                Public coach-quality eval-trend (scaffold — VOL-148)
```

The `LegalLinks` Swift wrapper in the iOS app (`App/LegalLinks.swift`) routes to `/terms` and `/privacy` on this site. Keep both in sync.

## Pulling Shadcnblocks components

Per [`mv-design/docs/shadcnblocks.md`](https://github.com/Mabry-Ventures/mv-design/blob/main/docs/shadcnblocks.md), the registry is configured in [`components.json`](components.json). To install a block:

```bash
SHADCNBLOCKS_API_KEY=$(grep SHADCNBLOCKS_API_KEY .env.local | cut -d= -f2) \
  npx shadcn@latest add @shadcnblocks/<block-name>
```

The API key is never written into `components.json` — it's interpolated at install time from the env var. In CI / Vercel, the `SHADCNBLOCKS_API_KEY` GitHub repository secret (mirror of the one in `mv-design`) provides the same value.

## Tailwind Plus templates

Mabry Ventures has commercial licenses for the full Tailwind Plus catalog under [`mv-design/Design Assets/`](https://github.com/Mabry-Ventures/mv-design/tree/main/Design%20Assets). When refreshing layout patterns, copy from a template (e.g., `tailwind-plus-pocket/pocket-ts/src/components/`) into this repo and adapt — do not link directly. See [`mv-design/docs/tailwind-plus.md`](https://github.com/Mabry-Ventures/mv-design/blob/main/docs/tailwind-plus.md) for the canonical workflow.

## Deployment

Vercel auto-deploys on push:

- **Preview**: every PR opens a preview URL
- **Production**: pushes to `main` deploy to `volumearc.app`

The build command and output directory are pinned in [`vercel.json`](vercel.json). Vercel project environment variables:

| Variable | Production | Preview | Notes |
|---|---|---|---|
| `SHADCNBLOCKS_API_KEY` | required | required | Same value as in `mv-design` |
| `NEXT_PUBLIC_SITE_URL` | `https://volumearc.app` | (auto) | |
| `RESEND_API_KEY` | required | required | Server-only; powers `/api/support` |
| `RESEND_FROM_EMAIL` | `VolumeArc <noreply@volumearc.app>` | same or verified preview sender | Must be a Resend-verified domain |
| `SUPPORT_EMAIL_TO` | `support@mabryventures.com` | same | Destination for support form submissions |

CI build smoke (no deploy) runs in [`.github/workflows/marketing.yml`](../.github/workflows/marketing.yml).

## Content ownership

| Section | Owner | Source of truth |
|---|---|---|
| Hero copy | Marketing + Founder | This repo + `docs/PRODUCT_POSITIONING.md` |
| Feature descriptions | Engineering + Marketing | `docs/FEATURES.md` is canonical for feature status |
| Pricing | Founder | App Store Connect StoreKit products |
| FAQs | Support + Engineering | This repo |
| Coach quality (`/quality`) | Engineering | `docs/coach-eval-trend.json` (auto-published, VOL-148) |
| Terms / Privacy | Legal counsel | This repo (after legal review, VOL-124) |

When a feature ships or its scope changes, update `docs/FEATURES.md` first; this site reflects the canonical doc.

## Related docs

- Marketing-site architecture & deploy flow: [`docs/MARKETING.md`](../docs/MARKETING.md)
- Forensic audit + project burndown: [`docs/AUDIT.md`](../docs/AUDIT.md)
- Linear: [VolumeArc Production Readiness](https://linear.app/mabry-ventures/project/volumearc-production-readiness-af810008523d)

## License

The Tailwind Plus Pocket template this site was adapted from is licensed under the [Tailwind Plus license](https://tailwindcss.com/plus/license). VolumeArc-specific code, copy, and design adaptations are © Mabry Ventures, LLC.
