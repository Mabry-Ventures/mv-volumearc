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

    // `domcontentloaded` is the right wait condition for a static
    // marketing page — `networkidle` never settles on the homepage
    // because of the persistent analytics + (in preview builds)
    // hot-reload websockets, even though the page has been fully
    // rendered for the user. The `h1` visibility check below is the
    // contract.
    const response = await page.goto(route.path, {
      waitUntil: 'domcontentloaded',
    })

    expect(response?.status(), `${route.path} should return HTTP 200`).toBe(
      200,
    )
    await expect(
      page.getByRole('heading', { level: 1, name: route.h1 }),
    ).toBeVisible()

    expect(pageErrors).toEqual([])
    expect(consoleErrors).toEqual([])
  })
}
