import { v4 as uuidv4 } from 'uuid';
import type {
  AiFallbackEvent,
  AiLatencyEvent,
  UiInteractionEvent,
  WorkoutFunnelEvent,
} from '@/types';
import type { UsageEndpoint } from '@/lib/server/usageLedger';

type DashboardSummary = {
  generatedAt: string;
  counts: {
    uiEvents: number;
    funnelEvents: number;
    aiLatencyEvents: number;
    aiFallbackEvents: number;
  };
  kpis: {
    setLogLatencyMs: { p50: number | null; p95: number | null };
    liveCoachLatencyMs: { p50: number | null; p95: number | null };
    aiFallbackRate: number;
    dailyActiveUsers: number;
    day7RetentionRate: number;
  };
};

const MAX_EVENTS = 10000;

const uiEvents: UiInteractionEvent[] = [];
const funnelEvents: WorkoutFunnelEvent[] = [];
const aiLatencyEvents: AiLatencyEvent[] = [];
const aiFallbackEvents: AiFallbackEvent[] = [];

const boundedPush = <T>(arr: T[], value: T) => {
  arr.push(value);
  if (arr.length > MAX_EVENTS) {
    arr.splice(0, arr.length - MAX_EVENTS);
  }
};

const percentile = (values: number[], p: number): number | null => {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[index];
};

const toDayKey = (date: string) => date.slice(0, 10);

export const telemetryStore = {
  ingestUiEvents(events: UiInteractionEvent[], fallbackActorId?: string): number {
    events.forEach(event => {
      const normalized: UiInteractionEvent = {
        ...event,
        id: event.id || uuidv4(),
        version: event.version || '1.0.0',
        actorId: event.actorId || fallbackActorId,
        createdAt: event.createdAt || new Date().toISOString(),
      };
      boundedPush(uiEvents, normalized);
    });
    return events.length;
  },

  ingestFunnelEvents(events: WorkoutFunnelEvent[]): number {
    events.forEach(event => {
      boundedPush(funnelEvents, {
        ...event,
        id: event.id || uuidv4(),
        createdAt: event.createdAt || new Date().toISOString(),
      });
    });
    return events.length;
  },

  recordAiLatency(params: {
    actorId: string;
    endpoint: UsageEndpoint;
    model: string;
    latencyMs: number;
  }) {
    const event: AiLatencyEvent = {
      id: uuidv4(),
      actorId: params.actorId,
      endpoint: params.endpoint,
      model: params.model,
      latencyMs: params.latencyMs,
      createdAt: new Date().toISOString(),
    };

    boundedPush(aiLatencyEvents, event);
    return event;
  },

  recordAiFallback(params: {
    actorId: string;
    endpoint: UsageEndpoint;
    reason: string;
  }) {
    const event: AiFallbackEvent = {
      id: uuidv4(),
      actorId: params.actorId,
      endpoint: params.endpoint,
      reason: params.reason,
      createdAt: new Date().toISOString(),
    };
    boundedPush(aiFallbackEvents, event);
    return event;
  },

  getDashboardSummary(): DashboardSummary {
    const setLatencies = uiEvents
      .filter(event => event.action === 'set_complete_toggle' && typeof event.elapsedMs === 'number')
      .map(event => event.elapsedMs as number)
      .filter(value => Number.isFinite(value) && value >= 0);

    const liveCoachLatencies = aiLatencyEvents
      .filter(event => event.endpoint === 'live-coach')
      .map(event => event.latencyMs)
      .filter(value => Number.isFinite(value) && value >= 0);

    const totalAiRequests = aiLatencyEvents.length;
    const fallbackRate =
      totalAiRequests === 0 ? 0 : aiFallbackEvents.length / Math.max(1, totalAiRequests);

    const actorsToday = new Set<string>();
    const dayToActors = new Map<string, Set<string>>();
    const todayKey = toDayKey(new Date().toISOString());
    const day7Key = toDayKey(new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString());

    uiEvents.forEach(event => {
      const actorId = event.actorId || 'anonymous';
      const dayKey = toDayKey(event.createdAt);

      if (dayKey === todayKey) {
        actorsToday.add(actorId);
      }

      const set = dayToActors.get(dayKey) || new Set<string>();
      set.add(actorId);
      dayToActors.set(dayKey, set);
    });

    const day7Actors = dayToActors.get(day7Key) || new Set<string>();
    const retained = Array.from(day7Actors).filter(actor => actorsToday.has(actor)).length;
    const day7RetentionRate =
      day7Actors.size === 0 ? 0 : retained / Math.max(1, day7Actors.size);

    return {
      generatedAt: new Date().toISOString(),
      counts: {
        uiEvents: uiEvents.length,
        funnelEvents: funnelEvents.length,
        aiLatencyEvents: aiLatencyEvents.length,
        aiFallbackEvents: aiFallbackEvents.length,
      },
      kpis: {
        setLogLatencyMs: {
          p50: percentile(setLatencies, 50),
          p95: percentile(setLatencies, 95),
        },
        liveCoachLatencyMs: {
          p50: percentile(liveCoachLatencies, 50),
          p95: percentile(liveCoachLatencies, 95),
        },
        aiFallbackRate: Number(fallbackRate.toFixed(4)),
        dailyActiveUsers: actorsToday.size,
        day7RetentionRate: Number(day7RetentionRate.toFixed(4)),
      },
    };
  },
};
