import { NextResponse } from 'next/server';
import type { AiHistoryDigest } from '@/types';
import { buildProgressionBlock } from '@/lib/progression/engine';
import { enforceRateAndBudget, jsonError } from '@/lib/ai/http';
import { getActorIdFromRequest } from '@/lib/server/actor';
import { aiFlags } from '@/lib/ai/flags';
import { featureFlags } from '@/lib/flags';

export const runtime = 'nodejs';

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const isAiHistoryDigest = (value: unknown): value is AiHistoryDigest => {
  if (!isObject(value)) return false;
  return (
    typeof value.generatedAt === 'string' &&
    (value.unit === 'lbs' || value.unit === 'kg') &&
    typeof value.totalWorkouts === 'number' &&
    Array.isArray(value.exerciseTrends) &&
    isObject(value.fatigueSignals)
  );
};

export async function POST(request: Request) {
  if (!aiFlags.progressionPlan) {
    return jsonError('Progression plan AI feature is disabled.', 503);
  }
  if (!featureFlags.progressionAutopilot) {
    return jsonError('Progression autopilot is currently disabled.', 503);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return jsonError('Invalid progression payload.', 400);
  }

  if (!isObject(payload) || !isAiHistoryDigest(payload.fullHistoryDigest)) {
    return jsonError('Invalid progression payload.', 400);
  }

  const guard = await enforceRateAndBudget(
    request,
    'progression-plan',
    JSON.stringify(payload).length
  );
  if (guard) return guard;

  const actorId = getActorIdFromRequest(request);
  const block = buildProgressionBlock(payload.fullHistoryDigest);

  return NextResponse.json({
    actorId,
    progression: block,
    generatedAt: new Date().toISOString(),
  });
}
