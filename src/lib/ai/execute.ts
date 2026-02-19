import { aiRouter } from '@/lib/ai/router';
import { costGuard, type AiEndpointName } from '@/lib/ai/costGuard';
import { openaiClient } from '@/lib/ai/openaiClient';
import { aiOutputSchemas } from '@/lib/ai/schemas';

export const executeStructuredTask = async <T>(params: {
  endpoint: AiEndpointName;
  schemaKey: keyof typeof aiOutputSchemas;
  systemPrompt: string;
  userPrompt: string;
  parseResponse: (value: unknown) => T | null;
  fallback: () => T;
}): Promise<{ value: T; model: string; usedFallback: boolean }> => {
  const schema = aiOutputSchemas[params.schemaKey];
  const maxOutputTokens = costGuard.getOutputTokenLimit(params.endpoint);

  const { value, modelTried } = await aiRouter.withModelFallback(
    params.endpoint,
    async model => {
      const response = await openaiClient.createStructuredResponse(
        model,
        params.systemPrompt,
        params.userPrompt,
        schema,
        maxOutputTokens
      );

      if (!response) return null;
      const parsed = params.parseResponse(response.content);
      if (!parsed) return null;

      const withUsage = {
        ...(parsed as Record<string, unknown>),
        tokenUsage: response.usage,
      } as T;

      return withUsage;
    }
  );

  if (value !== null) {
    return { value, model: modelTried[modelTried.length - 1] || 'unknown', usedFallback: false };
  }

  return {
    value: params.fallback(),
    model: modelTried.join(',') || 'deterministic-fallback',
    usedFallback: true,
  };
};
