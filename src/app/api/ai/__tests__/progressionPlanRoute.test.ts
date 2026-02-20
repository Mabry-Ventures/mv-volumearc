/** @jest-environment node */

import { POST } from '@/app/api/ai/progression-plan/route';
import { aiFlags } from '@/lib/ai/flags';
import { featureFlags } from '@/lib/flags';
import { sampleDigest } from '@/test/fixtures/ai';

describe('progression-plan route', () => {
  const originalAiFlags = { ...aiFlags };
  const originalFeatureFlags = { ...featureFlags };

  beforeEach(() => {
    Object.assign(aiFlags, originalAiFlags);
    Object.assign(featureFlags, originalFeatureFlags);
    aiFlags.progressionPlan = true;
    featureFlags.progressionAutopilot = true;
  });

  afterAll(() => {
    Object.assign(aiFlags, originalAiFlags);
    Object.assign(featureFlags, originalFeatureFlags);
  });

  it('returns 503 when progression plan is disabled', async () => {
    aiFlags.progressionPlan = false;
    const response = await POST(
      new Request('http://localhost/api/ai/progression-plan', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ fullHistoryDigest: sampleDigest }),
      })
    );
    expect(response.status).toBe(503);
  });

  it('returns 400 for invalid payload', async () => {
    const response = await POST(
      new Request('http://localhost/api/ai/progression-plan', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ fullHistoryDigest: { invalid: true } }),
      })
    );
    expect(response.status).toBe(400);
  });

  it('returns progression data for valid payload', async () => {
    const response = await POST(
      new Request('http://localhost/api/ai/progression-plan', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-user-id': 'tester' },
        body: JSON.stringify({ fullHistoryDigest: sampleDigest }),
      })
    );
    const payload = await response.json();
    expect(response.status).toBe(200);
    expect(payload.actorId).toBe('user:tester');
    expect(payload.progression).toHaveProperty('updates');
  });
});

