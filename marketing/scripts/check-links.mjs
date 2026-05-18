#!/usr/bin/env node
// VOL-217 Phase 1: static link guard for the built marketing site.
//
// Runs after `next build` and walks the static HTML output in
// `.next/server/app/` (Next 16 static-page renders) looking for:
//
//   1. Any anchor with `href="#"` — a dead CTA on a primary navigation
//      surface (e.g. the App Store badge before VOL-208 fixed it). App
//      Review treats `href="#"` on a primary CTA as a flag.
//   2. Internal links (`href="/some/path"`) that don't resolve to a
//      built page under `.next/server/app/<route>/page.html`. Catches
//      broken navigation links before Vercel deploys them.
//
// Phase 2 (separate ticket): Playwright smoke + axe-core accessibility
// scan + Lighthouse CI with LCP/CLS/INP budgets. Each requires
// substantial CI tooling that doesn't fit in this PR's scope; the
// Phase 1 check above is the smallest fix that closes the highest-
// signal half of F-M-008.

import { readdir, readFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join, resolve } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const marketingRoot = resolve(here, '..')
const buildRoot = resolve(marketingRoot, '.next', 'server', 'app')

if (!existsSync(buildRoot)) {
  console.error(
    `check-links: cannot find ${buildRoot}. Run \`npm run build\` first.`,
  )
  process.exit(1)
}

// Routes the marketing site exposes. Keep in sync with the
// `app/(main)/<route>/page.tsx` layout. Used for the "internal link
// must resolve" check.
const KNOWN_ROUTES = new Set([
  '/',
  '/privacy',
  '/terms',
  '/support',
  '/quality',
  '/download', // redirect target — vercel.json handles, not a page route
  '/app',      // redirect target
])

// Hosts we treat as "internal" for the resolution check. Anything
// not on this list is considered external and skipped.
const INTERNAL_HOSTS = new Set([
  'volumearc.app',
  'www.volumearc.app',
])

/** Recursively list every .html file under `dir`. */
async function listHtml(dir) {
  const entries = await readdir(dir, { withFileTypes: true })
  const results = []
  for (const entry of entries) {
    const full = join(dir, entry.name)
    if (entry.isDirectory()) {
      results.push(...(await listHtml(full)))
    } else if (entry.name.endsWith('.html')) {
      results.push(full)
    }
  }
  return results
}

/** Strip query string + fragment from a URL path for route resolution. */
function normalizePath(path) {
  return path.split('?')[0].split('#')[0]
}

const htmlFiles = await listHtml(buildRoot)
let failures = 0

for (const file of htmlFiles) {
  const body = await readFile(file, 'utf8')

  // Pattern 1: href="#" on any anchor. Pure-substring check
  // (regex would match `href="#section"` which is legitimate);
  // we match the closing-quote immediately after `#`.
  const deadAnchors = body.match(/href="#"/g)
  if (deadAnchors) {
    console.error(
      `check-links: FAIL — ${file.replace(marketingRoot + '/', '')}: ` +
      `${deadAnchors.length} dead anchor(s) with href="#" — primary CTAs ` +
      `must route somewhere (see VOL-208 / VOL-217).`,
    )
    failures += deadAnchors.length
  }

  // Pattern 2: internal `href="/path"` that doesn't match a known route.
  // Skip mailto:, tel:, http:, #fragment-only.
  const hrefPattern = /href="([^"#][^"]*)"/g
  let match
  while ((match = hrefPattern.exec(body)) !== null) {
    const href = match[1]
    if (href.startsWith('mailto:') || href.startsWith('tel:') || href.startsWith('javascript:')) continue
    if (href.startsWith('http://') || href.startsWith('https://')) {
      // External — only validate if it's one of our hosts.
      try {
        const url = new URL(href)
        if (!INTERNAL_HOSTS.has(url.hostname)) continue
        const path = normalizePath(url.pathname)
        if (!KNOWN_ROUTES.has(path)) {
          console.error(
            `check-links: FAIL — ${file.replace(marketingRoot + '/', '')}: ` +
            `internal absolute URL points at unknown route ${path} (${href}).`,
          )
          failures++
        }
      } catch {
        // Malformed URL — log and continue
        console.error(
          `check-links: WARN — ${file.replace(marketingRoot + '/', '')}: ` +
          `malformed href ${href}; skipped`,
        )
      }
      continue
    }
    if (href.startsWith('/')) {
      const path = normalizePath(href)
      // Skip Next.js-internal asset paths and auto-generated icons
      // — these aren't page routes, they're build artifacts emitted by
      // Next/Vercel into the static HTML (script tags, link tags,
      // favicon, OG image). The route-resolution check is about
      // user-clickable anchors, not framework plumbing.
      if (
        path.startsWith('/_next/') ||
        path === '/icon.png' ||
        path === '/apple-icon.png' ||
        path === '/favicon.ico' ||
        path === '/manifest.webmanifest' ||
        path === '/robots.txt' ||
        path === '/sitemap.xml' ||
        path.startsWith('/og-image')
      ) {
        continue
      }
      if (!KNOWN_ROUTES.has(path)) {
        console.error(
          `check-links: FAIL — ${file.replace(marketingRoot + '/', '')}: ` +
          `internal path ${path} (href="${href}") doesn't match any built page route.`,
        )
        failures++
      }
    }
  }
}

if (failures > 0) {
  console.error(`check-links: ${failures} failure(s) detected across ${htmlFiles.length} HTML file(s).`)
  process.exit(1)
}

console.log(`check-links: scanned ${htmlFiles.length} HTML file(s); no dead anchors or unresolved internal links.`)
