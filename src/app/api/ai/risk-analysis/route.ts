import { NextResponse } from 'next/server';
import { aiFlags } from '@/lib/ai/flags';
import { costGuard } from '@/lib/ai/costGuard';
import { enforceRateAndBudget, jsonError } from '@/lib/ai/http';
import { executeStructuredTask } from '@/lib/ai/execute';
import { aiFallbacks } from '@/lib/ai/fallbacks';
import { aiCache } from '@/lib/ai/cache';
import { baseSystemPrompt } from '@/lib/ai/prompts';
import {
  isAiRiskAnalysisRequest,
  parseAiRiskAnalysisResponse,
} from '@/lib/ai/schemas';
import { digestFingerprint } from '@/lib/ai/contextBuilder';
import { getActorIdFromRequest } from '@/lib/server/actor';
import { integrationStore } from '@/lib/server/integrationStore';

export const runtime = 'nodejs';

export async function POST(request: Request) {
  const actorId = getActorIdFromRequest(request);

  if (!aiFlags.riskAnalysis) {
    return jsonError('Risk analysis AI feature is disabled.', 503);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return jsonError('Invalid JSON payload.');
  }

  if (!isAiRiskAnalysisRequest(payload)) {
    return jsonError('Invalid risk-analysis payload.');
  }

  const guard = await enforceRateAndBudget(
    request,
    'risk-analysis',
    JSON.stringify(payload).length
  );
  if (guard) return guard;

  const pruned = costGuard.pruneDigestForBudget(payload.fullHistoryDigest, 'risk-analysis');
  const cacheKey = `risk:${digestFingerprint(pruned.digest)}:${payload.trendWindows.join('-')}`;
  const cached = aiCache.get<Record<string, unknown>>(cacheKey);
  if (cached) return NextResponse.json(cached);

  const recoverySummary = integrationStore.getSummary(actorId);

  const systemPrompt = baseSystemPrompt('Analyze plateau and overtraining risk with actionable guidance.');
  const userPrompt = JSON.stringify(
    {
      trusted_context: {
        fullHistoryDigest: pruned.digest,
        trendWindows: payload.trendWindows,
        recoverySummary,
      },
      instructions: [
        'Provide risk scores between 0 and 1 with conservative labeling.',
        'Focus recommendations on training load, recovery, and exercise rotation.',
      ],
    },
    null,
    2
  );

  const result = await executeStructuredTask({
    endpoint: 'risk-analysis',
    schemaKey: 'riskAnalysis',
    systemPrompt,
    userPrompt,
    parseResponse: parseAiRiskAnalysisResponse,
    fallback: () => aiFallbacks.riskAnalysis(),
    actorId,
  });

  const recoveryPenalty =
    recoverySummary.recoveryAverage !== null ? Math.max(0, 0.6 - recoverySummary.recoveryAverage) * 0.5 : 0;
  const sleepPenalty =
    recoverySummary.sleepAverageHours !== null ? Math.max(0, 7 - recoverySummary.sleepAverageHours) * 0.04 : 0;
  const enrichedPlateauScore = Math.min(
    1,
    result.value.plateauRisk.score + recoveryPenalty + sleepPenalty
  );
  const enrichedOvertrainingScore = Math.min(
    1,
    result.value.overtrainingRisk.score + recoveryPenalty + sleepPenalty
  );

  const toLevel = (score: number): 'low' | 'medium' | 'high' => {
    if (score >= 0.67) return 'high';
    if (score >= 0.34) return 'medium';
    return 'low';
  };

  const response = {
    actorId,
    ...result.value,
    plateauRisk: {
      ...result.value.plateauRisk,
      score: Number(enrichedPlateauScore.toFixed(3)),
      level: toLevel(enrichedPlateauScore),
    },
    overtrainingRisk: {
      ...result.value.overtrainingRisk,
      score: Number(enrichedOvertrainingScore.toFixed(3)),
      level: toLevel(enrichedOvertrainingScore),
    },
    model: result.model,
    recoverySummary,
    fallbackReason: result.usedFallback
      ? 'ai_unavailable_or_invalid_response'
      : (result.value as { fallbackReason?: string }).fallbackReason,
    contextPruned: pruned.wasPruned,
  };

  aiCache.set(cacheKey, response, 1000 * 60 * 60 * 24);
  return NextResponse.json(response);
}
