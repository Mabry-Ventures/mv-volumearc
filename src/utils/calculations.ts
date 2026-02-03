import { Workout, WorkoutSet, WorkoutExercise, UserStats } from '@/types';

export const calculateSetVolume = (set: WorkoutSet): number => {
  return set.weight * set.reps;
};

export const calculateExerciseVolume = (exercise: WorkoutExercise): number => {
  return exercise.sets
    .filter(s => s.completed)
    .reduce((total, set) => total + calculateSetVolume(set), 0);
};

export const calculateWorkoutVolume = (workout: Workout): number => {
  return workout.exercises.reduce(
    (total, exercise) => total + calculateExerciseVolume(exercise),
    0
  );
};

export const calculateTotalVolume = (workouts: Workout[]): number => {
  return workouts.reduce(
    (total, workout) => total + calculateWorkoutVolume(workout),
    0
  );
};

export const calculate1RM = (weight: number, reps: number): number => {
  // Brzycki formula
  if (reps === 1) return weight;
  return Math.round(weight * (36 / (37 - reps)));
};

export const convertWeight = (
  weight: number,
  from: 'lbs' | 'kg',
  to: 'lbs' | 'kg'
): number => {
  if (from === to) return weight;
  if (from === 'lbs' && to === 'kg') {
    return Math.round(weight * 0.453592 * 10) / 10;
  }
  return Math.round(weight * 2.20462 * 10) / 10;
};

export const calculateStreak = (workouts: Workout[]): { current: number; longest: number } => {
  if (workouts.length === 0) return { current: 0, longest: 0 };

  const sortedWorkouts = [...workouts]
    .filter(w => w.completed)
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());

  if (sortedWorkouts.length === 0) return { current: 0, longest: 0 };

  let currentStreak = 0;
  let longestStreak = 0;
  let tempStreak = 1;

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const lastWorkoutDate = new Date(sortedWorkouts[0].date);
  lastWorkoutDate.setHours(0, 0, 0, 0);

  const daysSinceLastWorkout = Math.floor(
    (today.getTime() - lastWorkoutDate.getTime()) / (1000 * 60 * 60 * 24)
  );

  // Check if streak is still active (worked out today or yesterday)
  if (daysSinceLastWorkout <= 1) {
    currentStreak = 1;

    for (let i = 1; i < sortedWorkouts.length; i++) {
      const currentDate = new Date(sortedWorkouts[i - 1].date);
      const prevDate = new Date(sortedWorkouts[i].date);
      currentDate.setHours(0, 0, 0, 0);
      prevDate.setHours(0, 0, 0, 0);

      const dayDiff = Math.floor(
        (currentDate.getTime() - prevDate.getTime()) / (1000 * 60 * 60 * 24)
      );

      if (dayDiff <= 1) {
        currentStreak++;
      } else {
        break;
      }
    }
  }

  // Calculate longest streak
  for (let i = 1; i < sortedWorkouts.length; i++) {
    const currentDate = new Date(sortedWorkouts[i - 1].date);
    const prevDate = new Date(sortedWorkouts[i].date);
    currentDate.setHours(0, 0, 0, 0);
    prevDate.setHours(0, 0, 0, 0);

    const dayDiff = Math.floor(
      (currentDate.getTime() - prevDate.getTime()) / (1000 * 60 * 60 * 24)
    );

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

export const calculateUserStats = (workouts: Workout[]): UserStats => {
  const completedWorkouts = workouts.filter(w => w.completed);
  const streaks = calculateStreak(workouts);

  // Find favorite exercise (most frequently performed)
  const exerciseCounts: Record<string, { count: number; exercise: any }> = {};
  completedWorkouts.forEach(workout => {
    workout.exercises.forEach(ex => {
      if (!exerciseCounts[ex.exercise.id]) {
        exerciseCounts[ex.exercise.id] = { count: 0, exercise: ex.exercise };
      }
      exerciseCounts[ex.exercise.id].count++;
    });
  });

  let favoriteExercise;
  let maxCount = 0;
  Object.values(exerciseCounts).forEach(({ count, exercise }) => {
    if (count > maxCount) {
      maxCount = count;
      favoriteExercise = exercise;
    }
  });

  return {
    totalWorkouts: completedWorkouts.length,
    totalVolume: calculateTotalVolume(completedWorkouts),
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
