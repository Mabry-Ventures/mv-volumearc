const OPENAI_MODELS_ENDPOINT = 'https://api.openai.com/v1/models';

const DEFAULT_MODELS = {
  primary: process.env.OPENAI_MODEL_PRIMARY || 'gpt-5',
  fast: process.env.OPENAI_MODEL_FAST || 'gpt-5-mini',
  transcribe: process.env.OPENAI_MODEL_TRANSCRIBE || 'gpt-4o-mini-transcribe',
  embed: process.env.OPENAI_MODEL_EMBED || 'text-embedding-3-small',
} as const;

const ALLOWED_MODEL_PREFIXES = ['gpt-', 'o', 'text-embedding-'];

type ModelCatalogCache = {
  fetchedAt: number;
  models: Set<string>;
};

const modelCache: { value: ModelCatalogCache | null } = { value: null };
const MODEL_CACHE_TTL_MS = 1000 * 60 * 10;

const isAllowedModel = (model: string): boolean => {
  return ALLOWED_MODEL_PREFIXES.some(prefix => model.startsWith(prefix));
};

const getApiKey = (): string | null => {
  const key = process.env.OPENAI_API_KEY;
  return key && key.trim().length > 0 ? key : null;
};

const fetchModelCatalog = async (): Promise<Set<string> | null> => {
  const key = getApiKey();
  if (!key) return null;

  const now = Date.now();
  if (modelCache.value && now - modelCache.value.fetchedAt < MODEL_CACHE_TTL_MS) {
    return modelCache.value.models;
  }

  const response = await fetch(OPENAI_MODELS_ENDPOINT, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${key}`,
    },
    cache: 'no-store',
  });

  if (!response.ok) {
    return null;
  }

  const payload = (await response.json()) as { data?: Array<{ id?: string }> };
  const models = new Set(
    (payload.data || [])
      .map(item => item.id)
      .filter((id): id is string => typeof id === 'string')
  );

  modelCache.value = { fetchedAt: now, models };
  return models;
};

export const modelRegistry = {
  getConfiguredModels: () => DEFAULT_MODELS,

  validateModelSyntax: (model: string): boolean => isAllowedModel(model),

  validateConfiguredModels: async (): Promise<{
    primary: boolean;
    fast: boolean;
    transcribe: boolean;
  }> => {
    const configured = modelRegistry.getConfiguredModels();
    const catalog = await fetchModelCatalog();

    // If catalog is unavailable, fall back to syntax-only checks.
    if (!catalog) {
      return {
        primary: isAllowedModel(configured.primary),
        fast: isAllowedModel(configured.fast),
        transcribe: isAllowedModel(configured.transcribe),
      };
    }

    return {
      primary: catalog.has(configured.primary),
      fast: catalog.has(configured.fast),
      transcribe: catalog.has(configured.transcribe),
    };
  },
};
