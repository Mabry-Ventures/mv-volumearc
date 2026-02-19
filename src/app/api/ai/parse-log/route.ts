import { NextResponse } from 'next/server';
import { aiFlags } from '@/lib/ai/flags';
import { enforceRateAndBudget, jsonError } from '@/lib/ai/http';
import { executeStructuredTask } from '@/lib/ai/execute';
import { aiFallbacks } from '@/lib/ai/fallbacks';
import { baseSystemPrompt } from '@/lib/ai/prompts';
import {
  isAiParseLogRequest,
  parseAiParseLogResponse,
} from '@/lib/ai/schemas';

export const runtime = 'nodejs';

export async function POST(request: Request) {
  if (!aiFlags.logParser) {
    return jsonError('Log parser AI feature is disabled.', 503);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return jsonError('Invalid JSON payload.');
  }

  if (!isAiParseLogRequest(payload)) {
    return jsonError('Invalid log parser payload.');
  }

  const guard = await enforceRateAndBudget(
    request,
    'parse-log',
    JSON.stringify(payload).length
  );
  if (guard) return guard;

  const systemPrompt = baseSystemPrompt('Parse workout notes into structured exercises and sets.');
  const userPrompt = JSON.stringify(
    {
      trusted_context: {
        sessionContext: payload.sessionContext || null,
      },
      user_text: payload.text,
      instructions: [
        'Extract exercises and set details when available.',
        'If uncertain, lower confidence and include notes for manual review.',
      ],
    },
    null,
    2
  );

  const result = await executeStructuredTask({
    endpoint: 'parse-log',
    schemaKey: 'parseLog',
    systemPrompt,
    userPrompt,
    parseResponse: parseAiParseLogResponse,
    fallback: () => aiFallbacks.parseLog(payload.text),
  });

  const response = {
    ...result.value,
    model: result.model,
    fallbackReason: result.usedFallback
      ? 'ai_unavailable_or_invalid_response'
      : (result.value as { fallbackReason?: string }).fallbackReason,
  };

  return NextResponse.json(response);
}
