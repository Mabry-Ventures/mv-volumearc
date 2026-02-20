/** @jest-environment node */

jest.mock('@/lib/server/syncPersistence', () => ({
  syncPersistence: {
    push: jest.fn(),
    pull: jest.fn(),
  },
}));

import { GET as getFeatures } from '@/app/api/me/features/route';
import { GET as getEntitlements } from '@/app/api/subscription/entitlements/route';
import { POST as telemetryIngest } from '@/app/api/telemetry/ingest/route';
import { POST as syncPull } from '@/app/api/sync/pull/route';
import { POST as syncPush } from '@/app/api/sync/push/route';
import { featureFlags } from '@/lib/flags';
import { syncPersistence } from '@/lib/server/syncPersistence';

describe('platform API routes', () => {
  const originalFlags = { ...featureFlags };

  beforeEach(() => {
    Object.assign(featureFlags, originalFlags);
    jest.clearAllMocks();
  });

  afterAll(() => {
    Object.assign(featureFlags, originalFlags);
  });

  it('ingests telemetry events', async () => {
    featureFlags.telemetryIngest = true;
    const request = new Request('http://localhost/api/telemetry/ingest', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-user-id': 'tester' },
      body: JSON.stringify({
        uiEvents: [
          {
            id: 'evt-1',
            version: '1.0.0',
            stage: 'workout_active',
            action: 'set_complete_toggle',
            elapsedMs: 120,
            createdAt: new Date().toISOString(),
          },
        ],
      }),
    });

    const response = await telemetryIngest(request);
    const payload = await response.json();
    expect(response.status).toBe(200);
    expect(payload.acceptedUi).toBe(1);
    expect(payload.actorId).toBe('user:tester');
  });

  it('returns feature flags for actor', async () => {
    const response = await getFeatures(
      new Request('http://localhost/api/me/features', {
        headers: { 'x-user-id': 'tester' },
      })
    );
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.actorId).toBe('user:tester');
    expect(payload.featureFlags).toHaveProperty('aiWorkoutPlan');
  });

  it('returns entitlements when monetization controls are enabled', async () => {
    featureFlags.monetizationControls = true;
    const response = await getEntitlements(
      new Request('http://localhost/api/subscription/entitlements', {
        headers: { 'x-user-id': 'tester' },
      })
    );
    const payload = await response.json();

    expect(response.status).toBe(200);
    expect(payload.entitlement).toBeDefined();
    expect(payload.actorId).toBe('user:tester');
  });

  it('sync push delegates to syncPersistence', async () => {
    featureFlags.cloudSyncAlpha = true;
    (syncPersistence.push as jest.Mock).mockResolvedValue({
      applied: [{ id: 'op-1' }],
      conflicts: [],
      checkpoint: { actorId: 'user:tester', cursor: 1, lastSyncedAt: new Date().toISOString() },
    });

    const response = await syncPush(
      new Request('http://localhost/api/sync/push', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-user-id': 'tester' },
        body: JSON.stringify({
          operations: [
            {
              id: 'op-1',
              deviceId: 'device-1',
              entityType: 'workout',
              entityId: 'w-1',
              op: 'upsert',
              clientUpdatedAt: '2026-02-10T10:00:00.000Z',
              payload: { name: 'Workout' },
            },
          ],
        }),
      })
    );

    const payload = await response.json();
    expect(response.status).toBe(200);
    expect(syncPersistence.push).toHaveBeenCalledTimes(1);
    expect(payload.appliedCount).toBe(1);
  });

  it('sync pull delegates to syncPersistence', async () => {
    featureFlags.cloudSyncAlpha = true;
    (syncPersistence.pull as jest.Mock).mockResolvedValue({
      operations: [{ id: 'op-1' }],
      conflicts: [],
      checkpoint: { actorId: 'user:tester', cursor: 1, lastSyncedAt: new Date().toISOString() },
    });

    const response = await syncPull(
      new Request('http://localhost/api/sync/pull', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-user-id': 'tester' },
        body: JSON.stringify({ sinceCursor: 0 }),
      })
    );

    const payload = await response.json();
    expect(response.status).toBe(200);
    expect(syncPersistence.pull).toHaveBeenCalledWith('user:tester', 0);
    expect(Array.isArray(payload.operations)).toBe(true);
  });
});

