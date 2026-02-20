import { runAiEvalSuite } from '../src/lib/ai/evals/runner';

const THRESHOLDS = {
  schemaValidity: 1,
  parseLogAccuracy: 0.85,
  liveCoachCalibration: 0.7,
};

const report = runAiEvalSuite();

console.log('AI Eval Summary');
console.log(JSON.stringify(report.summary, null, 2));

for (const result of report.results) {
  const status = result.passed ? 'PASS' : 'FAIL';
  console.log(`[${status}] ${result.caseId} (${result.category}) score=${result.score.toFixed(2)} :: ${result.details}`);
}

const failedThresholds: string[] = [];
if (report.summary.schemaValidity < THRESHOLDS.schemaValidity) {
  failedThresholds.push(`schemaValidity ${report.summary.schemaValidity.toFixed(2)} < ${THRESHOLDS.schemaValidity.toFixed(2)}`);
}
if (report.summary.parseLogAccuracy < THRESHOLDS.parseLogAccuracy) {
  failedThresholds.push(`parseLogAccuracy ${report.summary.parseLogAccuracy.toFixed(2)} < ${THRESHOLDS.parseLogAccuracy.toFixed(2)}`);
}
if (report.summary.liveCoachCalibration < THRESHOLDS.liveCoachCalibration) {
  failedThresholds.push(`liveCoachCalibration ${report.summary.liveCoachCalibration.toFixed(2)} < ${THRESHOLDS.liveCoachCalibration.toFixed(2)}`);
}

if (report.summary.failed > 0 || failedThresholds.length > 0) {
  console.error('AI eval failed release gates.');
  if (failedThresholds.length > 0) {
    console.error(failedThresholds.join('\n'));
  }
  process.exit(1);
}

console.log('AI eval passed all release gates.');
