import { NextResponse } from 'next/server';
import type { SyncOperation } from '@/types';
import { getActorIdFromRequest } from '@/lib/server/actor';
import { syncPersistence } from '@/lib/server/syncPersistence';
import { featureFlags } from '@/lib/flags';

export const runtime = 'nodejs';

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const isSyncOperation = (value: unknown): value is SyncOperation => {
  if (!isObject(value)) return false;

  const idValid = value.id === undefined || typeof value.id === 'string';
  return (
    idValid &&
    typeof value.deviceId === 'string' &&
    (value.entityType === 'workout' || value.entityType === 'template' || value.entityType === 'preference') &&
    typeof value.entityId === 'string' &&
    (value.op === 'upsert' || value.op === 'delete') &&
    typeof value.clientUpdatedAt === 'string'
  );
};

export async function POST(request: Request) {
  if (!featureFlags.cloudSyncAlpha) {
    return NextResponse.json({ error: 'Cloud sync alpha is not enabled.' }, { status: 503 });
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid sync push payload.' }, { status: 400 });
  }

  if (!isObject(payload) || !Array.isArray(payload.operations)) {
    return NextResponse.json({ error: 'Missing operations array.' }, { status: 400 });
  }

  const operations = payload.operations.filter(isSyncOperation);
  if (operations.length === 0) {
    return NextResponse.json({ error: 'No valid operations provided.' }, { status: 400 });
  }

  const actorId = getActorIdFromRequest(request);
  const result = await syncPersistence.push(actorId, operations);

  return NextResponse.json({
    actorId,
    appliedCount: result.applied.length,
    conflicts: result.conflicts,
    checkpoint: result.checkpoint,
  });
}
