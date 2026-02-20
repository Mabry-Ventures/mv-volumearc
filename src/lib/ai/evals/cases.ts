import type { AiEvalCase } from '@/types';

export const aiEvalCases: AiEvalCase[] = [
  {
    id: 'schema-workout-plan-001',
    category: 'workout-plan-schema',
    input: {
      workoutName: 'Upper Strength',
      warmup: ['Bike 5m'],
      exercises: [
        {
          exerciseId: 'bench-press',
          exerciseName: 'Bench Press',
          category: 'barbell',
          muscleGroups: ['chest'],
          sets: 4,
          reps: 5,
          targetWeight: 185,
          unit: 'lbs',
          restSeconds: 120,
        },
      ],
      cooldown: ['Stretch 5m'],
      notes: ['Progressive overload'],
    },
    expected: { valid: true },
    threshold: 1,
  },
  {
    id: 'live-coach-quality-001',
    category: 'live-coach-quality',
    input: {
      nextSet: { weight: 200, reps: 5, restSeconds: 120, unit: 'lbs' },
      confidence: 0.82,
      rationale: ['Steady progression while preserving form.'],
    },
    expected: { minConfidence: 0.5, maxWeightJump: 15 },
    threshold: 0.7,
  },
  {
    id: 'parse-log-accuracy-001',
    category: 'parse-log-accuracy',
    input: {
      text: 'Bench 3x5 185, row 3x10 95',
      parsed: {
        exercises: [
          { exerciseName: 'Bench Press', sets: [{ reps: 5, weight: 185, unit: 'lbs' }] },
          { exerciseName: 'Barbell Row', sets: [{ reps: 10, weight: 95, unit: 'lbs' }] },
        ],
      },
    },
    expected: { minExercises: 2 },
    threshold: 0.85,
  },
  {
    id: 'risk-consistency-001',
    category: 'risk-consistency',
    input: {
      plateauRisk: { score: 0.42, level: 'medium' },
      overtrainingRisk: { score: 0.31, level: 'low' },
      recommendedActions: ['Add one rest day'],
    },
    expected: { scoreRange: [0, 1] },
    threshold: 1,
  },
];
