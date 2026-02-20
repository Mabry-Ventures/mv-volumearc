import { and, asc, count, desc, eq } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { database, hasDatabase } from '@/db/client';
import { workoutSyncConflicts, workoutSyncOps } from '@/db/schema';
import type { ConflictRecord, SyncCheckpoint, SyncOperation } from '@/types';
import { syncStore } from '@/lib/server/syncStore';

const toIso = (value: string | Date | undefined): string => {
  if (!value) return new Date(0).toISOString();
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return new Date(0).toISOString();
  return date.toISOString();
};

const toDate = (value: string): Date => {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return new Date(0);
  return date;
};

const getCheckpoint = async (actorId: string): Promise<SyncCheckpoint> => {
  if (!database) {
    return {
      actorId,
      cursor: 0,
      lastSyncedAt: new Date().toISOString(),
    };
  }

  const result = await database
    .select({ total: count() })
    .from(workoutSyncOps)
    .where(eq(workoutSyncOps.userKey, actorId));

  return {
    actorId,
    cursor: Number(result[0]?.total || 0),
    lastSyncedAt: new Date().toISOString(),
  };
};

export const syncPersistence = {
  async push(
    actorId: string,
    operations: SyncOperation[]
  ): Promise<{
    applied: SyncOperation[];
    conflicts: ConflictRecord[];
    checkpoint: SyncCheckpoint;
  }> {
    if (!hasDatabase || !database) {
      return syncStore.push(actorId, operations);
    }

    try {
      const applied: SyncOperation[] = [];
      const conflicts: ConflictRecord[] = [];

      for (const operation of operations) {
        const normalized: SyncOperation = {
          ...operation,
          id: operation.id || uuidv4(),
          serverReceivedAt: new Date().toISOString(),
        };

        const latest = await database
          .select()
          .from(workoutSyncOps)
          .where(
            and(
              eq(workoutSyncOps.userKey, actorId),
              eq(workoutSyncOps.entityType, normalized.entityType),
              eq(workoutSyncOps.entityId, normalized.entityId)
            )
          )
          .orderBy(desc(workoutSyncOps.clientUpdatedAt), desc(workoutSyncOps.serverReceivedAt))
          .limit(1);

        const existing = latest[0];
        const existingUpdated = toIso(existing?.clientUpdatedAt);
        const incomingUpdated = toIso(normalized.clientUpdatedAt);

        if (!existing || incomingUpdated >= existingUpdated) {
          await database.insert(workoutSyncOps).values({
            id: normalized.id,
            userKey: actorId,
            deviceId: normalized.deviceId,
            entityType: normalized.entityType,
            entityId: normalized.entityId,
            opType: normalized.op,
            payload: normalized.payload ?? null,
            clientUpdatedAt: toDate(normalized.clientUpdatedAt),
            serverReceivedAt: toDate(normalized.serverReceivedAt || new Date().toISOString()),
          });

          if (existing) {
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
            conflicts.push(conflict);
            await database.insert(workoutSyncConflicts).values({
              id: conflict.id,
              userKey: actorId,
              entityType: conflict.entityType,
              entityId: conflict.entityId,
              keptOperationId: conflict.keptOperationId,
              droppedOperationId: conflict.droppedOperationId,
              reason: conflict.reason,
              resolvedAt: toDate(conflict.resolvedAt),
            });
          }

          applied.push(normalized);
          continue;
        }

        const staleConflict: ConflictRecord = {
          id: uuidv4(),
          actorId,
          entityType: normalized.entityType,
          entityId: normalized.entityId,
          keptOperationId: existing.id,
          droppedOperationId: normalized.id,
          reason: 'incoming operation stale; last-write-wins',
          resolvedAt: new Date().toISOString(),
        };

        conflicts.push(staleConflict);
        await database.insert(workoutSyncConflicts).values({
          id: staleConflict.id,
          userKey: actorId,
          entityType: staleConflict.entityType,
          entityId: staleConflict.entityId,
          keptOperationId: staleConflict.keptOperationId,
          droppedOperationId: staleConflict.droppedOperationId,
          reason: staleConflict.reason,
          resolvedAt: toDate(staleConflict.resolvedAt),
        });
      }

      const checkpoint = await getCheckpoint(actorId);
      return { applied, conflicts, checkpoint };
    } catch (error) {
      console.warn('Sync persistence DB path failed. Falling back to memory store.', error);
      return syncStore.push(actorId, operations);
    }
  },

  async pull(
    actorId: string,
    sinceCursor = 0
  ): Promise<{
    operations: SyncOperation[];
    conflicts: ConflictRecord[];
    checkpoint: SyncCheckpoint;
  }> {
    if (!hasDatabase || !database) {
      return syncStore.pull(actorId, sinceCursor);
    }

    try {
      const operationsRows = await database
        .select()
        .from(workoutSyncOps)
        .where(eq(workoutSyncOps.userKey, actorId))
        .orderBy(asc(workoutSyncOps.serverReceivedAt), asc(workoutSyncOps.clientUpdatedAt))
        .offset(Math.max(0, sinceCursor));

      const conflictRows = await database
        .select()
        .from(workoutSyncConflicts)
        .where(eq(workoutSyncConflicts.userKey, actorId))
        .orderBy(asc(workoutSyncConflicts.resolvedAt))
        .offset(Math.max(0, sinceCursor));

      const operations: SyncOperation[] = operationsRows.map(row => ({
        id: row.id,
        deviceId: row.deviceId,
        entityType: row.entityType as SyncOperation['entityType'],
        entityId: row.entityId,
        op: row.opType as SyncOperation['op'],
        payload: row.payload,
        clientUpdatedAt: toIso(row.clientUpdatedAt),
        serverReceivedAt: toIso(row.serverReceivedAt),
      }));

      const conflicts: ConflictRecord[] = conflictRows.map(row => ({
        id: row.id,
        actorId,
        entityType: row.entityType as SyncOperation['entityType'],
        entityId: row.entityId,
        keptOperationId: row.keptOperationId,
        droppedOperationId: row.droppedOperationId,
        reason: row.reason,
        resolvedAt: toIso(row.resolvedAt),
      }));

      const checkpoint = await getCheckpoint(actorId);
      return { operations, conflicts, checkpoint };
    } catch (error) {
      console.warn('Sync pull DB path failed. Falling back to memory store.', error);
      return syncStore.pull(actorId, sinceCursor);
    }
  },
};

