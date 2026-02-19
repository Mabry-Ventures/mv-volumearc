import { NextResponse } from 'next/server';
import { aiFlags } from '@/lib/ai/flags';
import { enforceRateAndBudget, jsonError } from '@/lib/ai/http';
import { executeStructuredTask } from '@/lib/ai/execute';
import { aiFallbacks } from '@/lib/ai/fallbacks';
import { aiCache } from '@/lib/ai/cache';
import { baseSystemPrompt } from '@/lib/ai/prompts';
import {
  isAiLiveCoachRequest,
  parseAiLiveCoachResponse,
} from '@/lib/ai/schemas';

export const runtime = 'nodejs';

export async function POST(request: Request) {
  if (!aiFlags.liveCoach) {
    return jsonError('Live coach AI feature is disabled.', 503);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return jsonError('Invalid JSON payload.');
  }

  if (!isAiLiveCoachRequest(payload)) {
    return jsonError('Invalid live coach payload.');
  }

  const guard = await enforceRateAndBudget(
    request,
    'live-coach',
    JSON.stringify(payload).length
  );
  if (guard) return guard;

  const key = `live-coach:${payload.activeWorkout.id}:${payload.lastSet?.id || 'none'}`;
  const cached = aiCache.get<Record<string, unknown>>(key);
  if (cached) return NextResponse.json(cached);

  const systemPrompt = baseSystemPrompt('Provide the next set recommendation in-session.');
  const userPrompt = JSON.stringify(
    {
      trusted_context: {
        activeWorkout: payload.activeWorkout,
        lastSet: payload.lastSet,
        fatigueSignals: payload.fatigueSignals || {},
        digestLite: payload.fullHistoryDigestLite,
      },
      instructions: [
        'Recommend the next set with weight, reps, and rest.',
        'Lower recommendation confidence if data is incomplete.',
      ],
    },
    null,
    2
  );

  const fallback = aiFallbacks.liveCoach(
    payload.fullHistoryDigestLite.unit,
    payload.lastSet
      ? { weight: payload.lastSet.weight, reps: payload.lastSet.reps }
      : null
  );

  const result = await executeStructuredTask({
    endpoint: 'live-coach',
    schemaKey: 'liveCoach',
    systemPrompt,
    userPrompt,
    parseResponse: parseAiLiveCoachResponse,
    fallback: () => fallback,
  });

  const response = {
    ...result.value,
    model: result.model,
    fallbackReason: result.usedFallback
      ? 'ai_unavailable_or_invalid_response'
      : (result.value as { fallbackReason?: string }).fallbackReason,
  };

  aiCache.set(key, response, 1000 * 10);
  return NextResponse.json(response);
}
