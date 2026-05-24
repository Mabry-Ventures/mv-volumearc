import { existsSync } from 'node:fs'

import { defineConfig } from '@playwright/test'

const runIdPortOffset = Number(process.env.GITHUB_RUN_ID ?? 0) % 1_000
const port = Number(process.env.MARKETING_E2E_PORT ?? process.env.PORT ?? 3_100 + runIdPortOffset)
const host = process.env.MARKETING_E2E_HOST ?? '127.0.0.1'
const baseURL = process.env.MARKETING_E2E_BASE_URL ?? `http://${host}:${port}`
const localChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const executablePath =
  process.env.CHROME_PATH ??
  (!process.env.CI && existsSync(localChrome) ? localChrome : undefined)

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: false,
  workers: 1,
  timeout: 30_000,
  expect: {
    timeout: 5_000,
  },
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL,
    headless: true,
    launchOptions: executablePath ? { executablePath } : undefined,
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: {
        browserName: 'chromium',
      },
    },
  ],
  webServer: {
    command: `PORT=${port} npm run start`,
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
})
