/** @jest-environment node */

import { healthConnectors } from '@/lib/server/healthConnectors';

const originalFetch = global.fetch;

const mockJsonResponse = (payload: unknown, status = 200) =>
  ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => payload,
  }) as Response;

describe('healthConnectors', () => {
  beforeEach(() => {
    global.fetch = jest.fn();
  });

  afterEach(() => {
    global.fetch = originalFetch;
    jest.clearAllMocks();
  });

  it('pulls from generic-json provider', async () => {
    (global.fetch as jest.Mock).mockResolvedValue(
      mockJsonResponse({
        recovery: [{ recordedAt: '2026-02-10T10:00:00.000Z', score: 82 }],
        sleep: [{ recordedAt: '2026-02-10T10:00:00.000Z', durationHours: 7.5 }],
        heart: [{ recordedAt: '2026-02-10T10:00:00.000Z', restingHr: 54 }],
      })
    );

    const result = await healthConnectors.pullSignals({
      provider: 'generic-json',
      accessToken: 'token',
      genericUrl: 'https://provider.example.com/health',
    });

    expect(result.recovery[0]?.score).toBeCloseTo(0.82, 2);
    expect(result.sleep[0]?.durationHours).toBe(7.5);
    expect(result.heart[0]?.restingHr).toBe(54);
  });

  it('requires genericUrl for generic-json provider', async () => {
    await expect(
      healthConnectors.pullSignals({
        provider: 'generic-json',
        accessToken: 'token',
      })
    ).rejects.toThrow('genericUrl is required');
  });

  it('pulls and normalizes from oura provider', async () => {
    (global.fetch as jest.Mock)
      .mockResolvedValueOnce(
        mockJsonResponse({ data: [{ day: '2026-02-10', score: 81 }] })
      )
      .mockResolvedValueOnce(
        mockJsonResponse({ data: [{ day: '2026-02-10', total_sleep_duration: 25200, score: 77 }] })
      )
      .mockResolvedValueOnce(
        mockJsonResponse({ data: [{ timestamp: '2026-02-10T09:00:00.000Z', bpm: 55, hrv: 42 }] })
      );

    const result = await healthConnectors.pullSignals({
      provider: 'oura',
      accessToken: 'token',
      startDate: '2026-02-09',
      endDate: '2026-02-10',
    });

    expect(result.recovery[0]?.score).toBeCloseTo(0.81, 2);
    expect(result.sleep[0]?.durationHours).toBe(7);
    expect(result.heart[0]?.hrvMs).toBe(42);
  });
});

