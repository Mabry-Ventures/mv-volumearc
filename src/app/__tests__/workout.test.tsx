import { render, screen } from '@testing-library/react';
import WorkoutPage from '@/app/workout/page';
import { storage } from '@/utils/storage';
import type { Workout } from '@/types';

const workoutWithExercise: Workout = {
  id: 'workout-1',
  name: 'Strength Session',
  date: '2026-02-04T10:00:00.000Z',
  completed: false,
  exercises: [
    {
      id: 'ex-1',
      exercise: {
        id: 'bench-press',
        name: 'Bench Press',
        category: 'barbell',
        muscleGroups: ['chest'],
      },
      sets: [
        {
          id: 'set-1',
          reps: 5,
          weight: 100,
          unit: 'lbs',
          completed: false,
        },
      ],
    },
  ],
};

describe('WorkoutPage', () => {
  it('renders start screen when no current workout', async () => {
    render(<WorkoutPage />);

    expect(await screen.findByText('Start Empty Workout')).toBeInTheDocument();
  });

  it('renders active workout when current workout exists', async () => {
    storage.saveCurrentWorkout(workoutWithExercise);
    render(<WorkoutPage />);

    expect(await screen.findByText('Bench Press')).toBeInTheDocument();
    expect(screen.getByText('Complete Workout')).toBeInTheDocument();
  });
});
