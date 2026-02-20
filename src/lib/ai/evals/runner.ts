import type { AiEvalResult } from '@/types';
import { aiEvalCases } from '@/lib/ai/evals/cases';

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const evaluateWorkoutPlanSchema = (input: unknown): AiEvalResult => {
  const valid =
    isObject(input) &&
    typeof input.workoutName === 'string' &&
    Array.isArray(input.warmup) &&
    Array.isArray(input.exercises) &&
    Array.isArray(input.cooldown) &&
    Array.isArray(input.notes);

  return {
    caseId: 'schema-workout-plan-001',
    category: 'workout-plan-schema',
    passed: valid,
    score: valid ? 1 : 0,
    details: valid ? 'Workout plan schema is valid.' : 'Workout plan schema invalid.',
  };
};

const evaluateLiveCoachQuality = (input: unknown): AiEvalResult => {
  if (!isObject(input) || !isObject(input.nextSet)) {
    return {
      caseId: 'live-coach-quality-001',
      category: 'live-coach-quality',
      passed: false,
      score: 0,
      details: 'Live coach response missing nextSet.',
    };
  }

  const confidence = typeof input.confidence === 'number' ? input.confidence : 0;
  const reps = typeof input.nextSet.reps === 'number' ? input.nextSet.reps : 0;
  const weight = typeof input.nextSet.weight === 'number' ? input.nextSet.weight : 0;

  const score =
    (confidence >= 0.5 ? 0.5 : 0) +
    (reps >= 1 ? 0.25 : 0) +
    (weight >= 0 ? 0.25 : 0);

  return {
    caseId: 'live-coach-quality-001',
    category: 'live-coach-quality',
    passed: score >= 0.7,
    score,
    details: `Live coach quality score ${score.toFixed(2)}.`,
  };
};

const evaluateParseLogAccuracy = (input: unknown): AiEvalResult => {
  if (!isObject(input) || !isObject(input.parsed) || !Array.isArray(input.parsed.exercises)) {
    return {
      caseId: 'parse-log-accuracy-001',
      category: 'parse-log-accuracy',
      passed: false,
      score: 0,
      details: 'Parse-log output missing exercises.',
    };
  }

  const exerciseCount = input.parsed.exercises.length;
  const score = Math.min(1, exerciseCount / 2);

  return {
    caseId: 'parse-log-accuracy-001',
    category: 'parse-log-accuracy',
    passed: score >= 0.85,
    score,
    details: `Detected ${exerciseCount} exercises.`,
  };
};

const evaluateRiskConsistency = (input: unknown): AiEvalResult => {
  if (!isObject(input) || !isObject(input.plateauRisk) || !isObject(input.overtrainingRisk)) {
    return {
      caseId: 'risk-consistency-001',
      category: 'risk-consistency',
      passed: false,
      score: 0,
      details: 'Risk payload missing structures.',
    };
  }

  const plateau = typeof input.plateauRisk.score === 'number' && input.plateauRisk.score >= 0 && input.plateauRisk.score <= 1;
  const overtraining = typeof input.overtrainingRisk.score === 'number' && input.overtrainingRisk.score >= 0 && input.overtrainingRisk.score <= 1;
  const score = plateau && overtraining ? 1 : 0;

  return {
    caseId: 'risk-consistency-001',
    category: 'risk-consistency',
    passed: score === 1,
    score,
    details: score === 1 ? 'Risk scores within expected range.' : 'Risk scores out of range.',
  };
};

export const runAiEvalSuite = (): {
  results: AiEvalResult[];
  summary: {
    total: number;
    passed: number;
    failed: number;
    schemaValidity: number;
    parseLogAccuracy: number;
    liveCoachCalibration: number;
  };
} => {
  const results: AiEvalResult[] = [];

  for (const evalCase of aiEvalCases) {
    if (evalCase.category === 'workout-plan-schema') {
      results.push(evaluateWorkoutPlanSchema(evalCase.input));
      continue;
    }

    if (evalCase.category === 'live-coach-quality') {
      results.push(evaluateLiveCoachQuality(evalCase.input));
      continue;
    }

    if (evalCase.category === 'parse-log-accuracy') {
      results.push(evaluateParseLogAccuracy(evalCase.input));
      continue;
    }

    results.push(evaluateRiskConsistency(evalCase.input));
  }

  const passed = results.filter(result => result.passed).length;
  const failed = results.length - passed;

  const schemaValidity = results
    .filter(result => result.category === 'workout-plan-schema')
    .reduce((sum, result, _, arr) => sum + result.score / Math.max(1, arr.length), 0);

  const parseLogAccuracy = results
    .filter(result => result.category === 'parse-log-accuracy')
    .reduce((sum, result, _, arr) => sum + result.score / Math.max(1, arr.length), 0);

  const liveCoachCalibration = results
    .filter(result => result.category === 'live-coach-quality')
    .reduce((sum, result, _, arr) => sum + result.score / Math.max(1, arr.length), 0);

  return {
    results,
    summary: {
      total: results.length,
      passed,
      failed,
      schemaValidity,
      parseLogAccuracy,
      liveCoachCalibration,
    },
  };
};
