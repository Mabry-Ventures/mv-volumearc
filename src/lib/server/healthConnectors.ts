import type { HrSignal, RecoverySignal, SleepSignal } from '@/types';

export type HealthProvider = 'oura' | 'generic-json';

type PullParams = {
  provider: HealthProvider;
  accessToken: string;
  startDate?: string;
  endDate?: string;
  genericUrl?: string;
};

type PullResult = {
  recovery: RecoverySignal[];
  sleep: SleepSignal[];
  heart: HrSignal[];
};

const toIsoDate = (value: unknown): string | null => {
  if (typeof value !== 'string') return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
};

const toNumber = (value: unknown): number | null => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return null;
  return numeric;
};

const clamp = (value: number, min = 0, max = 1): number => Math.max(min, Math.min(max, value));
const notNull = <T>(value: T | null): value is T => value !== null;

const safeJson = async (response: Response): Promise<Record<string, unknown> | null> => {
  try {
    const payload = (await response.json()) as unknown;
    if (typeof payload !== 'object' || payload === null) return null;
    return payload as Record<string, unknown>;
  } catch {
    return null;
  }
};

const pullFromOura = async (params: PullParams): Promise<PullResult> => {
  const start = params.startDate || new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const end = params.endDate || new Date().toISOString().slice(0, 10);
  const base = process.env.OURA_API_BASE_URL?.trim() || 'https://api.oura.com/v2/usercollection';
  const headers = {
    Authorization: `Bearer ${params.accessToken}`,
    'Content-Type': 'application/json',
  };

  const [readinessRes, sleepRes, heartRes] = await Promise.all([
    fetch(`${base}/daily_readiness?start_date=${start}&end_date=${end}`, { headers, cache: 'no-store' }),
    fetch(`${base}/daily_sleep?start_date=${start}&end_date=${end}`, { headers, cache: 'no-store' }),
    fetch(`${base}/heartrate?start_datetime=${start}T00:00:00Z&end_datetime=${end}T23:59:59Z`, {
      headers,
      cache: 'no-store',
    }),
  ]);

  if (!readinessRes.ok && !sleepRes.ok && !heartRes.ok) {
    throw new Error('Unable to read data from Oura endpoints.');
  }

  const readinessPayload = readinessRes.ok ? await safeJson(readinessRes) : null;
  const sleepPayload = sleepRes.ok ? await safeJson(sleepRes) : null;
  const heartPayload = heartRes.ok ? await safeJson(heartRes) : null;

  const readinessRows = Array.isArray(readinessPayload?.data) ? readinessPayload.data : [];
  const sleepRows = Array.isArray(sleepPayload?.data) ? sleepPayload.data : [];
  const heartRows = Array.isArray(heartPayload?.data) ? heartPayload.data : [];

  const recovery: RecoverySignal[] = readinessRows
    .map(row => {
      if (typeof row !== 'object' || row === null) return null;
      const recordedAt =
        toIsoDate((row as { day?: unknown }).day) ||
        toIsoDate((row as { timestamp?: unknown }).timestamp);
      const scoreRaw =
        toNumber((row as { score?: unknown }).score) ??
        toNumber((row as { readiness_score?: unknown }).readiness_score);
      if (!recordedAt || scoreRaw === null) return null;
      const score = scoreRaw > 1 ? clamp(scoreRaw / 100) : clamp(scoreRaw);
      return { recordedAt, score, source: 'wearable' as const };
    })
    .filter(notNull);

  const sleep: SleepSignal[] = sleepRows
    .map(row => {
      if (typeof row !== 'object' || row === null) return null;
      const recordedAt =
        toIsoDate((row as { day?: unknown }).day) ||
        toIsoDate((row as { timestamp?: unknown }).timestamp);
      const totalSleepSeconds =
        toNumber((row as { total_sleep_duration?: unknown }).total_sleep_duration) ??
        toNumber((row as { duration?: unknown }).duration);
      const qualityRaw =
        toNumber((row as { score?: unknown }).score) ??
        toNumber((row as { sleep_score?: unknown }).sleep_score);
      if (!recordedAt || totalSleepSeconds === null) return null;
      return {
        recordedAt,
        durationHours: Math.max(0, totalSleepSeconds / 3600),
        qualityScore: qualityRaw === null ? undefined : qualityRaw > 1 ? clamp(qualityRaw / 100) : clamp(qualityRaw),
        source: 'wearable' as const,
      };
    })
    .filter(notNull);

  const heart: HrSignal[] = heartRows
    .map(row => {
      if (typeof row !== 'object' || row === null) return null;
      const recordedAt = toIsoDate((row as { timestamp?: unknown }).timestamp);
      if (!recordedAt) return null;
      return {
        recordedAt,
        restingHr: toNumber((row as { bpm?: unknown }).bpm) ?? undefined,
        hrvMs: toNumber((row as { hrv?: unknown }).hrv) ?? undefined,
        source: 'wearable' as const,
      };
    })
    .filter(notNull);

  return { recovery, sleep, heart };
};

const pullFromGenericJson = async (params: PullParams): Promise<PullResult> => {
  const target = params.genericUrl?.trim();
  if (!target) {
    throw new Error('genericUrl is required for generic-json provider.');
  }

  const response = await fetch(target, {
    headers: { Authorization: `Bearer ${params.accessToken}` },
    cache: 'no-store',
  });

  if (!response.ok) {
    throw new Error(`Generic provider request failed (${response.status}).`);
  }

  const payload = await safeJson(response);
  if (!payload) return { recovery: [], sleep: [], heart: [] };

  const recoveryRows = Array.isArray(payload.recovery) ? payload.recovery : [];
  const sleepRows = Array.isArray(payload.sleep) ? payload.sleep : [];
  const heartRows = Array.isArray(payload.heart) ? payload.heart : [];

  const recovery: RecoverySignal[] = recoveryRows
    .map(row => {
      if (typeof row !== 'object' || row === null) return null;
      const recordedAt = toIsoDate((row as { recordedAt?: unknown }).recordedAt);
      const scoreRaw = toNumber((row as { score?: unknown }).score);
      if (!recordedAt || scoreRaw === null) return null;
      return {
        recordedAt,
        score: scoreRaw > 1 ? clamp(scoreRaw / 100) : clamp(scoreRaw),
        source: 'wearable' as const,
      };
    })
    .filter(notNull);

  const sleep: SleepSignal[] = sleepRows
    .map(row => {
      if (typeof row !== 'object' || row === null) return null;
      const recordedAt = toIsoDate((row as { recordedAt?: unknown }).recordedAt);
      const durationHours = toNumber((row as { durationHours?: unknown }).durationHours);
      const quality = toNumber((row as { qualityScore?: unknown }).qualityScore);
      if (!recordedAt || durationHours === null) return null;
      return {
        recordedAt,
        durationHours,
        qualityScore: quality === null ? undefined : clamp(quality > 1 ? quality / 100 : quality),
        source: 'wearable' as const,
      };
    })
    .filter(notNull);

  const heart: HrSignal[] = heartRows
    .map(row => {
      if (typeof row !== 'object' || row === null) return null;
      const recordedAt = toIsoDate((row as { recordedAt?: unknown }).recordedAt);
      if (!recordedAt) return null;
      return {
        recordedAt,
        restingHr: toNumber((row as { restingHr?: unknown }).restingHr) ?? undefined,
        hrvMs: toNumber((row as { hrvMs?: unknown }).hrvMs) ?? undefined,
        source: 'wearable' as const,
      };
    })
    .filter(notNull);

  return { recovery, sleep, heart };
};

export const healthConnectors = {
  async pullSignals(params: PullParams): Promise<PullResult> {
    if (params.provider === 'oura') {
      return pullFromOura(params);
    }

    return pullFromGenericJson(params);
  },
};
