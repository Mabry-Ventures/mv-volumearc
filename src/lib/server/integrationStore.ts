import type { HrSignal, RecoverySignal, SleepSignal } from '@/types';

type ActorIntegrationState = {
  recovery: RecoverySignal[];
  sleep: SleepSignal[];
  heart: HrSignal[];
};

const store = new Map<string, ActorIntegrationState>();

const getState = (actorId: string): ActorIntegrationState => {
  const existing = store.get(actorId);
  if (existing) return existing;

  const created: ActorIntegrationState = {
    recovery: [],
    sleep: [],
    heart: [],
  };

  store.set(actorId, created);
  return created;
};

const toRecent = <T extends { recordedAt: string }>(items: T[], limit = 30): T[] => {
  return [...items]
    .sort((a, b) => new Date(b.recordedAt).getTime() - new Date(a.recordedAt).getTime())
    .slice(0, limit);
};

export const integrationStore = {
  importSignals(
    actorId: string,
    payload: {
      recovery?: RecoverySignal[];
      sleep?: SleepSignal[];
      heart?: HrSignal[];
    }
  ) {
    const state = getState(actorId);

    if (payload.recovery) {
      state.recovery = toRecent([...state.recovery, ...payload.recovery]);
    }

    if (payload.sleep) {
      state.sleep = toRecent([...state.sleep, ...payload.sleep]);
    }

    if (payload.heart) {
      state.heart = toRecent([...state.heart, ...payload.heart]);
    }

    store.set(actorId, state);
    return state;
  },

  getSummary(actorId: string): {
    recoveryAverage: number | null;
    sleepAverageHours: number | null;
    restingHrAverage: number | null;
  } {
    const state = getState(actorId);

    const recoveryAverage =
      state.recovery.length === 0
        ? null
        : state.recovery.reduce((sum, signal) => sum + signal.score, 0) /
          state.recovery.length;

    const sleepAverageHours =
      state.sleep.length === 0
        ? null
        : state.sleep.reduce((sum, signal) => sum + signal.durationHours, 0) /
          state.sleep.length;

    const restingHrValues = state.heart
      .map(signal => signal.restingHr)
      .filter((value): value is number => typeof value === 'number' && Number.isFinite(value));

    const restingHrAverage =
      restingHrValues.length === 0
        ? null
        : restingHrValues.reduce((sum, value) => sum + value, 0) / restingHrValues.length;

    return {
      recoveryAverage,
      sleepAverageHours,
      restingHrAverage,
    };
  },
};
