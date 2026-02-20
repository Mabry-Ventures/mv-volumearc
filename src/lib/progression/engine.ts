import type { AiHistoryDigest, ProgressionBlock, ProgressionDecisionReason, TargetSetUpdate } from '@/types';

const roundToIncrement = (value: number, increment: number) =>
  Math.round(value / increment) * increment;

const buildReasons = (params: {
  plateauScore: number;
  overtrainingScore: number;
  hasRecentProgress: boolean;
}): ProgressionDecisionReason[] => {
  const reasons: ProgressionDecisionReason[] = [];

  if (params.overtrainingScore >= 0.65) {
    reasons.push({
      code: 'recovery_low',
      detail: 'Recovery signals suggest reducing progression speed this week.',
    });
  }

  if (params.plateauScore >= 0.55) {
    reasons.push({
      code: 'plateau_risk',
      detail: 'Plateau risk elevated; use micro-load increases and rep quality focus.',
    });
  }

  if (params.hasRecentProgress) {
    reasons.push({
      code: 'volume_up',
      detail: 'Recent trend supports a small progression increase.',
    });
  } else {
    reasons.push({
      code: 'stable_progress',
      detail: 'Maintain stable loads and progress via rep quality.',
    });
  }

  return reasons;
};

const buildUpdate = (params: {
  exerciseId: string;
  exerciseName: string;
  topWeight: number;
  topReps: number;
  unit: 'lbs' | 'kg';
  plateauScore: number;
  overtrainingScore: number;
}): TargetSetUpdate => {
  const heavyFatigue = params.overtrainingScore >= 0.65;
  const plateau = params.plateauScore >= 0.55;

  const baseIncrement = params.unit === 'lbs' ? 5 : 2.5;

  let nextWeight = params.topWeight;
  let nextReps = params.topReps;

  if (heavyFatigue) {
    nextWeight = Math.max(0, params.topWeight * 0.95);
    nextReps = Math.max(1, params.topReps - 1);
  } else if (plateau) {
    nextWeight = params.topWeight + baseIncrement * 0.5;
    nextReps = params.topReps;
  } else {
    nextWeight = params.topWeight + baseIncrement;
    nextReps = Math.max(1, params.topReps + (params.topReps < 8 ? 1 : 0));
  }

  nextWeight = roundToIncrement(nextWeight, baseIncrement * 0.5);

  return {
    exerciseId: params.exerciseId,
    exerciseName: params.exerciseName,
    currentTarget: {
      reps: params.topReps,
      weight: params.topWeight,
      unit: params.unit,
    },
    nextTarget: {
      reps: nextReps,
      weight: Math.max(0, nextWeight),
      unit: params.unit,
    },
    confidence: heavyFatigue ? 0.62 : plateau ? 0.74 : 0.82,
    reasons: buildReasons({
      plateauScore: params.plateauScore,
      overtrainingScore: params.overtrainingScore,
      hasRecentProgress: !plateau && !heavyFatigue,
    }),
  };
};

export const buildProgressionBlock = (digest: AiHistoryDigest): ProgressionBlock => {
  const plateauScore = digest.fatigueSignals.plateauScore;
  const overtrainingScore = digest.fatigueSignals.overtrainingScore;

  const updates = digest.exerciseTrends
    .slice(0, 8)
    .map(trend => {
      const topWeight = trend.topSet?.weight ?? trend.latestSet?.weight ?? 0;
      const topReps = trend.topSet?.reps ?? trend.latestSet?.reps ?? 8;

      return buildUpdate({
        exerciseId: trend.exerciseId,
        exerciseName: trend.exerciseName,
        topWeight,
        topReps,
        unit: digest.unit,
        plateauScore,
        overtrainingScore,
      });
    });

  return {
    generatedAt: new Date().toISOString(),
    blockName: plateauScore >= 0.55 ? 'Stability + Recovery Block' : 'Progressive Overload Block',
    durationWeeks: 1,
    updates,
    deloadRecommended: overtrainingScore >= 0.7,
    notes: [
      'Use RPE and form quality to adjust each target in-session.',
      'If sleep or soreness worsens, keep loads stable and prioritize technique.',
    ],
  };
};
