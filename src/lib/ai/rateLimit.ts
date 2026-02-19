const RATE_LIMIT_WINDOW_SECONDS = 60;
const RATE_LIMIT_MAX_REQUESTS = 40;

type MemoryRateEntry = {
  count: number;
  resetAt: number;
};

const memoryRateLimits = new Map<string, MemoryRateEntry>();

const getUpstashConfig = () => {
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) return null;
  return { url, token };
};

const inMemoryRateLimit = (key: string) => {
  const now = Date.now();
  const entry = memoryRateLimits.get(key);

  if (!entry || now >= entry.resetAt) {
    memoryRateLimits.set(key, {
      count: 1,
      resetAt: now + RATE_LIMIT_WINDOW_SECONDS * 1000,
    });
    return { allowed: true, remaining: RATE_LIMIT_MAX_REQUESTS - 1 };
  }

  if (entry.count >= RATE_LIMIT_MAX_REQUESTS) {
    return { allowed: false, remaining: 0 };
  }

  entry.count += 1;
  memoryRateLimits.set(key, entry);
  return { allowed: true, remaining: RATE_LIMIT_MAX_REQUESTS - entry.count };
};

const upstashRateLimit = async (key: string) => {
  const config = getUpstashConfig();
  if (!config) return null;

  const redisKey = `ai-rate:${key}`;
  const commandUrl = `${config.url}/pipeline`;

  // INCR + EXPIRE (best effort) + GET
  const body = JSON.stringify([
    ['INCR', redisKey],
    ['EXPIRE', redisKey, RATE_LIMIT_WINDOW_SECONDS],
    ['GET', redisKey],
  ]);

  const response = await fetch(commandUrl, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.token}`,
      'Content-Type': 'application/json',
    },
    body,
    cache: 'no-store',
  });

  if (!response.ok) {
    return null;
  }

  const payload = (await response.json()) as Array<{ result?: unknown }>;
  const countRaw = payload[2]?.result;
  const count = typeof countRaw === 'string' ? Number.parseInt(countRaw, 10) : Number(countRaw);
  if (!Number.isFinite(count)) return null;

  if (count > RATE_LIMIT_MAX_REQUESTS) {
    return { allowed: false, remaining: 0 };
  }

  return { allowed: true, remaining: RATE_LIMIT_MAX_REQUESTS - count };
};

export const rateLimit = {
  check: async (key: string): Promise<{ allowed: boolean; remaining: number }> => {
    try {
      const upstream = await upstashRateLimit(key);
      if (upstream) return upstream;
    } catch {
      // Fall through to in-memory limiter.
    }

    return inMemoryRateLimit(key);
  },
};
