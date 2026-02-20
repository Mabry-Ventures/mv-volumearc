import { v4 as uuidv4 } from 'uuid';
import type { SetActionType, UiInteractionEvent, WorkoutFlowStage } from '@/types';

const STORAGE_KEY = 'beast-mode-ui-events';
const MAX_EVENTS = 300;

const readEvents = (): UiInteractionEvent[] => {
  if (typeof window === 'undefined') return [];

  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];

    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      event =>
        typeof event === 'object' &&
        event !== null &&
        typeof (event as { id?: unknown }).id === 'string'
    ) as UiInteractionEvent[];
  } catch {
    return [];
  }
};

const writeEvents = (events: UiInteractionEvent[]) => {
  if (typeof window === 'undefined') return;

  localStorage.setItem(STORAGE_KEY, JSON.stringify(events.slice(-MAX_EVENTS)));
};

const shipEvent = async (event: UiInteractionEvent): Promise<void> => {
  if (typeof window === 'undefined') return;

  try {
    await fetch('/api/telemetry/ingest', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ uiEvents: [event] }),
      keepalive: true,
    });
  } catch {
    // Best-effort telemetry.
  }
};

export const uiAnalytics = {
  track(params: {
    stage: WorkoutFlowStage;
    action: string;
    elapsedMs?: number;
    metadata?: Record<string, string | number | boolean | null>;
  }): UiInteractionEvent {
    const event: UiInteractionEvent = {
      id: uuidv4(),
      version: '1.0.0',
      stage: params.stage,
      action: params.action,
      elapsedMs: params.elapsedMs,
      metadata: params.metadata,
      createdAt: new Date().toISOString(),
    };

    const events = readEvents();
    events.push(event);
    writeEvents(events);
    void shipEvent(event);
    return event;
  },

  trackSetAction(action: SetActionType, metadata?: Record<string, string | number | boolean | null>) {
    return uiAnalytics.track({
      stage: 'workout_active',
      action,
      metadata,
    });
  },

  getEvents(): UiInteractionEvent[] {
    return readEvents();
  },
};
