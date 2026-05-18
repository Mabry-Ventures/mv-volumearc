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
    const response = await page.goto(route.path)

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
        seriousOrCritical.has(violation.impact),
    )

    expect(blockingViolations, formatViolations(blockingViolations)).toEqual(
      [],
    )
  })
}
