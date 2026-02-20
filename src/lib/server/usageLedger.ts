import type { AiTokenUsage } from '@/types';

export type UsageEndpoint =
  | 'workout-plan'
  | 'live-coach'
  | 'post-workout'
  | 'risk-analysis'
  | 'parse-log'
  | 'transcribe'
  | 'progression-plan';

type DailyUsage = {
  dayKey: string;
  totalUsd: number;
  tokenUsage: AiTokenUsage;
  endpointCounts: Partial<Record<UsageEndpoint, number>>;
};

const ledger = new Map<string, DailyUsage>();

const COST_PER_1K_TOKENS_USD = 0.01;
const getDayKey = () => new Date().toISOString().slice(0, 10);

const estimateCostUsd = (usage: AiTokenUsage): number =>
  (usage.totalTokens / 1000) * COST_PER_1K_TOKENS_USD;

const emptyUsage = (): AiTokenUsage => ({
  inputTokens: 0,
  outputTokens: 0,
  totalTokens: 0,
});

export const usageLedger = {
  record(actorId: string, endpoint: UsageEndpoint, usage: AiTokenUsage): { totalUsd: number } {
    const dayKey = getDayKey();
    const cost = estimateCostUsd(usage);
    const existing = ledger.get(actorId);

    if (!existing || existing.dayKey !== dayKey) {
      ledger.set(actorId, {
        dayKey,
        totalUsd: cost,
        tokenUsage: {
          inputTokens: usage.inputTokens,
          outputTokens: usage.outputTokens,
          totalTokens: usage.totalTokens,
        },
        endpointCounts: { [endpoint]: 1 },
      });
      return { totalUsd: cost };
    }

    existing.totalUsd += cost;
    existing.tokenUsage.inputTokens += usage.inputTokens;
    existing.tokenUsage.outputTokens += usage.outputTokens;
    existing.tokenUsage.totalTokens += usage.totalTokens;
    existing.endpointCounts[endpoint] = (existing.endpointCounts[endpoint] || 0) + 1;
    ledger.set(actorId, existing);

    return { totalUsd: existing.totalUsd };
  },

  get(actorId: string): DailyUsage {
    const dayKey = getDayKey();
    const current = ledger.get(actorId);
    if (current && current.dayKey === dayKey) return current;

    return {
      dayKey,
      totalUsd: 0,
      tokenUsage: emptyUsage(),
      endpointCounts: {},
    };
  },

  canSpend(actorId: string, budgetUsd: number): boolean {
    return usageLedger.get(actorId).totalUsd < budgetUsd;
  },
};
