/** @jest-environment node */

jest.mock('@/lib/server/healthConnectors', () => ({
  healthConnectors: {
    pullSignals: jest.fn(),
  },
}));

import { POST as importHealth } from '@/app/api/integrations/health/import/route';
import { POST as syncHealth } from '@/app/api/integrations/health/sync/route';
import { featureFlags } from '@/lib/flags';
import { healthConnectors } from '@/lib/server/healthConnectors';

describe('integration routes', () => {
  const originalFlags = { ...featureFlags };

  beforeEach(() => {
    Object.assign(featureFlags, originalFlags);
    featureFlags.healthIntegrations = true;
    jest.clearAllMocks();
  });

  afterAll(() => {
    Object.assign(featureFlags, originalFlags);
  });

  it('imports health signals from manual payload', async () => {
    const response = await importHealth(
      new Request('http://localhost/api/integrations/health/import', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-user-id': 'tester' },
        body: JSON.stringify({
          recovery: [{ recordedAt: '2026-02-10T10:00:00.000Z', score: 0.8, source: 'manual' }],
        }),
      })
    );

    const payload = await response.json();
    expect(response.status).toBe(200);
    expect(payload.imported.recovery).toBe(1);
  });

  it('syncs health signals from provider connector', async () => {
    (healthConnectors.pullSignals as jest.Mock).mockResolvedValue({
      recovery: [{ recordedAt: '2026-02-10T10:00:00.000Z', score: 0.82, source: 'wearable' }],
      sleep: [],
      heart: [],
    });

    const response = await syncHealth(
      new Request('http://localhost/api/integrations/health/sync', {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: 'Bearer token' },
        body: JSON.stringify({ provider: 'oura' }),
      })
    );
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(healthConnectors.pullSignals).toHaveBeenCalledTimes(1);
    expect(payload.imported.recovery).toBe(1);
  });

  it('requires auth token for provider sync', async () => {
    const response = await syncHealth(
      new Request('http://localhost/api/integrations/health/sync', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ provider: 'oura' }),
      })
    );
    expect(response.status).toBe(401);
  });
});

