import type { Entitlement } from '@/types';

const toFloat = (value: string | undefined, fallback: number): number => {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
};

export const getEntitlementForActor = (_actorId: string): Entitlement => {
  const tier = (process.env.BEAST_MODE_TIER || 'free') as Entitlement['tier'];

  if (tier === 'pro') {
    return {
      tier,
      aiEnabled: true,
      liveCoachEnabled: true,
      syncEnabled: true,
      maxDailyAiUsd: toFloat(process.env.BEAST_MODE_DAILY_AI_BUDGET_USD, 10),
      maxMonthlyAiUsd: toFloat(process.env.BEAST_MODE_MONTHLY_AI_BUDGET_USD, 120),
      supportLevel: 'priority',
    };
  }

  if (tier === 'team') {
    return {
      tier,
      aiEnabled: true,
      liveCoachEnabled: true,
      syncEnabled: true,
      maxDailyAiUsd: toFloat(process.env.BEAST_MODE_DAILY_AI_BUDGET_USD, 30),
      maxMonthlyAiUsd: toFloat(process.env.BEAST_MODE_MONTHLY_AI_BUDGET_USD, 600),
      supportLevel: 'priority',
    };
  }

  return {
    tier: 'free',
    aiEnabled: true,
    liveCoachEnabled: true,
    syncEnabled: false,
    maxDailyAiUsd: toFloat(process.env.BEAST_MODE_DAILY_AI_BUDGET_USD, 2),
    maxMonthlyAiUsd: toFloat(process.env.BEAST_MODE_MONTHLY_AI_BUDGET_USD, 30),
    supportLevel: 'community',
  };
};
