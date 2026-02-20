import { defaultExercises } from '@/data/exercises';
import type {
  AiLiveCoachResponse,
  AiParseLogResponse,
  AiPostWorkoutResponse,
  AiRiskAnalysisResponse,
  AiWorkoutPlanRequest,
  AiWorkoutPlanResponse,
  Workout,
} from '@/types';
import { calculateWorkoutVolume } from '@/utils/calculations';

const toTitleCase = (value: string) =>
  value
    .split(/\s+/)
    .filter(Boolean)
    .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(' ');

export const aiFallbacks = {
  workoutPlan(input: AiWorkoutPlanRequest): AiWorkoutPlanResponse {
    const pool = defaultExercises
      .filter(exercise =>
        input.equipment.length === 0
          ? true
          : input.equipment.some(item =>
              exercise.category.toLowerCase().includes(item.toLowerCase())
            )
      )
      .slice(0, 6);

    const exercises = (pool.length > 0 ? pool : defaultExercises.slice(0, 5)).map(exercise => ({
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      category: exercise.category,
      muscleGroups: exercise.muscleGroups,
      sets: 3,
      reps: exercise.category === 'cardio' ? 10 : 8,
      targetWeight: 0,
      unit: input.fullHistoryDigest.unit,
      restSeconds: exercise.category === 'cardio' ? 60 : 90,
      notes: 'Start conservatively and add load after clean reps.',
    }));

    return {
      workoutName: `${toTitleCase(input.goal)} Plan`,
      estimatedSessionMinutes: input.durationMinutes,
      warmup: ['5 minutes easy cardio', '2 ramp-up sets on first compound movement'],
      cooldown: ['Light stretch for 5 minutes'],
      notes: ['Generated from deterministic fallback because AI was unavailable.'],
      exercises,
      fallbackReason: 'ai_unavailable',
    };
  },

  liveCoach(unit: 'lbs' | 'kg', lastSet: { reps: number; weight: number } | null): AiLiveCoachResponse {
    const nextWeight = lastSet ? lastSet.weight : 0;
    const nextReps = lastSet ? Math.max(1, lastSet.reps) : 8;

    return {
      nextSet: {
        weight: nextWeight,
        reps: nextReps,
        restSeconds: 90,
        unit,
      },
      actionability: 'review',
      confidence: 0.35,
      rationale: ['Keep effort controlled and focus on form consistency.'],
      caution: 'Fallback suggestion: adjust manually if needed.',
      fallbackReason: 'ai_unavailable',
    };
  },

  postWorkout(workout: Workout): AiPostWorkoutResponse {
    const volume = Math.round(calculateWorkoutVolume(workout, 'lbs'));

    return {
      generatedAt: new Date().toISOString(),
      model: 'deterministic-fallback',
      summary: `Workout complete: ${workout.name}. Total fallback-estimated volume ${volume} lbs.`,
      keyWins: [
        `Completed ${workout.exercises.length} exercises`,
        `Duration ${workout.duration || 0} minutes`,
      ],
      prCandidates: [],
      nextSessionRecommendation: {
        focus: 'Progressive overload',
        rationale: 'Aim to add one rep or small load increase on core lifts.',
        adjustments: ['Prioritize sleep and hydration before your next session.'],
      },
    };
  },

  riskAnalysis(): AiRiskAnalysisResponse {
    return {
      plateauRisk: {
        score: 0.25,
        level: 'low',
        reasons: ['Insufficient AI context available; using conservative baseline.'],
      },
      overtrainingRisk: {
        score: 0.2,
        level: 'low',
        reasons: ['No high-risk pattern detected from fallback logic.'],
      },
      recommendedActions: [
        'Track RPE for each top set to improve future risk analysis.',
        'Schedule at least 1 rest day this week.',
      ],
      fallbackReason: 'ai_unavailable',
    };
  },

  parseLog(text: string): AiParseLogResponse {
    const normalized = text.trim();
    if (normalized.length === 0) {
      return {
        confidence: 0,
        exercises: [],
        notes: ['No text provided to parse.'],
        fallbackReason: 'empty_input',
      };
    }

    const firstExercise = defaultExercises.find(exercise =>
      normalized.toLowerCase().includes(exercise.name.toLowerCase())
    );

    return {
      confidence: 0.3,
      requiresReview: true,
      exercises: firstExercise
        ? [
            {
              exerciseId: firstExercise.id,
              exerciseName: firstExercise.name,
              category: firstExercise.category,
              muscleGroups: firstExercise.muscleGroups,
              sets: [{ reps: 8, weight: 0, unit: 'lbs', completed: false }],
            },
          ]
        : [],
      notes: [
        'Fallback parser could not confidently extract all details.',
        'Review and edit before applying.',
      ],
      fallbackReason: 'ai_unavailable',
    };
  },
};
