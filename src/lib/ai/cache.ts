type CacheEntry<T> = {
  expiresAt: number;
  value: T;
};

const cacheStore = new Map<string, CacheEntry<unknown>>();

export const aiCache = {
  get<T>(key: string): T | null {
    const entry = cacheStore.get(key);
    if (!entry) return null;

    if (Date.now() > entry.expiresAt) {
      cacheStore.delete(key);
      return null;
    }

    return entry.value as T;
  },

  set<T>(key: string, value: T, ttlMs: number): void {
    cacheStore.set(key, {
      value,
      expiresAt: Date.now() + ttlMs,
    });
  },
};
