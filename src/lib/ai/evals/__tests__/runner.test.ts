import { runAiEvalSuite } from '@/lib/ai/evals/runner';

describe('ai eval suite', () => {
  it('returns passing summary for baseline cases', () => {
    const report = runAiEvalSuite();

    expect(report.summary.total).toBeGreaterThan(0);
    expect(report.summary.failed).toBe(0);
    expect(report.summary.schemaValidity).toBe(1);
    expect(report.summary.parseLogAccuracy).toBeGreaterThanOrEqual(0.85);
    expect(report.summary.liveCoachCalibration).toBeGreaterThanOrEqual(0.7);
  });
});
