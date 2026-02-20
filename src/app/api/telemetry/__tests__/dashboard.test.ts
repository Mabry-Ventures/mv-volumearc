/** @jest-environment node */

import { GET } from '@/app/api/telemetry/dashboard/route';

describe('telemetry dashboard route', () => {
  it('returns dashboard summary payload', async () => {
    const response = await GET();
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload).toHaveProperty('kpis');
    expect(payload).toHaveProperty('counts');
  });
});

