import { NextResponse } from 'next/server';
import { aiFlags } from '@/lib/ai/flags';
import { costGuard } from '@/lib/ai/costGuard';
import { enforceRateAndBudget, jsonError } from '@/lib/ai/http';
import { executeStructuredTask } from '@/lib/ai/execute';
import { aiFallbacks } from '@/lib/ai/fallbacks';
import { aiCache } from '@/lib/ai/cache';
import { baseSystemPrompt } from '@/lib/ai/prompts';
import {
  isAiWorkoutPlanRequest,
  parseAiWorkoutPlanResponse,
} from '@/lib/ai/schemas';
import { digestFingerprint } from '@/lib/ai/contextBuilder';

export const runtime = 'nodejs';

export async function POST(request: Request) {
  if (!aiFlags.workoutPlan) {
    return jsonError('Workout plan AI feature is disabled.', 503);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return jsonError('Invalid JSON payload.');
  }

  if (!isAiWorkoutPlanRequest(payload)) {
    return jsonError('Invalid workout plan request payload.');
  }

  const guard = await enforceRateAndBudget(
    request,
    'workout-plan',
    JSON.stringify(payload).length
  );
  if (guard) return guard;

  const pruned = costGuard.pruneDigestForBudget(payload.fullHistoryDigest, 'workout-plan');

  const cacheKey = `workout-plan:${digestFingerprint(pruned.digest)}:${payload.goal}:${payload.durationMinutes}`;
  const cached = aiCache.get<ReturnType<typeof aiFallbacks.workoutPlan>>(cacheKey);
  if (cached) {
    return NextResponse.json(cached);
  }

  const systemPrompt = baseSystemPrompt('Build a safe, progressive workout plan.');
  const userPrompt = JSON.stringify(
    {
      trusted_context: {
        durationMinutes: payload.durationMinutes,
        fullHistoryDigest: pruned.digest,
      },
      user_constraints: {
        goal: payload.goal,
        equipment: payload.equipment,
        constraints: payload.constraints,
      },
      instructions: [
        'Use realistic load targets and rest periods.',
        'Prefer compound movements first unless constraints conflict.',
      ],
    },
    null,
    2
  );

  const result = await executeStructuredTask({
    endpoint: 'workout-plan',
    schemaKey: 'workoutPlan',
    systemPrompt,
    userPrompt,
    parseResponse: parseAiWorkoutPlanResponse,
    fallback: () => aiFallbacks.workoutPlan({ ...payload, fullHistoryDigest: pruned.digest }),
  });

  const response = {
    ...result.value,
    model: result.model,
    fallbackReason: result.usedFallback
      ? 'ai_unavailable_or_invalid_response'
      : (result.value as { fallbackReason?: string }).fallbackReason,
    contextPruned: pruned.wasPruned,
  };

  aiCache.set(cacheKey, response, 1000 * 60 * 60 * 6);
  return NextResponse.json(response);
}
