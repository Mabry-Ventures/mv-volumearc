import { NextResponse } from 'next/server';
import { getActorIdFromRequest } from '@/lib/server/actor';
import { syncPersistence } from '@/lib/server/syncPersistence';
import { featureFlags } from '@/lib/flags';

export const runtime = 'nodejs';

const toSafeInt = (value: unknown): number => {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? Math.floor(parsed) : 0;
};

export async function POST(request: Request) {
  if (!featureFlags.cloudSyncAlpha) {
    return NextResponse.json({ error: 'Cloud sync alpha is not enabled.' }, { status: 503 });
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    payload = {};
  }

  const sinceCursor =
    payload && typeof payload === 'object' && 'sinceCursor' in payload
      ? toSafeInt((payload as Record<string, unknown>).sinceCursor)
      : 0;

  const actorId = getActorIdFromRequest(request);
  const result = await syncPersistence.pull(actorId, sinceCursor);

  return NextResponse.json({
    actorId,
    operations: result.operations,
    conflicts: result.conflicts,
    checkpoint: result.checkpoint,
  });
}
