'use client';

import { useState, useEffect, useCallback } from 'react';
import { v4 as uuidv4 } from 'uuid';
import { Workout, WorkoutExercise, WorkoutSet, Exercise } from '@/types';
import { storage } from '@/utils/storage';

export const useWorkouts = () => {
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [currentWorkout, setCurrentWorkout] = useState<Workout | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    setWorkouts(storage.getWorkouts());
    setCurrentWorkout(storage.getCurrentWorkout());
    setIsLoading(false);
  }, []);

  const startWorkout = useCallback((name?: string) => {
    const workout: Workout = {
      id: uuidv4(),
      name: name || `Workout ${new Date().toLocaleDateString()}`,
      date: new Date().toISOString(),
      exercises: [],
      completed: false,
    };
    setCurrentWorkout(workout);
    storage.saveCurrentWorkout(workout);
    return workout;
  }, []);

  const addExerciseToWorkout = useCallback((exercise: Exercise) => {
    if (!currentWorkout) return;

    const workoutExercise: WorkoutExercise = {
      id: uuidv4(),
      exercise,
      sets: [
        {
          id: uuidv4(),
          reps: 0,
          weight: 0,
          unit: 'lbs',
          completed: false,
        },
      ],
    };

    const updated = {
      ...currentWorkout,
      exercises: [...currentWorkout.exercises, workoutExercise],
    };
    setCurrentWorkout(updated);
    storage.saveCurrentWorkout(updated);
  }, [currentWorkout]);

  const removeExerciseFromWorkout = useCallback((exerciseId: string) => {
    if (!currentWorkout) return;

    const updated = {
      ...currentWorkout,
      exercises: currentWorkout.exercises.filter(e => e.id !== exerciseId),
    };
    setCurrentWorkout(updated);
    storage.saveCurrentWorkout(updated);
  }, [currentWorkout]);

  const addSetToExercise = useCallback((exerciseId: string) => {
    if (!currentWorkout) return;

    const updated = {
      ...currentWorkout,
      exercises: currentWorkout.exercises.map(ex => {
        if (ex.id !== exerciseId) return ex;

        const lastSet = ex.sets[ex.sets.length - 1];
        const newSet: WorkoutSet = {
          id: uuidv4(),
          reps: lastSet?.reps || 0,
          weight: lastSet?.weight || 0,
          unit: lastSet?.unit || 'lbs',
          completed: false,
        };

        return { ...ex, sets: [...ex.sets, newSet] };
      }),
    };
    setCurrentWorkout(updated);
    storage.saveCurrentWorkout(updated);
  }, [currentWorkout]);

  const updateSet = useCallback((
    exerciseId: string,
    setId: string,
    updates: Partial<WorkoutSet>
  ) => {
    if (!currentWorkout) return;

    const updated = {
      ...currentWorkout,
      exercises: currentWorkout.exercises.map(ex => {
        if (ex.id !== exerciseId) return ex;

        return {
          ...ex,
          sets: ex.sets.map(set => {
            if (set.id !== setId) return set;
            return { ...set, ...updates };
          }),
        };
      }),
    };
    setCurrentWorkout(updated);
    storage.saveCurrentWorkout(updated);
  }, [currentWorkout]);

  const removeSet = useCallback((exerciseId: string, setId: string) => {
    if (!currentWorkout) return;

    const updated = {
      ...currentWorkout,
      exercises: currentWorkout.exercises.map(ex => {
        if (ex.id !== exerciseId) return ex;

        return {
          ...ex,
          sets: ex.sets.filter(set => set.id !== setId),
        };
      }),
    };
    setCurrentWorkout(updated);
    storage.saveCurrentWorkout(updated);
  }, [currentWorkout]);

  const completeWorkout = useCallback(() => {
    if (!currentWorkout) return;

    const endTime = new Date();
    const startTime = new Date(currentWorkout.date);
    const duration = Math.round((endTime.getTime() - startTime.getTime()) / 60000);

    const completed: Workout = {
      ...currentWorkout,
      completed: true,
      duration,
    };

    const updatedWorkouts = [...workouts, completed];
    setWorkouts(updatedWorkouts);
    storage.saveWorkouts(updatedWorkouts);
    setCurrentWorkout(null);
    storage.saveCurrentWorkout(null);

    return completed;
  }, [currentWorkout, workouts]);

  const cancelWorkout = useCallback(() => {
    setCurrentWorkout(null);
    storage.saveCurrentWorkout(null);
  }, []);

  const deleteWorkout = useCallback((id: string) => {
    const updated = workouts.filter(w => w.id !== id);
    setWorkouts(updated);
    storage.saveWorkouts(updated);
  }, [workouts]);

  const getWorkoutsByDateRange = useCallback((startDate: Date, endDate: Date) => {
    return workouts.filter(w => {
      const workoutDate = new Date(w.date);
      return workoutDate >= startDate && workoutDate <= endDate;
    });
  }, [workouts]);

  return {
    workouts,
    currentWorkout,
    isLoading,
    startWorkout,
    addExerciseToWorkout,
    removeExerciseFromWorkout,
    addSetToExercise,
    updateSet,
    removeSet,
    completeWorkout,
    cancelWorkout,
    deleteWorkout,
    getWorkoutsByDateRange,
  };
};
