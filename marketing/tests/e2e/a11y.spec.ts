import AxeBuilder from '@axe-core/playwright'
import { expect, test, type Page } from '@playwright/test'

const routes = [
  { path: '/', h1: 'Your strength coach, built into your Apple Watch.' },
  { path: '/privacy', h1: 'Privacy Policy' },
  { path: '/terms', h1: 'Terms of Service' },
  { path: '/support', h1: 'Get help with VolumeArc' },
  { path: '/quality', h1: 'Coach quality, in the open.' },
] as const

const seriousOrCritical = new Set(['serious', 'critical'])

/// VOL-228 (closed): the three rules that previously appeared in
/// the introduction allow-list (`aria-required-children`,
/// `aria-required-parent`, `color-contrast`) all had a single
/// underlying root cause fixed in the same PR:
///
///   * Headless UI `<Tab>` wasn't a direct child of `<TabList>` in
///     `PrimaryFeatures.tsx` (Tab nested inside `<div><h3><Tab>`),
///     so axe flagged both `aria-required-children` on the TabList
///     and `aria-required-parent` on the inner Tab. Restructuring
///     to `<Tab as="div">` as the direct TabList child fixed both.
///   * `bg-sunrise-500` (#F26B33) with white text only hit a
///     3.27:1 contrast ratio — below WCAG AA 4.5:1 for
///     `text-sm font-semibold`. Bumped to `bg-sunrise-700`
///     (`#D14F1C`, the palette's `primaryDeep` anchor) — ~5.07:1.
///   * Pricing's period-switcher overlay used `text-white` on a
///     clip-path-revealed `bg-sunrise-500` parent, which axe
///     resolved as white-on-white. Added explicit `bg-sunrise-500`
///     on each inner div so axe sees the same contrast the user
///     sees.
///
/// The allow-list is now empty. The gate fails on ANY new
/// serious/critical violation, no exceptions. If the gate needs
/// to ratchet again in the future, follow the VOL-205 staged-
/// ratchet pattern — single-rule allow-list with a tracking
/// ticket for the underlying fix.
const knownIssueRuleIds: Set<string> = new Set()

async function injectAxe(page: Page) {
  return new AxeBuilder({ page })
}

async function getViolations(axe: AxeBuilder) {
  const results = await axe.analyze()
  return results.violations
}

function formatViolations(
  violations: Awaited<ReturnType<typeof getViolations>>,
) {
  return violations
    .map((violation) => {
      const targets = violation.nodes
        .flatMap((node) => node.target)
        .slice(0, 5)
        .join(', ')

      return `${violation.id} (${violation.impact}): ${violation.help} [${targets}]`
    })
    .join('\n')
}

for (const route of routes) {
  test(`${route.path} has no serious or critical axe violations`, async ({
    page,
  }) => {
    // Same `domcontentloaded` rationale as `smoke.spec.ts` — the
    // homepage's persistent analytics + websocket connections
    // prevent `load` / `networkidle` from settling within 30s on
    // a CI runner. The `h1` visibility check below is the contract.
    const response = await page.goto(route.path, {
      waitUntil: 'domcontentloaded',
    })

    expect(response?.status(), `${route.path} should return HTTP 200`).toBe(
      200,
    )
    await expect(
      page.getByRole('heading', { level: 1, name: route.h1 }),
    ).toBeVisible()

    const axe = await injectAxe(page)
    const violations = await getViolations(axe)
    const blockingViolations = violations.filter(
      (violation) =>
        typeof violation.impact === 'string' &&
        seriousOrCritical.has(violation.impact) &&
        !knownIssueRuleIds.has(violation.id),
    )

    expect(blockingViolations, formatViolations(blockingViolations)).toEqual(
      [],
    )
  })
}
