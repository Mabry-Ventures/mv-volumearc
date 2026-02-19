import type { Exercise, Workout, WorkoutSet, WorkoutExercise, UserStats } from '@/types';

const normalizeNumber = (value: number): number => {
  return Number.isFinite(value) ? value : 0;
};

const convertWeightValue = (
  weight: number,
  from: 'lbs' | 'kg',
  to: 'lbs' | 'kg'
): number => {
  if (from === to) return weight;
  const ratio = 0.45359237;
  return from === 'lbs' ? weight * ratio : weight / ratio;
};

export const calculateSetVolume = (
  set: WorkoutSet,
  targetUnit: 'lbs' | 'kg' = 'lbs'
): number => {
  const weight = normalizeNumber(set.weight);
  const reps = normalizeNumber(set.reps);
  const weightInTarget = convertWeightValue(weight, set.unit, targetUnit);
  return Math.max(0, weightInTarget) * Math.max(0, reps);
};

export const calculateExerciseVolume = (
  exercise: WorkoutExercise,
  targetUnit: 'lbs' | 'kg' = 'lbs'
): number => {
  return exercise.sets
    .filter(s => s.completed)
    .reduce((total, set) => total + calculateSetVolume(set, targetUnit), 0);
};

export const calculateWorkoutVolume = (
  workout: Workout,
  targetUnit: 'lbs' | 'kg' = 'lbs'
): number => {
  return workout.exercises.reduce(
    (total, exercise) => total + calculateExerciseVolume(exercise, targetUnit),
    0
  );
};

export const calculateTotalVolume = (
  workouts: Workout[],
  targetUnit: 'lbs' | 'kg' = 'lbs'
): number => {
  return workouts.reduce(
    (total, workout) => total + calculateWorkoutVolume(workout, targetUnit),
    0
  );
};

export const calculate1RM = (weight: number, reps: number): number => {
  const safeWeight = normalizeNumber(weight);
  const safeReps = normalizeNumber(reps);

  if (safeWeight <= 0 || safeReps <= 0) return 0;

  // Brzycki formula
  if (safeReps === 1) return Math.round(safeWeight);

  // Keep formula numerically stable for very high rep counts.
  if (safeReps >= 37) return Math.round(safeWeight);

  return Math.round(safeWeight * (36 / (37 - safeReps)));
};

export const convertWeight = (
  weight: number,
  from: 'lbs' | 'kg',
  to: 'lbs' | 'kg'
): number => {
  const value = convertWeightValue(weight, from, to);
  return Math.round(value * 10) / 10;
};

export const calculateStreak = (workouts: Workout[]): { current: number; longest: number } => {
  if (workouts.length === 0) return { current: 0, longest: 0 };

  const sortedWorkouts = [...workouts]
    .filter(w => w.completed)
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());

  if (sortedWorkouts.length === 0) return { current: 0, longest: 0 };

  const dayMillis = 1000 * 60 * 60 * 24;
  const uniqueDays = Array.from(
    new Set(
      sortedWorkouts.map(workout => {
        const date = new Date(workout.date);
        date.setHours(0, 0, 0, 0);
        return date.getTime();
      })
    )
  ).sort((a, b) => b - a);

  if (uniqueDays.length === 0) return { current: 0, longest: 0 };

  let currentStreak = 0;
  let longestStreak = 0;
  let tempStreak = 1;

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const lastWorkoutDate = uniqueDays[0];

  const daysSinceLastWorkout = Math.floor(
    (today.getTime() - lastWorkoutDate) / dayMillis
  );

  // Check if streak is still active (worked out today or yesterday)
  if (daysSinceLastWorkout <= 1) {
    currentStreak = 1;

    for (let i = 1; i < uniqueDays.length; i++) {
      const dayDiff = Math.floor((uniqueDays[i - 1] - uniqueDays[i]) / dayMillis);

      if (dayDiff <= 1) {
        currentStreak++;
      } else {
        break;
      }
    }
  }

  // Calculate longest streak
  for (let i = 1; i < uniqueDays.length; i++) {
    const dayDiff = Math.floor((uniqueDays[i - 1] - uniqueDays[i]) / dayMillis);

    if (dayDiff <= 1) {
      tempStreak++;
    } else {
      longestStreak = Math.max(longestStreak, tempStreak);
      tempStreak = 1;
    }
  }
  longestStreak = Math.max(longestStreak, tempStreak);

  return { current: currentStreak, longest: longestStreak };
};

export const calculateUserStats = (
  workouts: Workout[],
  targetUnit: 'lbs' | 'kg' = 'lbs'
): UserStats => {
  const completedWorkouts = workouts.filter(w => w.completed);
  const streaks = calculateStreak(workouts);

  // Find favorite exercise (most frequently performed)
  const exerciseCounts: Record<string, { count: number; exercise: Exercise }> = {};
  completedWorkouts.forEach(workout => {
    workout.exercises.forEach(ex => {
      if (!exerciseCounts[ex.exercise.id]) {
        exerciseCounts[ex.exercise.id] = { count: 0, exercise: ex.exercise };
      }
      exerciseCounts[ex.exercise.id].count++;
    });
  });

  let favoriteExercise: Exercise | undefined;
  let maxCount = 0;
  Object.values(exerciseCounts).forEach(({ count, exercise }) => {
    if (count > maxCount) {
      maxCount = count;
      favoriteExercise = exercise;
    }
  });

  return {
    totalWorkouts: completedWorkouts.length,
    totalVolume: calculateTotalVolume(completedWorkouts, targetUnit),
    currentStreak: streaks.current,
    longestStreak: streaks.longest,
    favoriteExercise,
  };
};

export const formatWeight = (weight: number, unit: 'lbs' | 'kg'): string => {
  return `${weight} ${unit}`;
};

export const formatDuration = (minutes: number): string => {
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  if (hours > 0) {
    return `${hours}h ${mins}m`;
  }
  return `${mins}m`;
};
