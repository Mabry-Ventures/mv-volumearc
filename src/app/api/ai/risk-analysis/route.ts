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

export const runtime = 'nodejs';

export async function POST(request: Request) {
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

  const systemPrompt = baseSystemPrompt('Analyze plateau and overtraining risk with actionable guidance.');
  const userPrompt = JSON.stringify(
    {
      trusted_context: {
        fullHistoryDigest: pruned.digest,
        trendWindows: payload.trendWindows,
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
  });

  const response = {
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
