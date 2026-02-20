/** @jest-environment node */

jest.mock('@/db/client', () => ({
  hasDatabase: false,
  database: null,
}));

jest.mock('@/lib/server/syncStore', () => ({
  syncStore: {
    push: jest.fn(),
    pull: jest.fn(),
  },
}));

import { syncPersistence } from '@/lib/server/syncPersistence';
import { syncStore } from '@/lib/server/syncStore';
import type { SyncOperation } from '@/types';

describe('syncPersistence', () => {
  const operations: SyncOperation[] = [
    {
      id: 'op-1',
      deviceId: 'device-a',
      entityType: 'workout',
      entityId: 'w-1',
      op: 'upsert',
      clientUpdatedAt: '2026-02-10T10:00:00.000Z',
      payload: { name: 'Workout 1' },
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('falls back to in-memory sync store for push', async () => {
    (syncStore.push as jest.Mock).mockReturnValue({
      applied: operations,
      conflicts: [],
      checkpoint: {
        actorId: 'user:test',
        cursor: 1,
        lastSyncedAt: '2026-02-10T10:00:00.000Z',
      },
    });

    const result = await syncPersistence.push('user:test', operations);
    expect(syncStore.push).toHaveBeenCalledWith('user:test', operations);
    expect(result.applied).toHaveLength(1);
  });

  it('falls back to in-memory sync store for pull', async () => {
    (syncStore.pull as jest.Mock).mockReturnValue({
      operations,
      conflicts: [],
      checkpoint: {
        actorId: 'user:test',
        cursor: 1,
        lastSyncedAt: '2026-02-10T10:00:00.000Z',
      },
    });

    const result = await syncPersistence.pull('user:test', 0);
    expect(syncStore.pull).toHaveBeenCalledWith('user:test', 0);
    expect(result.operations[0]?.id).toBe('op-1');
  });
});

