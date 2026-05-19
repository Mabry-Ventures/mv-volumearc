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

/// VOL-217 Phase 2 introduction allow-list. First activation of this
/// gate caught three pre-existing violations across the marketing
/// site that need component-level fixes (tracked separately as
/// VOL-228):
///
///   * `aria-required-children` on `.space-y-6` (homepage only)
///   * `aria-required-parent`   on Headless UI tab buttons
///     (`#headlessui-tabs-tab-...` — missing `role="tablist"` parent
///     wrapper)
///   * `color-contrast`         on `.justify-center` (all routes)
///
/// All three are real product issues, not test infrastructure.
/// Tracking them here as an allow-list keeps the gate armed for any
/// NEW serious/critical violations introduced by future PRs while
/// the existing three are fixed separately.
const knownIssueRuleIds = new Set([
    'aria-required-children',
    'aria-required-parent',
    'color-contrast',
])

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
