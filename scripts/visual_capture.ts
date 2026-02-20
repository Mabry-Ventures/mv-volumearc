import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const BASE_URL = process.env.BASE_URL || 'http://127.0.0.1:4173';
const OUTPUT_DIR = process.env.OUTPUT_DIR || 'output/playwright/visual-current';

const ROUTES = [
  { route: '/', name: 'home' },
  { route: '/workout', name: 'workout' },
  { route: '/history', name: 'history' },
  { route: '/stats', name: 'stats' },
  { route: '/settings', name: 'settings' },
];

const VIEWPORTS = [
  { width: 1440, height: 900, label: 'desktop' },
  { width: 390, height: 844, label: 'mobile' },
];

const ensureDir = (dir: string) => {
  fs.mkdirSync(dir, { recursive: true });
};

const capture = async () => {
  ensureDir(OUTPUT_DIR);
  const browser = await chromium.launch({ headless: true });

  try {
    for (const viewport of VIEWPORTS) {
      const context = await browser.newContext({
        viewport: { width: viewport.width, height: viewport.height },
      });

      for (const target of ROUTES) {
        const page = await context.newPage();
        const url = `${BASE_URL}${target.route}`;
        await page.goto(url, { waitUntil: 'networkidle', timeout: 30_000 });
        const outPath = path.join(OUTPUT_DIR, `${target.name}-${viewport.label}.png`);
        await page.screenshot({ path: outPath });
        await page.close();
      }

      await context.close();
    }
  } finally {
    await browser.close();
  }
};

capture()
  .then(() => {
    console.log(`Visual snapshots saved to ${OUTPUT_DIR}`);
  })
  .catch(error => {
    console.error('Visual capture failed:', error);
    process.exit(1);
  });
