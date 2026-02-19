import { renderHook, act, waitFor } from '@testing-library/react';
import { useWorkouts } from '@/hooks/useWorkouts';
import { storage } from '@/utils/storage';
import type { Exercise } from '@/types';

const exercise: Exercise = {
  id: 'bench-press',
  name: 'Bench Press',
  category: 'barbell',
  muscleGroups: ['chest'],
};

describe('useWorkouts', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-02-04T10:00:00.000Z'));
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('starts a workout and adds exercises/sets with settings unit', async () => {
    storage.saveSettings({ unit: 'kg' });
    const { result } = renderHook(() => useWorkouts());

    await waitFor(() => expect(result.current.isLoading).toBe(false));

    act(() => {
      result.current.startWorkout('Leg Day');
    });

    await waitFor(() => expect(result.current.currentWorkout).not.toBeNull());

    act(() => {
      result.current.addExerciseToWorkout(exercise);
    });

    await waitFor(() => {
      expect(result.current.currentWorkout?.exercises.length).toBe(1);
    });

    const workout = result.current.currentWorkout;
    expect(workout).not.toBeNull();
    if (!workout) throw new Error('Expected an active workout');

    const workoutExercise = workout.exercises[0];
    expect(workoutExercise.sets[0].unit).toBe('kg');

    act(() => {
      result.current.addSetToExercise(workoutExercise.id);
    });

    await waitFor(() => {
      expect(result.current.currentWorkout?.exercises[0].sets.length).toBe(2);
    });

    const firstSetId = workoutExercise.sets[0].id;

    act(() => {
      result.current.updateSet(workoutExercise.id, firstSetId, { weight: 80, reps: 5 });
    });

    await waitFor(() => {
      const updatedWorkout = result.current.currentWorkout;
      expect(updatedWorkout).not.toBeNull();
      if (!updatedWorkout) throw new Error('Expected workout after update');

      const updatedSet = updatedWorkout.exercises[0].sets[0];
      expect(updatedSet.weight).toBe(80);
      expect(updatedSet.reps).toBe(5);
    });

    const workoutAfterUpdate = result.current.currentWorkout;
    expect(workoutAfterUpdate).not.toBeNull();
    if (!workoutAfterUpdate) throw new Error('Expected workout before removing set');

    const secondSet = workoutAfterUpdate.exercises[0].sets[1];
    expect(secondSet).toBeDefined();
    if (!secondSet) throw new Error('Expected second set to exist');

    act(() => {
      result.current.removeSet(workoutExercise.id, secondSet.id);
    });

    await waitFor(() => {
      const updatedWorkout = result.current.currentWorkout;
      expect(updatedWorkout).not.toBeNull();
      if (!updatedWorkout) throw new Error('Expected workout after removing set');

      expect(updatedWorkout.exercises[0].sets.length).toBe(1);
    });
  });

  it('completes a workout and clears current workout', async () => {
    const { result } = renderHook(() => useWorkouts());

    await waitFor(() => expect(result.current.isLoading).toBe(false));

    act(() => {
      result.current.startWorkout('Quick Session');
    });

    await waitFor(() => expect(result.current.currentWorkout).not.toBeNull());

    act(() => {
      result.current.addExerciseToWorkout(exercise);
    });

    jest.setSystemTime(new Date('2026-02-04T10:30:00.000Z'));

    act(() => {
      result.current.completeWorkout();
    });

    await waitFor(() => {
      expect(result.current.currentWorkout).toBeNull();
      expect(result.current.workouts.length).toBe(1);
    });
  });
});
