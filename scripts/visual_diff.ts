import fs from 'node:fs';
import path from 'node:path';
import pixelmatch from 'pixelmatch';
import { PNG } from 'pngjs';

const BASELINE_DIR = process.env.BASELINE_DIR || 'output/playwright/visual-baselines';
const CURRENT_DIR = process.env.CURRENT_DIR || 'output/playwright/visual-current';
const DIFF_DIR = process.env.DIFF_DIR || 'output/playwright/visual-diff';
const MAX_DIFF_RATIO = Number(process.env.MAX_VISUAL_DIFF_RATIO || 0.015);

const ensureDir = (dir: string) => {
  fs.mkdirSync(dir, { recursive: true });
};

const readPng = (filePath: string): PNG => PNG.sync.read(fs.readFileSync(filePath));

const baselineFiles = fs
  .readdirSync(BASELINE_DIR)
  .filter(file => file.endsWith('.png'))
  .sort();

if (baselineFiles.length === 0) {
  console.error(`No baseline screenshots found in ${BASELINE_DIR}`);
  process.exit(1);
}

ensureDir(DIFF_DIR);

let hasFailures = false;

for (const fileName of baselineFiles) {
  const baselinePath = path.join(BASELINE_DIR, fileName);
  const currentPath = path.join(CURRENT_DIR, fileName);

  if (!fs.existsSync(currentPath)) {
    hasFailures = true;
    console.error(`Missing current screenshot: ${currentPath}`);
    continue;
  }

  const baseline = readPng(baselinePath);
  const current = readPng(currentPath);

  if (baseline.width !== current.width || baseline.height !== current.height) {
    hasFailures = true;
    console.error(
      `Dimension mismatch for ${fileName}. baseline=${baseline.width}x${baseline.height} current=${current.width}x${current.height}`
    );
    continue;
  }

  const diff = new PNG({ width: baseline.width, height: baseline.height });
  const diffPixels = pixelmatch(
    baseline.data,
    current.data,
    diff.data,
    baseline.width,
    baseline.height,
    {
      threshold: 0.1,
    }
  );

  const totalPixels = baseline.width * baseline.height;
  const ratio = diffPixels / Math.max(1, totalPixels);
  const ratioRounded = Number(ratio.toFixed(6));

  if (ratio > MAX_DIFF_RATIO) {
    hasFailures = true;
    const diffPath = path.join(DIFF_DIR, fileName);
    fs.writeFileSync(diffPath, PNG.sync.write(diff));
    console.error(
      `Visual regression for ${fileName}: diffRatio=${ratioRounded} exceeds max=${MAX_DIFF_RATIO}`
    );
  } else {
    console.log(`OK ${fileName}: diffRatio=${ratioRounded}`);
  }
}

if (hasFailures) {
  console.error('Visual diff check failed.');
  process.exit(1);
}

console.log('Visual diff check passed.');

