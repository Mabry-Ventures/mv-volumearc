import { NextResponse } from 'next/server';
import type { HrSignal, RecoverySignal, SleepSignal } from '@/types';
import { getActorIdFromRequest } from '@/lib/server/actor';
import { integrationStore } from '@/lib/server/integrationStore';
import { featureFlags } from '@/lib/flags';

export const runtime = 'nodejs';

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const isRecoverySignal = (value: unknown): value is RecoverySignal => {
  if (!isObject(value)) return false;
  return (
    typeof value.recordedAt === 'string' &&
    typeof value.score === 'number' &&
    value.score >= 0 &&
    value.score <= 1 &&
    typeof value.source === 'string'
  );
};

const isSleepSignal = (value: unknown): value is SleepSignal => {
  if (!isObject(value)) return false;
  return (
    typeof value.recordedAt === 'string' &&
    typeof value.durationHours === 'number' &&
    value.durationHours >= 0 &&
    typeof value.source === 'string'
  );
};

const isHrSignal = (value: unknown): value is HrSignal => {
  if (!isObject(value)) return false;
  return (
    typeof value.recordedAt === 'string' &&
    typeof value.source === 'string'
  );
};

export async function POST(request: Request) {
  if (!featureFlags.healthIntegrations) {
    return NextResponse.json({ error: 'Health integrations are currently disabled.' }, { status: 503 });
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid integration payload.' }, { status: 400 });
  }

  if (!isObject(payload)) {
    return NextResponse.json({ error: 'Invalid integration payload.' }, { status: 400 });
  }

  const recovery = Array.isArray(payload.recovery)
    ? payload.recovery.filter(isRecoverySignal)
    : undefined;
  const sleep = Array.isArray(payload.sleep)
    ? payload.sleep.filter(isSleepSignal)
    : undefined;
  const heart = Array.isArray(payload.heart)
    ? payload.heart.filter(isHrSignal)
    : undefined;

  const importedCount =
    (recovery?.length || 0) + (sleep?.length || 0) + (heart?.length || 0);

  if (importedCount === 0) {
    return NextResponse.json({ error: 'No supported signals provided.' }, { status: 400 });
  }

  const actorId = getActorIdFromRequest(request);
  const state = integrationStore.importSignals(actorId, { recovery, sleep, heart });
  const summary = integrationStore.getSummary(actorId);

  return NextResponse.json({
    actorId,
    imported: {
      recovery: recovery?.length || 0,
      sleep: sleep?.length || 0,
      heart: heart?.length || 0,
    },
    summary,
    updatedAt: new Date().toISOString(),
    retainedSignals: {
      recovery: state.recovery.length,
      sleep: state.sleep.length,
      heart: state.heart.length,
    },
  });
}
