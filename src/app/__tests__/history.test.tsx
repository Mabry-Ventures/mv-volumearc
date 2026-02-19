import { render, screen, fireEvent } from '@testing-library/react';
import HistoryPage from '@/app/history/page';
import { storage } from '@/utils/storage';
import type { Workout } from '@/types';

const completedWorkout: Workout = {
  id: 'workout-1',
  name: 'History Session',
  date: '2026-02-03T10:00:00.000Z',
  completed: true,
  duration: 45,
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
          completed: true,
        },
      ],
    },
  ],
};

describe('HistoryPage', () => {
  it('shows workouts and detail view', async () => {
    storage.saveWorkouts([completedWorkout]);
    render(<HistoryPage />);

    const item = await screen.findByText('History Session');
    fireEvent.click(item);

    expect(await screen.findByText(/Total Volume:/)).toBeInTheDocument();
    expect(screen.getByText('Bench Press')).toBeInTheDocument();
  });
});
