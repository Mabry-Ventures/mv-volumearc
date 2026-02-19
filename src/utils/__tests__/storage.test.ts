import { storage } from '@/utils/storage';
import type { Exercise, PersonalRecord, Workout, WorkoutTemplate } from '@/types';

const exercise: Exercise = {
  id: 'bench-press',
  name: 'Bench Press',
  category: 'barbell' as const,
  muscleGroups: ['chest'],
};

const workout: Workout = {
  id: 'workout-1',
  name: 'Test Workout',
  date: '2026-02-04T10:00:00.000Z',
  exercises: [],
  completed: true,
};

const template: WorkoutTemplate = {
  id: 'template-1',
  name: 'Template',
  exercises: [],
};

const record: PersonalRecord = {
  id: 'pr-1',
  exercise,
  weight: 200,
  reps: 5,
  date: '2026-02-04T10:00:00.000Z',
  workoutId: 'workout-1',
};

describe('storage', () => {
  it('saves and retrieves workouts', () => {
    storage.saveWorkouts([workout]);
    expect(storage.getWorkouts()).toEqual([workout]);
  });

  it('adds, updates, and deletes workouts', () => {
    storage.saveWorkouts([]);
    storage.addWorkout(workout);
    expect(storage.getWorkouts()).toHaveLength(1);

    const updated = { ...workout, name: 'Updated Workout' };
    storage.updateWorkout(updated);
    expect(storage.getWorkouts()[0].name).toBe('Updated Workout');

    storage.deleteWorkout(workout.id);
    expect(storage.getWorkouts()).toHaveLength(0);
  });

  it('manages templates and personal records', () => {
    storage.saveTemplates([template]);
    expect(storage.getTemplates()).toEqual([template]);

    storage.savePersonalRecords([record]);
    expect(storage.getPersonalRecords()).toEqual([record]);
  });

  it('migrates legacy personal record shape', () => {
    localStorage.setItem(
      'beast-mode-prs',
      JSON.stringify([
        {
          id: 'legacy-pr-1',
          odeum: exercise,
          weight: 185,
          reps: 3,
          date: '2026-02-04T10:00:00.000Z',
          workoutId: 'workout-1',
        },
      ])
    );

    const records = storage.getPersonalRecords();
    expect(records).toEqual([
      {
        id: 'legacy-pr-1',
        exercise,
        weight: 185,
        reps: 3,
        date: '2026-02-04T10:00:00.000Z',
        workoutId: 'workout-1',
      },
    ]);
  });

  it('persists current workout and settings', () => {
    storage.saveCurrentWorkout(workout);
    expect(storage.getCurrentWorkout()).toEqual(workout);

    storage.saveSettings({ unit: 'kg' });
    expect(storage.getSettings().unit).toBe('kg');
  });

  it('handles malformed JSON by clearing bad values', () => {
    localStorage.setItem('beast-mode-workouts', '{not-json');

    expect(storage.getWorkouts()).toEqual([]);
    expect(localStorage.getItem('beast-mode-workouts')).toBeNull();
  });

  it('imports validated backup data', () => {
    const payload = {
      workouts: [workout],
      templates: [template],
      personalRecords: [record],
      settings: { unit: 'kg' as const },
    };

    expect(storage.importData(payload)).toBe(true);
    expect(storage.getWorkouts()).toEqual([workout]);
    expect(storage.getTemplates()).toEqual([template]);
    expect(storage.getPersonalRecords()).toEqual([record]);
    expect(storage.getSettings()).toEqual({ unit: 'kg' });
  });

  it('rejects invalid backup data without mutating existing data', () => {
    storage.saveWorkouts([workout]);

    const invalidPayload = {
      workouts: { bad: true },
    };

    expect(storage.importData(invalidPayload)).toBe(false);
    expect(storage.getWorkouts()).toEqual([workout]);
  });

  it('clears all storage keys', () => {
    storage.saveWorkouts([workout]);
    storage.saveTemplates([template]);
    storage.savePersonalRecords([record]);
    storage.saveCurrentWorkout(workout);
    storage.saveSettings({ unit: 'lbs' });

    storage.clearAll();

    expect(storage.getWorkouts()).toEqual([]);
    expect(storage.getTemplates()).toEqual([]);
    expect(storage.getPersonalRecords()).toEqual([]);
    expect(storage.getCurrentWorkout()).toBeNull();
    expect(storage.getSettings()).toEqual({ unit: 'lbs' });
  });
});
