import { v4 as uuidv4 } from 'uuid';
import type { ConflictRecord, SyncCheckpoint, SyncOperation } from '@/types';

type ActorSyncState = {
  actorId: string;
  cursor: number;
  operations: SyncOperation[];
  latestByEntity: Map<string, SyncOperation>;
  conflicts: ConflictRecord[];
};

const actorStore = new Map<string, ActorSyncState>();

const getEntityKey = (operation: Pick<SyncOperation, 'entityType' | 'entityId'>) =>
  `${operation.entityType}:${operation.entityId}`;

const getOrCreateState = (actorId: string): ActorSyncState => {
  const existing = actorStore.get(actorId);
  if (existing) return existing;

  const state: ActorSyncState = {
    actorId,
    cursor: 0,
    operations: [],
    latestByEntity: new Map(),
    conflicts: [],
  };

  actorStore.set(actorId, state);
  return state;
};

const toIso = (value: string | undefined): string => {
  if (!value) return new Date(0).toISOString();
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return new Date(0).toISOString();
  return date.toISOString();
};

export const syncStore = {
  push(actorId: string, operations: SyncOperation[]): {
    applied: SyncOperation[];
    conflicts: ConflictRecord[];
    checkpoint: SyncCheckpoint;
  } {
    const state = getOrCreateState(actorId);
    const applied: SyncOperation[] = [];
    const conflicts: ConflictRecord[] = [];

    operations.forEach(operation => {
      const normalized: SyncOperation = {
        ...operation,
        id: operation.id || uuidv4(),
        serverReceivedAt: new Date().toISOString(),
      };

      const entityKey = getEntityKey(normalized);
      const existing = state.latestByEntity.get(entityKey);

      if (!existing) {
        state.cursor += 1;
        state.latestByEntity.set(entityKey, normalized);
        state.operations.push(normalized);
        applied.push(normalized);
        return;
      }

      const existingUpdated = toIso(existing.clientUpdatedAt);
      const incomingUpdated = toIso(normalized.clientUpdatedAt);

      if (incomingUpdated >= existingUpdated) {
        const conflict: ConflictRecord = {
          id: uuidv4(),
          actorId,
          entityType: normalized.entityType,
          entityId: normalized.entityId,
          keptOperationId: normalized.id,
          droppedOperationId: existing.id,
          reason: 'last-write-wins overwrite',
          resolvedAt: new Date().toISOString(),
        };

        state.cursor += 1;
        state.latestByEntity.set(entityKey, normalized);
        state.operations.push(normalized);
        state.conflicts.push(conflict);
        applied.push(normalized);
        conflicts.push(conflict);
        return;
      }

      const conflict: ConflictRecord = {
        id: uuidv4(),
        actorId,
        entityType: normalized.entityType,
        entityId: normalized.entityId,
        keptOperationId: existing.id,
        droppedOperationId: normalized.id,
        reason: 'incoming operation stale; last-write-wins',
        resolvedAt: new Date().toISOString(),
      };

      state.conflicts.push(conflict);
      conflicts.push(conflict);
    });

    actorStore.set(actorId, state);

    return {
      applied,
      conflicts,
      checkpoint: {
        actorId,
        cursor: state.cursor,
        lastSyncedAt: new Date().toISOString(),
      },
    };
  },

  pull(actorId: string, sinceCursor = 0): {
    operations: SyncOperation[];
    conflicts: ConflictRecord[];
    checkpoint: SyncCheckpoint;
  } {
    const state = getOrCreateState(actorId);

    const operations = state.operations.slice(Math.max(0, sinceCursor));
    const conflicts = state.conflicts.slice(Math.max(0, sinceCursor));

    return {
      operations,
      conflicts,
      checkpoint: {
        actorId,
        cursor: state.cursor,
        lastSyncedAt: new Date().toISOString(),
      },
    };
  },
};
