/** @jest-environment node */

import { costGuard } from '@/lib/ai/costGuard';
import { sampleDigest } from '@/test/fixtures/ai';

describe('costGuard', () => {
  it('returns endpoint output token limit', () => {
    expect(costGuard.getOutputTokenLimit('live-coach')).toBeGreaterThan(0);
  });

  it('prunes digest when oversized', () => {
    const largeDigest = {
      ...sampleDigest,
      exerciseTrends: Array.from({ length: 25 }).map((_, idx) => ({
        ...sampleDigest.exerciseTrends[0],
        exerciseId: `ex-${idx}`,
      })),
      recentWorkouts: Array.from({ length: 25 }).map((_, idx) => ({
        ...sampleDigest.recentWorkouts[0],
        id: `w-${idx}`,
        name: `workout-${idx}`,
      })),
    };

    const result = costGuard.pruneDigestForBudget(largeDigest, 'live-coach');
    expect(result.wasPruned).toBe(true);
    expect(result.digest.recentWorkouts.length).toBeLessThan(largeDigest.recentWorkouts.length);
  });

  it('rejects spend when budget is exceeded', () => {
    const actorId = `budget-${Date.now()}`;
    const allowed = costGuard.canSpendForActor(actorId, 3000, 1);
    const denied = costGuard.canSpendForActor(actorId, 500_000, 0.001);
    expect(allowed).toBe(true);
    expect(denied).toBe(false);
  });
});
