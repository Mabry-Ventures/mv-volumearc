import { render, screen } from '@testing-library/react';
import StatsPage from '@/app/stats/page';
import { storage } from '@/utils/storage';
import type { Workout } from '@/types';

const completedWorkout: Workout = {
  id: 'workout-1',
  name: 'Stats Session',
  date: '2026-02-04T10:00:00.000Z',
  completed: true,
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

describe('StatsPage', () => {
  it('renders statistics when data exists', async () => {
    storage.saveWorkouts([completedWorkout]);
    render(<StatsPage />);

    expect(await screen.findByText('Weekly Volume')).toBeInTheDocument();
    expect(screen.getByText('Averages')).toBeInTheDocument();
  });
});
