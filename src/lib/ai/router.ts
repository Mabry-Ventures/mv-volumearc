import { modelRegistry } from '@/lib/ai/modelRegistry';
import type { AiEndpointName } from '@/lib/ai/costGuard';

const modelOrder = (endpoint: AiEndpointName): string[] => {
  const configured = modelRegistry.getConfiguredModels();

  if (endpoint === 'live-coach' || endpoint === 'parse-log') {
    return [configured.fast, configured.primary];
  }

  if (endpoint === 'transcribe') {
    return [configured.transcribe];
  }

  return [configured.primary, configured.fast];
};

export const aiRouter = {
  async withModelFallback<T>(
    endpoint: AiEndpointName,
    runner: (model: string) => Promise<T | null>
  ): Promise<{ value: T | null; modelTried: string[] }> {
    const tried: string[] = [];

    for (const model of modelOrder(endpoint)) {
      if (!modelRegistry.validateModelSyntax(model)) continue;

      tried.push(model);
      try {
        const value = await runner(model);
        if (value !== null) {
          return { value, modelTried: tried };
        }
      } catch {
        // Continue fallback chain.
      }
    }

    return { value: null, modelTried: tried };
  },
};
