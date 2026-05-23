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

test('/support form posts a support request and renders success', async ({
  page,
}) => {
  await page.route('**/api/support', async (route) => {
    const request = route.request()
    const body = request.postDataJSON() as Record<string, unknown>

    expect(request.method()).toBe('POST')
    expect(body.name).toBe('Jared Mabry')
    expect(body.email).toBe('jared@example.com')
    expect(body.category).toBe('bug-report')
    expect(body.message).toContain('coach response panel')
    expect(body.company).toBe('')

    await route.fulfill({
      status: 202,
      contentType: 'application/json',
      body: JSON.stringify({ ok: true }),
    })
  })

  await page.goto('/support', { waitUntil: 'domcontentloaded' })
  await page.getByLabel('Name').fill('Jared Mabry')
  await page.getByLabel('Email').fill('jared@example.com')
  await page.getByLabel('Topic').selectOption('bug-report')
  await page
    .getByLabel('Message')
    .fill('The coach response panel got stuck after a streamed reply.')
  await page.getByRole('button', { name: 'Send message' }).click()

  await expect(page.getByRole('status')).toContainText('Message sent.')
  await expect(page.getByRole('status')).toContainText('one business day')
})
