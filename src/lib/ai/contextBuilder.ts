import { calculateStreak, calculateWorkoutVolume, convertWeight } from '@/utils/calculations';
import type { AiHistoryDigest, Workout } from '@/types';
import { AI_PROMPT_VERSION, AI_SCHEMA_VERSION } from '@/lib/ai/schemas';

type DateWindow = 7 | 30 | 90;

const DAY_MS = 24 * 60 * 60 * 1000;

const toDayStart = (value: string): number => {
  const date = new Date(value);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
};

const volumeSinceDays = (
  workouts: Workout[],
  unit: 'lbs' | 'kg',
  days: DateWindow
): number => {
  const cutoff = Date.now() - days * DAY_MS;
  return workouts
    .filter(workout => new Date(workout.date).getTime() >= cutoff)
    .reduce((sum, workout) => sum + calculateWorkoutVolume(workout, unit), 0);
};

export const buildHistoryDigest = (
  workouts: Workout[],
  unit: 'lbs' | 'kg',
  recentWorkoutLimit = 12
): AiHistoryDigest => {
  const completed = workouts
    .filter(workout => workout.completed)
    .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());

  const streak = calculateStreak(completed);
  const totalVolume = completed.reduce(
    (sum, workout) => sum + calculateWorkoutVolume(workout, unit),
    0
  );

  const averageDurationMinutes =
    completed.length === 0
      ? 0
      : Math.round(
          completed.reduce((sum, workout) => sum + (workout.duration || 0), 0) /
            completed.length
        );

  const performanceDeltas: number[] = [];
  for (let index = 1; index < completed.length; index++) {
    const previous = calculateWorkoutVolume(completed[index - 1], unit);
    const current = calculateWorkoutVolume(completed[index], unit);
    if (previous > 0) {
      performanceDeltas.push((current - previous) / previous);
    }
  }

  const lowPerformanceRuns = performanceDeltas
    .slice(-6)
    .filter(delta => delta < -0.08).length;

  const highRpeCount = completed.reduce((sum, workout) => {
    return (
      sum +
      workout.exercises.reduce((exerciseSum, exercise) => {
        return (
          exerciseSum +
          exercise.sets.filter(set => typeof set.rpe === 'number' && set.rpe >= 8).length
        );
      }, 0)
    );
  }, 0);

  const exerciseMap = new Map<
    string,
    {
      exerciseId: string;
      exerciseName: string;
      sessions: number;
      volume7d: number;
      volume30d: number;
      topSet?: { weight: number; reps: number; unit: 'lbs' | 'kg'; date: string };
      latestSet?: { weight: number; reps: number; unit: 'lbs' | 'kg'; date: string };
    }
  >();

  const now = Date.now();

  completed.forEach(workout => {
    const workoutDateMs = new Date(workout.date).getTime();
    const isWithin7d = now - workoutDateMs <= 7 * DAY_MS;
    const isWithin30d = now - workoutDateMs <= 30 * DAY_MS;

    workout.exercises.forEach(exercise => {
      const existing = exerciseMap.get(exercise.exercise.id) || {
        exerciseId: exercise.exercise.id,
        exerciseName: exercise.exercise.name,
        sessions: 0,
        volume7d: 0,
        volume30d: 0,
      };

      existing.sessions += 1;

      let exerciseVolume = 0;
      exercise.sets
        .filter(set => set.completed)
        .forEach(set => {
          const weightInUnit = set.unit === unit ? set.weight : convertWeight(set.weight, set.unit, unit);
          exerciseVolume += Math.max(0, weightInUnit) * Math.max(0, set.reps);

          if (
            !existing.topSet ||
            weightInUnit > existing.topSet.weight ||
            (weightInUnit === existing.topSet.weight && set.reps > existing.topSet.reps)
          ) {
            existing.topSet = {
              weight: weightInUnit,
              reps: set.reps,
              unit,
              date: workout.date,
            };
          }

          existing.latestSet = {
            weight: weightInUnit,
            reps: set.reps,
            unit,
            date: workout.date,
          };
        });

      if (isWithin7d) existing.volume7d += exerciseVolume;
      if (isWithin30d) existing.volume30d += exerciseVolume;

      exerciseMap.set(exercise.exercise.id, existing);
    });
  });

  const plateauScore = Math.min(
    1,
    Math.max(0, lowPerformanceRuns / 4 + (performanceDeltas.length > 0 ? 0.15 : 0))
  );

  const overtrainingScore = Math.min(
    1,
    Math.max(0, highRpeCount / 80 + (averageDurationMinutes >= 90 ? 0.15 : 0))
  );

  const recentWorkouts = [...completed]
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
    .slice(0, recentWorkoutLimit);

  return {
    generatedAt: new Date().toISOString(),
    schemaVersion: AI_SCHEMA_VERSION,
    promptVersion: AI_PROMPT_VERSION,
    unit,
    totalWorkouts: workouts.length,
    completedWorkouts: completed.length,
    currentStreak: streak.current,
    longestStreak: streak.longest,
    totalVolume,
    averageDurationMinutes,
    rollingVolume: {
      days7: volumeSinceDays(completed, unit, 7),
      days30: volumeSinceDays(completed, unit, 30),
      days90: volumeSinceDays(completed, unit, 90),
    },
    exerciseTrends: Array.from(exerciseMap.values()).sort(
      (a, b) => b.sessions - a.sessions
    ),
    fatigueSignals: {
      plateauScore,
      overtrainingScore,
      lowPerformanceRuns,
      highRpeCount,
    },
    recentWorkouts,
  };
};

export const buildHistoryDigestLite = (
  digest: AiHistoryDigest
): Pick<AiHistoryDigest, 'unit' | 'rollingVolume' | 'exerciseTrends' | 'fatigueSignals'> => ({
  unit: digest.unit,
  rollingVolume: digest.rollingVolume,
  exerciseTrends: digest.exerciseTrends.slice(0, 8),
  fatigueSignals: digest.fatigueSignals,
});

export const digestFingerprint = (digest: AiHistoryDigest): string => {
  const keyPayload = {
    totalWorkouts: digest.totalWorkouts,
    completedWorkouts: digest.completedWorkouts,
    rollingVolume: digest.rollingVolume,
    topExercises: digest.exerciseTrends.slice(0, 5).map(exercise => ({
      id: exercise.exerciseId,
      sessions: exercise.sessions,
      volume30d: Math.round(exercise.volume30d),
    })),
    latestWorkoutDay: digest.recentWorkouts[0]?.date ? toDayStart(digest.recentWorkouts[0].date) : null,
  };

  return JSON.stringify(keyPayload);
};
