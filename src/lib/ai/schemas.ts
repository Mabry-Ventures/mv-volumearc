import type {
  AiLiveCoachRequest,
  AiLiveCoachResponse,
  AiParseLogRequest,
  AiParseLogResponse,
  AiPostWorkoutRequest,
  AiPostWorkoutResponse,
  AiRiskAnalysisRequest,
  AiRiskAnalysisResponse,
  AiWorkoutPlanRequest,
  AiWorkoutPlanResponse,
} from '@/types';

type JsonSchema = {
  type: 'object';
  properties: Record<string, unknown>;
  required: string[];
  additionalProperties: boolean;
};

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const isString = (value: unknown): value is string => typeof value === 'string';

const isFiniteNumber = (value: unknown): value is number =>
  typeof value === 'number' && Number.isFinite(value);

const isStringArray = (value: unknown): value is string[] =>
  Array.isArray(value) && value.every(isString);

const isUnit = (value: unknown): value is 'lbs' | 'kg' => value === 'lbs' || value === 'kg';

const EXERCISE_CATEGORIES = [
  'barbell',
  'dumbbell',
  'machine',
  'bodyweight',
  'cable',
  'cardio',
] as const;

const MUSCLE_GROUPS = [
  'chest',
  'back',
  'shoulders',
  'biceps',
  'triceps',
  'legs',
  'glutes',
  'core',
  'forearms',
  'calves',
] as const;

const isExerciseCategory = (
  value: unknown
): value is (typeof EXERCISE_CATEGORIES)[number] =>
  isString(value) &&
  (EXERCISE_CATEGORIES as readonly string[]).includes(value);

const isMuscleGroup = (value: unknown): value is (typeof MUSCLE_GROUPS)[number] =>
  isString(value) && (MUSCLE_GROUPS as readonly string[]).includes(value);

const parseBoundedNumber = (
  value: unknown,
  min = 0,
  max = Number.POSITIVE_INFINITY
): number | null => {
  if (!isFiniteNumber(value)) return null;
  if (value < min || value > max) return null;
  return value;
};

export const AI_SCHEMA_VERSION = '1.0.0';
export const AI_PROMPT_VERSION = '1.0.0';

export const aiOutputSchemas: Record<
  'workoutPlan' | 'liveCoach' | 'postWorkout' | 'riskAnalysis' | 'parseLog',
  { name: string; schema: JsonSchema }
> = {
  workoutPlan: {
    name: 'workout_plan',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['workoutName', 'warmup', 'exercises', 'cooldown', 'notes'],
      properties: {
        workoutName: { type: 'string' },
        warmup: { type: 'array', items: { type: 'string' } },
        cooldown: { type: 'array', items: { type: 'string' } },
        notes: { type: 'array', items: { type: 'string' } },
        exercises: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            required: [
              'exerciseId',
              'exerciseName',
              'category',
              'muscleGroups',
              'sets',
              'reps',
              'targetWeight',
              'unit',
              'restSeconds',
            ],
            properties: {
              exerciseId: { type: 'string' },
              exerciseName: { type: 'string' },
              category: { type: 'string' },
              muscleGroups: { type: 'array', items: { type: 'string' } },
              sets: { type: 'number' },
              reps: { type: 'number' },
              targetWeight: { type: 'number' },
              unit: { type: 'string' },
              restSeconds: { type: 'number' },
              notes: { type: 'string' },
            },
          },
        },
      },
    },
  },
  liveCoach: {
    name: 'live_coach',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['nextSet', 'confidence', 'rationale'],
      properties: {
        nextSet: {
          type: 'object',
          additionalProperties: false,
          required: ['weight', 'reps', 'restSeconds', 'unit'],
          properties: {
            weight: { type: 'number' },
            reps: { type: 'number' },
            restSeconds: { type: 'number' },
            unit: { type: 'string' },
          },
        },
        confidence: { type: 'number' },
        rationale: { type: 'array', items: { type: 'string' } },
        caution: { type: 'string' },
      },
    },
  },
  postWorkout: {
    name: 'post_workout',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: [
        'generatedAt',
        'model',
        'summary',
        'keyWins',
        'prCandidates',
        'nextSessionRecommendation',
      ],
      properties: {
        generatedAt: { type: 'string' },
        model: { type: 'string' },
        summary: { type: 'string' },
        keyWins: { type: 'array', items: { type: 'string' } },
        prCandidates: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['exerciseId', 'exerciseName', 'newBest'],
            properties: {
              exerciseId: { type: 'string' },
              exerciseName: { type: 'string' },
              previousBest: { type: 'object' },
              newBest: { type: 'object' },
            },
          },
        },
        nextSessionRecommendation: {
          type: 'object',
          additionalProperties: false,
          required: ['focus', 'rationale', 'adjustments'],
          properties: {
            focus: { type: 'string' },
            rationale: { type: 'string' },
            adjustments: { type: 'array', items: { type: 'string' } },
          },
        },
      },
    },
  },
  riskAnalysis: {
    name: 'risk_analysis',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['plateauRisk', 'overtrainingRisk', 'recommendedActions'],
      properties: {
        plateauRisk: {
          type: 'object',
          additionalProperties: false,
          required: ['score', 'level', 'reasons'],
          properties: {
            score: { type: 'number' },
            level: { type: 'string' },
            reasons: { type: 'array', items: { type: 'string' } },
          },
        },
        overtrainingRisk: {
          type: 'object',
          additionalProperties: false,
          required: ['score', 'level', 'reasons'],
          properties: {
            score: { type: 'number' },
            level: { type: 'string' },
            reasons: { type: 'array', items: { type: 'string' } },
          },
        },
        recommendedActions: { type: 'array', items: { type: 'string' } },
      },
    },
  },
  parseLog: {
    name: 'parse_log',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['confidence', 'exercises', 'notes'],
      properties: {
        confidence: { type: 'number' },
        notes: { type: 'array', items: { type: 'string' } },
        exercises: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['exerciseName', 'sets'],
            properties: {
              exerciseId: { type: 'string' },
              exerciseName: { type: 'string' },
              category: { type: 'string' },
              muscleGroups: { type: 'array', items: { type: 'string' } },
              notes: { type: 'string' },
              sets: {
                type: 'array',
                items: {
                  type: 'object',
                  additionalProperties: false,
                  required: ['reps', 'weight', 'unit'],
                  properties: {
                    reps: { type: 'number' },
                    weight: { type: 'number' },
                    unit: { type: 'string' },
                    completed: { type: 'boolean' },
                    rpe: { type: 'number' },
                  },
                },
              },
            },
          },
        },
      },
    },
  },
};

export const isAiWorkoutPlanRequest = (value: unknown): value is AiWorkoutPlanRequest => {
  if (!isObject(value)) return false;
  return (
    isString(value.goal) &&
    isFiniteNumber(value.durationMinutes) &&
    value.durationMinutes > 0 &&
    Array.isArray(value.equipment) &&
    value.equipment.every(isString) &&
    Array.isArray(value.constraints) &&
    value.constraints.every(isString) &&
    isObject(value.fullHistoryDigest)
  );
};

export const isAiLiveCoachRequest = (value: unknown): value is AiLiveCoachRequest => {
  if (!isObject(value)) return false;
  return isObject(value.activeWorkout) && isObject(value.fullHistoryDigestLite);
};

export const isAiPostWorkoutRequest = (value: unknown): value is AiPostWorkoutRequest => {
  if (!isObject(value)) return false;
  return isObject(value.completedWorkout) && isObject(value.fullHistoryDigest);
};

export const isAiRiskAnalysisRequest = (value: unknown): value is AiRiskAnalysisRequest => {
  if (!isObject(value)) return false;
  if (!isObject(value.fullHistoryDigest)) return false;
  if (!Array.isArray(value.trendWindows)) return false;

  return value.trendWindows.every(window => window === 7 || window === 30 || window === 90);
};

export const isAiParseLogRequest = (value: unknown): value is AiParseLogRequest => {
  if (!isObject(value)) return false;
  if (!isString(value.text)) return false;

  return value.sessionContext === undefined || value.sessionContext === null || isObject(value.sessionContext);
};

export const parseAiWorkoutPlanResponse = (value: unknown): AiWorkoutPlanResponse | null => {
  if (!isObject(value)) return null;
  if (!isString(value.workoutName)) return null;
  if (!isStringArray(value.warmup)) return null;
  if (!isStringArray(value.cooldown)) return null;
  if (!isStringArray(value.notes)) return null;
  if (!Array.isArray(value.exercises)) return null;

  const exercises = value.exercises
    .map(entry => {
      if (!isObject(entry)) return null;
      const sets = parseBoundedNumber(entry.sets, 1, 20);
      const reps = parseBoundedNumber(entry.reps, 1, 100);
      const targetWeight = parseBoundedNumber(entry.targetWeight, 0, 5000);
      const restSeconds = parseBoundedNumber(entry.restSeconds, 15, 600);
      if (!isString(entry.exerciseId) || !isString(entry.exerciseName)) return null;
      if (!isExerciseCategory(entry.category)) return null;
      if (!Array.isArray(entry.muscleGroups) || !entry.muscleGroups.every(isMuscleGroup)) return null;
      if (sets === null || reps === null || targetWeight === null || restSeconds === null) return null;
      if (!isUnit(entry.unit)) return null;

      return {
        exerciseId: entry.exerciseId,
        exerciseName: entry.exerciseName,
        category: entry.category,
        muscleGroups: entry.muscleGroups,
        sets,
        reps,
        targetWeight,
        unit: entry.unit,
        restSeconds,
        notes: isString(entry.notes) ? entry.notes : undefined,
      };
    })
    .filter(entry => entry !== null) as AiWorkoutPlanResponse['exercises'];

  if (exercises.length === 0) return null;

  return {
    workoutName: value.workoutName,
    warmup: value.warmup,
    cooldown: value.cooldown,
    notes: value.notes,
    exercises,
  };
};

export const parseAiLiveCoachResponse = (value: unknown): AiLiveCoachResponse | null => {
  if (!isObject(value)) return null;
  if (!isObject(value.nextSet)) return null;

  const reps = parseBoundedNumber(value.nextSet.reps, 1, 100);
  const weight = parseBoundedNumber(value.nextSet.weight, 0, 5000);
  const restSeconds = parseBoundedNumber(value.nextSet.restSeconds, 15, 600);
  const confidence = parseBoundedNumber(value.confidence, 0, 1);
  if (reps === null || weight === null || restSeconds === null || confidence === null) return null;
  if (!isUnit(value.nextSet.unit)) return null;
  if (!isStringArray(value.rationale)) return null;

  return {
    nextSet: {
      reps,
      weight,
      restSeconds,
      unit: value.nextSet.unit,
    },
    confidence,
    rationale: value.rationale,
    caution: isString(value.caution) ? value.caution : undefined,
  };
};

export const parseAiPostWorkoutResponse = (value: unknown): AiPostWorkoutResponse | null => {
  if (!isObject(value)) return null;
  if (!isString(value.generatedAt) || !isString(value.model) || !isString(value.summary)) return null;
  if (!isStringArray(value.keyWins)) return null;
  if (!Array.isArray(value.prCandidates)) return null;
  if (!isObject(value.nextSessionRecommendation)) return null;
  if (
    !isString(value.nextSessionRecommendation.focus) ||
    !isString(value.nextSessionRecommendation.rationale) ||
    !isStringArray(value.nextSessionRecommendation.adjustments)
  ) {
    return null;
  }

  const prCandidates = value.prCandidates
    .map(candidate => {
      if (!isObject(candidate)) return null;
      if (!isString(candidate.exerciseId) || !isString(candidate.exerciseName)) return null;
      if (!isObject(candidate.newBest)) return null;
      if (
        !isFiniteNumber(candidate.newBest.weight) ||
        !isFiniteNumber(candidate.newBest.reps) ||
        !isUnit(candidate.newBest.unit)
      ) {
        return null;
      }

      let previousBest: AiPostWorkoutResponse['prCandidates'][number]['previousBest'];
      if (isObject(candidate.previousBest)) {
        if (
          isFiniteNumber(candidate.previousBest.weight) &&
          isFiniteNumber(candidate.previousBest.reps) &&
          isUnit(candidate.previousBest.unit)
        ) {
          previousBest = {
            weight: candidate.previousBest.weight,
            reps: candidate.previousBest.reps,
            unit: candidate.previousBest.unit,
            date: isString(candidate.previousBest.date) ? candidate.previousBest.date : undefined,
          };
        }
      }

      return {
        exerciseId: candidate.exerciseId,
        exerciseName: candidate.exerciseName,
        previousBest,
        newBest: {
          weight: candidate.newBest.weight,
          reps: candidate.newBest.reps,
          unit: candidate.newBest.unit,
        },
      };
    })
    .filter(candidate => candidate !== null) as AiPostWorkoutResponse['prCandidates'];

  return {
    generatedAt: value.generatedAt,
    model: value.model,
    summary: value.summary,
    keyWins: value.keyWins,
    prCandidates,
    nextSessionRecommendation: {
      focus: value.nextSessionRecommendation.focus,
      rationale: value.nextSessionRecommendation.rationale,
      adjustments: value.nextSessionRecommendation.adjustments,
    },
  };
};

export const parseAiRiskAnalysisResponse = (value: unknown): AiRiskAnalysisResponse | null => {
  if (!isObject(value)) return null;
  if (!isObject(value.plateauRisk) || !isObject(value.overtrainingRisk)) return null;
  if (!isStringArray(value.recommendedActions)) return null;

  const plateauScore = parseBoundedNumber(value.plateauRisk.score, 0, 1);
  const overtrainingScore = parseBoundedNumber(value.overtrainingRisk.score, 0, 1);
  if (plateauScore === null || overtrainingScore === null) return null;
  if (!isStringArray(value.plateauRisk.reasons) || !isStringArray(value.overtrainingRisk.reasons)) return null;

  const isLevel = (level: unknown): level is 'low' | 'medium' | 'high' =>
    level === 'low' || level === 'medium' || level === 'high';

  if (!isLevel(value.plateauRisk.level) || !isLevel(value.overtrainingRisk.level)) return null;

  return {
    plateauRisk: {
      score: plateauScore,
      level: value.plateauRisk.level,
      reasons: value.plateauRisk.reasons,
    },
    overtrainingRisk: {
      score: overtrainingScore,
      level: value.overtrainingRisk.level,
      reasons: value.overtrainingRisk.reasons,
    },
    recommendedActions: value.recommendedActions,
  };
};

export const parseAiParseLogResponse = (value: unknown): AiParseLogResponse | null => {
  if (!isObject(value)) return null;
  const confidence = parseBoundedNumber(value.confidence, 0, 1);
  if (confidence === null) return null;
  if (!isStringArray(value.notes)) return null;
  if (!Array.isArray(value.exercises)) return null;

  const exercises = value.exercises
    .map(entry => {
      if (!isObject(entry)) return null;
      if (!isString(entry.exerciseName)) return null;
      if (!Array.isArray(entry.sets)) return null;

      const sets = entry.sets
        .map(set => {
          if (!isObject(set)) return null;
          const reps = parseBoundedNumber(set.reps, 1, 100);
          const weight = parseBoundedNumber(set.weight, 0, 5000);
          if (reps === null || weight === null || !isUnit(set.unit)) return null;

          return {
            reps,
            weight,
            unit: set.unit,
            completed: typeof set.completed === 'boolean' ? set.completed : undefined,
            rpe: parseBoundedNumber(set.rpe, 1, 10) ?? undefined,
          };
        })
        .filter((set): set is NonNullable<typeof set> => set !== null);

      if (sets.length === 0) return null;

      return {
        exerciseId: isString(entry.exerciseId) ? entry.exerciseId : undefined,
        exerciseName: entry.exerciseName,
        category: isExerciseCategory(entry.category) ? entry.category : undefined,
        muscleGroups:
          Array.isArray(entry.muscleGroups) && entry.muscleGroups.every(isMuscleGroup)
            ? entry.muscleGroups
            : undefined,
        notes: isString(entry.notes) ? entry.notes : undefined,
        sets,
      };
    })
    .filter(entry => entry !== null) as AiParseLogResponse['exercises'];

  return {
    confidence,
    exercises,
    notes: value.notes,
  };
};
