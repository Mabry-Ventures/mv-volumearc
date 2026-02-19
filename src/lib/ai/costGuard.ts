import type { AiHistoryDigest } from '@/types';

export type AiEndpointName =
  | 'workout-plan'
  | 'live-coach'
  | 'post-workout'
  | 'risk-analysis'
  | 'parse-log'
  | 'transcribe';

const ENDPOINT_MAX_INPUT_CHARS: Record<AiEndpointName, number> = {
  'workout-plan': 20000,
  'live-coach': 9000,
  'post-workout': 18000,
  'risk-analysis': 16000,
  'parse-log': 12000,
  transcribe: 2000,
};

const ENDPOINT_MAX_OUTPUT_TOKENS: Record<AiEndpointName, number> = {
  'workout-plan': 1000,
  'live-coach': 400,
  'post-workout': 700,
  'risk-analysis': 600,
  'parse-log': 600,
  transcribe: 500,
};

const DAILY_BUDGET_DEFAULT_USD = 2;
const COST_PER_1K_TOKENS_ESTIMATE_USD = 0.01;

const budgetLedger = new Map<string, { dayKey: string; usd: number }>();

const getDayKey = () => new Date().toISOString().slice(0, 10);

const approximateCostUsd = (inputChars: number, outputChars = 0): number => {
  // Rough estimate: ~4 chars/token.
  const tokenEstimate = (inputChars + outputChars) / 4;
  return (tokenEstimate / 1000) * COST_PER_1K_TOKENS_ESTIMATE_USD;
};

export const costGuard = {
  getOutputTokenLimit: (endpoint: AiEndpointName): number => ENDPOINT_MAX_OUTPUT_TOKENS[endpoint],

  pruneDigestForBudget: (
    digest: AiHistoryDigest,
    endpoint: AiEndpointName
  ): { digest: AiHistoryDigest; wasPruned: boolean } => {
    const budget = ENDPOINT_MAX_INPUT_CHARS[endpoint];

    const clone: AiHistoryDigest = {
      ...digest,
      exerciseTrends: [...digest.exerciseTrends],
      recentWorkouts: [...digest.recentWorkouts],
    };

    let wasPruned = false;

    const serializeLength = (): number => JSON.stringify(clone).length;

    while (serializeLength() > budget && clone.recentWorkouts.length > 4) {
      clone.recentWorkouts.pop();
      wasPruned = true;
    }

    while (serializeLength() > budget && clone.exerciseTrends.length > 6) {
      clone.exerciseTrends.pop();
      wasPruned = true;
    }

    if (serializeLength() > budget) {
      clone.exerciseTrends = clone.exerciseTrends.slice(0, 4);
      clone.recentWorkouts = clone.recentWorkouts.slice(0, 4);
      wasPruned = true;
    }

    return { digest: clone, wasPruned };
  },

  canSpendForIp: (ip: string, inputChars: number, requestedBudgetUsd?: number): boolean => {
    const dayKey = getDayKey();
    const budgetLimit =
      typeof requestedBudgetUsd === 'number' && requestedBudgetUsd >= 0
        ? requestedBudgetUsd
        : DAILY_BUDGET_DEFAULT_USD;

    const estimated = approximateCostUsd(inputChars);
    const existing = budgetLedger.get(ip);

    if (!existing || existing.dayKey !== dayKey) {
      budgetLedger.set(ip, { dayKey, usd: estimated });
      return estimated <= budgetLimit;
    }

    if (existing.usd + estimated > budgetLimit) return false;

    existing.usd += estimated;
    budgetLedger.set(ip, existing);
    return true;
  },
};
