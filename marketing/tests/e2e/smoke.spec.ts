import { expect, test } from '@playwright/test'

const routes = [
  {
    path: '/',
    h1: 'Your strength coach, built into your Apple Watch.',
  },
  {
    path: '/privacy',
    h1: 'Privacy Policy',
  },
  {
    path: '/terms',
    h1: 'Terms of Service',
  },
  {
    path: '/support',
    h1: 'Get help with VolumeArc',
  },
  {
    path: '/quality',
    h1: 'Coach quality, in the open.',
  },
] as const

for (const route of routes) {
  test(`${route.path} returns 200 and renders the expected h1`, async ({
    page,
  }) => {
    const consoleErrors: string[] = []
    const pageErrors: string[] = []

    page.on('console', (message) => {
      if (message.type() === 'error') {
        consoleErrors.push(message.text())
      }
    })
    page.on('pageerror', (error) => {
      pageErrors.push(error.message)
    })

    const response = await page.goto(route.path)

    expect(response?.status(), `${route.path} should return HTTP 200`).toBe(
      200,
    )
    await expect(
      page.getByRole('heading', { level: 1, name: route.h1 }),
    ).toBeVisible()
    await page.waitForLoadState('networkidle')

    expect(pageErrors).toEqual([])
    expect(consoleErrors).toEqual([])
  })
}
