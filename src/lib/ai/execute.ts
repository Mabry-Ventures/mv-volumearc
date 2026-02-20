import { aiRouter } from '@/lib/ai/router';
import { costGuard, type AiEndpointName } from '@/lib/ai/costGuard';
import { openaiClient } from '@/lib/ai/openaiClient';
import { AI_PROMPT_VERSION, AI_SCHEMA_VERSION, aiOutputSchemas } from '@/lib/ai/schemas';
import { telemetryExporter } from '@/lib/server/telemetryExporter';
import { telemetryStore } from '@/lib/server/telemetryStore';
import { usageLedger } from '@/lib/server/usageLedger';

export const executeStructuredTask = async <T>(params: {
  endpoint: AiEndpointName;
  schemaKey: keyof typeof aiOutputSchemas;
  systemPrompt: string;
  userPrompt: string;
  parseResponse: (value: unknown) => T | null;
  fallback: () => T;
  actorId?: string;
}): Promise<{ value: T; model: string; usedFallback: boolean }> => {
  const schema = aiOutputSchemas[params.schemaKey];
  const maxOutputTokens = costGuard.getOutputTokenLimit(params.endpoint);
  const startedAt = Date.now();

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

      const normalizedUsage = response.usage || {
        inputTokens: 0,
        outputTokens: 0,
        totalTokens: 0,
      };

      if (params.actorId) {
        usageLedger.record(params.actorId, params.endpoint, normalizedUsage);
      }

      const withUsage = {
        ...(parsed as Record<string, unknown>),
        tokenUsage: normalizedUsage,
        audit: {
          promptVersion: AI_PROMPT_VERSION,
          schemaVersion: AI_SCHEMA_VERSION,
          model,
          generatedAt: new Date().toISOString(),
        },
      } as T;

      return withUsage;
    }
  );

  const modelUsed = modelTried[modelTried.length - 1] || 'unknown';
  if (params.actorId) {
    telemetryStore.recordAiLatency({
      actorId: params.actorId,
      endpoint: params.endpoint,
      model: modelUsed,
      latencyMs: Date.now() - startedAt,
    });
    void telemetryExporter.exportDashboard('ai-latency', params.actorId);
  }

  if (value !== null) {
    return { value, model: modelUsed, usedFallback: false };
  }

  if (params.actorId) {
    telemetryStore.recordAiFallback({
      actorId: params.actorId,
      endpoint: params.endpoint,
      reason: 'ai_unavailable_or_invalid_response',
    });
    void telemetryExporter.exportDashboard('ai-fallback', params.actorId);
  }

  return {
    value: params.fallback(),
    model: modelTried.join(',') || 'deterministic-fallback',
    usedFallback: true,
  };
};
