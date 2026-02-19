import { render, screen } from '@testing-library/react';
import HomePage from '@/app/page';
import { storage } from '@/utils/storage';
import type { Workout } from '@/types';

const workout: Workout = {
  id: 'workout-1',
  name: 'Morning Session',
  date: '2026-02-04T10:00:00.000Z',
  exercises: [],
  completed: false,
};

describe('HomePage', () => {
  it('shows empty state when no workouts', async () => {
    render(<HomePage />);

    expect(await screen.findByText('Ready to start?')).toBeInTheDocument();
  });

  it('shows continue workout when a current workout exists', async () => {
    storage.saveCurrentWorkout(workout);
    render(<HomePage />);

    expect(await screen.findByText('Continue Workout')).toBeInTheDocument();
  });
});
