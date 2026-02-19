import { modelRegistry } from '@/lib/ai/modelRegistry';

type JsonSchemaConfig = {
  name: string;
  schema: {
    type: 'object';
    properties: Record<string, unknown>;
    required: string[];
    additionalProperties: boolean;
  };
};

const OPENAI_RESPONSES_ENDPOINT = 'https://api.openai.com/v1/responses';
const OPENAI_TRANSCRIBE_ENDPOINT = 'https://api.openai.com/v1/audio/transcriptions';

let hasValidatedModelAvailability = false;

const getApiKey = (): string | null => {
  const key = process.env.OPENAI_API_KEY;
  return key && key.trim().length > 0 ? key : null;
};

const parseResponseText = (payload: Record<string, unknown>): string | null => {
  if (typeof payload.output_text === 'string' && payload.output_text.trim().length > 0) {
    return payload.output_text;
  }

  if (Array.isArray(payload.output)) {
    const text = payload.output
      .flatMap(item => {
        if (
          typeof item === 'object' &&
          item !== null &&
          Array.isArray((item as { content?: unknown }).content)
        ) {
          return ((item as { content: unknown[] }).content || []).flatMap(content => {
            if (
              typeof content === 'object' &&
              content !== null &&
              typeof (content as { text?: unknown }).text === 'string'
            ) {
              return (content as { text: string }).text;
            }
            return [];
          });
        }
        return [];
      })
      .join('\n')
      .trim();

    return text.length > 0 ? text : null;
  }

  return null;
};

const parseUsage = (payload: Record<string, unknown>) => {
  const usage = payload.usage;
  if (typeof usage !== 'object' || usage === null) return undefined;

  const input = Number((usage as { input_tokens?: unknown }).input_tokens || 0);
  const output = Number((usage as { output_tokens?: unknown }).output_tokens || 0);
  const total = Number((usage as { total_tokens?: unknown }).total_tokens || input + output);

  return {
    inputTokens: Number.isFinite(input) ? input : 0,
    outputTokens: Number.isFinite(output) ? output : 0,
    totalTokens: Number.isFinite(total) ? total : 0,
  };
};

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

const postWithRetry = async (
  url: string,
  init: RequestInit,
  maxAttempts = 2
): Promise<Response> => {
  let lastError: unknown = null;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const response = await fetch(url, init);
      if (response.ok) return response;

      if (response.status >= 500 && attempt < maxAttempts) {
        await sleep(150 * attempt);
        continue;
      }

      return response;
    } catch (error) {
      lastError = error;
      if (attempt < maxAttempts) {
        await sleep(150 * attempt);
      }
    }
  }

  throw lastError instanceof Error ? lastError : new Error('OpenAI request failed');
};

const ensureModelValidation = async () => {
  if (hasValidatedModelAvailability) return;
  hasValidatedModelAvailability = true;

  try {
    const result = await modelRegistry.validateConfiguredModels();
    if (!result.primary || !result.fast || !result.transcribe) {
      console.warn('One or more configured OpenAI models are not listed in /v1/models');
    }
  } catch {
    // Non-fatal validation check.
  }
};

export const openaiClient = {
  isConfigured: (): boolean => getApiKey() !== null,

  createStructuredResponse: async (
    model: string,
    systemPrompt: string,
    userPrompt: string,
    schema: JsonSchemaConfig,
    maxOutputTokens = 600
  ): Promise<{
    content: unknown;
    model: string;
    usage?: { inputTokens: number; outputTokens: number; totalTokens: number };
  } | null> => {
    const apiKey = getApiKey();
    if (!apiKey) return null;

    await ensureModelValidation();

    const response = await postWithRetry(OPENAI_RESPONSES_ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        instructions: systemPrompt,
        input: userPrompt,
        max_output_tokens: maxOutputTokens,
        text: {
          format: {
            type: 'json_schema',
            name: schema.name,
            schema: schema.schema,
            strict: true,
          },
        },
      }),
      cache: 'no-store',
    });

    if (!response.ok) {
      return null;
    }

    const payload = (await response.json()) as Record<string, unknown>;
    const outputText = parseResponseText(payload);
    if (!outputText) return null;

    try {
      return {
        content: JSON.parse(outputText),
        model:
          typeof payload.model === 'string' && payload.model.length > 0
            ? payload.model
            : model,
        usage: parseUsage(payload),
      };
    } catch {
      return null;
    }
  },

  transcribeAudio: async (
    file: File,
    language?: string
  ): Promise<{ text: string; durationSeconds?: number } | null> => {
    const apiKey = getApiKey();
    if (!apiKey) return null;

    await ensureModelValidation();

    const transcribeModel = modelRegistry.getConfiguredModels().transcribe;
    const formData = new FormData();
    formData.append('file', file);
    formData.append('model', transcribeModel);
    if (language && language.trim().length > 0) {
      formData.append('language', language);
    }

    const response = await postWithRetry(OPENAI_TRANSCRIBE_ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
      },
      body: formData,
      cache: 'no-store',
    });

    if (!response.ok) return null;

    const payload = (await response.json()) as {
      text?: string;
      duration?: number;
    };

    if (typeof payload.text !== 'string') return null;

    return {
      text: payload.text,
      durationSeconds:
        typeof payload.duration === 'number' && Number.isFinite(payload.duration)
          ? payload.duration
          : undefined,
    };
  },
};
