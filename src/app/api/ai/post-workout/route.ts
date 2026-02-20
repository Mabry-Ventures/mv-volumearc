import { NextResponse } from 'next/server';
import { aiFlags } from '@/lib/ai/flags';
import { costGuard } from '@/lib/ai/costGuard';
import { enforceRateAndBudget, jsonError } from '@/lib/ai/http';
import { executeStructuredTask } from '@/lib/ai/execute';
import { aiFallbacks } from '@/lib/ai/fallbacks';
import { aiCache } from '@/lib/ai/cache';
import { baseSystemPrompt } from '@/lib/ai/prompts';
import { getActorIdFromRequest } from '@/lib/server/actor';
import {
  isAiPostWorkoutRequest,
  parseAiPostWorkoutResponse,
} from '@/lib/ai/schemas';

export const runtime = 'nodejs';

export async function POST(request: Request) {
  const actorId = getActorIdFromRequest(request);

  if (!aiFlags.postWorkout) {
    return jsonError('Post-workout AI feature is disabled.', 503);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return jsonError('Invalid JSON payload.');
  }

  if (!isAiPostWorkoutRequest(payload)) {
    return jsonError('Invalid post-workout payload.');
  }

  const guard = await enforceRateAndBudget(
    request,
    'post-workout',
    JSON.stringify(payload).length
  );
  if (guard) return guard;

  const pruned = costGuard.pruneDigestForBudget(payload.fullHistoryDigest, 'post-workout');
  const cacheKey = `post-workout:${payload.completedWorkout.id}`;

  const cached = aiCache.get<Record<string, unknown>>(cacheKey);
  if (cached) return NextResponse.json(cached);

  const systemPrompt = baseSystemPrompt('Generate concise post-workout insights and next-session guidance.');
  const userPrompt = JSON.stringify(
    {
      trusted_context: {
        completedWorkout: payload.completedWorkout,
        fullHistoryDigest: pruned.digest,
      },
      instructions: [
        'Summarize outcomes, identify likely PR candidates, and provide practical next-session adjustments.',
      ],
    },
    null,
    2
  );

  const result = await executeStructuredTask({
    endpoint: 'post-workout',
    schemaKey: 'postWorkout',
    systemPrompt,
    userPrompt,
    parseResponse: parseAiPostWorkoutResponse,
    fallback: () => aiFallbacks.postWorkout(payload.completedWorkout),
    actorId,
  });

  const response = {
    actorId,
    ...result.value,
    model: result.model,
    fallbackReason: result.usedFallback
      ? 'ai_unavailable_or_invalid_response'
      : (result.value as { fallbackReason?: string }).fallbackReason,
    contextPruned: pruned.wasPruned,
  };

  aiCache.set(cacheKey, response, 1000 * 60 * 60 * 24);
  return NextResponse.json(response);
}
