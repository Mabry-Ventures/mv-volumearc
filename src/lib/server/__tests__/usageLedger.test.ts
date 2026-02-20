/** @jest-environment node */

import { usageLedger } from '@/lib/server/usageLedger';

describe('usageLedger', () => {
  it('records usage and accumulates endpoint counts', () => {
    const actorId = `actor-${Date.now()}`;
    usageLedger.record(actorId, 'workout-plan', {
      inputTokens: 100,
      outputTokens: 40,
      totalTokens: 140,
    });
    usageLedger.record(actorId, 'workout-plan', {
      inputTokens: 20,
      outputTokens: 10,
      totalTokens: 30,
    });

    const usage = usageLedger.get(actorId);
    expect(usage.tokenUsage.totalTokens).toBe(170);
    expect(usage.endpointCounts['workout-plan']).toBe(2);
    expect(usage.totalUsd).toBeGreaterThan(0);
  });
});

