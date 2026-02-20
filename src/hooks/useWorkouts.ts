'use client';

import { useState, useEffect, useCallback } from 'react';
import { v4 as uuidv4 } from 'uuid';
import type {
  AiParseLogResponse,
  AiPlanExercise,
  Exercise,
  Workout,
  WorkoutExercise,
  WorkoutSet,
} from '@/types';
import { storage } from '@/utils/storage';
import { defaultExercises } from '@/data/exercises';

export const useWorkouts = () => {
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [currentWorkout, setCurrentWorkout] = useState<Workout | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    setWorkouts(storage.getWorkouts());
    setCurrentWorkout(storage.getCurrentWorkout());
    setIsLoading(false);
  }, []);

  const updateCurrentWorkout = useCallback(
    (updater: (prev: Workout) => Workout) => {
      setCurrentWorkout(prev => {
        if (!prev) return prev;
        const updated = updater(prev);
        storage.saveCurrentWorkout(updated);
        return updated;
      });
    },
    []
  );

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

  const startWorkoutWithPlan = useCallback((name: string, planExercises: AiPlanExercise[]) => {
    const workout: Workout = {
      id: uuidv4(),
      name: name || `Workout ${new Date().toLocaleDateString()}`,
      date: new Date().toISOString(),
      exercises: planExercises.map(planExercise => {
        const knownExercise =
          defaultExercises.find(exercise => exercise.id === planExercise.exerciseId) ||
          defaultExercises.find(exercise => exercise.name === planExercise.exerciseName);

        const exercise: Exercise = knownExercise || {
          id: planExercise.exerciseId || uuidv4(),
          name: planExercise.exerciseName,
          category: planExercise.category,
          muscleGroups: planExercise.muscleGroups,
        };

        const sets: WorkoutSet[] = Array.from({ length: Math.max(1, planExercise.sets) }).map(
          () => ({
            id: uuidv4(),
            reps: Math.max(0, planExercise.reps),
            weight: Math.max(0, planExercise.targetWeight),
            unit: planExercise.unit,
            completed: false,
          })
        );

        return {
          id: uuidv4(),
          exercise,
          sets,
          notes: planExercise.notes,
        };
      }),
      completed: false,
    };

    setCurrentWorkout(workout);
    storage.saveCurrentWorkout(workout);
    return workout;
  }, []);

  const addExerciseToWorkout = useCallback((exercise: Exercise) => {
    const { unit } = storage.getSettings();

    const workoutExercise: WorkoutExercise = {
      id: uuidv4(),
      exercise,
      sets: [
        {
          id: uuidv4(),
          reps: 0,
          weight: 0,
          unit,
          completed: false,
        },
      ],
    };

    updateCurrentWorkout(prev => ({
      ...prev,
      exercises: [...prev.exercises, workoutExercise],
    }));
  }, [updateCurrentWorkout]);

  const removeExerciseFromWorkout = useCallback((exerciseId: string) => {
    updateCurrentWorkout(prev => ({
      ...prev,
      exercises: prev.exercises.filter(e => e.id !== exerciseId),
    }));
  }, [updateCurrentWorkout]);

  const addSetToExercise = useCallback((exerciseId: string) => {
    updateCurrentWorkout(prev => ({
      ...prev,
      exercises: prev.exercises.map(ex => {
        if (ex.id !== exerciseId) return ex;

        const lastSet = ex.sets[ex.sets.length - 1];
        const newSet: WorkoutSet = {
          id: uuidv4(),
          reps: lastSet?.reps || 0,
          weight: lastSet?.weight || 0,
          unit: lastSet?.unit || storage.getSettings().unit,
          completed: false,
        };

        return { ...ex, sets: [...ex.sets, newSet] };
      }),
    }));
  }, [updateCurrentWorkout]);

  const updateSet = useCallback((
    exerciseId: string,
    setId: string,
    updates: Partial<WorkoutSet>
  ) => {
    updateCurrentWorkout(prev => ({
      ...prev,
      exercises: prev.exercises.map(ex => {
        if (ex.id !== exerciseId) return ex;

        return {
          ...ex,
          sets: ex.sets.map(set => {
            if (set.id !== setId) return set;
            return { ...set, ...updates };
          }),
        };
      }),
    }));
  }, [updateCurrentWorkout]);

  const removeSet = useCallback((exerciseId: string, setId: string) => {
    updateCurrentWorkout(prev => ({
      ...prev,
      exercises: prev.exercises.map(ex => {
        if (ex.id !== exerciseId) return ex;

        return {
          ...ex,
          sets: ex.sets.filter(set => set.id !== setId),
        };
      }),
    }));
  }, [updateCurrentWorkout]);

  const duplicateSet = useCallback((exerciseId: string, setId: string) => {
    updateCurrentWorkout(prev => ({
      ...prev,
      exercises: prev.exercises.map(ex => {
        if (ex.id !== exerciseId) return ex;

        const sourceSet = ex.sets.find(set => set.id === setId);
        if (!sourceSet) return ex;

        const duplicated: WorkoutSet = {
          ...sourceSet,
          id: uuidv4(),
          completed: false,
        };

        return { ...ex, sets: [...ex.sets, duplicated] };
      }),
    }));
  }, [updateCurrentWorkout]);

  const completeWorkout = useCallback(() => {
    if (!currentWorkout) return;

    const endTime = new Date();
    const startTime = new Date(currentWorkout.date);
    const duration = Math.max(
      0,
      Math.round((endTime.getTime() - startTime.getTime()) / 60000)
    );

    const completed: Workout = {
      ...currentWorkout,
      completed: true,
      duration,
    };

    setWorkouts(prev => {
      const updatedWorkouts = [...prev, completed];
      storage.saveWorkouts(updatedWorkouts);
      return updatedWorkouts;
    });
    setCurrentWorkout(null);
    storage.saveCurrentWorkout(null);

    return completed;
  }, [currentWorkout]);

  const cancelWorkout = useCallback(() => {
    setCurrentWorkout(null);
    storage.saveCurrentWorkout(null);
  }, []);

  const applyParsedLogPatch = useCallback((patch: AiParseLogResponse) => {
    if (patch.exercises.length === 0) return;

    updateCurrentWorkout(prev => {
      const next = { ...prev, exercises: [...prev.exercises] };

      patch.exercises.forEach(parsedExercise => {
        const normalizedName = parsedExercise.exerciseName.toLowerCase();
        const existing = next.exercises.find(
          exercise =>
            exercise.exercise.id === parsedExercise.exerciseId ||
            exercise.exercise.name.toLowerCase() === normalizedName
        );

        if (existing) {
          const parsedSets = parsedExercise.sets.map(set => ({
            id: uuidv4(),
            reps: set.reps,
            weight: set.weight,
            unit: set.unit,
            completed: set.completed ?? false,
            rpe: set.rpe,
          }));
          existing.sets = [...existing.sets, ...parsedSets];
          if (parsedExercise.notes) {
            existing.notes = [existing.notes, parsedExercise.notes].filter(Boolean).join(' | ');
          }
          return;
        }

        const knownExercise =
          (parsedExercise.exerciseId &&
            defaultExercises.find(exercise => exercise.id === parsedExercise.exerciseId)) ||
          defaultExercises.find(
            exercise => exercise.name.toLowerCase() === normalizedName
          );

        const exercise: Exercise = knownExercise || {
          id: parsedExercise.exerciseId || uuidv4(),
          name: parsedExercise.exerciseName,
          category: parsedExercise.category || 'bodyweight',
          muscleGroups: parsedExercise.muscleGroups || ['core'],
        };

        const workoutExercise: WorkoutExercise = {
          id: uuidv4(),
          exercise,
          sets: parsedExercise.sets.map(set => ({
            id: uuidv4(),
            reps: set.reps,
            weight: set.weight,
            unit: set.unit,
            completed: set.completed ?? false,
            rpe: set.rpe,
          })),
          notes: parsedExercise.notes,
        };

        next.exercises.push(workoutExercise);
      });

      return next;
    });
  }, [updateCurrentWorkout]);

  const deleteWorkout = useCallback((id: string) => {
    setWorkouts(prev => {
      const updated = prev.filter(w => w.id !== id);
      storage.saveWorkouts(updated);
      return updated;
    });
  }, []);

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
    startWorkoutWithPlan,
    addExerciseToWorkout,
    removeExerciseFromWorkout,
    addSetToExercise,
    updateSet,
    removeSet,
    duplicateSet,
    completeWorkout,
    cancelWorkout,
    applyParsedLogPatch,
    deleteWorkout,
    getWorkoutsByDateRange,
  };
};
