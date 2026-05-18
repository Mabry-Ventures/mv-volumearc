#!/usr/bin/env node

import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { delimiter, dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const marketingRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const baseUrl = 'http://localhost:3000'
const binDir = resolve(marketingRoot, 'node_modules', '.bin')
const localChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

const env = {
  ...process.env,
  NEXT_TELEMETRY_DISABLED: '1',
  PATH: `${binDir}${delimiter}${process.env.PATH ?? ''}`,
}

if (!env.CHROME_PATH) {
  try {
    const { chromium } = await import('playwright')
    const chromiumPath = chromium.executablePath()
    if (existsSync(chromiumPath)) {
      env.CHROME_PATH = chromiumPath
    }
  } catch {
    // The CI workflow installs Playwright before this script runs. If the
    // package or browser is missing locally, LHCI can still use system Chrome.
  }
}

if (!env.CHROME_PATH && existsSync(localChrome)) {
  env.CHROME_PATH = localChrome
}

const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm'
const lhci = process.platform === 'win32' ? 'lhci.cmd' : 'lhci'

function run(command, args) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(command, args, {
      cwd: marketingRoot,
      env,
      stdio: 'inherit',
    })

    child.on('error', rejectRun)
    child.on('exit', (code, signal) => {
      if (code === 0) {
        resolveRun()
        return
      }

      rejectRun(
        new Error(
          `${command} ${args.join(' ')} failed with ${
            signal ? `signal ${signal}` : `exit code ${code}`
          }`,
        ),
      )
    })
  })
}

async function waitForServer(server, timeoutMs = 120_000) {
  const deadline = Date.now() + timeoutMs
  let serverExit = null

  server.once('exit', (code, signal) => {
    serverExit = signal ? `signal ${signal}` : `exit code ${code}`
  })

  while (Date.now() < deadline) {
    if (serverExit) {
      throw new Error(
        `next start exited before ${baseUrl} was ready: ${serverExit}`,
      )
    }

    try {
      const response = await fetch(baseUrl)
      if (response.ok) {
        return
      }
    } catch {
      // Server is still booting.
    }

    await new Promise((resolveWait) => setTimeout(resolveWait, 500))
  }

  throw new Error(`Timed out waiting for ${baseUrl}`)
}

const server = spawn(npm, ['run', 'start'], {
  cwd: marketingRoot,
  env,
  stdio: 'inherit',
})

let shuttingDown = false

function shutdown() {
  if (!shuttingDown && server.exitCode === null && server.signalCode === null) {
    shuttingDown = true
    server.kill('SIGTERM')
  }
}

process.on('SIGINT', () => {
  shutdown()
  process.exit(130)
})
process.on('SIGTERM', () => {
  shutdown()
  process.exit(143)
})

try {
  await waitForServer(server)
  await run(lhci, ['collect', '--config=./lighthouserc.json'])
  await run(lhci, ['assert', '--config=./lighthouserc.json'])
} finally {
  shutdown()
}
