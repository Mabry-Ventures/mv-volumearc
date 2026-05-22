#!/usr/bin/env node
// VOL-195 / VOL-C-003 audit follow-up: assert that /terms and /privacy
// don't carry placeholder language. App Review Guideline 3.1.2 requires
// final legal copy at submission. If a future PR accidentally reverts
// to a draft / TBD / "pending legal review" state, this check fails the
// marketing CI build before Vercel publishes the regression.
//
// Wired into `marketing/package.json` as `npm run check:legal`, which
// `.github/workflows/marketing.yml` runs alongside `lint` and `build`.

import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const marketingRoot = resolve(here, '..')

const targets = [
  'src/app/(main)/terms/page.tsx',
  'src/app/(main)/privacy/page.tsx',
]

// Case-insensitive. The token list reflects the explicit set the
// 2026-05-18 audit (F-C-003) called out, plus a couple of common
// near-equivalents that would also indicate a half-finished page.
const placeholderTokens = [
  'TBD',
  'pending legal review',
  'placeholder structure',
  'lorem ipsum',
]

// We allow the literal word "Draft" inside the file ONLY when it
// appears as part of a documentation comment, because some lawful
// uses ("we drafted this on…") would otherwise false-positive. The
// banner we removed used the standalone token <strong>Draft.</strong>,
// so we look for that exact pattern instead.
const draftBannerPattern = /<strong>\s*Draft[.!]?\s*<\/strong>/i

// VOL-124: positive-content assertions. Placeholder-absence (above)
// catches a page that reverted to a stub, but NOT a page that silently
// dropped a required disclosure (e.g. someone deletes the GDPR section
// in an unrelated refactor). App Review Guideline 3.1.2 + GDPR/CCPA
// require these topics to be present, so we assert each one. Patterns
// are deliberately loose (topic keyword, case-insensitive) so ordinary
// copy-editing doesn't trip them — we're guarding presence of a topic,
// not exact wording.
const requiredContent = {
  'src/app/(main)/privacy/page.tsx': [
    { label: 'HealthKit disclosure', pattern: /HealthKit/i },
    { label: 'CloudKit disclosure', pattern: /CloudKit/i },
    { label: 'AI relay / Gemini disclosure', pattern: /Gemini|relay\.volumearc/i },
    { label: 'Sentry crash-reporting disclosure', pattern: /Sentry/i },
    { label: 'GDPR rights', pattern: /GDPR/i },
    { label: 'CCPA rights', pattern: /CCPA/i },
    { label: 'deletion / data-rights flow', pattern: /delet/i },
    { label: 'children / under-13 notice', pattern: /under 13|children/i },
  ],
  'src/app/(main)/terms/page.tsx': [
    { label: 'auto-renewal disclosure', pattern: /auto-?renew/i },
    { label: 'refund policy', pattern: /refund/i },
    { label: 'Apple Guideline 3.1.2 reference', pattern: /3\.1\.2/ },
    { label: 'governing law', pattern: /governing law|Tennessee/i },
    { label: 'Apple third-party-beneficiary clause', pattern: /third-party beneficiar/i },
  ],
}

// VOL-124: the routed contact domain is volumearc.COM (Fastmail
// catch-all). The legal pages previously used @volumearc.app, which
// has no mailbox — a GDPR/CCPA request emailed there would bounce.
// Forbid the email form specifically (not the bare domain, which
// legitimately appears as relay.volumearc.app / the site URL).
const forbiddenEmailDomain = /@volumearc\.app\b/i

let failures = 0

for (const relative of targets) {
  const absolute = resolve(marketingRoot, relative)
  let body
  try {
    body = await readFile(absolute, 'utf8')
  } catch (error) {
    console.error(`check-legal-pages: cannot read ${absolute}: ${error.message}`)
    failures++
    continue
  }

  for (const token of placeholderTokens) {
    const pattern = new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i')
    if (pattern.test(body)) {
      console.error(
        `check-legal-pages: FAIL — ${relative} still contains "${token}". ` +
        `App Review Guideline 3.1.2 requires final legal copy at submission. ` +
        `See VOL-195 / 2026-05-18 audit F-C-003.`,
      )
      failures++
    }
  }

  if (draftBannerPattern.test(body)) {
    console.error(
      `check-legal-pages: FAIL — ${relative} still has the "Draft" banner ` +
      `(<strong>Draft</strong>). Remove it; the page is now final copy. ` +
      `See VOL-195.`,
    )
    failures++
  }

  for (const { label, pattern } of requiredContent[relative] ?? []) {
    if (!pattern.test(body)) {
      console.error(
        `check-legal-pages: FAIL — ${relative} is missing the ${label} ` +
        `(expected to match ${pattern}). Required by App Review 3.1.2 / ` +
        `GDPR / CCPA. See VOL-124.`,
      )
      failures++
    }
  }

  if (forbiddenEmailDomain.test(body)) {
    console.error(
      `check-legal-pages: FAIL — ${relative} references an @volumearc.app ` +
      `email. Contact mail routes via @volumearc.com (Fastmail catch-all); ` +
      `@volumearc.app has no mailbox and would bounce. See VOL-124.`,
    )
    failures++
  }
}

if (failures > 0) {
  console.error(`check-legal-pages: ${failures} placeholder failure(s) detected.`)
  process.exit(1)
}

console.log('check-legal-pages: /terms and /privacy contain no placeholder tokens.')
